// Statistiques des tickets PapAI (page du support et console de l'organisation) :
// tickets par catégorie et par semaine, temps de résolution, part réglée par un
// automate, exemples cliquables, suggestion d'automate. SVG fait main, sans bibliothèque.
(function () {
  const NS = 'http://www.w3.org/2000/svg';
  const css = document.createElement('style');
  css.textContent = `
    .ps { --ps-card: var(--card, #fff); --ps-ink: var(--ink, #141A2E); --ps-muted: var(--muted, #5B6478);
          --ps-bar: #2F6EF7; --ps-bar-soft: #C9D8FF; --ps-track: #EEF2FB; --ps-line: rgba(20,40,100,.08);
          background: var(--ps-card); color: var(--ps-ink); border-radius: 20px; padding: 16px;
          box-shadow: var(--shadow, 0 1px 2px rgba(25,45,110,.05), 0 8px 24px rgba(30,60,150,.07));
          display: flex; flex-direction: column; gap: 16px; }
    /* Sombre quand la page l'est (data-theme="dark" ou color-scheme dark sur <html>) : les pages actuelles sont claires. */
    :root[data-theme="dark"] .ps, .ps[data-theme="dark"] {
      --ps-card: #171C2E; --ps-ink: #E9EDF8; --ps-muted: #A6AEC4; --ps-bar: #6E9BFF; --ps-bar-soft: #34446E;
      --ps-track: #232A40; --ps-line: rgba(255,255,255,.08); }
    .ps h4 { margin: 0; font-size: 15px; font-weight: 600; color: var(--ps-muted); }
    .ps-kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 10px; }
    .ps-kpi { border-radius: 14px; padding: 10px 12px; box-shadow: inset 0 0 0 1px var(--ps-line); }
    .ps-kpi b { display: block; font-size: 22px; font-variant-numeric: tabular-nums; }
    .ps-kpi span { font-size: 13px; color: var(--ps-muted); }
    .ps svg { display: block; width: 100%; height: auto; overflow: visible; }
    .ps svg text { fill: var(--ps-muted); font: 12px -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; }
    .ps svg .ps-val { fill: var(--ps-ink); font-weight: 600; }
    .ps-cat { display: grid; grid-template-columns: minmax(110px, 38%) 1fr auto; gap: 10px; align-items: center;
              width: 100%; background: none; border: 0; padding: 6px 0; font: inherit; font-size: 15px; color: var(--ps-ink);
              cursor: pointer; text-align: left; min-height: 36px; box-shadow: none; border-radius: 8px; }
    .ps-cat:hover .ps-fill { opacity: .85; }
    .ps-track { height: 12px; border-radius: 6px; background: var(--ps-track); overflow: hidden; }
    .ps-fill { height: 100%; border-radius: 6px; background: var(--ps-bar); }
    .ps-n { font-variant-numeric: tabular-nums; font-weight: 600; min-width: 2ch; text-align: right; }
    .ps-ex { display: flex; flex-wrap: wrap; gap: 6px; margin: 0 0 6px; }
    .ps-ex button { font: inherit; font-size: 13px; border: 0; border-radius: 999px; padding: 4px 10px; min-height: 30px;
                    background: var(--ps-track); color: var(--ps-ink); cursor: pointer; box-shadow: none; max-width: 100%;
                    overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .ps-sug { display: flex; gap: 12px; align-items: center; flex-wrap: wrap; border-radius: 14px; padding: 12px 14px;
              background: var(--ps-track); }
    .ps-sug p { flex: 1; margin: 0; font-weight: 600; min-width: 180px; }
    .ps-sug button, .ps-form button { font: inherit; font-size: 14px; font-weight: 600; border: 0; border-radius: 999px;
              padding: 0 16px; min-height: 40px; cursor: pointer; color: #fff; background: linear-gradient(180deg, #2B6BFF 0%, #1A52E0 100%); }
    .ps-form { display: flex; flex-direction: column; gap: 8px; }
    .ps-form label { font-size: 13px; color: var(--ps-muted); font-weight: 600; }
    .ps-form input, .ps-form textarea { font: inherit; font-size: 15px; border: 0; border-radius: 12px; padding: 10px 12px;
              background: var(--ps-track); color: var(--ps-ink); width: 100%; box-sizing: border-box; }
    .ps-form .ps-row { display: flex; gap: 14px; align-items: center; flex-wrap: wrap; font-size: 15px; }
    .ps-form .ps-light { background: none; color: var(--ps-bar); box-shadow: inset 0 0 0 1.5px var(--ps-bar-soft); }
    .ps-empty { color: var(--ps-muted); font-size: 15px; margin: 0; }
    .ps-line { margin: 0; font-size: 15px; }
    .ps-line b { font-weight: 600; }`;
  document.head.appendChild(css);

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function svg(tag, attrs, text) {
    const e = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs || {})) e.setAttribute(k, v);
    if (text != null) e.textContent = text;
    return e;
  }
  function duration(s) {
    if (s == null) return '—';
    if (s < 3600) return `${Math.max(1, Math.round(s / 60))} min`;
    if (s < 86400) return `${Math.round(s / 3600 * 10) / 10} h`.replace('.', ',');
    return `${Math.round(s / 86400 * 10) / 10} j`.replace('.', ',');
  }
  const day = iso => new Date(iso + 'T00:00:00Z').toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', timeZone: 'UTC' });

  // Barres par semaine : total, la catégorie choisie en plus foncé.
  function weeksChart(weeks, focus) {
    const W = 560, H = 150, pad = 22, n = weeks.length, gap = 8;
    const bw = (W - gap * (n - 1)) / n;
    const max = Math.max(1, ...weeks.map(w => w.total));
    const s = svg('svg', { viewBox: `0 0 ${W} ${H + pad}`, role: 'img',
      'aria-label': 'Tickets par semaine : ' + weeks.map(w => `${day(w.start)} ${w.total}`).join(', ') });
    weeks.forEach((w, i) => {
      const x = i * (bw + gap), h = (w.total / max) * (H - 18), y = H - h;
      const part = focus ? (w.by[focus] || 0) : w.total;
      const hp = (part / max) * (H - 18);
      s.append(svg('rect', { x, y: 0, width: bw, height: H, rx: 6, fill: 'var(--ps-track)' }));
      if (w.total) {
        s.append(svg('rect', { x, y, width: bw, height: h, rx: 6, fill: focus ? 'var(--ps-bar-soft)' : 'var(--ps-bar)' }));
        if (focus && part) s.append(svg('rect', { x, y: H - hp, width: bw, height: hp, rx: 6, fill: 'var(--ps-bar)' }));
        s.append(svg('text', { x: x + bw / 2, y: y - 4, 'text-anchor': 'middle', class: 'ps-val' },
                     focus ? `${part}/${w.total}` : String(w.total)));
      }
      s.append(svg('text', { x: x + bw / 2, y: H + 16, 'text-anchor': 'middle' }, day(w.start)));
    });
    return s;
  }

  // render(box, stats, { onCategory(id|null), onExample(ex), onSuggest(sug), focus, skipCategory })
  // skipCategory : suggestion déjà montrée ailleurs (carte « Cette semaine »), non répétée ici.
  function render(box, st, opts) {
    opts = opts || {};
    box.replaceChildren();
    box.classList.add('ps');
    const tot = st.totals || {};
    if (!tot.count) { box.append(el('h4', '', 'Statistiques'), el('p', 'ps-empty', 'Pas encore de ticket sur ces semaines.')); return; }
    const kpis = el('div', 'ps-kpis');
    const kpi = (v, l) => { const k = el('div', 'ps-kpi'); k.append(el('b', '', v), el('span', '', l)); kpis.append(k); };
    kpi(String(tot.count), `tickets depuis le ${day(st.since)}`);
    kpi(String(tot.resolved), 'résolus');
    kpi(duration(tot.median_resolution_s), 'temps de résolution (médian)');
    kpi(`${Math.round((tot.automate_share || 0) * 100)} %`, 'réglés par un automate');
    box.append(kpis);

    for (const sug of st.suggestions || []) {
      if (opts.skipCategory && sug.category === opts.skipCategory) continue;
      const b = el('div', 'ps-sug');
      const go = el('button', '', 'Créer l’automate'); go.type = 'button';
      go.onclick = () => opts.onSuggest && opts.onSuggest(sug);
      b.append(el('p', '', sug.text), go);
      box.append(b);
    }

    const focus = opts.focus || null;
    const label = (st.labels || []).find(l => l.id === focus);
    box.append(el('h4', '', 'Par semaine' + (label ? ` · ${label.label}` : '')), weeksChart(st.weeks || [], focus));

    box.append(el('h4', '', 'Catégories qui reviennent le plus'));
    const max = Math.max(1, ...(st.categories || []).map(c => c.count));
    for (const c of st.categories || []) {
      const row = el('button', 'ps-cat'); row.type = 'button';
      row.setAttribute('aria-pressed', focus === c.id ? 'true' : 'false');
      row.title = `${c.count} tickets, ${c.resolved} résolus, ${c.by_automate} par un automate, médiane ${duration(c.median_resolution_s)}`;
      const track = el('span', 'ps-track'), fill = el('span', 'ps-fill');
      fill.style.display = 'block'; fill.style.width = `${(c.count / max) * 100}%`;
      if (focus && focus !== c.id) fill.style.opacity = '.35';
      track.append(fill);
      row.append(el('span', '', c.label), track, el('span', 'ps-n', String(c.count)));
      row.onclick = () => opts.onCategory && opts.onCategory(focus === c.id ? null : c.id);
      box.append(row);
      if (!focus || focus === c.id) {
        const ex = el('div', 'ps-ex');
        for (const e of c.examples || []) {
          const b = el('button', '', `« ${e.task} »`); b.type = 'button';
          b.title = (e.poste ? e.poste + ' · ' : '') + `T-${String(e.number).padStart(4, '0')}`;
          b.onclick = () => opts.onExample && opts.onExample(e);
          ex.append(b);
        }
        if (ex.childElementCount) box.append(ex);
      }
    }
  }

  // Carte « Cette semaine » : `stats.week` (7 derniers jours). onSuggest(sug) comme render.
  function renderSuggestion(box, w, opts) {
    if (!w.suggestion) return;
    const b = el('div', 'ps-sug');
    const go = el('button', '', 'Créer l’automate'); go.type = 'button';
    go.onclick = () => opts.onSuggest && opts.onSuggest(w.suggestion);
    b.append(el('p', '', w.suggestion.text), go);
    box.append(b);
  }

  function renderWeek(box, st, opts) {
    opts = opts || {};
    const w = (st && st.week) || {};
    box.replaceChildren();
    box.classList.add('ps');
    box.append(el('h4', '', 'Cette semaine'));
    if (!w.count && !w.resolved) { box.append(el('p', 'ps-empty', 'Aucune demande ces 7 derniers jours.')); renderSuggestion(box, w, opts); return; }
    const kpis = el('div', 'ps-kpis');
    const kpi = (v, l) => { const k = el('div', 'ps-kpi'); k.append(el('b', '', v), el('span', '', l)); kpis.append(k); };
    kpi(String(w.count || 0), 'demandes reçues');
    kpi(String(w.resolved || 0), 'réglées');
    kpi(`${Math.round((w.automate_share || 0) * 100)} %`, 'réglées par un automate');
    kpi(duration(w.mean_resolution_s), 'temps moyen');
    box.append(kpis);
    if ((w.top || []).length) {
      const p = el('p', 'ps-line'); p.append(el('b', '', 'En tête : '),
        w.top.map(c => `${c.label} (${c.count})`).join(', '));
      box.append(p);
    }
    const a = w.automate;
    const p = el('p', 'ps-line');
    p.append(el('b', '', 'Automate le plus utile : '),
      a ? `« ${a.title} », ${a.count} demande${a.count > 1 ? 's' : ''} réglée${a.count > 1 ? 's' : ''}` : 'aucun cette semaine');
    box.append(p);
    renderSuggestion(box, w, opts);
  }

  // Formulaire d'automate prérempli. submit(pack) → Promise<{ok, error}>
  function draftForm(box, draft, publisher, submit) {
    box.replaceChildren();
    box.classList.add('ps');
    const f = el('form', 'ps-form');
    const field = (l, tag, v) => { const i = el(tag); i.value = v || ''; const w = el('label', '', l); f.append(w, i); return i; };
    f.append(el('h4', '', 'Créer un automate'));
    const title = field('Titre', 'input', draft.title);
    const desc = field('Description', 'textarea', draft.description); desc.rows = 3;
    const goal = field('Ce que Holo fait', 'textarea', draft.goal); goal.rows = 2;
    const steps = field('Pas à pas (une étape par ligne, facultatif)', 'textarea', ''); steps.rows = 3;
    const plat = el('div', 'ps-row');
    const mac = el('input'); mac.type = 'checkbox'; mac.checked = true;
    const win = el('input'); win.type = 'checkbox'; win.checked = true;
    const lm = el('label'); lm.append(mac, ' Mac'); const lw = el('label'); lw.append(win, ' Windows');
    plat.append(lm, lw); f.append(plat);
    const err = el('p', 'ps-empty'); err.hidden = true;
    const row = el('div', 'ps-row');
    const ok = el('button', '', 'Créer'); ok.type = 'submit';
    const cancel = el('button', 'ps-light', 'Annuler'); cancel.type = 'button';
    cancel.onclick = () => { box.replaceChildren(); box.hidden = true; };
    row.append(ok, cancel); f.append(err, row);
    f.onsubmit = async ev => {
      ev.preventDefault();
      const s = steps.value.split('\n').map(x => x.trim()).filter(Boolean);
      const platforms = [mac.checked && 'mac', win.checked && 'windows'].filter(Boolean);
      if (!title.value.trim() || !goal.value.trim() || !platforms.length) {
        err.textContent = 'Un titre, ce que Holo fait, et au moins Mac ou Windows.'; err.hidden = false; return;
      }
      ok.disabled = true;
      const r = await submit({ papai: 1, title: title.value.trim(), description: desc.value.trim(), publisher,
        platforms, actions: [{ do: 'holo', goal: goal.value.trim(), steps: s }], steps: s.map(i => ({ instruction: i })) });
      ok.disabled = false;
      if (r && r.ok) { box.replaceChildren(); box.hidden = true; } else { err.textContent = (r && r.error) || 'Création refusée.'; err.hidden = false; }
    };
    box.append(f);
    box.hidden = false;
    title.focus();
  }

  window.PapaiStats = { render, renderWeek, draftForm, duration };
})();
