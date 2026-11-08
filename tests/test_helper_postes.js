// Page du support (helper.html) : barre « Postes » tirée de l'organisation, sans liaison.
//   node --test tests/test_helper_postes.js
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '../backend/static/helper.html'), 'utf8');

function page({ orgs, spaces, status = 200 }) {
  const nodes = new Map(), fetched = [], sockets = [];
  function element(tag) {
    return { tag, hidden: true, textContent: '', value: '', checked: false, style: {}, href: '', className: '',
      children: [], classList: { add() {}, remove() {}, toggle() {} },
      addEventListener() {}, setAttribute() {}, removeAttribute() {},
      querySelector() { return element(); }, querySelectorAll() { return []; },
      appendChild(child) { this.children.push(child); },
      append(...children) { this.children.push(...children); },
      replaceChildren(...children) { this.children = [...children]; } };
  }
  const get = id => { if (!nodes.has(id)) nodes.set(id, element('div')); return nodes.get(id); };
  class WebSocket {
    static OPEN = 1;
    readyState = 1;
    constructor(url) { this.url = url; sockets.push(this); }
    send() {}
    close() {}
  }
  const context = vm.createContext({
    document: { getElementById: get, querySelectorAll: () => [], createElement: element, title: '' },
    location: { pathname: '/a/cle-a', protocol: 'http:', host: 'localhost' },
    localStorage: { getItem: k => (k === 'papai_orgs' ? JSON.stringify(orgs) : ''), setItem() {} },
    fetch: async url => { fetched.push(url); return { ok: status === 200, json: async () => ({ org: 'Acme', spaces }) }; },
    WebSocket, navigator: {},
    setInterval() {}, setTimeout() {}, clearTimeout() {},
    window: { addEventListener() {}, scrollTo() {} },
  });
  vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
  return { get, fetched, sockets, context };
}

const tick = () => new Promise(r => setImmediate(r));
const text = el => [el.textContent, ...el.children.map(text)].join(' ');

test('les postes de l’organisation remplissent la barre, sans ajout ni retrait', async () => {
  const p = page({ orgs: ['sup-jetonDeTest_123'], spaces: [
    { key: 'cle-a', name: 'Christine', label: 'Comptabilité', online: true },
    { key: 'cle-b', name: 'Marc', label: 'Marc', online: false },
    { key: '../x', name: 'Intrus' },
  ] });
  await tick(); await tick();
  assert.deepEqual(p.fetched, ['/o/sup-jetonDeTest_123/spaces']);
  const nav = p.get('people');
  assert.equal(nav.hidden, false);
  const items = nav.children;
  assert.equal(items.length, 3, 'deux postes et le lien vers tous les postes');
  assert.match(text(items[0]), /Christine · Comptabilité/);
  assert.match(text(items[1]), /Marc/);
  assert.doesNotMatch(text(items[1]), /Marc · Marc/);
  assert.equal(items[1].href, '/a/cle-b');
  assert.equal(items[2].textContent, 'Tous les postes');
  assert.equal(items[2].href, '/o/sup-jetonDeTest_123');
  assert.ok(!items.some(i => i.href === '/p'), 'aucun lien de liaison');
  assert.ok(!items.some(i => typeof i.oncontextmenu === 'function'), 'aucun « Retirer »');
  assert.deepEqual(p.sockets.map(s => s.url).filter(u => u.includes('/ws/aidant/cle-b')).length, 1, 'l’autre poste est surveillé');
  assert.ok(!p.sockets.some(s => s.url.includes('Intrus') || s.url.includes('..')));
});

test('sans organisation connue : pas de barre, aucune requête', async () => {
  const p = page({ orgs: [], spaces: [] });
  await tick();
  assert.deepEqual(p.fetched, []);
  assert.equal(p.get('people').hidden, true);
});

test('jeton illisible ignoré', async () => {
  const p = page({ orgs: ['sup-<script>'], spaces: [] });
  await tick();
  assert.deepEqual(p.fetched, []);
});

test('plus aucun texte de liaison dans les pages du support', () => {
  for (const f of ['helper.html', 'org.html', 'pair.html']) {
    const h = fs.readFileSync(path.join(__dirname, '../backend/static', f), 'utf8');
    assert.doesNotMatch(h, /Ajouter une personne|Mes personnes aidées|code à 6 chiffres|Devenir support/, f);
  }
});
