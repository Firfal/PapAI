// Tickets PapAI : liste commune à la page du support et à celle de l'organisation.
(function () {
  const STATUS = {
    nouveau: 'Nouveau', en_attente: "En attente d'un support", rdv: 'Rendez-vous',
    en_cours: 'En cours', a_reprendre: 'À reprendre', resolu: 'Résolu',
  };
  const SOURCE = { personne: 'Demandé par la personne', support: 'Proposé par le support', automatisme: 'Automatisme' };
  const OPEN = ['nouveau', 'en_attente', 'rdv', 'a_reprendre'];

  const css = document.createElement('style');
  css.textContent = `
    .tk { background: var(--card, #fff); border-radius: 18px; padding: 14px 16px; display: flex; flex-direction: column; gap: 6px; }
    .tk + .tk { margin-top: 10px; }
    .tk-head { display: flex; gap: 8px; align-items: baseline; flex-wrap: wrap; }
    .tk-num { font-weight: 700; } .tk-task { font-weight: 600; }
    .tk-st { font-size: 13px; font-weight: 600; padding: 2px 10px; border-radius: 999px; background: var(--bg, #EEF0EE); }
    .tk-st.en_attente, .tk-st.a_reprendre, .tk-st.nouveau { background: #FCE8E6; color: #B3261E; }
    .tk-st.rdv { background: #FFF4D6; color: #7A5B00; } .tk-st.en_cours { background: var(--mint, #E2F2E7); color: var(--accent, #2E9E5B); }
    .tk-meta { font-size: 14px; color: var(--muted, #7A807C); }
    .tk-notes { font-size: 14px; margin: 0; padding-left: 18px; }
    .tk-acts { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 4px; }
    .tk-acts button { font: inherit; font-size: 14px; font-weight: 600; border: 0; border-radius: 999px; padding: 7px 14px;
                      cursor: pointer; background: var(--mint, #E2F2E7); color: var(--accent, #2E9E5B); width: auto; min-height: 0; }
    .tk-acts input { font: inherit; font-size: 14px; border-radius: 10px; border: 1px solid #ccc; padding: 5px 8px; }`;
  document.head.appendChild(css);

  const when = s => new Date(s * 1000).toLocaleString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  const num = t => `T-${String(t.number).padStart(4, '0')}`;
  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function meta(t) {
    const m = [SOURCE[t.source] || t.source, when(t.created)];
    if (t.poste) m.unshift(t.poste);
    if (t.status === 'rdv' && t.rdv) m.push(`rendez-vous ${when(t.rdv)}`);
    if (t.assignee) m.push(`pris par ${t.assignee}`);
    if (t.helper) m.push(`aidé par ${t.helper}`);
    if (t.plan && t.plan.length) m.push(`${Math.min(t.steps_done || 0, t.plan.length)}/${t.plan.length} étapes`);
    if (t.stopped_by && t.status !== 'resolu') m.push(`arrêté (${t.stopped_by === 'senior' ? 'la personne' : t.stopped_by})`);
    if (t.closed_by) m.push(`clos par ${t.closed_by}`);
    return m.join(' · ');
  }

  // act(ticket, action, extra) → Promise<{ok, error}>
  function render(box, list, act) {
    box.replaceChildren();
    if (!list.length) { box.append(el('p', 'tk-meta', 'Aucun ticket.')); return; }
    for (const t of list) {
      const c = el('div', 'tk');
      const head = el('div', 'tk-head');
      head.append(el('span', 'tk-num', num(t)), el('span', 'tk-st ' + t.status, STATUS[t.status] || t.status),
                  el('span', 'tk-task', t.task || '(sans texte)'));
      c.append(head, el('div', 'tk-meta', meta(t)));
      if (t.notes && t.notes.length) {
        const ul = el('ul', 'tk-notes');
        for (const n of t.notes.slice(-3)) ul.append(el('li', '', `${n.by ? n.by + ' : ' : ''}${n.text}`));
        c.append(ul);
      }
      const acts = el('div', 'tk-acts');
      const btn = (label, fn) => { const b = el('button', '', label); b.type = 'button'; b.onclick = fn; acts.append(b); };
      if (OPEN.includes(t.status)) {
        btn('Prendre', () => act(t, 'take'));
        btn('Rendez-vous', () => {
          if (acts.querySelector('input')) return;
          const i = el('input'); i.type = 'datetime-local';
          const ok = el('button', '', 'Fixer'); ok.type = 'button';
          ok.onclick = () => { const at = Date.parse(i.value) / 1000; if (at) act(t, 'schedule', { at }); };
          acts.append(i, ok);
        });
      }
      if (t.status !== 'en_cours' && t.status !== 'resolu') btn('Clore', () => act(t, 'close', { text: prompt('Résolution (facultatif) :') || '' }));
      if (t.status === 'resolu') btn('Rouvrir', () => act(t, 'reopen'));
      btn('Note', () => { const text = prompt('Note pour ce ticket :'); if (text) act(t, 'note', { text }); });
      c.append(acts);
      box.append(c);
    }
  }

  function csv(list) {
    const cols = [['Ticket', num], ['Poste', t => t.poste || ''], ['Statut', t => STATUS[t.status] || t.status],
      ['Demande', t => t.task], ['Source', t => SOURCE[t.source] || t.source], ['Créé', t => new Date(t.created * 1000).toISOString()],
      ['Mis à jour', t => new Date(t.updated * 1000).toISOString()], ['Rendez-vous', t => t.rdv ? new Date(t.rdv * 1000).toISOString() : ''],
      ['Pris par', t => t.assignee || ''], ['Aidé par', t => t.helper || ''],
      ['Étapes', t => (t.plan || []).length ? `${t.steps_done || 0}/${t.plan.length}` : ''],
      ['Arrêté par', t => t.stopped_by || ''], ['Clos par', t => t.closed_by || ''],
      ['Notes', t => (t.notes || []).map(n => `${n.by}: ${n.text}`).join(' | ')]];
    const q = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
    return [cols.map(c => q(c[0])).join(';'), ...list.map(t => cols.map(c => q(c[1](t))).join(';'))].join('\r\n');
  }

  window.PapaiTickets = { render, csv, OPEN, STATUS };
})();
