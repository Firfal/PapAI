// Tickets PapAI : liste commune à la page du support et à celle de l'organisation.
(function () {
  const STATUS = {
    nouveau: 'Nouveau', en_attente: "En attente d'un support", rdv: 'Rendez-vous',
    en_cours: 'En cours', a_reprendre: 'À reprendre', plan_valide: 'Plan validé', resolu: 'Résolu',
  };
  const SOURCE = { personne: 'Demandé par l’utilisateur', support: 'Proposé par le support', automatisme: 'Automate' };
  const OPEN = ['nouveau', 'en_attente', 'rdv', 'a_reprendre', 'plan_valide'];
  const CATEGORY = {
    wifi: 'Wi-Fi et réseau', imprimante: 'Imprimante', comptes: 'Comptes et mots de passe', logiciels: 'Logiciels',
    messagerie: 'Messagerie', fichiers: 'Fichiers', securite: 'Sécurité', autre: 'Autre',
  };
  const CATEGORY_BY = { regles: 'catégorie choisie par les règles', holo: 'catégorie choisie par Holo',
    support: 'catégorie corrigée par le support', doute: 'catégorie à vérifier' };

  const css = document.createElement('style');
  css.textContent = `
    .tk { background: var(--card, #fff); border-radius: 20px; padding: 16px; display: flex; flex-direction: column; gap: 8px;
          box-shadow: var(--shadow, 0 1px 2px rgba(25,45,110,.05), 0 8px 24px rgba(30,60,150,.07)); }
    .tk + .tk { margin-top: 12px; }
    .tk-head { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
    .tk-num { font-weight: 600; font-size: 14px; color: var(--muted, #5B6478); font-variant-numeric: tabular-nums; }
    .tk-task { font-weight: 600; flex-basis: 100%; font-size: 17px; }
    .tk-st { font-size: 13px; font-weight: 600; padding: 3px 9px; border-radius: 7px; background: #EEF0F5; color: #4A5263; }
    .tk-st.nouveau { background: #E6EEFF; color: #1F4FD1; }
    .tk-st.en_attente, .tk-st.a_reprendre { background: #FFF0DE; color: #9A4A00; }
    .tk-st.rdv { background: #F1EBFF; color: #6236C9; }
    .tk-st.plan_valide { background: #E5F5EC; color: #1B7A43; }
    .tk-st.en_cours { background: #E6EEFF; color: #1F4FD1; box-shadow: inset 0 0 0 1px rgba(31,79,209,.25); }
    .tk-st.resolu { background: #E5F5EC; color: #1B7A43; }
    .tk-cat { font-size: 13px; font-weight: 600; padding: 3px 9px; border-radius: 7px; background: var(--sky, #EAF0FF);
              color: var(--accent, #1F5AE8); }
    .tk-cat.doute { background: transparent; box-shadow: inset 0 0 0 1px rgba(31,90,232,.35); }
    .tk.tk-focus { box-shadow: 0 0 0 3px rgba(43,107,255,.55), var(--shadow, 0 8px 24px rgba(30,60,150,.07)); }
    .tk-acts select { font: inherit; font-size: 14px; min-height: 44px; border-radius: 999px; border: 0; padding: 0 12px;
                      background: var(--field, #F1F3F9); color: var(--ink, #141A2E); }
    .tk-meta { font-size: 14px; color: var(--muted, #5B6478); }
    .tk-notes { font-size: 14px; margin: 0; padding: 8px 12px 8px 28px; border-radius: 12px; background: var(--field, #F1F3F9); }
    .tk-acts { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 4px; padding-top: 12px;
               border-top: 1px solid var(--line, rgba(20,40,100,.08)); }
    .tk-acts button { font: inherit; font-size: 14px; font-weight: 600; border: 0; border-radius: 999px; padding: 0 16px;
                      cursor: pointer; background: var(--sky, #EAF0FF); color: var(--accent, #1F5AE8); width: auto; min-height: 44px; }
    .tk-proposal, .tk-decision { padding: 10px 12px; border-radius: 12px; background: var(--field, #F1F3F9); }
    .tk-proposal ol { margin: 6px 0; padding-left: 24px; }
    .tk-proposal-warning { color: #9A4A00; font-weight: 600; }
    .tk-live-slots { display: flex; gap: 6px; flex-wrap: wrap; }
    /* Tickets ouverts : « Prendre » est l'action principale. */
    .tk:has(.tk-st.nouveau, .tk-st.en_attente, .tk-st.rdv, .tk-st.a_reprendre, .tk-st.plan_valide) .tk-acts button:first-child { background: linear-gradient(180deg, #2B6BFF 0%, #1A52E0 100%); color: #fff;
                                  box-shadow: 0 4px 12px rgba(31,90,232,.25); }
    .tk-acts input { font: inherit; font-size: 15px; min-height: 44px; border-radius: 12px; border: 0; padding: 0 12px;
                     background: var(--field, #F1F3F9); color: var(--ink, #141A2E); box-shadow: inset 0 0 0 1px var(--line, rgba(20,40,100,.08)); }`;
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
    if (t.blocked && t.blocked.step) m.push(`bloqué à l’étape ${t.blocked.step}${t.blocked.label ? ` (${t.blocked.label})` : ''}${t.blocked.reason ? ` : ${t.blocked.reason}` : ''}`);
    else if (t.stopped_by && t.status !== 'resolu') m.push(`arrêté (${t.stopped_by === 'senior' ? 'la personne' : t.stopped_by})`);
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
      const cat = CATEGORY[t.category] ? t.category : 'autre';
      const chip = el('span', 'tk-cat' + (t.category_by === 'doute' ? ' doute' : ''),
                      CATEGORY[cat] + (t.category_by === 'doute' ? ' ?' : ''));
      chip.title = CATEGORY_BY[t.category_by] || '';
      c.id = 'tk-' + t.id;
      head.append(el('span', 'tk-num', num(t)), el('span', 'tk-st ' + t.status, STATUS[t.status] || t.status), chip,
                  el('span', 'tk-task', t.task || '(sans texte)'));
      c.append(head, el('div', 'tk-meta', meta(t)));
      if (Array.isArray(t.suggestions) && t.suggestions.length) {
        const suggestions = el('div', 'tk-meta', '');
        for (const suggestion of t.suggestions) {
          if (!suggestion || !suggestion.title) continue;
          const state = suggestion.id === t.suggestion_lancee ? 'lancé' : 'pas lancé';
          suggestions.append(el('div', '', `Automate proposé : ${suggestion.title} · ${state}`));
        }
        c.append(suggestions);
      }
      if (t.linkup_answer) {
        c.append(el('p', 'tk-meta', t.linkup_answer.content || ''));
        for (const s of t.linkup_answer.sources || []) {
          if (!/^https?:\/\//.test(s.url || '')) continue;
          const a = el('a', 'tk-meta', s.name || s.url);
          a.href = s.url; a.target = '_blank'; a.rel = 'noopener noreferrer'; c.append(a);
        }
      }
      if (t.proposal && typeof t.proposal === 'object') {
        const proposal = el('div', 'tk-proposal');
        proposal.append(el('strong', '', t.proposal.title || 'Plan proposé par Holo'));
        if (Array.isArray(t.proposal.steps) && t.proposal.steps.length) {
          const steps = el('ol');
          for (const step of t.proposal.steps) steps.append(el('li', '', step));
          proposal.append(steps);
        }
        if (t.proposal.warning) proposal.append(el('div', 'tk-proposal-warning', t.proposal.warning));
        c.append(proposal);
      }
      if (t.decision && typeof t.decision === 'object') {
        const decision = el('div', 'tk-decision');
        if (t.decision.kind === 'plan') {
          decision.append(el('strong', '', `Plan validé par ${t.decision.by || 'le support'}`));
          if (Array.isArray(t.decision.steps) && t.decision.steps.length) {
            const steps = el('ol');
            for (const step of t.decision.steps) steps.append(el('li', '', step));
            decision.append(steps);
          }
        } else if (t.decision.kind === 'live') {
          decision.append(el('strong', '', 'Assistance en direct obligatoire'));
          if (t.decision.rdv || t.rdv) decision.append(el('div', '', `Rendez-vous choisi : ${when(t.decision.rdv || t.rdv)}`));
          else if (t.decision.other) decision.append(el('div', '', 'Aucun créneau ne convient.'));
          else {
            decision.append(el('div', '', 'Créneaux proposés :'));
            const slots = el('div', 'tk-live-slots');
            for (const at of t.decision.slots || []) slots.append(el('span', '', when(at)));
            decision.append(slots);
          }
        }
        c.append(decision);
      }
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
        if (t.proposal && typeof t.proposal === 'object') {
          if (Array.isArray(t.proposal.steps) && t.proposal.steps.length)
            btn('Valider', () => act(t, 'validate'));
          btn('Préciser', () => {
            const text = prompt('Que faut-il préciser à Holo ?');
            if (text && text.trim()) act(t, 'refine', { text: text.trim() });
          });
        } else if (!t.proposal) {
          btn('Proposer un plan', () => act(t, 'draft'));
        }
        btn('Assistance en direct obligatoire', () => {
          if (acts.querySelector('.tk-live-form')) return;
          const form = el('div', 'tk-live-form');
          const inputs = [];
          const addSlot = () => {
            if (inputs.length >= 3) return;
            const input = el('input'); input.type = 'datetime-local'; input.required = true;
            inputs.push(input); form.append(input);
          };
          addSlot();
          const add = el('button', '', 'Ajouter un créneau'); add.type = 'button';
          add.onclick = () => { addSlot(); add.hidden = inputs.length >= 3; };
          const propose = el('button', '', 'Proposer'); propose.type = 'button';
          propose.onclick = () => {
            const slots = inputs.map(i => Date.parse(i.value) / 1000);
            if (slots.some(x => !Number.isFinite(x))) return;
            act(t, 'live', { slots });
          };
          form.append(add, propose);
          acts.append(form);
        });
      }
      if (t.status !== 'en_cours' && t.status !== 'resolu') btn('Clore', () => act(t, 'close', { text: prompt('Résolution (facultatif) :') || '' }));
      if (t.status === 'resolu') btn('Rouvrir', () => act(t, 'reopen'));
      btn('Note', () => { const text = prompt('Note pour ce ticket :'); if (text) act(t, 'note', { text }); });
      const sel = el('select');
      sel.setAttribute('aria-label', 'Catégorie du ticket');
      for (const [k, v] of Object.entries(CATEGORY)) { const o = el('option', '', v); o.value = k; sel.append(o); }
      sel.value = cat;
      sel.onchange = () => act(t, 'category', { category: sel.value });
      acts.append(sel);
      c.append(acts);
      box.append(c);
    }
  }

  function csv(list) {
    const cols = [['Ticket', num], ['Poste', t => t.poste || ''], ['Statut', t => STATUS[t.status] || t.status],
      ['Demande', t => t.task], ['Catégorie', t => CATEGORY[t.category] || ''], ['Source', t => SOURCE[t.source] || t.source], ['Créé', t => new Date(t.created * 1000).toISOString()],
      ['Mis à jour', t => new Date(t.updated * 1000).toISOString()], ['Rendez-vous', t => t.rdv ? new Date(t.rdv * 1000).toISOString() : ''],
      ['Pris par', t => t.assignee || ''], ['Utilisateur par', t => t.helper || ''],
      ['Étapes', t => (t.plan || []).length ? `${t.steps_done || 0}/${t.plan.length}` : ''],
      ['Arrêté par', t => t.stopped_by || ''],
      ['Décision', t => {
        const d = t.decision || {};
        if (d.kind === 'plan') return `Plan validé par ${d.by || 'le support'}`;
        if (d.kind === 'live') return d.rdv || t.rdv ? `Assistance en direct · rendez-vous ${when(d.rdv || t.rdv)}`
          : d.other ? 'Assistance en direct · aucun créneau ne convient'
            : `Assistance en direct · ${(d.slots || []).map(when).join(', ')}`;
        return '';
      }],
      ['Bloqué à', t => t.blocked && t.blocked.step ? `${t.blocked.step}. ${t.blocked.label || ''} ${t.blocked.reason || ''}`.trim() : ''], ['Clos par', t => t.closed_by || ''],
      ['Notes', t => (t.notes || []).map(n => `${n.by}: ${n.text}`).join(' | ')]];
    // Une case qui commence par = + - @ serait lue comme une formule par le tableur.
    const q = v => `"${String(v ?? '').replace(/^[=+\-@\t\r]/, "'$&").replace(/"/g, '""')}"`;
    return [cols.map(c => q(c[0])).join(';'), ...list.map(t => cols.map(c => q(c[1](t))).join(';'))].join('\r\n');
  }

  window.PapaiTickets = { render, csv, OPEN, STATUS, CATEGORY };
})();
