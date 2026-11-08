const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const html = fs.readFileSync(path.join(__dirname, '../backend/static/pair.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];

function page(pathname, fetch) {
  const elements = {};
  const writes = [];
  const listeners = {};
  const get = id => elements[id] ||= {
    hidden: ['codeRow', 'appRow', 'done'].includes(id), value: '', disabled: false,
    textContent: '', addEventListener: (type, fn) => { listeners[id] = fn; },
  };
  vm.runInNewContext(script, {
    location: { origin: 'https://papai.example', pathname },
    document: { getElementById: get }, fetch,
    localStorage: { getItem: () => '', setItem: (...args) => writes.push(args) },
  });
  get('name').value = 'Claire';
  get('relation').value = 'sa fille';
  return { get, writes, submit: () => listeners.form({ preventDefault() {} }) };
}

test('QR et ancien lien : lien d’app sans clé', () => {
  for (const route of ['/p/123456', '/k/cle-secrete/p/123456']) {
    const p = page(route);
    const link = new URL(p.get('openApp').href);
    assert.equal(link.searchParams.get('u'), 'https://papai.example/p/123456');
    assert.equal(p.get('codeRow').hidden, true);
    assert.equal(p.get('appRow').hidden, false);
  }
});

test('invitation : POST du jeton, attente puis succès', async () => {
  const route = '/i/Abc_def-123456789012345';
  let finish;
  const p = page(route, (url, request) => {
    assert.equal(url, route);
    assert.equal(JSON.parse(request.body).name, 'Claire');
    return new Promise(resolve => { finish = resolve; });
  });
  assert.equal(new URL(p.get('openApp').href).searchParams.get('u'), 'https://papai.example' + route);
  assert.equal(p.get('codeRow').hidden, true);
  const pending = p.submit();
  assert.equal(p.get('go').disabled, true);
  assert.equal(p.get('waiting').hidden, false);
  finish({ status: 200, json: async () => ({ ok: true, name: 'Claire', aidant_url: '/a/autorise' }) });
  await pending;
  assert.deepEqual(p.writes, [['papai_name', 'Claire']]);
  assert.equal(p.get('done').hidden, false);
  assert.equal(p.get('go').disabled, false);
  assert.equal(p.get('waiting').hidden, true);
});

test('erreurs serveur littérales, sans enregistrement hors 200 et ok:true', async () => {
  for (const [status, ok] of [[400, false], [403, false], [408, false], [409, false], [429, false], [403, true], [200, false]]) {
    const message = '<b>Message du serveur & prénom</b>';
    const p = page('/i/Abc_def-123456789012345', async () => ({
      status, json: async () => ({ ok, error: message, refused: status === 403 }),
    }));
    await p.submit();
    assert.equal(p.get('err').textContent, message);
    assert.equal('innerHTML' in p.get('err'), false);
    assert.deepEqual(p.writes, []);
    assert.equal(p.get('done').hidden, true);
  }
});

test('code manuel et prénom vides : aucun POST', async () => {
  const p = page('/p', () => assert.fail('POST inattendu'));
  await p.submit();
  assert.equal(p.get('err').textContent, 'Le code fait 6 chiffres.');
  p.get('code').value = '123456';
  p.get('name').value = '';
  await p.submit();
  assert.equal(p.get('err').textContent, 'Indiquez votre prénom.');
  assert.deepEqual(p.writes, []);
});
