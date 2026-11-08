const { test } = require('node:test');
const assert = require('node:assert/strict');
const Narration = require('../ui/narration.js');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const active = { screen: 'session', sessionOpen: true, connected: true, state: 'active',
  paused: false, alert: null, dictation: { phase: 'idle' } };
const french = { lang: 'fr-FR', localService: true };
function setup(voices = [french], value = null) {
  const spoken = [], listeners = {}, prefs = new Map(value === null ? [] : [['papai.readAloud', value]]);
  let cancellations = 0;
  const synth = { getVoices: () => voices, speak: u => spoken.push(u), cancel: () => { cancellations++; },
    addEventListener: (name, fn) => { listeners[name] = fn; } };
  const storage = { getItem: key => prefs.get(key), setItem: (key, val) => prefs.set(key, val) };
  const n = new Narration(synth, class { constructor(text) { this.text = text; } }, storage);
  n.update(active);
  return { n, spoken, listeners, prefs, storage, synth, get cancellations() { return cancellations; } };
}

test('activée par défaut, préférence locale conservée', () => {
  const h = setup();
  assert.equal(h.n.enabled, true);
  h.n.setEnabled(false);
  assert.equal(h.prefs.get('papai.readAloud'), 'false');
  assert.equal(new Narration(null, null, h.storage).enabled, false);
  h.n.setEnabled(true);
  assert.equal(h.prefs.get('papai.readAloud'), 'true');
});
test('file ordonnée, normalisation et aucun doublon après fin de phrase', () => {
  const h = setup();
  h.n.enqueue(' Je clique\n ici ');
  h.n.enqueue('Je clique ici');
  h.n.enqueue("J'ouvre le dossier");
  assert.deepEqual(h.spoken.map(u => u.text), ['Je clique ici']);
  assert.equal(h.spoken[0].voice, french);
  h.spoken[0].onend();
  assert.deepEqual(h.spoken.map(u => u.text), ['Je clique ici', "J'ouvre le dossier"]);
  h.spoken[1].onend();
  h.n.enqueue('Je clique ici');
  h.n.enqueue('  ');
  assert.equal(h.spoken.length, 2);
});
for (const phase of ['starting', 'listening', 'transcribing']) {
  test(`dictée ${phase} : coupure immédiate, file vidée, pas de rattrapage`, () => {
    const h = setup();
    h.n.enqueue('En cours');
    h.n.enqueue('En attente');
    const old = h.spoken[0];
    h.n.update({ ...active, dictation: { phase }, currentAction: 'Pendant la dictée' });
    assert.equal(h.cancellations, 1);
    assert.deepEqual(h.n.pending, []);
    h.n.update({ ...active, currentAction: 'Pendant la dictée' });
    h.n.enqueue('En cours');
    h.n.enqueue('En attente');
    assert.equal(h.spoken.length, 1);
    h.n.enqueue('Après la dictée');
    old.onend();
    old.onerror();
    assert.equal(h.n.current.text, 'Après la dictée');
    assert.equal(h.spoken.length, 2);
  });
}
test('coupure avant de démarrer le micro, réactivation sans répétition', () => {
  const h = setup();
  h.n.enqueue('En cours');
  h.n.setDictating(true);
  assert.equal(h.cancellations, 1);
  h.n.setDictating(false);
  h.n.enqueue('En cours');
  assert.equal(h.spoken.length, 1);
});
test('interrupteur : coupe immédiatement, vide la file, ignore les phrases coupées', () => {
  const h = setup();
  h.n.enqueue('En cours');
  h.n.enqueue('En attente');
  h.n.setEnabled(false);
  h.n.enqueue('Coupée');
  assert.equal(h.cancellations, 1);
  h.n.setEnabled(true);
  for (const t of ['En cours', 'En attente', 'Coupée']) h.n.enqueue(t);
  assert.equal(h.spoken.length, 1);
});
for (const change of [{ paused: true }, { connected: false }, { alert: {} }, { state: 'awaiting_helper' },
  { state: 'done', sessionOpen: false }, { state: 'stopped', sessionOpen: false }, { screen: 'home' }]) {
  test(`pause/arrêt/fin/alerte/déconnexion : ${JSON.stringify(change)}`, () => {
    const h = setup();
    h.n.enqueue('En cours');
    h.n.enqueue('En attente');
    h.n.update({ ...active, ...change });
    assert.equal(h.cancellations, 1);
    assert.equal(h.n.current, null);
    assert.deepEqual(h.n.pending, []);
  });
}
test('les snapshots répétés ne relisent pas ; une nouvelle assistance peut répéter', () => {
  const h = setup();
  for (let i = 0; i < 3; i++) h.n.update({ ...active, currentAction: 'Je clique' });
  assert.equal(h.spoken.length, 1);
  h.n.update({ ...active, state: 'done', sessionOpen: false });
  h.n.update({ ...active, currentAction: 'Je clique' });
  assert.equal(h.spoken.length, 2);
});
test('aucune voix distante ni étrangère, attente du chargement de la voix française locale', () => {
  const voices = [{ lang: 'fr-FR', localService: false }, { lang: 'en-US', localService: true }];
  const h = setup(voices);
  h.n.enqueue('Bonjour');
  assert.equal(h.spoken.length, 0);
  voices.push(french);
  h.listeners.voiceschanged();
  assert.equal(h.spoken.length, 1);
  assert.equal(h.spoken[0].voice, french);
});
test('API de synthèse ou stockage absents : aucune exception', () => {
  const n = new Narration(null, null, undefined);
  n.update({ ...active, currentAction: 'Bonjour' });
  n.setEnabled(false);
  n.cancel();
});
test('une erreur de synthèse ne bloque pas la phrase suivante', () => {
  const h = setup();
  h.n.enqueue('Première'); h.n.enqueue('Deuxième');
  h.spoken[0].onerror();
  assert.equal(h.spoken[1].text, 'Deuxième');
});

test('raccords de la vraie interface : réglage local, snapshots, micro, pause et arrêt', async () => {
  const h = setup();
  const listeners = {}, calls = [];
  const root = { innerHTML: '' }, sheet = { innerHTML: '' };
  const state = { connected: true, onboarded: true, screen: 'home', state: null,
    firstName: '', storedFirstName: '', helperName: 'Support IT', textScale: 1, textScales: [],
    lessons: [], notice: null, homeShortcuts: [], microPresent: true, helpers: [],
    dictation: { phase: 'idle', message: null } };
  const document = { documentElement: { style: { setProperty() {} } },
    getElementById: id => ({ root, sheet }[id] || null),
    addEventListener: (name, fn) => { listeners[name] = fn; } };
  const window = { PapAINarration: h.n, addEventListener() {}, pywebview: { api: {
    ready: async () => state,
    dictation_toggle: () => { calls.push('dictation_toggle'); assert.equal(h.n.current, null); },
    stop: () => calls.push('stop'), toggle_pause: () => calls.push('toggle_pause'),
  } } };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../ui/app.js'), 'utf8'), {
    window, document, icon: () => '<svg></svg>', URLSearchParams, location: { search: '' }, setTimeout,
  });
  await new Promise(resolve => setImmediate(resolve));
  const click = act => listeners.click({ target: { closest: () => ({ dataset: { act } }) } });
  const update = changes => window.PapAI.update({ ...state, ...changes });
  click('openSettings');
  assert.match(sheet.innerHTML, /Lire à voix haute/);
  click('readAloud');
  assert.equal(h.n.enabled, false);
  assert.equal(h.prefs.get('papai.readAloud'), 'false');
  assert.deepEqual(calls, []);
  click('readAloud');
  update({ ...active, compact: true, currentAction: 'Je clique ici' });
  assert.match(root.innerHTML, /Je clique ici/);
  assert.equal(h.spoken.at(-1).text, 'Je clique ici');
  update({ ...active, currentAction: "J'ouvre le dossier" });
  assert.match(root.innerHTML, /J&#39;ouvre le dossier/);
  click('pause');
  assert.equal(h.n.current, null);
  assert.equal(calls.at(-1), 'toggle_pause');
  update({ ...active, currentAction: 'Nouvelle action' });
  click('stop');
  assert.equal(h.n.current, null);
  assert.equal(calls.at(-1), 'stop');
  update({ ...active, currentAction: 'Action suivante' });
  update({ ...active, screen: 'home' });
  // Même si une lecture a été engagée juste avant le clic, elle s'arrête avant l'API micro.
  h.n.update(active); h.n.enqueue('Avant le micro');
  click('mic');
  assert.equal(h.n.current, null);
  assert.equal(calls.at(-1), 'dictation_toggle');
});
