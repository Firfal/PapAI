// Brouillon réel de helper.html avec un DOM et un WebSocket simulés.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

test('cible retirable et refus sensible persistant jusqu’à Compris ou au geste suivant', () => {
  const nodes = new Map(), sent = [], timers = [];
  function element() {
    return { hidden: true, textContent: '', value: '', checked: false, style: {},
      children: [], classList: { add() {}, remove() {}, toggle() {} },
      addEventListener() {}, setAttribute() {}, removeAttribute() {}, remove() {},
      querySelector() { return element(); }, querySelectorAll() { return []; },
      appendChild(child) { this.children.push(child); },
      append(...children) { this.children.push(...children); },
      replaceChildren(...children) { this.children = [...children]; } };
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
    setInterval() {}, setTimeout(callback) { timers.push(callback); }, clearTimeout() {},
    window: { addEventListener() {}, scrollTo() {} },
  });
  const html = fs.readFileSync(path.join(__dirname, '../backend/static/helper.html'), 'utf8');
  vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
  function draft(shortcut) {
    context.payload = JSON.stringify({ type: 'lesson_draft', lesson: { title: 'Photos', steps: [], shortcut } });
    vm.runInContext('onMessage({data: payload})', context);
  }
  draft({ folder: 'pictures', subfolder: 'Séminaire 2025' });
  assert.equal(get('draftTarget').hidden, false);
  assert.equal(get('draftTargetLabel').textContent, 'Ouvrira : Images › Séminaire 2025');
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
  function message(m) {
    context.payload = JSON.stringify(m);
    vm.runInContext('onMessage({data: payload})', context);
  }
  const reason = 'Clic non effectué : cette fenêtre est protégée (réglages ou mots de passe). Guidez Jeanne par téléphone.';
  message({ type: 'refused', blocked: 'sensitive', reason });
  assert.equal(get('sensitiveRefusal').hidden, false);
  assert.equal(get('sensitiveRefusalText').textContent, reason);
  for (const callback of timers.splice(0)) callback();
  assert.equal(get('sensitiveRefusal').hidden, false);
  message({ type: 'senior', name: 'Jeanne' });
  assert.equal(get('sensitiveRefusal').hidden, false);
  get('sensitiveRefusalOk').onclick();
  assert.equal(get('sensitiveRefusal').hidden, true);
  message({ type: 'refused', blocked: 'sensitive', reason });
  vm.runInContext("send({ type: 'helper_hello' })", context);
  assert.equal(get('sensitiveRefusal').hidden, false);
  vm.runInContext("send({ type: 'answer', text: 'C’est fait.' })", context);
  assert.equal(get('sensitiveRefusal').hidden, true);
  message({ type: 'refused', reason: 'Autre erreur' });
  assert.equal(get('toast').textContent, 'Autre erreur');
  assert.equal(get('toast').style.display, 'block');
  for (const callback of timers.splice(0)) callback();
  assert.equal(get('toast').style.display, 'none');
  message({ type: 'status', session: 'linkup-test', state: 'awaiting_approval', task: 'Erreur logiciel', plan: ['Ouvrir'] });
  get('linkupOpen').onclick();
  assert.equal(get('linkupQuery').value, 'Erreur logiciel');
  const beforeEmpty = sent.length;
  get('linkupQuery').value = '   ';
  get('linkupSearch').onclick();
  assert.equal(sent.length, beforeEmpty);
  get('linkupQuery').value = 'Documentation';
  get('linkupSearch').onclick();
  assert.equal(sent.at(-1).type, 'linkup_search');
  assert.equal(get('linkupSearch').disabled, true);
  vm.runInContext('ws.readyState = 3; ws.onclose()', context);
  assert.equal(get('linkupSearch').disabled, false);
  assert.equal(get('linkupRefuse').disabled, false);
  const beforeOffline = sent.length;
  get('linkupSearch').onclick();
  assert.equal(sent.length, beforeOffline);
  assert.equal(get('linkupSearch').disabled, false);
  vm.runInContext('ws.readyState = 1; ws.onopen()', context);
  get('linkupSearch').onclick();
  assert.equal(get('linkupSearch').disabled, true);
  vm.runInContext('ws.onopen()', context);
  assert.equal(get('linkupSearch').disabled, false);
  message({ type: 'linkup_proposed', session: 'linkup-test', query: 'Documentation' });
  message({ type: 'linkup_result', session: 'linkup-test', id: 'result-1', summary: '<script>texte brut</script>',
    sources: [{name: '<b>Source</b>', url: 'https://example.org'}, {name: 'Interdit', url: 'javascript:alert(1)'}] });
  assert.equal(get('linkupText').value, '<script>texte brut</script>');
  assert.equal(get('linkupSources').children.length, 1);
  assert.equal(get('linkupSources').children[0].children[0].textContent, '<b>Source</b>');
  get('linkupText').value = '';
  const beforeApprove = sent.length;
  get('linkupApprove').onclick();
  assert.equal(sent.length, beforeApprove);
  get('linkupText').value = 'Réponse corrigée';
  get('linkupApprove').onclick();
  assert.equal(sent.at(-1).type, 'linkup_approve');
  assert.equal(sent.at(-1).id, 'result-1');
  assert.equal(sent.at(-1).text, 'Réponse corrigée');
  message({ type: 'linkup_result', session: 'linkup-test', error: 'disabled' });
  assert.equal(get('linkupMessage').textContent, 'Recherche indisponible pour le moment');
  assert.equal(get('linkupReview').hidden, true);
  get('linkupRefuse').onclick();
  assert.equal(sent.at(-1).approved, false);
  message({ type: 'status', session: 'next-test', state: 'awaiting_approval', task: 'Autre demande' });
  assert.equal(get('linkupCard').hidden, true);
});

test('ticket documentaire : réponse et liens affichés sans HTML actif', () => {
  function element() {
    return { children: [], textContent: '', append(...children) { this.children.push(...children); },
      appendChild(child) { this.children.push(child); }, replaceChildren() { this.children = []; },
      setAttribute() {} };
  }
  const context = { window: {}, document: { head: element(), createElement: element } };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../backend/static/tickets.js'), 'utf8'), context);
  const box = element();
  const ticket = { number: 1, status: 'resolu', created: 1, source: 'support', task: 'Documentation',
    linkup_answer: { content: '<script>réponse</script>', sources: [
      { name: '<b>Source</b>', url: 'https://example.org' },
      { name: 'Interdit', url: 'javascript:alert(1)' }] } };
  context.window.PapaiTickets.render(box, [ticket], () => {});
  const card = box.children[0];
  assert.equal(card.children[2].textContent, '<script>réponse</script>');
  assert.equal(card.children[3].textContent, '<b>Source</b>');
  assert.equal(card.children[3].href, 'https://example.org');
  assert.equal(card.children.filter(c => c.href).length, 1);
  ticket.linkup_answer.sources = [];
  context.window.PapaiTickets.render(box, [ticket], () => {});
  assert.equal(box.children[0].children.filter(c => c.href).length, 0);
  context.window.PapaiTickets.render(box, [], () => {});
  assert.equal(box.children[0].textContent, 'Aucun ticket.');
});
