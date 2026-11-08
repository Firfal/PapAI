// Brouillon réel de helper.html avec un DOM et un WebSocket simulés.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

test('la cible est visible, retirable seulement, et réinitialisée entre brouillons', () => {
  const nodes = new Map(), sent = [];
  function element() {
    return { hidden: true, textContent: '', value: '', checked: false, style: {},
      children: [], classList: { add() {}, remove() {}, toggle() {} },
      addEventListener() {}, setAttribute() {}, removeAttribute() {},
      querySelector() { return element(); }, querySelectorAll() { return []; },
      appendChild(child) { this.children.push(child); } };
  }
  function get(id) {
    if (!nodes.has(id)) nodes.set(id, element());
    return nodes.get(id);
  }
  class WebSocket {
    static OPEN = 1;
    readyState = 1;
    send(raw) { sent.push(JSON.parse(raw)); }
  }
  const context = vm.createContext({
    document: { getElementById: get, querySelectorAll: () => [], createElement: element },
    location: { pathname: '/a/demo', protocol: 'http:', host: 'localhost' },
    localStorage: { getItem: () => '' }, WebSocket,
    setInterval() {}, setTimeout() {}, clearTimeout() {},
    window: { addEventListener() {}, scrollTo() {} },
  });
  const html = fs.readFileSync(path.join(__dirname, '../backend/static/helper.html'), 'utf8');
  vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
  function draft(shortcut) {
    context.payload = JSON.stringify({ type: 'lesson_draft', lesson: { title: 'Photos', steps: [], shortcut } });
    vm.runInContext('onMessage({data: payload})', context);
  }
  draft({ folder: 'pictures', subfolder: 'Noël 2025' });
  assert.equal(get('draftTarget').hidden, false);
  assert.equal(get('draftTargetLabel').textContent, 'Ouvrira : Images › Noël 2025');
  get('approve').onclick();
  assert.equal(Object.hasOwn(sent.at(-1).lesson, 'shortcut'), false);
  get('noShortcut').checked = true;
  get('approve').onclick();
  assert.equal(sent.at(-1).lesson.shortcut, null);
  draft({ folder: 'downloads', subfolder: '' });
  assert.equal(get('noShortcut').checked, false);
  assert.equal(get('draftTargetLabel').textContent, 'Ouvrira : Téléchargements');
  draft(null);
  assert.equal(get('draftTarget').hidden, true);
  assert.equal(get('draftTargetLabel').textContent, '');
  get('noShortcut').checked = true;
  get('approve').onclick();
  assert.equal(Object.hasOwn(sent.at(-1).lesson, 'shortcut'), false);
});
