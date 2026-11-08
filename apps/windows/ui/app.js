/* Les écrans de l'app Mac (apps/mac/Sources/*View.swift), à l'identique.
   L'état vient de Python (papai/model.py) par PapAI.update(snapshot) ;
   les gestes repartent par window.pywebview.api.<méthode>. */
(function () {
  'use strict';
  let S = null;
  let api = null;
  const ui = { request: '', warning: null, lessonId: null, lessonIndex: 0,
               sheet: null, lastDictMsg: null,
               writing: false, dictating: false, lastDictation: null, submitting: false, editingShortcuts: false };

  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  // rounded(size, weight) de Theme.swift : 4 regular, 5 medium, 6 semibold, 7 bold
  const f = (size, w) => `font-size:max(15px, calc(${size}px * var(--ts)));font-weight:${(w || 5) * 100};`;
  const cap = (s) => s ? s.charAt(0).toUpperCase() + s.slice(1) : s;

  function call(name, ...args) {
    if (api && typeof api[name] === 'function') return api[name](...args);
    if (preview[name]) preview[name](...args);
  }

  // ---------------------------------------------------------------- briques
  const pill = (label, act, o = {}) =>
    `<button class="pill ${o.filled === false ? 'plain' : 'filled'} ${o.grow ? 'grow' : ''}" data-act="${act}"
      ${o.arg != null ? `data-arg="${esc(o.arg)}"` : ''} ${o.disabled ? 'disabled' : ''}
      style="height:${o.height || 64}px;${f(20, 6)}">${label}</button>`;

  const mint = (inner, pad, gap) =>
    `<div class="mintCard" style="padding:${pad}px;gap:${gap}px">${inner}</div>`;

  const promise = (sym, text, size) =>
    `<div class="row" style="gap:16px">
       <div style="width:34px;display:flex;justify-content:center;color:var(--accent)">${icon(sym, 26)}</div>
       <div style="${f(size, 5)}">${esc(text)}</div></div>`;

  // ------------------------------------------------------------------ Header
  // Chaque écran pose son titre dans l'en-tête bleu (hd), comme la maquette :
  // pastille, titre blanc, sous-titre, puis le champ de demande s'il existe.
  let hd = null;
  const hdTitle = (text, size, w) => `<div class="hdrTitle" style="${f(size || 40, w || 6)};letter-spacing:-0.6px;line-height:1.1">${text}</div>`;
  const hdSub = (text, size) => `<div class="hdrSub" style="${f(size || 20, 5)}">${text}</div>`;
  const hdChip = (sym, text) => `<div class="pillChip chip-blue" style="align-self:flex-start;gap:8px;padding:8px 16px;${f(16, 6)}">${sym ? icon(sym, 20) : ''}<span>${text}</span></div>`;
  function header() {
    const h = hd || {};
    return `<div class="hdr${h.tone === 'danger' ? ' danger' : ''}${h.home ? ' hdrHome' : ''}">
      <div class="row hdrTop">
      <img class="logotype" src="logotype-papai.svg" alt="papai">
      <div class="spacer"></div>
      ${S.connected ? '' : `<div class="pillChip chip-gray" style="gap:10px;padding:11px 18px">
        <span class="dot" style="background:#7A8296"></span>
        <span style="${f(16, 5)}">Pas de connexion pour le moment</span>
      </div>`}
      ${h.home ? `<button class="pillChip chip-blue press" data-act="openRequests" style="padding:10px 16px;min-height:44px;${f(16, 6)}">Mes demandes</button>` : ''}
      <button class="circle press" data-act="openSettings" aria-label="Réglages"
        style="width:44px;height:44px">${icon('gear', 20)}</button>
      </div>
      ${h.title ? `<div class="col hdrBody">${h.chip || ''}${h.title}${h.sub || ''}${h.extra || ''}</div>` : ''}
    </div>`;
  }

  // -------------------------------------------------------------------- Home
  // Accueil du Mac (HomeView.swift) : en-tête bleu avec salutation et barre de
  // demande (petit micro intégré), puis deux colonnes 60/40, automates et raccourcis.
  function home() {
    const mic = S.microPresent;
    const ph = S.dictation.phase;
    const busy = ui.dictating || ph !== 'idle';
    const wait = S.queued && !S.queued.show ? `<button class="pillChip chip-orange press" data-act="openQueued" style="align-self:flex-start;gap:8px;padding:0 18px;min-height:44px;${f(17, 6)}">
        ${icon('personWave', 20)}<span>Demande n° ${esc(S.queued.number)} ${S.queued.rdv ? '· rendez-vous ' + esc(rdvText(S.queued.rdv)) : 'en attente'}</span></button>` : '';
    const warn = ui.warning ? `<div class="row homeWarn" style="gap:8px;${f(17, 6)}">${icon('exclam', 20)}<span>${esc(ui.warning)}</span></div>` : '';
    const etat = ph === 'listening' ? 'Je vous écoute… Touchez le carré quand vous avez fini.'
      : ph === 'transcribing' || ph === 'starting' ? 'Je note…' : '';
    const field = `<div class="requestRow homeBar">
        <span class="fieldIcon">${icon('compose', 18)}</span>
        <textarea id="req" rows="1" placeholder="${mic ? 'Écrivez ou dites ce que vous voulez faire' : 'Écrivez ce que vous voulez faire'}" aria-label="Ma demande"
          style="${f(18, 5)};line-height:1.3">${esc(ui.request)}</textarea>
        ${mic ? micButton() : ''}
        <button class="pill filled" data-act="submit" ${busy || ui.submitting ? 'disabled' : ''} style="height:44px;padding:0 18px;${f(16, 6)}">Envoyer</button>
      </div>`;
    hd = {
      home: true,
      title: `<div class="hdrTitle" style="${f(34, 7)};letter-spacing:-0.6px;line-height:1.1">${(h => (h >= 19 || h < 5) ? "Bonsoir" : "Bonjour")(new Date().getHours())}${S.firstName ? ' ' + esc(S.firstName) + ' !' : ''}</div>`,
      sub: hdSub('Que voulez-vous faire ?', 19),
      extra: field + (etat ? `<div class="hdrSub" style="padding-left:18px;${f(17, 6)}">${etat}</div>` : '')
        + (warn || wait ? `<div class="row" style="gap:10px;flex-wrap:wrap">${warn}${wait}</div>` : ''),
    };
    return `<div class="homeCols">
      <section class="col homeLeft">${tutorials()}</section>
      <section class="col homeRight">${appsGrid()}</section></div>`;
  }

  // Titre de section, le même dans les deux colonnes pour qu'ils tombent sur la même ligne.
  const sectionTitle = (sym, text, extra) => `<div class="row sectionTitle" style="gap:10px;min-height:44px">
      <span class="accent" style="width:26px;display:flex;justify-content:center" aria-hidden="true">${icon(sym, 22)}</span>
      <h2 class="grow" style="margin:0;${f(22, 7)}">${text}</h2>${extra || ''}</div>`;

  // Petit micro dans la barre : la même dictée qu'avant, juste plus discrète.
  function micButton() {
    const ph = S.dictation.phase;
    const listening = ph === 'listening';
    const inner = ph === 'transcribing' || ph === 'starting' ? '<div class="spinner small"></div>'
      : icon(listening ? 'stop' : 'mic', 16, listening ? '#fff' : 'var(--accent)');
    return `<button class="press micMini" data-act="mic" ${ph === 'transcribing' || ph === 'starting' ? 'disabled' : ''}
        aria-label="${listening ? 'Arrêter la dictée' : 'Dicter ma demande'}" title="${listening ? 'Arrêter la dictée' : 'Dicter ma demande'}">
        ${listening ? '<span class="micRing"></span>' : ''}<span class="circle microDisc${listening ? ' on' : ''}">${inner}</span></button>`;
  }

  const folderIcon = (folder) => ({ pictures: 'photo', documents: 'doc', downloads: 'download',
    desktop: 'desktop', videos: 'film', music: 'music' }[String(folder || '').toLowerCase()] || 'list');

  const lessonIcon = (l) => !l.shortcut && (l.actions || []).length ? 'wand' : folderIcon((l.shortcut || {}).folder);
  function runCell(l) {
    const st = S.runStatus && S.runStatus.id === l.id ? S.runStatus : null;
    if (!st) {
      return `<button class="press accent softChip" data-act="run" data-arg="${esc(l.id)}" aria-label="Exécuter ${esc(l.title)}" style="${f(15, 6)}">Exécuter</button>`;
    }
    const stopped = st.text === 'Arrêté';
    const chip = `<span class="pillChip ${st.running ? 'chip-blue' : stopped ? 'chip-gray' : 'chip-green'}" role="status" aria-label="${esc(st.text)}"
        style="gap:6px;min-height:44px;padding:0 14px;white-space:nowrap;${f(15, 6)}">
        ${st.running ? '<span class="spinner small"></span>' : icon(stopped ? 'stopCircle' : 'checkCircle', 18)}${esc(st.text)}</span>`;
    // Sur Windows, Arrêter reste à portée de clic pendant qu'un automate tourne.
    const stop = st.running ? `<button class="circle press stopBtn" data-act="stop" aria-label="Arrêter l'automate (Échap)" title="Arrêter"
        style="width:44px;height:44px">${icon('stop', 16, '#fff')}</button>` : '';
    return chip + stop;
  }
  function tutorials() {
    const notice = S.notice ? `<div class="row accent" style="gap:10px;background:var(--mint);border-radius:var(--r);padding:18px;${f(17, 5)}">${icon('info', 20)}<span>${esc(S.notice)}</span></div>` : '';
    const tiles = S.lessons.map((l) => `<div class="row lessonRow" style="padding:10px 14px;gap:10px">
        <button class="row press grow" data-act="doc" data-arg="${esc(l.id)}" aria-label="Voir l'automate ${esc(l.title)}" style="gap:12px;text-align:left;min-height:44px">
          <span class="circle" style="width:40px;height:40px;background:var(--mint);color:var(--accentIcon)">${icon(lessonIcon(l), 20)}</span>
          <span class="col" style="gap:3px"><span style="${f(18, 6)}">${esc(l.title)}</span>${l.publisher ? `<span class="muted" style="${f(14, 4)}">${esc('Fourni par ' + l.publisher)}</span>` : ''}</span>
        </button>${runCell(l)}
      </div>`).join('');
    const assist = S.automationRun && S.automationRun.local ? assistButton() : '';
    const list = S.lessons.length ? `<div class="card listCard">${tiles}</div>`
      : `<div class="card col" style="padding:20px;gap:6px"><div style="${f(18, 6)}">Aucun automate pour l'instant.</div>
          <div class="muted" style="${f(17, 4)}">Un automate est une tâche toute prête. Quand ${esc(S.helperName)} en enregistre un pour vous, il apparaît ici et se lance d'un clic.</div></div>`;
    return `${sectionTitle('wand', 'Mes automates')}${assist ? `<div class="row" style="justify-content:flex-end">${assist}</div>` : ''}${notice}${list}`;
  }

  // L'automate ouvert depuis « Mes automates » (LessonDocView du Mac).
  function docSheet() {
    const l = (S.lessons || []).find((x) => x.id === ui.docId);
    if (!l) return '';
    const steps = (l.steps || []).map((x) => x.instruction || x).filter(Boolean);
    const list = steps.map((t, i) => `<div class="row" style="gap:12px;align-items:flex-start">
        <span class="docNum" style="${f(16, 6)}">${i + 1}</span><span style="padding-top:4px;${f(18, 5)}">${esc(t)}</span></div>`).join('');
    return `<div class="sheet col" role="dialog" aria-modal="true" aria-label="Automate ${esc(l.title)}" style="width:620px;padding:32px;gap:18px;background:var(--card)">
      <div class="sheetHead row" style="gap:14px;align-items:flex-start">
        <div class="col grow" style="gap:6px"><div style="${f(15, 6)};opacity:.85">Automate</div>
          <div style="${f(30, 7)};letter-spacing:-0.4px">${esc(l.title)}</div>
          ${l.publisher ? `<div style="${f(15, 4)};opacity:.85">${esc('Fourni par ' + l.publisher)}</div>` : ''}</div>
        <button class="circle press" data-act="closeSheet" aria-label="Fermer" style="width:44px;height:44px;background:rgba(255,255,255,.18);color:#fff">${icon('xmark', 18)}</button>
      </div>
      <div class="col scroll" style="gap:18px">
        ${l.description ? `<div style="${f(19, 5)}">${esc(l.description)}</div>` : ''}
        ${steps.length ? `<div class="muted" style="${f(17, 6)}">Les étapes</div><div class="col" style="gap:12px">${list}</div>` : ''}
      </div>
      <div class="row" style="gap:12px">
        ${steps.length ? pill('Montrez-moi', 'docLesson', { filled: false, height: 58, grow: true }) : ''}
        <button class="pill filled press grow row" data-act="docRun" style="height:58px;gap:10px;${f(20, 6)}">${icon('play', 20, '#fff')}<span>Exécuter</span></button>
      </div></div>`;
  }

  const APP_STYLE = {
    Mail: ['mail', 'linear-gradient(180deg,#4FA3F7,#1C6FE0)'],
    Photos: ['photos', 'linear-gradient(180deg,#FF9F6B,#E8457A)'],
    Internet: ['globe', 'linear-gradient(180deg,#38C7C9,#1677D2)'],
    Visio: ['video', 'linear-gradient(180deg,#5BD47E,#23A55A)'],
    Explorateur: ['folder', 'linear-gradient(180deg,#FFD15C,#F2A922)'],
    Calendrier: ['calendar', 'linear-gradient(180deg,#FF7A70,#E2403A)'],
  };

  function appsGrid() {
    const items = (S.homeShortcuts || []).map((a) => {
      const img = a.icon && a.icon.startsWith('data:image/png;base64,') ? `<img src="${esc(a.icon)}" alt="" width="48" height="48">`
        : icon(a.symbol || (APP_STYLE[a.label] || ['app'])[0], 30, 'var(--accentIcon)');
      return `<div class="col" style="position:relative"><button class="col press" data-act="homeShortcut" data-arg="${esc(a.id)}" aria-label="Ouvrir ${esc(a.label)}"
          style="gap:8px;align-items:center">
        <span class="tileIcon">${img}</span>
        <span class="tileLabel" style="${f(16, 5)}">${esc(a.label)}</span></button>
        ${a.personal && ui.editingShortcuts ? `<button class="removeShortcut" data-act="removeShortcut" data-arg="${esc(a.id)}" aria-label="Retirer ${esc(a.label)}" style="${f(15, 6)}">Retirer</button>` : ''}</div>`;
    }).join('');
    const edit = (S.homeShortcuts || []).some(a => a.personal) ? `<button class="press accent" data-act="editShortcuts" aria-pressed="${ui.editingShortcuts}" style="min-height:44px;${f(15, 6)}">${ui.editingShortcuts ? 'Terminer' : 'Modifier'}</button>` : '';
    return `${sectionTitle('app', 'Mes raccourcis', edit)}<div class="card listCard"><div class="grid3 homeGrid">${items}
      <button class="col press" data-act="addShortcut" style="gap:8px;align-items:center">
        <span class="tileIcon">${icon('plus', 30, 'var(--accentIcon)')}</span>
        <span class="tileLabel" style="${f(16, 5)}">Ajouter</span></button></div></div>`;
  }

  function addShortcutSheet() {
    return `<div class="sheet card col" style="width:540px;padding:32px;gap:20px">
      <div class="sheetHead" style="${f(26, 6)}">Ajouter un raccourci</div>
      <div style="${f(16, 5)}">Jusqu'à 4 raccourcis personnels, gardés sur cet ordinateur.</div>
      ${pill('Un dossier', 'chooseFolder', { filled: false, height: 50 })}
      ${ui.warning ? `<div role="status" style="${f(17, 5)}">${esc(ui.warning)}</div>` : ''}
      ${pill('Fermer', 'closeSheet', { height: 50 })}</div>`;
  }

  // ----------------------------------------------------------------- Consent
  function consent() {
    hd = { title: hdTitle('PapAI va regarder votre écran', 44) };
    return mint(`
      <div class="accent" style="${f(18, 6)}">Votre demande</div>
      <div style="${f(30, 6)}">« ${esc(S.pendingTask)} »</div>
      <div class="sep"></div>
      ${promise('eye', 'Holo voit votre écran pour comprendre le problème.', 21)}
      ${promise('hand', `Rien ne bouge avant l'accord de ${S.helperName}.`, 21)}
      ${promise('stopCircle', 'Le bouton Arrêter reste visible : vous pouvez tout arrêter à tout moment.', 21)}
      ${promise('check', 'On ne vous le redemandera pas.', 21)}`, 40, 24) +
      `<div class="row" style="gap:14px;margin-top:18px">
        ${pill('Annuler', 'cancelConsent', { filled: false, height: 78, grow: true })}
        ${pill("D'accord, je partage mon écran", 'share', { height: 78, grow: true, disabled: !S.connected })}
      </div>`;
  }

  // « Demander une assistance », discret, en haut à droite d’un automate : le support
  // n’est prévenu que sur ce geste, avec l’étape où l’automate s’est arrêté.
  function assistButton() {
    if (S.automationRun && S.automationRun.asked) {
      return `<span class="row muted" style="gap:8px;padding:8px 14px;${f(15, 6)}">${icon('checkCircle', 16)}Assistance demandée</span>`;
    }
    if (!S.canAskAutomationSupport) return '';
    return `<button class="row press" data-act="askAssist" aria-label="Demander une assistance : votre support reçoit l’étape où l’automate s’est arrêté"
        style="gap:8px;min-height:36px;padding:0 14px;border-radius:999px;border:1.2px solid var(--line);background:transparent;color:var(--muted);${f(15, 6)}">
        ${icon('personWave', 16)}<span>Demander une assistance</span></button>`;
  }

  // ----------------------------------------------------------------- Session
  const guardStopped = (st) => st === 'stopped' && S.stoppedBy === 'gardien';
  // Automate lancé depuis la liste : il se joue seul, sans support.
  const automate = () => (S.automationRun && !S.automationRun.local ? S.automationRun : null);
  const blocked = (st) => st === 'stopped' && S.stoppedBy === 'blocage';
  function sessionTitle(st) {
    if (S.paused && S.sessionOpen) return "L'aide est en pause";
    if (guardStopped(st)) return 'PapAI a arrêté : cette démarche peut être une arnaque';
    const a = automate();
    if (a) {
      return { planning: `Holo prépare « ${a.title} »…`, awaiting_approval: `Holo prépare « ${a.title} »…`,
        active: `Holo s’occupe de « ${a.title} »`, awaiting_helper: a.asked ? `${S.HelperName} vous aide` : 'Holo a une question',
        done: "C'est fait !", stopped: blocked(st) ? 'L’automate s’est arrêté' : 'L’automate est arrêté.' }[st];
    }
    return { planning: 'Holo regarde votre écran…', awaiting_approval: `${S.HelperName} vérifie votre demande`,
      active: `${S.carer} s'en occupe`, awaiting_helper: `${S.HelperName} vous aide`, done: "C'est fait !",
      stopped: "L'assistance est arrêtée." }[st];
  }
  const onWeb = (st) => S.sessionWhere === 'web' && (st === 'active' || st === 'awaiting_helper');
  function sessionSubtitle(st) {
    if (S.paused && S.sessionOpen) return 'Vous pouvez utiliser votre ordinateur. Appuyez sur Reprendre quand vous voulez.';
    if (guardStopped(st)) return null;
    const a = automate();
    if (a && blocked(st)) {
      return `Holo n’a pas pu continuer seul ${a.step ? `à l’étape ${a.step}` : 'en route'}${a.reason ? ` : ${a.reason}` : '.'}`;
    }
    return { planning: "Un instant, je prépare ce qu'il faut faire.",
      awaiting_approval: 'Rien ne se passera sur votre écran avant son accord.',
      active: "Pendant l'aide, laissez la souris et le clavier à Holo. Pause ou Arrêter restent toujours possibles.",
      awaiting_helper: S.questionForMe ? "J'ai besoin d'une information que vous seul connaissez."
        : `${S.HelperName} répond à une question de Holo. Restez là, ne touchez à rien.`,
      done: null, stopped: "Votre écran n'est plus partagé." }[st];
  }

  // Où en est l'aide, sans détailler les étapes de Holo (comme sur le Mac).
  function fraction(st) {
    if (st === 'planning') return 0.15;
    if (st === 'awaiting_approval') return 0.35;
    if (st === 'active' || st === 'awaiting_helper') {
      return S.planStep && S.plan.length ? 0.45 + 0.5 * Math.max(S.planStep - 1, 0) / S.plan.length : 0.5;
    }
    return st === 'done' ? 1 : 0;
  }
  const bar = (st, h) => `<div class="track" style="height:${h}px;border-radius:999px;overflow:hidden" role="progressbar"
      aria-label="Avancement" aria-valuenow="${Math.round(fraction(st) * 100)}" aria-valuemin="0" aria-valuemax="100">
      <div class="fill" style="height:100%;width:max(${h}px, ${fraction(st) * 100}%);border-radius:999px;transition:width .6s"></div></div>`;
  function progress(st, phase) {
    const steps = automate() ? ['Holo regarde votre écran', 'L’automate est déjà validé', 'Holo s’en occupe, seul']
      : ['Holo regarde votre écran et prépare la suite', `${S.HelperName} vérifie et donne son accord`,
        `${S.carer} s'en occupe, avec Holo`];
    const rows = steps.map((text, i) => {
      const done = i < phase, now = i === phase;
      return `<div class="row" style="gap:14px" aria-label="${esc(done ? 'Fait : ' + text : now ? 'En cours : ' + text : text)}">
        <span style="color:${done || now ? 'var(--accent)' : 'var(--muted)'}">${icon(done ? 'checkCircle' : now ? 'circleDotted' : 'circle', 24)}</span>
        <span style="${f(21, now ? 6 : 4)};color:${done ? 'var(--muted)' : 'var(--ink)'}">${esc(text)}</span></div>`;
    }).join('');
    return `<div class="col progressBox" style="gap:18px;padding:24px;border-radius:var(--r)">${bar(st, 18)}${rows}</div>`;
  }

  // Une question que Holo pose à l’utilisateur, pour ce que lui seul sait.
  function seniorQuestion() {
    const sent = ui.seniorSent === S.question;
    const options = (S.questionOptions || []).map((o) =>
      `<button class="pill plain" data-act="seniorOption" data-arg="${esc(o)}" style="height:56px;padding:0 22px;${f(20, 6)}">${esc(o)}</button>`).join('');
    const reply = sent
      ? `<div class="row accent" style="gap:10px">${icon('checkCircle', 22)}<span style="${f(20, 6)}">Merci, c'est noté.</span></div>`
      : `${options ? `<div class="row" style="gap:10px;flex-wrap:wrap">${options}</div>` : ''}
        <div class="row" style="gap:12px">
          <input id="seniorReply" class="grow field" placeholder="Votre réponse" value="${esc(ui.seniorText || '')}"
            style="${f(22, 5)};padding:16px 20px;border:0;border-radius:var(--r);width:auto">
          ${pill('Répondre', 'seniorReply', { height: 56, disabled: !(ui.seniorText || '').trim() })}
        </div>
        <div class="muted" style="${f(15, 4)}">Ne donnez jamais de mot de passe ni de code : on ne vous les demandera pas.</div>`;
    return `<div class="card col" style="padding:24px;gap:16px">
      <div class="muted" style="${f(16, 6)}">Holo vous demande</div>
      <div style="${f(28, 5)}">${esc(S.question)}</div>${reply}</div>`;
  }

  const endNote = (sym, text) => `<div class="row" style="gap:14px"><span class="accent" style="width:28px;display:flex;justify-content:center">${icon(sym, 22)}</span>
    <span class="muted" style="${f(19, 4)}">${esc(text)}</span></div>`;

  // Holo travaille dans Chrome PapAI (WebAgentHost) : on le dit, comme sur le Mac.
  const webNote = (st) => onWeb(st) && !(S.paused && S.sessionOpen)
    ? `<div class="muted" style="${f(22, 5)}">Holo travaille dans une fenêtre Chrome à part, sans vos comptes ni vos onglets. Vous pouvez tout arrêter ici à tout moment.</div>` : '';
  const webClosed = () => S.sessionWhere === 'web' ? endNote('globe', 'Holo a fermé sa fenêtre Chrome.') : '';
  function sessionContent(st) {
    if (st === 'planning' || st === 'awaiting_approval' || st === 'active') {
      const p = progress(st, st === 'planning' ? 0 : st === 'awaiting_approval' ? 1 : 2);
      return st === 'active' && webNote(st) ? `<div class="col" style="gap:18px">${p}${webNote(st)}</div>` : p;
    }
    if (st === 'awaiting_helper') {
      if (S.questionForMe && S.question) return seniorQuestion();
      return webNote(st) ? `<div class="col" style="gap:18px">${progress(st, 2)}${webNote(st)}</div>` : progress(st, 2);
    }
    if (st === 'done') {
      return `<div class="col" style="gap:16px">
        <div class="answerCard" style="padding:28px;${f(26, 5)}">${esc(S.answer || 'Voilà, c\'est fait.')}</div>
        ${(S.answerSources || []).map(s => `<p style="${f(14)}">${esc(s.name || s.url)} · ${esc(s.url)}</p>`).join('')}
        ${endNote('lock', "Votre écran n'est plus partagé.")}${webClosed()}
        ${endNote('book', `${S.HelperName} peut en faire un automate. Vous le retrouverez dans « Mes automates » pour le refaire sans aide.`)}
      </div>`;
    }
    if (guardStopped(st)) {
      const who = (S.helpers[0] || {}).name || 'votre support';
      return `<div class="col" style="gap:20px;${f(23, 5)}">
        <div>Ne payez rien et ne donnez aucun code.</div>
        <div>Appelez ${esc(who)} à son numéro habituel.</div>
        ${S.guardAcknowledged ? "<div>Votre support a vu l'alerte et s'en occupe</div>" : ''}${webClosed()}</div>`;
    }
    const a = automate();
    if (st === 'stopped' && a) {
      const n = a.number ? ` n° ${a.number}` : '';
      return endNote('book', a.asked ? `${S.HelperName} a reçu la demande${n}, avec l’étape où l’automate s’est arrêté.`
        : `L’étape est notée${a.number ? ` sur la demande n° ${a.number}` : ''}. Rien n’est envoyé à ${S.helperName} sans votre accord.`);
    }
    if (st === 'stopped' && S.sessionWhere === 'web') return `<div class="col" style="gap:16px">${webClosed()}</div>`;
    return '';
  }

  const canPause = (st) => st === 'active' || st === 'awaiting_helper' || S.paused;
  function pauseButton(height, size) {
    return `<button class="row press softBtn" data-act="pause" aria-label="${S.paused ? "Reprendre l'aide" : "Mettre l'aide en pause"}"
        style="justify-content:center;gap:12px;height:${height}px;border-radius:999px;flex:1">
        ${icon(S.paused ? 'play' : 'pause', size - 4)}<span style="${f(size, 6)}">${S.paused ? 'Reprendre' : 'Pause'}</span></button>`;
  }
  function stopButton(height, size) {
    return `<button class="row press stopBtn" data-act="stop" aria-label="Arrêter l'assistance (Échap)"
        style="justify-content:center;gap:14px;height:${height}px;border-radius:999px;flex:1">
        ${icon('stop', size - 4, '#fff')}<span style="${f(size, 6)}">Arrêter</span></button>`;
  }

  function session() {
    const st = S.state || 'planning';
    const sub = sessionSubtitle(st);
    const shared = S.sessionOpen ? `<div class="pillChip chip-blue" style="gap:10px;padding:10px 18px;${f(16, 6)}">
      <span class="dot" style="background:currentColor"></span>Écran partagé</div>` : '';
    const assist = automate() ? assistButton() : '';
    const banner = shared || assist ? `<div class="row" style="gap:12px;align-items:center">${shared}<div class="spacer"></div>${assist}</div>` : '';
    const footer = (S.task && st !== 'stopped' && st !== 'awaiting_approval' && !(st === 'awaiting_helper' && S.questionForMe))
      ? `<div class="muted" style="${f(16, 4)};display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden">Votre demande : ${esc(S.task)}</div>` : '';
    const bottom = S.sessionOpen
      ? `<div class="row" style="gap:14px;width:100%">${canPause(st) ? pauseButton(70, 26) : ''}${stopButton(70, 26)}</div>`
      : pill("Retour à l'accueil", 'home', { height: 70, grow: true });
    hd = { chip: banner, title: hdTitle(esc(sessionTitle(st)), guardStopped(st) ? 34 : 40),
      sub: sub ? `<div class="hdrSub fade" style="${f(22, 5)}">${esc(sub)}</div>` : '',
      tone: guardStopped(st) ? 'danger' : null };
    const content = sessionContent(st);
    if (!content && !footer) return `<div class="spacer"></div><div class="row" style="margin-top:18px">${bottom}</div>`;
    const action = st === 'active' && !S.paused && S.currentAction
      ? `<div style="${f(24, 5)}">${esc(S.currentAction)}</div>` : '';
    const inner = `<div class="scroll">${action}${content}</div>
      <div class="spacer"></div>${footer}`;
    const card = guardStopped(st)
      ? `<div class="col guardCard" style="padding:40px 34px 34px;gap:18px;border-radius:var(--rBig);background:var(--card);flex:1;min-height:0">${inner}</div>`
      : mint(inner, 34, 18);
    return card + `<div class="row" style="margin-top:18px">${bottom}</div>`;
  }

  // Petit encart pendant que Holo agit (MiniPanel du Mac) : la fenêtre se range
  // en bas à droite pour qu'on voie ce qu'il fait ; Pause et Arrêter restent là.
  function mini() {
    const st = S.state || 'planning';
    const a = automate();
    const title = S.paused && S.sessionOpen ? "L'aide est en pause"
      : onWeb(st) && S.sessionOpen ? 'Holo travaille dans Chrome PapAI' : ({ planning: 'Holo prépare la suite…',
      awaiting_approval: `${S.HelperName} vérifie`, active: a ? 'Holo s’occupe de l’automate' : `${S.carer} s'en occupe`,
      awaiting_helper: `${S.HelperName} vous aide`, done: "C'est fait !" }[st] || 'PapAI');
    return `<div class="col mini" style="gap:10px;padding:14px 16px">
      <div class="row miniHead" style="gap:10px">
        <span class="dot" style="background:${S.sessionOpen && !S.paused ? '#fff' : 'rgba(255,255,255,.55)'}"></span>
        <span class="grow" style="${f(17, 6)};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(st === 'active' && !S.paused ? S.currentAction || title : title)}</span>
        <button class="circle press softBtn" data-act="expand" aria-label="Ouvrir PapAI en grand"
          style="width:44px;height:44px;color:var(--accent)">${icon('expand', 16)}</button>
      </div>
      ${bar(st, 8)}
      <div class="row" style="gap:8px">${canPause(st) ? pauseButton(44, 16) : ''}${stopButton(44, 16)}</div>
    </div>`;
  }

  // ------------------------------------------------------------------ Lesson
  function lesson() {
    const l = S.lesson;
    if (ui.lessonId !== l.id) { ui.lessonId = l.id; ui.lessonIndex = 0; }
    const steps = l.steps || [];
    const i = Math.min(ui.lessonIndex, Math.max(0, steps.length - 1));
    let body;
    if (!steps.length) {
      body = `<div style="${f(30, 6)}">Cet automate n'a pas encore d'étapes.</div>`;
    } else {
      const s = steps[i];
      const img = s.image ? `<img alt="" src="${esc(S.httpBase)}/lessons/${encodeURIComponent(l.id)}/${encodeURIComponent(s.image)}"
          style="flex:1;min-height:0;max-width:100%;object-fit:contain;border-radius:var(--r)">` : '<div class="spacer"></div>';
      body = `<div style="${f(36, 6)};letter-spacing:-0.4px;line-height:1.15">${esc(s.instruction || '')}</div>
        ${s.checkpoint ? `<div class="card" style="padding:18px;${f(19, 4)}">Vous devriez voir : ${esc(s.checkpoint)}</div>` : ''}
        ${img}`;
    }
    const last = i >= steps.length - 1;
    hd = { chip: steps.length ? hdChip('book', `Étape ${i + 1} sur ${steps.length}`) : '', title: hdTitle(esc(l.title), 30) };
    return mint(body, 40, 20) +
      `<div class="row" style="gap:14px;margin-top:18px">
        ${pill('Fermer', 'closeLesson', { filled: false, height: 72 })}
        ${i > 0 ? pill('Précédent', 'prevStep', { filled: false, height: 72 }) : ''}
        ${pill(last ? 'Terminé' : 'Suivant', 'nextStep', { height: 72, grow: true })}
      </div>`;
  }

  const lead = (text, size) => `<div class="muted" style="${f(size || 21, 5)}">${esc(text)}</div>`;

  // ------------------------------------------------- Demande en attente (ticket)
  function rdvText(at) {
    return new Date(at * 1000).toLocaleString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
  }

  function queued() {
    const q = S.queued;
    const slots = [['Dans 1 heure', '1h'], ['Demain à 9 h', 'demain9'], ['Demain à 14 h', 'demain14']];
    const suggestions = (q.suggestions || []).filter(s => s && s.id && s.title).map(s => {
      const launched = q.suggestion_lancee === s.id;
      const disabled = !!q.suggestion_lancee;
      return `<div class="card row" style="gap:14px;padding:14px">
        <div class="grow" style="${f(18, 6)}">${esc(s.title)}</div>
        <button class="pill ${launched ? 'plain' : 'filled'}" data-act="runSuggested" data-arg="${esc(s.id)}"
          data-ticket="${esc(q.ticket)}" ${disabled ? 'disabled' : ''} style="height:48px;padding:0 20px;${f(17, 6)}">
          ${launched ? 'Lancé' : 'Lancer'}</button></div>`;
    }).join('');
    hd = { chip: hdChip('personWave', `Demande n° ${esc(q.number)}`), title: hdTitle('Votre demande est partie', 44) };
    return mint(`${q.task ? `<div class="card" style="padding:24px;${f(24, 5)}">« ${esc(q.task)} »</div>` : ''}
      ${q.rdv ? lead(`Rendez-vous ${esc(rdvText(q.rdv))}. PapAI vous préviendra à l'heure dite.`)
        : lead(`Personne n'est disponible pour l'instant. PapAI vous préviendra dès que ${esc(S.helperName)} sera là. Vous pouvez aussi fixer un rendez-vous.`)}
      ${suggestions ? `<div class="col" style="gap:10px"><div class="muted" style="${f(19, 6)}">En attendant, vous pouvez essayer :</div>${suggestions}</div>` : ''}
      ${q.rdv ? '' : `<div class="row" style="gap:10px;flex-wrap:wrap">${slots.map(([label, v]) =>
        `<button class="pill plain" data-act="scheduleTicket" data-arg="${v}" style="height:56px;padding:0 22px;${f(20, 6)}">${label}</button>`).join('')}</div>`}`, 40, 22) +
      `<div class="row" style="gap:14px;margin-top:18px">${pill("D'accord", 'closeQueued', { height: 78, grow: true })}</div>`;
  }

  // ------------------------------------- Demande qui a déjà son ticket
  function existing() {
    const e = S.existing, solved = e.kind === 'solved';
    const task = e.task ? `<div class="card" style="padding:24px;${f(24, 5)}">« ${esc(e.task)} »</div>` : '';
    if (!solved) {
      const live = e.status === 'en_cours';
      const text = live ? `Une assistance est déjà en cours sur cette demande.`
        : e.status === 'rdv' && e.rdv ? `Rendez-vous ${rdvText(e.rdv)}. PapAI vous préviendra à l’heure dite.`
        : e.status === 'a_reprendre' ? `L’assistance s’est arrêtée avant la fin. ${S.helperName} a votre demande et va la reprendre.`
        : `Elle attend un support. PapAI vous préviendra dès que ${S.helperName} sera là.`;
      return mint(`<div class="row accent" style="gap:12px">${icon('personWave', 28)}<span style="${f(20, 6)}">Demande n° ${esc(e.number)}</span></div>
        <div style="${f(44, 6)};letter-spacing:-0.7px;line-height:1.1">${live ? 'Cette demande est déjà en cours' : 'Vous avez déjà fait cette demande'}</div>
        ${task}${lead(text + ' Inutile de la refaire.')}`, 40, 22) +
        `<div class="row" style="gap:14px;margin-top:18px">
          ${pill('C’est une autre demande', 'newRequest', { filled: false, height: 78, grow: true, disabled: !S.connected })}
          ${pill('D’accord', 'closeExisting', { height: 78, grow: true })}
        </div>`;
    }
    const who = e.by || 'Votre support';
    const note = e.note ? `<div class="card" style="padding:24px;${f(22, 5)}"><div class="muted" style="${f(16, 6)}">${esc(who)} a noté</div>« ${esc(e.note)} »</div>` : '';
    const steps = e.steps.length ? `<div class="col" style="gap:8px"><div class="muted" style="${f(16, 6)}">Ce qui l’avait réglée</div>
      ${e.steps.map((st, i) => `<div style="${f(21, 5)}">${i + 1}. ${esc(st)}</div>`).join('')}</div>` : '';
    const when = e.at ? ` le ${esc(new Date(e.at * 1000).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' }))}` : '';
    return mint(`<div class="row accent" style="gap:12px">${icon('personWave', 28)}<span style="${f(20, 6)}">Demande n° ${esc(e.number)} · réglée${when}</span></div>
      <div style="${f(44, 6)};letter-spacing:-0.7px;line-height:1.1">Cette demande a déjà été réglée</div>
      ${task}${note}${steps}
      ${lead('Si le problème est revenu, Holo peut refaire la même chose avec vous.')}`, 40, 22) +
      `<div class="row" style="gap:14px;margin-top:18px">
        ${pill('Ce n’est pas la même demande', 'newRequest', { filled: false, height: 78, grow: true, disabled: !S.connected })}
        ${pill('Refaire avec Holo', 'retryExisting', { filled: false, height: 78, grow: true, disabled: !S.connected })}
        ${pill('C’est réglé, merci', 'closeExisting', { height: 78, grow: true })}
      </div>`;
  }

  // ----------------------------------------------------------- RemoteRequest
  function remote() {
    const r = S.remoteRequest;
    hd = { chip: hdChip('personWave', r.rdv ? "C'est l'heure de votre rendez-vous" : r.ticket ? 'Votre demande en attente' : "Proposition d'aide"),
      title: hdTitle(`${esc(r.from)} ${r.ticket ? 'est disponible pour vous aider' : 'propose de vous aider'}`, 44) };
    return mint(`${r.task ? `<div class="card" style="padding:24px;${f(26, 5)}">« ${esc(r.task)} »</div>` : ''}
      ${lead(`Si vous acceptez, PapAI va regarder votre écran. Rien ne bouge avant l'accord de ${r.from}, et vous pouvez arrêter à tout moment.`)}`, 40, 22) +
      `<div class="row" style="gap:14px;margin-top:18px">
        ${pill('Non merci', 'refuseRemote', { filled: false, height: 78, grow: true })}
        ${pill("Oui, j'accepte", 'acceptRemote', { height: 78, grow: true, disabled: !S.connected })}
      </div>`;
  }

  // ------------------------------------------------------------------ Feuilles
  // « Mon support » : l'organisation rattachée par les stratégies de groupe, en lecture seule.
  function supportInfo() {
    const none = !S.orgConfigured && !S.orgName;
    const online = S.connected && (S.helpers || []).some((h) => h.online);
    const title = none ? 'Aucune organisation configurée' : S.orgName ? 'Support IT · ' + S.orgName : 'Support IT';
    const detail = none ? 'Contactez votre service informatique.'
      : !S.connected ? 'Hors connexion pour le moment.'
      : !S.orgName ? 'Rattachement à votre organisation en cours…'
      : online ? 'En ligne' : 'Aucun agent en ligne : votre demande sera mise en attente.';
    const sym = none ? 'exclam' : S.orgName ? 'personCheck' : 'clock';
    return `<div class="col" style="gap:12px"><div style="${f(22, 6)}">Mon support</div>
      <div class="row supportCard" style="gap:14px;padding:14px">
        <span class="circle" style="width:46px;height:46px;color:#fff;background:${S.orgName && !none ? 'var(--accentIcon)' : 'var(--muted)'}">${icon(sym, 20)}</span>
        <div class="col grow" style="gap:4px">
          <div style="${f(20, 6)}">${esc(title)}</div>
          <div class="${online && S.orgName ? 'accent' : 'muted'}" style="${f(15, 5)}">${esc(detail)}</div>
        </div></div>
      ${none ? '' : `<div class="muted" style="${f(14, 4)}">Configuré par votre service informatique.</div>`}</div>`;
  }

  function requestsSheet() {
    const states = { nouveau: 'En attente', en_attente: 'En attente', rdv: 'Rendez-vous prévu',
      en_cours: 'En cours', a_reprendre: 'Interrompue', resolu: 'Réglée' };
    const rows = (S.requests || []).map(r => {
      const date = new Date(Number(r.created) * 1000);
      const dateText = Number(r.created) > 0 && !Number.isNaN(date.getTime())
        ? date.toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' }) : '';
      const s = r.solution;
      let solution = '';
      if (s?.kind === 'automate') solution = `<div>Réglée par l'automate « ${esc(s.title || 'Automate')} »</div>`;
      if (s?.kind === 'plan') solution = `<div>Plan exécuté</div><ol>${(s.steps || []).map(t => `<li>${esc(t)}</li>`).join('')}</ol>`;
      if (s?.kind === 'answer') solution = `<div>Réponse validée par le support</div><div class="requestText">${esc(s.text)}</div>
        ${(s.sources || []).map(source => `<div class="muted">${esc(source.title)}${source.url ? ' · ' + esc(source.url) : ''}</div>`).join('')}`;
      const canRelaunch = r.relaunch && (S.lessons || []).some(l => l.id === r.relaunch);
      return `<article class="card col requestItem" style="padding:20px;gap:10px;${f(17, 5)}">
        <div class="row" style="gap:12px;flex-wrap:wrap"><span class="muted">${esc(dateText)}</span><span class="spacer"></span>
          <span style="color:var(--leaf);${f(16, 6)}">${esc(states[r.status] || 'En attente')}</span></div>
        <div class="requestText" style="${f(20, 6)}">${esc(r.task)}</div>
        ${solution ? `<div class="col" style="gap:8px">${solution}</div>` : ''}
        ${canRelaunch ? pill('Relancer', 'relaunchRequest', { arg: r.id, height: 44 }) : ''}</article>`;
    }).join('');
    const content = S.requestsLoading ? 'Chargement…' : S.requestsError ? "Liste indisponible pour l'instant."
      : !(S.requests || []).length ? "Aucune demande pour l'instant." : null;
    return `<section class="sheet col requestsSheet" role="dialog" aria-modal="true" aria-label="Mes demandes"
      style="width:720px;max-width:calc(100vw - 32px);padding:32px;gap:18px;background:var(--card)">
      <div class="sheetHead row" style="gap:16px"><span style="${f(28, 6)}">Mes demandes</span><span class="spacer"></span>
        <button class="pillChip chip-blue press" data-act="closeSheet" style="padding:10px 16px;${f(16, 6)}">Fermer</button></div>
      ${content ? `<div style="${f(20, 5)}">${esc(content)}</div>` : rows}</section>`;
  }

  function settingsSheet() {
    const on = S.realtimeProtection;
    const voix = window.PapAINarration?.enabled !== false;
    return `<div class="sheet col" role="dialog" aria-modal="true" aria-label="Réglages" style="width:560px;padding:32px;gap:18px;background:var(--card)">
      <div class="sheetHead col" style="gap:4px"><div style="${f(30, 7)}">Réglages</div>
        ${S.orgName ? `<div style="${f(15, 5)};opacity:.92">Poste géré par ${esc(S.orgName)}</div>` : ''}</div>
      <div class="col" style="gap:8px">
        <div class="row" style="gap:14px"><span class="grow" id="protLabel" style="${f(22, 6)}">Protection en temps réel</span>
          <button class="switch${on ? ' on' : ''}" role="switch" aria-checked="${on}" aria-labelledby="protLabel" data-act="protection" data-arg="${on ? '0' : '1'}"><span></span></button></div>
        <div class="muted" style="${f(17, 4)}">${on
          ? "Activée. PapAI repère les arnaques à partir des applications ouvertes, du titre de la fenêtre et du site visité. Jamais l'écran, jamais vos mots de passe."
          : "Coupée. Rien ne part de cet ordinateur en dehors d'une assistance, et les arnaques ne sont plus repérées."}</div></div>
      <div class="col" style="gap:8px">
        <div class="row" style="gap:14px"><span class="grow" id="voixLabel" style="${f(22, 6)}">Lire à voix haute</span>
          <button class="switch${voix ? ' on' : ''}" role="switch" aria-checked="${voix}" aria-labelledby="voixLabel" data-act="readAloud"><span></span></button></div>
        <div class="muted" style="${f(17, 4)}">Voix française locale uniquement. La lecture se coupe pendant la dictée.</div></div>
      ${supportInfo()}
      <div class="row" style="gap:8px;padding-top:14px;box-shadow:inset 0 1px 0 var(--line)">
        <div class="spacer"></div>
        ${pill('Fermer', 'closeSheet', { height: 50 })}
      </div></div>`;
  }

  // Alerte du gardien (PROTOCOL.md) : elle passe devant tout.
  function alertSheet() {
    const a = S.alert, danger = a.level === 'danger';
    return `<div class="sheet col ${danger ? 'alertDanger' : 'alertInfo'}" style="width:620px;padding:36px;gap:18px;background:var(--card)">
      <div class="sheetHead col" style="gap:12px">
        <div class="row" style="gap:14px">${icon('exclam', 30, '#fff')}
        <span style="${f(17, 6)}">${danger ? 'Attention' : 'Pour information'}</span></div>
        <div style="${f(30, 6)}">${esc(a.title)}</div></div>
      ${a.detail ? `<div class="muted" style="${f(19, 5)}">${esc(a.detail)}</div>` : ''}
      ${a.acknowledged ? `<div style="${f(20, 6)}">Votre support a vu l'alerte et s'en occupe</div>` : ''}
      ${a.blocked ? '' : `<div class="row"><div class="spacer"></div>${pill("J'ai compris", 'dismissAlert', { height: 56 })}</div>`}</div>`;
  }

  // ------------------------------------------------------------------- rendu
  function body() {
    if (S.remoteRequest) return remote();
    if (S.existing) return existing();
    if (S.queued && S.queued.show) return queued();
    if (S.screen === 'consent') return consent();
    if (S.screen === 'session') return session();
    if (S.screen === 'lesson' && S.lesson) return lesson();
    return home();
  }

  function autosize(el) {
    const max = parseFloat(getComputedStyle(el).lineHeight) * 3 + 44;
    el.style.height = '0px';
    el.style.height = Math.min(el.scrollHeight, max) + 'px';
  }

  function render() {
    if (!S) return;
    document.documentElement.style.setProperty('--ts', S.textScale);
    const a = document.activeElement;
    const focusId = a && a.id ? a.id : null;
    const sel = focusId && a.setSelectionRange ? [a.selectionStart, a.selectionEnd] : null;
    const compact = S.compact && S.screen === 'session' && !S.remoteRequest;
    if (document.body) document.body.classList.toggle('compact', compact);
    hd = null;
    const main = compact ? '' : body();
    document.getElementById('root').innerHTML = compact ? mini() : header() + `<div class="main">${main}</div>`;
    document.getElementById('sheet').innerHTML =
      S.alert ? alertSheet() : ui.sheet === 'settings' ? settingsSheet()
        : ui.sheet === 'requests' ? requestsSheet()
        : ui.sheet === 'addShortcut' ? addShortcutSheet()
        : ui.sheet === 'doc' ? docSheet() : '';
    const req = document.getElementById('req');
    if (req) autosize(req);
    if (focusId) {
      const el = document.getElementById(focusId);
      if (el) { el.focus(); if (sel && el.setSelectionRange) el.setSelectionRange(sel[0], sel[1]); }
    }
  }

  // ----------------------------------------------------------------- gestes
  function submit() {
    if (S.dictation.phase !== 'idle' || ui.dictating || ui.submitting || S.screen !== 'home' || S.remoteRequest || S.alert) return;
    const t = ui.request.trim();
    if (!t) { ui.warning = 'Dites en quelques mots ce qui ne va pas.'; render(); focus('req'); return; }
    if (!S.connected) { ui.warning = `Je ne joins pas ${S.helperName} pour le moment. Réessayez dans un instant.`; render(); return; }
    ui.warning = null;
    ui.submitting = true;
    ui.request = '';
    render();
    Promise.resolve(call('request_consent', t)).catch(() => {
      ui.submitting = false; ui.request = t; ui.warning = "La demande n'est pas partie. Réessayez."; render();
    });
  }
  function focus(id) { const el = document.getElementById(id); if (el) el.focus(); }
  function lessonNext() {
    const n = (S.lesson.steps || []).length;
    if (ui.lessonIndex >= n - 1) call('close_lesson'); else { ui.lessonIndex += 1; render(); }
  }

  const acts = {
    readAloud: () => { window.PapAINarration?.setEnabled(!window.PapAINarration.enabled); render(); },
    submit, mic: () => {
      if (!S.microPresent || S.dictation.phase === 'starting' || S.dictation.phase === 'transcribing') return;
      if (S.dictation.phase === 'idle' && ui.dictating) return;
      ui.warning = null; ui.dictating = true; render();
      window.PapAINarration?.setDictating(true);
      Promise.resolve(call('dictation_toggle')).catch(() => { ui.dictating = false; window.PapAINarration?.setDictating(false); render(); });
    },
    homeShortcut: (id) => call('open_home_shortcut', id),
    editShortcuts: () => { ui.editingShortcuts = !ui.editingShortcuts; render(); },
    removeShortcut: (id) => call('remove_home_shortcut', id),
    addShortcut: () => { ui.warning = null; ui.sheet = 'addShortcut'; render(); },
    chooseFolder: async () => {
      const result = await call('add_home_folder');
      if (result && result.ok) { ui.sheet = null; ui.warning = null; }
      else if (result && result.message) ui.warning = result.message;
      render();
    },
    openSettings: () => { ui.sheet = 'settings'; render(); },
    openRequests: () => { ui.sheet = 'requests'; call('open_requests'); render(); },
    relaunchRequest: (id) => {
      const r = (S.requests || []).find(r => r.id === id);
      if (!r?.relaunch || !(S.lessons || []).some(l => l.id === r.relaunch)) return;
      ui.sheet = null; render(); call('close_requests'); call('relaunch_request', id);
    },
    closeSheet: () => { if (ui.sheet === 'requests') call('close_requests'); ui.sheet = null; render(); },
    dismissAlert: () => { if (!S.alert?.blocked) { S.alert = null; render(); call('dismiss_alert'); } },
    protection: (v) => { S.realtimeProtection = v === '1'; render(); call('set_realtime_protection', S.realtimeProtection); },
    shortcut: (id) => call('run_shortcut', id),
    run: (id) => call('run_shortcut', id),
    doc: (id) => { ui.docId = id; ui.sheet = 'doc'; render(); },
    docRun: () => { const id = ui.docId; ui.sheet = null; render(); call('run_shortcut', id); },
    docLesson: () => { const id = ui.docId; ui.sheet = null; ui.lessonIndex = 0; render(); call('open_lesson', id); },
    lesson: (id) => call('open_lesson', id),
    cancelConsent: () => call('cancel_consent'),
    share: () => call('give_consent'),
    stop: () => { window.PapAINarration?.cancel(); call('stop'); },
    pause: () => { window.PapAINarration?.cancel(); call('toggle_pause'); },
    askAssist: () => call('ask_automation_support'),
    expand: () => call('expand_window'),
    seniorOption: (o) => acts.seniorReply(o),
    seniorReply: (o) => {
      const t = String(o || ui.seniorText || '').trim();
      if (!t || !S.question) return;
      ui.seniorSent = S.question; ui.seniorText = '';
      call('answer_senior', t);
      render();
    },
    home: () => call('back_home'),
    closeLesson: () => call('close_lesson'),
    prevStep: () => { ui.lessonIndex = Math.max(0, ui.lessonIndex - 1); render(); },
    nextStep: lessonNext,
    acceptRemote: () => call('accept_remote'),
    scheduleTicket: (slot) => call('schedule_ticket', slot),
    runSuggested: (id, ticket) => call('run_suggested_automation', id, ticket),
    closeQueued: () => call('close_queued'),
    closeExisting: () => call('close_existing'),
    retryExisting: () => call('retry_existing'),
    newRequest: () => call('new_request'),
    openQueued: () => { S.queued.show = true; render(); call('open_queued'); },
    refuseRemote: () => call('refuse_remote'),
  };

  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]');
    if (!b || b.disabled) return;
    const fn = acts[b.dataset.act];
    if (fn) fn(b.dataset.arg, b.dataset.ticket);
  });
  document.addEventListener('input', (e) => {
    const t = e.target;
    if (t.id === 'req') { ui.request = t.value; autosize(t); }
    else if (t.id === 'seniorReply') {
      const was = !(ui.seniorText || '').trim(), now = !t.value.trim();
      ui.seniorText = t.value;
      if (was !== now) render();
    }
  });
  // keyboardShortcut(.cancelAction) / (.defaultAction) des vues Mac
  document.addEventListener('keydown', (e) => {
    if (!S) return;
    const t = e.target;
    if (S.alert && (e.key === 'Enter' || e.key === 'Escape')) { e.preventDefault(); return; }
    if (e.key === 'Escape') {
      if (S.screen === 'session' && S.sessionOpen) { ui.sheet = null; return acts.stop(); }
      if (ui.sheet) { acts.closeSheet(); return; }
      if (S.remoteRequest) return acts.refuseRemote();
      if (S.screen === 'consent') return acts.cancelConsent();
      if (S.screen === 'lesson') return acts.closeLesson();
      return;
    }
    if (e.key !== 'Enter' || e.shiftKey || ui.sheet) return;
    if (t && t.tagName === 'BUTTON') return;
    if (t && t.id === 'req') { e.preventDefault(); submit(); return; }
    if (t && t.id === 'seniorReply') { e.preventDefault(); acts.seniorReply(); return; }
    if (S.remoteRequest) return;
    if (S.screen === 'consent' && S.connected) acts.share();
    else if (S.screen === 'lesson') lessonNext();
    else if (S.screen === 'session' && !S.sessionOpen) acts.home();
  });

  window.PapAI = {
    update(snap) {
      const was = S && S.screen;
      S = snap;
      window.PapAINarration?.update(snap);
      if (!(S.homeShortcuts || []).some(a => a.personal)) ui.editingShortcuts = false;
      const m = S.dictation && S.dictation.message;
      if (m && m !== ui.lastDictMsg) ui.warning = m;
      if (m && S.dictation.phase === 'idle') ui.dictating = false;
      ui.lastDictMsg = m || null;
      // Holo peut reposer la même question plus tard : la réponse vaut pour une seule question.
      if (!(S.questionForMe && S.question && S.state === 'awaiting_helper')) ui.seniorSent = null;
      if (was && was !== S.screen && S.screen === 'home') {
        ui.warning = null; ui.submitting = false; ui.dictating = false;
      }
      render();
    },
    dictated(text, id) {
      if (id === ui.lastDictation) return;
      ui.lastDictation = id;
      ui.dictating = false;
      if (!text.trim() || S.screen !== 'home' || S.remoteRequest || S.alert) { render(); return; }
      ui.request = ui.request.trim() ? ui.request.trim() + ' ' + text.trim() : text.trim();
      submit();
      render();
    },
  };

  // Aperçu dans un navigateur (python -m papai.preview) : l'état de démo vient
  // de Model en mode démonstration ; les gestes ne font que naviguer.
  const preview = {
    request_consent: (t) => { S.pendingTask = t; S.screen = 'session'; S.state = 'planning'; render(); },
    cancel_consent: () => { S.screen = 'home'; render(); },
    give_consent: () => { S.screenConsent = true; S.screen = 'session'; S.state = 'planning'; render(); },
    revoke_consent: () => {},
    open_lesson: (id) => { S.lesson = S.lessons.find((l) => l.id === id); S.screen = 'lesson'; render(); },
    close_lesson: () => { S.screen = 'home'; render(); },
    back_home: () => { S.screen = 'home'; S.state = null; ui.submitting = false; render(); },
    stop: () => { S.state = 'stopped'; S.sessionOpen = false; S.compact = false; render(); },
    toggle_pause: () => { S.paused = !S.paused; render(); },
    set_realtime_protection: () => {},
    expand_window: () => { S.compact = false; render(); },
    answer_senior: () => {},
    run_shortcut: (id) => { S.runStatus = { id, text: "C'est ouvert", running: false }; render(); },
    add_home_folder: () => ({ ok: false, message: "Le choix d'un dossier se fait dans l'app Windows." }),
  };

  function boot() {
    if (window.pywebview && window.pywebview.api) {
      api = window.pywebview.api;
      api.ready().then((snap) => window.PapAI.update(snap));
      return;
    }
    const q = new URLSearchParams(location.search);
    if (q.has('demo')) {
      fetch('state.json?' + q.toString()).then((r) => r.json()).then((snap) => {
        if (q.get('sheet')) ui.sheet = q.get('sheet');
        if (q.get('demo') === 'doc') { ui.sheet = 'doc'; ui.docId = (snap.lessons[0] || {}).id; }
        else if (q.get('demo') === 'requests') ui.sheet = 'requests';
        if (q.get('dictation')) snap.dictation = { phase: q.get('dictation'), message: null };
        if (q.get('request')) ui.request = q.get('request');
        if (q.get('connected') === '0') snap.connected = false;
        if (q.get('ts')) snap.textScale = parseFloat(q.get('ts'));
        window.PapAI.update(snap);
      });
    }
  }
  if (window.pywebview && window.pywebview.api) boot();
  else window.addEventListener('pywebviewready', boot);
  window.addEventListener('DOMContentLoaded', () => { if (!api) setTimeout(() => { if (!api && !S) boot(); }, 300); });
})();
