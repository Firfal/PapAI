// Statistiques des tickets (ticket_stats.js) : carte « Cette semaine » et panneau de #86.
//   node --test tests/test_ticket_stats_js.js
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const src = fs.readFileSync(path.join(__dirname, '../backend/static/ticket_stats.js'), 'utf8');

function element(tag) {
  return { tag, textContent: '', className: '', style: {}, children: [],
    classList: { add() {}, remove() {}, toggle() {} },
    setAttribute() {}, addEventListener() {},
    appendChild(c) { this.children.push(c); },
    append(...cs) { this.children.push(...cs); },
    replaceChildren(...cs) { this.children = [...cs]; } };
}

function load() {
  const window = {};
  const document = { head: element('head'), createElement: element, createElementNS: (_, t) => element(t),
    createTextNode: t => ({ textContent: String(t) }) };
  vm.runInContext(src, vm.createContext({ window, document }));
  return window.PapaiStats;
}

const texts = n => [n.textContent || '', ...(n.children || []).map(c => typeof c === 'string' ? c : texts(c))].join(' ');
const sugs = box => box.children.filter(c => c.className === 'ps-sug').map(c => c.children[0].textContent);

const wifi = { category: 'wifi', count: 6, text: '6 demandes Wi-Fi ce mois-ci : créer un automate ?', draft: {} };
const imp = { category: 'imprimante', count: 5, text: '5 demandes imprimante ce mois-ci : créer un automate ?', draft: {} };
const stats = { since: '2026-10-01', totals: { count: 11, resolved: 5 }, weeks: [], categories: [], labels: [],
  suggestions: [wifi, imp], week: { count: 0, resolved: 0, suggestion: wifi } };

test('le panneau ne répète pas la suggestion de la carte, garde les autres', () => {
  const S = load();
  const box = element('div');
  S.render(box, stats, { skipCategory: stats.week.suggestion.category });
  assert.deepEqual(sugs(box), [imp.text]);
});

test('sans skipCategory, toutes les suggestions restent dans le panneau', () => {
  const S = load();
  const box = element('div');
  S.render(box, stats, {});
  assert.deepEqual(sugs(box), [wifi.text, imp.text]);
});

test('semaine vide : la carte affiche quand même la suggestion', () => {
  const S = load();
  const box = element('div');
  S.renderWeek(box, stats, {});
  assert.match(texts(box), /Aucune demande ces 7 derniers jours/);
  assert.deepEqual(sugs(box), [wifi.text]);
});
