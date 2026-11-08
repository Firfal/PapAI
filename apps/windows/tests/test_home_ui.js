// Tests de la vraie logique app.js, sans navigateur ni dépendance npm.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

async function home(microPresent = true) {
  let state = { connected: true, screen: 'home', state: null,
    firstName: '', helperName: 'Claire', textScale: 1, textScales: [['Grande', 1], ['Très grande', 1.18]],
    orgName: '', orgConfigured: false, realtimeProtection: true, screenConsent: false,
    lessons: [], notice: null, homeShortcuts: [], queued: null, ticketPlan: null, ticketLive: null, microPresent,
    dictation: { phase: 'idle', message: null } };
  const listeners = {}, windowEvents = {}, sent = [], shortcuts = [], removed = [], actions = [], calls = [], automationCalls = [];
  const root = { innerHTML: '' }, sheet = { innerHTML: '' };
  const dialog = { focus() { document.activeElement = dialog; } };
  const document = { activeElement: null, documentElement: { style: { setProperty() {} } },
    getElementById: id => ({ root, sheet }[id] || null),
    addEventListener: (name, fn) => { listeners[name] = fn; } };
  const window = { pywebview: { api: {
    ready: async () => state,
    open_requests: () => { calls.push(['open_requests']); },
    close_requests: () => { calls.push(['close_requests']); },
    relaunch_request: id => { assert.equal(sheet.innerHTML, ''); calls.push(['relaunch_request', id]); },
    request_consent: task => { sent.push(task); },
    dictation_toggle: () => {},
    open_home_shortcut: id => { shortcuts.push(id); },
    remove_home_shortcut: id => { removed.push(id); },
    run_suggested_automation: (id, ticket) => { automationCalls.push([id, ticket]); },
    launch_ticket_plan: () => calls.push(['launch_ticket_plan']),
    defer_ticket_plan: () => calls.push(['defer_ticket_plan']),
    open_ticket_plan: () => calls.push(['open_ticket_plan']),
    choose_ticket_slot: at => calls.push(['choose_ticket_slot', at]),
    ticket_slot_other: () => calls.push(['ticket_slot_other']),
    close_ticket_live: () => calls.push(['close_ticket_live']),
    open_ticket_live: () => calls.push(['open_ticket_live']),
    dismiss_alert: () => { actions.push('dismiss_alert'); },
    stop: () => { actions.push('stop'); },
    toggle_pause: () => { calls.push(['toggle_pause']); },
    answer_senior: t => { calls.push(['answer_senior', t]); },
    expand_window: () => { calls.push(['expand_window']); },
  } }, addEventListener: (name, fn) => { windowEvents[name] = fn; } };
  const context = vm.createContext({ window, document, icon: () => '<svg></svg>',
    URLSearchParams, location: { search: '' }, setTimeout });
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../ui/app.js'), 'utf8'), context);
  await new Promise(resolve => setImmediate(resolve));
  const update = changes => { state = { ...state, ...changes }; window.PapAI.update(state); };
  const click = (act, arg, ticket) => listeners.click({ target: { closest: () => ({ dataset: { act, arg, ticket } }) } });
  const type = text => listeners.input({ target: { id: 'req', value: text,
    style: {}, scrollHeight: 30 } });
  context.getComputedStyle = () => ({ lineHeight: '22' });
  const enter = () => listeners.keydown({ key: 'Enter', target: { id: 'req' }, preventDefault() {} });
  return { state, root, sheet, dialog, document, update, click, type, enter, sent, shortcuts, removed, calls, window, listeners,
    automationCalls, actions, key: event => listeners.keydown(event) };
}

test('réponse documentaire et sources restent du texte brut', async () => {
  const h = await home();
  h.update(session({ state: 'done', answer: '<script>réponse</script>',
    answerSources: [{ name: '<b>Documentation</b>', url: 'https://example.org' }] }));
  assert.match(html(h), /&lt;script&gt;réponse&lt;\/script&gt;/);
  assert.match(html(h), /&lt;b&gt;Documentation&lt;\/b&gt;/);
  assert.match(html(h), /https:\/\/example.org/);
  assert.doesNotMatch(html(h), /<script>réponse/);
  h.update({ answerSources: [] });
  assert.doesNotMatch(html(h), /https:\/\/example.org/);
});

test('Mes demandes : feuille lecture seule, états et relance seulement si automate présent', async () => {
  const h = await home();
  assert.match(h.root.innerHTML, /data-act="openRequests"[\s\S]*Mes demandes/);
  h.click('openRequests');
  assert.deepEqual(h.calls.at(-1), ['open_requests']);
  assert.match(htmlSheet(h), /Aucune demande pour l'instant\./);
  h.update({ requestsLoading: true });
  assert.match(htmlSheet(h), /Chargement…/);
  h.update({ requestsLoading: false, requestsError: true });
  assert.match(htmlSheet(h), /Liste indisponible pour l'instant\./);
  const requests = [
    { id: 'r1', created: 1794132000, task: '<img src=x>', status: 'resolu', relaunch: 'a',
      solution: { kind: 'automate', title: '<Titre>', lesson: 'a' } },
    { id: 'r2', status: 'en_cours', solution: { kind: 'plan', steps: ['<Étape>'] } },
    { id: 'r3', status: 'rdv', solution: { kind: 'answer', text: '<Réponse>', sources: [{ title: '<Source>', url: 'https://example.org' }] } },
    ...['nouveau', 'en_attente', 'a_reprendre'].map((status, i) => ({ id: 'w' + i, status })),
  ];
  h.update({ requestsLoading: false, requestsError: false, requests, lessons: [] });
  assert.doesNotMatch(h.sheet.innerHTML, /data-act="relaunchRequest"|<img|<a |<input|<textarea/);
  h.click('relaunchRequest', 'r1');
  assert.deepEqual(h.calls.at(-1), ['open_requests']);
  for (const text of ['Réglée', 'En cours', 'Rendez-vous prévu', 'En attente', 'Interrompue',
    'novembre 2026', "Réglée par l'automate", 'Plan exécuté', 'Réponse validée par le support', 'https://example.org']) {
    assert.ok(htmlSheet(h).includes(text), text);
  }
  assert.match(h.sheet.innerHTML, /&lt;Étape&gt;|&lt;Réponse&gt;/);
  h.update({ lessons: [{ id: 'a' }] });
  assert.match(h.sheet.innerHTML, /data-act="relaunchRequest"[\s\S]*data-arg="r1"/);
  h.click('relaunchRequest', 'r1');
  assert.deepEqual(h.calls.slice(-2), [['close_requests'], ['relaunch_request', 'r1']]);
  assert.equal(h.sheet.innerHTML, '');
  h.click('openRequests');
  h.key({ key: 'Escape', target: {}, preventDefault() {} });
  assert.equal(h.sheet.innerHTML, '');
  assert.deepEqual(h.calls.at(-1), ['close_requests']);
});

const htmlSheet = h => h.sheet.innerHTML.replace(/&#39;/g, "'");

test("accueil direct : « Bonjour <nom Windows> », sans étapes d'accueil ni liaison", async () => {
  const h = await home();
  h.update({ firstName: '<Jeanne>' });
  assert.match(h.root.innerHTML, /(Bonjour|Bonsoir) &lt;Jeanne&gt;/);
  assert.doesNotMatch(h.root.innerHTML, /Bienvenue sur PapAI|Comment vous appelez-vous|Qui va vous aider/);
  h.update({ firstName: '' });
  assert.match(h.root.innerHTML, /(Bonjour|Bonsoir)<\/div>/);
  const js = fs.readFileSync(path.join(__dirname, '../ui/app.js'), 'utf8');
  assert.doesNotMatch(js, /pairDialog|start_pairing|copy_invitation|answer_pair|onboarding|WhatsApp|SMS|Ajouter un support/);
});

test("attente d'un support : automates proposés et lancement rattaché au ticket", async () => {
  const h = await home();
  const queued = { ticket: 'ticket-1', number: 7, task: 'Imprimer une facture', show: true,
    suggestions: [{ id: 'auto-1', title: 'Imprimer le document' }], suggestion_lancee: null };
  h.update({ queued });
  assert.match(h.root.innerHTML, /En attendant, vous pouvez essayer :/);
  assert.match(h.root.innerHTML, /Imprimer le document/);
  assert.match(h.root.innerHTML, /data-act="runSuggested" data-arg="auto-1"[\s\S]*data-ticket="ticket-1"/);
  h.click('runSuggested', 'auto-1', 'ticket-1');
  assert.deepEqual(h.automationCalls, [['auto-1', 'ticket-1']]);
  h.update({ queued: { ...queued, suggestion_lancee: 'auto-1' } });
  assert.match(h.root.innerHTML, />\s*Lancé<\/button>/);
  assert.match(h.root.innerHTML, /data-act="runSuggested"[^>]*disabled/);
});

test("plan validé : affichage, lancement avec Holo et retour à l'accueil", async () => {
  const h = await home();
  const plan = { ticket: 'ticket-plan', number: 8, task: 'Configurer le Wi-Fi',
    steps: ['Ouvrir les réglages réseau', 'Choisir le Wi-Fi'], by: 'Claire', show: true };
  h.update({ ticketPlan: plan });
  assert.match(h.root.innerHTML, /Votre support a validé la marche à suivre/);
  assert.match(h.root.innerHTML, /1\. Ouvrir les réglages réseau/);
  h.click('launchTicketPlan');
  assert.deepEqual(h.calls.at(-1), ['launch_ticket_plan']);
  h.update({ ticketPlan: { ...plan, show: false } });
  assert.match(h.root.innerHTML, /Plan validé · demande n° 8/);
  h.click('openTicketPlan');
  assert.deepEqual(h.calls.at(-1), ['open_ticket_plan']);
  h.update({ ticketPlan: plan });
  h.click('deferTicketPlan');
  assert.deepEqual(h.calls.at(-1), ['defer_ticket_plan']);
});

test("assistance en direct : créneaux, horaire choisi et demande d'un autre", async () => {
  const h = await home();
  const live = { ticket: 'ticket-live', number: 9, task: 'Partager l’écran', show: true,
    slots: [1794211200, 1794214800], chosenAt: null, other: false };
  h.update({ ticketLive: live });
  assert.match(h.root.innerHTML, /Votre support veut vous aider en direct/);
  assert.match(h.root.innerHTML, /Aucun ne me convient/);
  h.click('chooseTicketSlot', String(live.slots[0]));
  assert.deepEqual(h.calls.at(-1), ['choose_ticket_slot', live.slots[0]]);
  h.click('ticketSlotOther');
  assert.deepEqual(h.calls.at(-1), ['ticket_slot_other']);
  h.update({ ticketLive: { ...live, chosenAt: live.slots[0] } });
  assert.match(h.root.innerHTML, /Rendez-vous choisi/);
  h.click('closeTicketLive');
  assert.deepEqual(h.calls.at(-1), ['close_ticket_live']);
  h.update({ ticketLive: { ...live, show: false, chosenAt: live.slots[0] } });
  assert.match(h.root.innerHTML, /data-act="openTicketLive"[\s\S]*Rendez-vous/);
  h.click('openTicketLive');
  assert.deepEqual(h.calls.at(-1), ['open_ticket_live']);
});

test("Réglages : « Mon support » en lecture seule, organisation en ligne ou non", async () => {
  const h = await home();
  h.update({ orgName: '<Acme>', orgConfigured: true });
  h.click('openSettings');
  assert.match(h.sheet.innerHTML, /Mon support/);
  assert.match(h.sheet.innerHTML, /Support IT · &lt;Acme&gt;/);
  assert.match(h.sheet.innerHTML, /En ligne/);
  const withoutReadAloud = h.sheet.innerHTML.replace(/<input[^>]*data-act="readAloud"[^>]*>/g, '');
  assert.doesNotMatch(withoutReadAloud, /<input|Prénom|Serveur|Enregistrer|data-act="(pair|openHelpers|replayOnboarding)"/);
  h.update({ connected: false });
  assert.match(h.sheet.innerHTML, /Hors ligne pour le moment/);
  h.update({ orgName: '', orgConfigured: false, connected: true });
  assert.match(h.sheet.innerHTML, /Aucune organisation configurée : contactez votre service informatique\./);
  assert.doesNotMatch(h.sheet.innerHTML, /Support IT ·/);
  h.update({ orgConfigured: true });
  assert.match(h.sheet.innerHTML, /Rattachement en cours/);
  h.key({ key: 'Escape', target: {}, preventDefault() {} });
  assert.equal(h.sheet.innerHTML, '');
});

test('Entrée et Échap ne ferment aucune alerte ni ne déclenchent une action derrière', async () => {
  const h = await home();
  for (const blocked of [false, true]) {
    h.update({ screen: 'session', sessionOpen: true,
      alert: { level: 'info', title: 'Attention', detail: 'Attendez', blocked } });
    for (const key of ['Enter', 'Escape']) {
      let prevented = false;
      h.key({ key, target: { tagName: 'BUTTON' }, preventDefault() { prevented = true; } });
      assert.equal(prevented, true);
      assert.match(h.sheet.innerHTML, /Attendez/);
      assert.deepEqual(h.actions, []);
    }
  }
});

test('textes Mac #30, avertissement vide identique et titres renforcés', async () => {
  const h = await home(false);
  h.update({ helperName: 'Théo', lessons: [{ id: 'l', title: 'Mes photos', steps: [] }] });
  assert.match(h.root.innerHTML, /Que voulez-vous faire \?/);
  assert.match(h.root.innerHTML, /placeholder="Écrivez ce que vous voulez faire"/);
  assert.match(h.root.innerHTML, /font-weight:700;[^>]*>(Bonjour|Bonsoir)</);
  assert.match(h.root.innerHTML, /font-weight:700;[^>]*>Mes automates</);
  assert.match(h.root.innerHTML, /font-weight:700;[^>]*>Mes raccourcis</);
  assert.match(h.root.innerHTML, /class="pill filled" data-act="submit"[^>]*height:44px/);
  h.click('submit');
  assert.match(h.root.innerHTML, /Dites en quelques mots ce qui ne va pas\./);
  assert.deepEqual(h.sent, []);
  h.update({ microPresent: true });
  assert.match(h.root.innerHTML, /placeholder="Écrivez ou dites ce que vous voulez faire"/);
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
  assert.match(h.root.innerHTML, /id="req"/);
  h.type('Mes photos');
  h.update({ microPresent: false });
  assert.doesNotMatch(h.root.innerHTML, /Dicter ma demande/);
  assert.match(h.root.innerHTML, /placeholder="Écrivez ce que vous voulez faire"/);
  assert.match(h.root.innerHTML, /Mes photos<\/textarea>/);
  h.update({ microPresent: true });
  assert.match(h.root.innerHTML, /Dicter ma demande/);
  assert.match(h.root.innerHTML, /Mes photos<\/textarea>/);
});

test('sans automate : explication du Mac, ni date ni ancien bouton', async () => {
  const h = await home(false);
  assert.match(h.root.innerHTML, /Aucun automate pour l'instant\./);
  assert.doesNotMatch(h.root.innerHTML, /J'ai besoin d'aide|Demander une assistance|Mes applications/);
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

test("encart pendant que Holo agit, et fin du gardien adaptée à l’utilisateur", async () => {
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
