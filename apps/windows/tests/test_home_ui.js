// Tests de la vraie logique app.js, sans navigateur ni dépendance npm.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

async function home(microPresent = true) {
  let state = { connected: true, onboarded: true, screen: 'home', state: null,
    firstName: '', storedFirstName: '', helperName: 'Claire', textScale: 1,
    lessons: [], notice: null, homeShortcuts: [], microPresent,
    dictation: { phase: 'idle', message: null } };
  const listeners = {}, windowEvents = {}, sent = [], shortcuts = [], removed = [], calls = [];
  const root = { innerHTML: '' }, sheet = { innerHTML: '' };
  const document = { activeElement: null, documentElement: { style: { setProperty() {} } },
    getElementById: id => ({ root, sheet }[id] || null),
    addEventListener: (name, fn) => { listeners[name] = fn; } };
  const window = { pywebview: { api: {
    ready: async () => state,
    request_consent: task => { sent.push(task); },
    dictation_toggle: () => {},
    open_home_shortcut: id => { shortcuts.push(id); },
    remove_home_shortcut: id => { removed.push(id); },
    toggle_pause: () => { calls.push(['toggle_pause']); },
    answer_senior: t => { calls.push(['answer_senior', t]); },
    expand_window: () => { calls.push(['expand_window']); },
  } }, addEventListener: (name, fn) => { windowEvents[name] = fn; } };
  const context = vm.createContext({ window, document, icon: () => '<svg></svg>',
    URLSearchParams, location: { search: '' }, setTimeout });
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../ui/app.js'), 'utf8'), context);
  await new Promise(resolve => setImmediate(resolve));
  const update = changes => { state = { ...state, ...changes }; window.PapAI.update(state); };
  const click = (act, arg) => listeners.click({ target: { closest: () => ({ dataset: { act, arg } }) } });
  const type = text => listeners.input({ target: { id: 'req', value: text,
    style: {}, scrollHeight: 30 } });
  context.getComputedStyle = () => ({ lineHeight: '22' });
  const enter = () => listeners.keydown({ key: 'Enter', target: { id: 'req' }, preventDefault() {} });
  return { state, root, update, click, type, enter, sent, shortcuts, removed, calls, window, listeners };
}

test('textes Mac #30, avertissement vide identique et titres renforcés', async () => {
  const h = await home(false);
  h.update({ helperName: 'Théo', lessons: [{ id: 'l', title: 'Mes photos', steps: [] }] });
  assert.match(h.root.innerHTML, /Un souci sur l'ordinateur \? Écrivez ce dont vous avez besoin, un message part tout de suite à Théo\./);
  assert.match(h.root.innerHTML, /placeholder="Écrivez votre demande"/);
  assert.match(h.root.innerHTML, /font-weight:700;[^>]*>(Bonjour|Bonsoir)</);
  assert.match(h.root.innerHTML, /font-weight:700;[^>]*>Mes tutoriels</);
  assert.match(h.root.innerHTML, /font-weight:700;[^>]*>Mes raccourcis</);
  assert.match(h.root.innerHTML, /class="pill filled" data-act="submit"[^>]*height:44px/);
  h.click('submit');
  assert.match(h.root.innerHTML, /Dites en quelques mots ce qui ne va pas\./);
  assert.deepEqual(h.sent, []);
  h.update({ microPresent: true });
  assert.match(h.root.innerHTML, /Un souci sur l'ordinateur \? Dites-le simplement, un message part tout de suite à Théo\./);
  h.click('submit');
  assert.match(h.root.innerHTML, /Dites en quelques mots ce qui ne va pas\./);
});

test('Retirer exige le mode Modifier et Nouveau message transmet seulement son identifiant', async () => {
  const h = await home();
  h.update({ homeShortcuts: [{ id: 'perso', label: 'Photos', personal: true },
    { id: 'action:new-message', label: 'Nouveau message', symbol: 'compose' }] });
  assert.doesNotMatch(h.root.innerHTML, /data-act="removeShortcut"/);
  h.click('editShortcuts');
  assert.match(h.root.innerHTML, /data-act="removeShortcut"/);
  assert.match(h.root.innerHTML, />Terminer</);
  h.click('removeShortcut', 'perso');
  assert.deepEqual(h.removed, ['perso']);
  h.click('editShortcuts');
  assert.doesNotMatch(h.root.innerHTML, /data-act="removeShortcut"/);
  h.click('homeShortcut', 'action:new-message');
  assert.deepEqual(h.shortcuts, ['action:new-message']);
  assert.doesNotMatch(h.root.innerHTML, /href="mailto:/);
});

test('retirer le dernier personnel quitte le mode édition avant le prochain ajout', async () => {
  const h = await home();
  const message = { id: 'action:new-message', label: 'Nouveau message', symbol: 'compose' };
  const personal = { id: 'perso', label: 'Photos', personal: true };
  h.update({ homeShortcuts: [message, personal] });
  h.click('editShortcuts');
  h.update({ homeShortcuts: [message, personal] });
  assert.match(h.root.innerHTML, /data-act="removeShortcut"/);
  h.click('removeShortcut', 'perso');
  h.update({ homeShortcuts: [message] });
  assert.doesNotMatch(h.root.innerHTML, /data-act="editShortcuts"|data-act="removeShortcut"/);
  h.update({ homeShortcuts: [message, { ...personal, id: 'nouveau' }] });
  assert.match(h.root.innerHTML, />Modifier</);
  assert.doesNotMatch(h.root.innerHTML, /data-act="removeShortcut"|>Terminer</);
  h.click('editShortcuts');
  assert.match(h.root.innerHTML, /data-act="removeShortcut" data-arg="nouveau"/);
});

test('bascule micro/texte à chaud, sans perdre le brouillon', async () => {
  const h = await home();
  assert.match(h.root.innerHTML, /Dicter ma demande/);
  assert.match(h.root.innerHTML, />Écrire</);
  assert.doesNotMatch(h.root.innerHTML, /id="req"/);
  h.click('write');
  h.type('Mes photos');
  h.update({ microPresent: false });
  assert.doesNotMatch(h.root.innerHTML, /Dicter ma demande/);
  assert.match(h.root.innerHTML, /Écrivez ce dont vous avez besoin/);
  assert.match(h.root.innerHTML, /Mes photos<\/textarea>/);
  h.update({ microPresent: true });
  assert.match(h.root.innerHTML, /Dicter ma demande/);
  assert.match(h.root.innerHTML, /Mes photos<\/textarea>/);
});

test('aucun tutoriel vide, date ni ancien bouton', async () => {
  const h = await home(false);
  assert.doesNotMatch(h.root.innerHTML, /Mes tutoriels|J'ai besoin d'aide|Demander une assistance|Mes applications/);
  assert.match(h.root.innerHTML, /Mes raccourcis/);
  assert.match(h.root.innerHTML, /logotype-papai.svg/);
});

test('fin de dictée : envoi automatique unique, avec le texte déjà tapé', async () => {
  const h = await home();
  h.type('Retrouver');
  h.click('mic');
  h.update({ dictation: { phase: 'listening' } });
  h.click('submit'); h.enter();
  h.update({ dictation: { phase: 'transcribing' } });
  h.click('submit'); h.enter();
  assert.deepEqual(h.sent, []);
  h.update({ dictation: { phase: 'idle' } });
  h.enter(); // La phase idle précède le callback final Python.
  assert.deepEqual(h.sent, []);
  h.window.PapAI.dictated('mes photos', 1);
  h.window.PapAI.dictated('mes photos', 1);
  h.click('submit'); h.enter();
  assert.deepEqual(h.sent, ['Retrouver mes photos']);
  h.update({ screen: 'session' });
  h.update({ screen: 'home' });
  h.click('mic');
  h.window.PapAI.dictated('Mes documents', 2);
  assert.deepEqual(h.sent, ['Retrouver mes photos', 'Mes documents']);
});

test('silence, texte vide et session déjà ouverte : aucun envoi', async () => {
  const h = await home();
  h.window.PapAI.dictated('   ', 1);
  assert.deepEqual(h.sent, []);
  h.click('mic');
  h.update({ dictation: { phase: 'idle', message: "Je n'ai rien entendu." } });
  assert.deepEqual(h.sent, []);
  h.type('Mes photos');
  h.click('submit');
  assert.deepEqual(h.sent, ['Mes photos']);
  h.update({ screen: 'session' });
  h.window.PapAI.dictated('Texte tardif', 2);
  assert.deepEqual(h.sent, ['Mes photos']);
});

test('hors connexion : texte conservé pour un seul nouvel essai', async () => {
  const h = await home();
  h.update({ connected: false });
  h.window.PapAI.dictated('Mes photos', 1);
  assert.deepEqual(h.sent, []);
  h.update({ connected: true });
  h.click('submit'); h.enter();
  assert.deepEqual(h.sent, ['Mes photos']);
});

const html = (h) => h.root.innerHTML.replace(/&#39;/g, "'");
const session = (changes) => ({ screen: 'session', sessionOpen: true, HelperName: 'Claire', carer: 'Claire',
  helpers: [{ id: '1', name: 'Claire' }], plan: ['a', 'b'], planStep: 1, task: 'Mes photos',
  question: null, questionForMe: false, questionOptions: [], paused: false, compact: false, ...changes });

test('session comme sur Mac : avancement en 3 étapes, Pause puis Reprendre', async () => {
  const h = await home();
  h.update(session({ state: 'active' }));
  assert.match(html(h), /Claire s'en occupe/);
  assert.match(html(h), /role="progressbar"/);
  assert.match(html(h), /En cours : Claire s'en occupe, avec Holo/);
  assert.match(html(h), /data-act="pause"[\s\S]*Pause/);
  h.click('pause');
  assert.deepEqual(h.calls.at(-1), ['toggle_pause']);
  h.update({ paused: true });
  assert.match(html(h), /L'aide est en pause/);
  assert.match(html(h), />Reprendre</);
  h.update({ state: 'awaiting_approval', paused: false });
  assert.doesNotMatch(html(h), /data-act="pause"/);
});

test('question de Holo à la personne : réponse proposée ou écrite, une seule fois', async () => {
  const h = await home();
  h.update(session({ state: 'awaiting_helper', question: 'Ordinateur ou clé USB ?', questionForMe: true,
    questionOptions: ['Ordinateur', 'Clé USB'] }));
  assert.match(html(h), /Holo vous demande/);
  assert.match(html(h), /Ne donnez jamais de mot de passe ni de code/);
  h.click('seniorOption', 'Clé USB');
  assert.deepEqual(h.calls.at(-1), ['answer_senior', 'Clé USB']);
  assert.match(html(h), /Merci, c'est noté\./);
  h.update({ state: 'active', questionForMe: false, question: null });
  h.update({ state: 'awaiting_helper', questionForMe: true, question: 'Ordinateur ou clé USB ?' });
  assert.match(html(h), /data-act="seniorOption"/);
  h.update({ question: 'Et le dossier ?', questionOptions: [] });
  h.listeners.input({ target: { id: 'seniorReply', value: 'Noël 2025' } });
  h.listeners.keydown({ key: 'Enter', target: { id: 'seniorReply' }, preventDefault() {} });
  assert.deepEqual(h.calls.at(-1), ['answer_senior', 'Noël 2025']);
});

test("encart pendant que Holo agit, et fin du gardien adaptée à l'aidé", async () => {
  const h = await home();
  h.update(session({ state: 'active', compact: true }));
  assert.match(html(h), /class="col mini"/);
  assert.doesNotMatch(html(h), /Écran partagé/);
  assert.match(html(h), /data-act="stop"/);
  h.click('expand');
  assert.deepEqual(h.calls.at(-1), ['expand_window']);
  h.update(session({ state: 'stopped', sessionOpen: false, stoppedBy: 'gardien', guardAcknowledged: true }));
  assert.match(html(h), /cette démarche peut être une arnaque/);
  assert.match(html(h), /Appelez Claire à son numéro habituel\./);
  assert.match(html(h), /Votre support a vu l'alerte et s'en occupe/);
});
