/* Les écrans de l'app Mac (apps/mac/Sources/*View.swift), à l'identique.
   L'état vient de Python (papai/model.py) par PapAI.update(snapshot) ;
   les gestes repartent par window.pywebview.api.<méthode>. */
(function () {
  'use strict';
  let S = null;
  let api = null;
  const ui = { request: '', warning: null, lessonId: null, lessonIndex: 0, name: null,
               sheet: null, settings: { name: '', server: '' }, lastDictMsg: null,
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
  function header() {
    return `<div class="hdr">
      <img class="logotype" src="logotype-papai.svg" alt="papai">
      <div class="spacer"></div>
      ${S.connected ? '' : `<div class="pillChip" style="gap:10px;padding:11px 18px">
        <span class="dot" style="background:rgba(122,128,124,.5)"></span>
        <span style="${f(16, 5)}">Pas de connexion pour le moment</span>
      </div>`}
      <button class="circle press" data-act="openSettings" aria-label="Réglages"
        style="width:42px;height:42px;background:var(--card)">${icon('gear', 19)}</button>
    </div>`;
  }

  // -------------------------------------------------------------------- Home
  function home() {
    return `<div class="row" style="align-items:stretch;gap:24px;flex:1;min-height:0">
      ${helpCard()}
      <div class="scroll" style="width:400px;flex:none">
        <div class="col" style="gap:16px;padding-bottom:8px">${tutorials()}${appsGrid()}</div>
      </div></div>`;
  }

  function helpCard() {
    const mic = S.microPresent;
    const busy = ui.dictating || S.dictation.phase !== 'idle';
    const warn = ui.warning ? `<div class="pillChip" style="align-self:flex-start;gap:8px;padding:12px 18px;${f(17, 6)}">
        ${icon('exclam', 20)}<span>${esc(ui.warning)}</span></div>` : '';
    return `<div class="mintCard homeCard" style="padding:32px;gap:16px">
      <div style="${f(44, 7)};letter-spacing:-0.8px;line-height:1.1">${(h => (h >= 19 || h < 5) ? "Bonsoir" : "Bonjour")(new Date().getHours())}${S.storedFirstName ? ' ' + esc(S.storedFirstName) : ''}</div>
      <div class="muted" style="${f(18, 5)}">Un souci sur l'ordinateur ? ${mic ? 'Dites-le simplement' : 'Écrivez ce dont vous avez besoin'}, un message part tout de suite à ${esc(S.helperName)}.</div>
      <div class="spacer"></div>
      ${mic ? micButton() : ''}
      ${ui.writing || !mic ? `<div class="requestRow">
        <textarea id="req" rows="1" placeholder="Écrivez votre demande" aria-label="Écrivez votre demande"
          style="${f(18, 5)};line-height:1.3">${esc(ui.request)}</textarea>
        <button class="pill filled" data-act="submit" ${busy || ui.submitting ? 'disabled' : ''} style="height:44px;padding:0 18px;${f(15, 6)}">Envoyer</button>
      </div>` : S.dictation.phase === 'idle' ? `<button class="pillChip press writeButton" data-act="write" style="${f(15, 6)}">Écrire</button>` : ''}
      ${warn}<div class="spacer"></div></div>`;
  }

  function micButton() {
    const ph = S.dictation.phase;
    const listening = ph === 'listening';
    const inner = ph === 'transcribing' ? '<div class="spinner"></div>'
      : icon(listening ? 'stop' : 'mic', 48, listening ? '#fff' : 'var(--ink)');
    const label = listening ? 'Je vous écoute…' : ph === 'transcribing' || ph === 'starting' ? 'Je note…' : 'Parler à PapAI';
    return `<div class="col" style="align-items:center;gap:12px">
      <button class="press" data-act="mic" ${ph === 'transcribing' || ph === 'starting' ? 'disabled' : ''}
        aria-label="${listening ? 'Arrêter la dictée' : 'Dicter ma demande'}"
        style="flex:none">
      <span class="microFrame" style="position:relative;width:180px;height:180px;display:flex;align-items:center;justify-content:center">
        ${listening ? '<span class="micRing"></span>' : ''}
        <span class="circle microDisc" style="position:relative;width:148px;height:148px;background:${listening ? 'var(--accent)' : '#fff'}">${inner}</span>
      </span></button><span style="${f(20, 6)}">${label}</span>
      ${ui.request && !ui.writing ? `<span style="${f(18, 5)}">${esc(ui.request)}</span>` : ''}</div>`;
  }

  const folderIcon = (folder) => ({ pictures: 'photo', documents: 'doc', downloads: 'download',
    desktop: 'desktop', videos: 'film', music: 'music' }[String(folder || '').toLowerCase()] || 'list');

  function tutorials() {
    const notice = S.notice ? `<div style="background:var(--mint);border-radius:var(--r);padding:18px;${f(17, 5)}">${esc(S.notice)}</div>` : '';
    const tiles = S.lessons.map((l) => {
      const steps = (l.steps || []).length;
      return `<div class="card row" style="padding:12px;gap:10px">
        <button class="row press grow" data-act="shortcut" data-arg="${esc(l.id)}" aria-label="${esc(l.title)}" style="gap:10px;text-align:left;min-height:36px">
          <span class="circle" style="width:36px;height:36px;background:var(--mint);color:var(--accent)">${icon(folderIcon((l.shortcut || {}).folder), 19)}</span>
          <span style="${f(18, 6)}">${esc(l.title)}</span>
        </button>
        ${steps ? `<button class="press accent" data-act="lesson" data-arg="${esc(l.id)}"
          style="white-space:nowrap;min-height:44px;padding:5px 10px;border-radius:999px;background:var(--mint);${f(15, 6)}">Montrez-moi</button>` : ''}
      </div>`;
    }).join('');
    if (!S.lessons.length && !notice) return '';
    return `<div class="col" style="gap:14px">${notice}${S.lessons.length ? `<div style="${f(21, 7)}">Mes automates</div>` : ''}${tiles}</div>`;
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
      const img = a.icon && a.icon.startsWith('data:image/png;base64,') ? `<img src="${esc(a.icon)}" alt="" width="36" height="36">`
        : icon(a.symbol || (APP_STYLE[a.label] || ['app'])[0], 24, 'var(--accent)');
      return `<div class="col" style="position:relative"><button class="col press" data-act="homeShortcut" data-arg="${esc(a.id)}" aria-label="Ouvrir ${esc(a.label)}"
          style="gap:4px;align-items:center">
        <span class="circle" style="width:54px;height:54px;background:var(--card)">${img}</span>
        <span style="${f(15, 5)};min-height:24px;text-align:center">${esc(a.label)}</span></button>
        ${a.personal && ui.editingShortcuts ? `<button class="removeShortcut" data-act="removeShortcut" data-arg="${esc(a.id)}" aria-label="Retirer ${esc(a.label)}" style="${f(15, 6)}">Retirer</button>` : ''}</div>`;
    }).join('');
    return `<div class="col" style="gap:12px"><div class="row" style="gap:10px;justify-content:space-between">
      <div style="${f(21, 7)}">Mes raccourcis</div>
      ${(S.homeShortcuts || []).some(a => a.personal) ? `<button class="press" data-act="editShortcuts" aria-pressed="${ui.editingShortcuts}" style="min-height:44px;${f(15, 6)}">${ui.editingShortcuts ? 'Terminer' : 'Modifier'}</button>` : ''}
      </div><div class="grid3 homeGrid">${items}
      <button class="col press" data-act="addShortcut" style="gap:4px;align-items:center">
        <span class="circle" style="width:54px;height:54px;background:var(--card)">${icon('plus', 24, 'var(--muted)')}</span>
        <span style="${f(15, 5)};min-height:24px">Ajouter</span></button></div></div>`;
  }

  function addShortcutSheet() {
    return `<div class="sheet card col" style="width:540px;padding:32px;gap:20px">
      <div style="${f(26, 6)}">Ajouter un raccourci</div>
      <div style="${f(16, 5)}">Jusqu'à 4 raccourcis personnels, gardés sur cet ordinateur.</div>
      ${pill('Un dossier', 'chooseFolder', { filled: false, height: 50 })}
      ${ui.warning ? `<div role="status" style="${f(17, 5)}">${esc(ui.warning)}</div>` : ''}
      ${pill('Fermer', 'closeSheet', { height: 50 })}</div>`;
  }

  // ----------------------------------------------------------------- Consent
  function consent() {
    return mint(`
      <div class="accent" style="${f(18, 6)}">Votre demande</div>
      <div style="${f(30, 6)}">« ${esc(S.pendingTask)} »</div>
      <div style="${f(44, 6)};letter-spacing:-0.6px;line-height:1.12">PapAI va regarder votre écran</div>
      ${promise('eye', 'Holo voit votre écran pour comprendre le problème.', 21)}
      ${promise('hand', `Rien ne bouge avant l'accord de ${S.helperName}.`, 21)}
      ${promise('stopCircle', 'Le bouton Arrêter reste visible : vous pouvez tout arrêter à tout moment.', 21)}
      ${promise('check', 'On ne vous le redemandera pas. Vous pouvez retirer cet accord dans Réglages.', 21)}`, 40, 24) +
      `<div class="row" style="gap:14px;margin-top:18px">
        ${pill('Annuler', 'cancelConsent', { filled: false, height: 78, grow: true })}
        ${pill("D'accord, je partage mon écran", 'share', { height: 78, grow: true, disabled: !S.connected })}
      </div>`;
  }

  // ----------------------------------------------------------------- Session
  const guardStopped = (st) => st === 'stopped' && S.stoppedBy === 'gardien';
  function sessionTitle(st) {
    if (S.paused && S.sessionOpen) return "L'aide est en pause";
    if (guardStopped(st)) return 'PapAI a arrêté : cette démarche peut être une arnaque';
    return { planning: 'Holo regarde votre écran…', awaiting_approval: `${S.HelperName} vérifie votre demande`,
      active: `${S.carer} s'en occupe`, awaiting_helper: `${S.HelperName} vous aide`, done: "C'est fait !",
      stopped: "L'assistance est arrêtée." }[st];
  }
  function sessionSubtitle(st) {
    if (S.paused && S.sessionOpen) return 'Vous pouvez utiliser votre ordinateur. Appuyez sur Reprendre quand vous voulez.';
    if (guardStopped(st)) return null;
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
  const bar = (st, h) => `<div style="height:${h}px;border-radius:999px;background:var(--card);overflow:hidden" role="progressbar"
      aria-label="Avancement" aria-valuenow="${Math.round(fraction(st) * 100)}" aria-valuemin="0" aria-valuemax="100">
      <div style="height:100%;width:max(${h}px, ${fraction(st) * 100}%);border-radius:999px;background:var(--accent);transition:width .6s"></div></div>`;
  function progress(st, phase) {
    const steps = ['Holo regarde votre écran et prépare la suite', `${S.HelperName} vérifie et donne son accord`,
      `${S.carer} s'en occupe, avec Holo`];
    const rows = steps.map((text, i) => {
      const done = i < phase, now = i === phase;
      return `<div class="row" style="gap:14px" aria-label="${esc(done ? 'Fait : ' + text : now ? 'En cours : ' + text : text)}">
        <span style="color:${done || now ? 'var(--accent)' : 'var(--muted)'}">${icon(done ? 'checkCircle' : now ? 'circleDotted' : 'circle', 24)}</span>
        <span style="${f(21, now ? 6 : 4)};color:${done ? 'var(--muted)' : 'var(--ink)'}">${esc(text)}</span></div>`;
    }).join('');
    return `<div class="col" style="gap:18px;padding:24px;border-radius:var(--r);background:rgba(255,255,255,.55)">${bar(st, 18)}${rows}</div>`;
  }

  // Une question que Holo pose à la personne aidée, pour ce qu'elle seule sait.
  function seniorQuestion() {
    const sent = ui.seniorSent === S.question;
    const options = (S.questionOptions || []).map((o) =>
      `<button class="pill plain" data-act="seniorOption" data-arg="${esc(o)}" style="height:56px;padding:0 22px;${f(20, 6)}">${esc(o)}</button>`).join('');
    const reply = sent
      ? `<div class="row accent" style="gap:10px">${icon('checkCircle', 22)}<span style="${f(20, 6)}">Merci, c'est noté.</span></div>`
      : `${options ? `<div class="row" style="gap:10px;flex-wrap:wrap">${options}</div>` : ''}
        <div class="row" style="gap:12px">
          <input id="seniorReply" class="grow" placeholder="Votre réponse" value="${esc(ui.seniorText || '')}"
            style="${f(22, 5)};padding:16px 20px;border:0;border-radius:var(--r);background:var(--bg)">
          ${pill('Répondre', 'seniorReply', { height: 56, disabled: !(ui.seniorText || '').trim() })}
        </div>
        <div class="muted" style="${f(15, 4)}">Ne donnez jamais de mot de passe ni de code : on ne vous les demandera pas.</div>`;
    return `<div class="card col" style="padding:24px;gap:16px">
      <div class="muted" style="${f(16, 6)}">Holo vous demande</div>
      <div style="${f(28, 5)}">${esc(S.question)}</div>${reply}</div>`;
  }

  const endNote = (sym, text) => `<div class="row" style="gap:14px"><span class="accent" style="width:28px;display:flex;justify-content:center">${icon(sym, 22)}</span>
    <span class="muted" style="${f(19, 4)}">${esc(text)}</span></div>`;

  function sessionContent(st) {
    if (st === 'planning' || st === 'awaiting_approval' || st === 'active') {
      return progress(st, st === 'planning' ? 0 : st === 'awaiting_approval' ? 1 : 2);
    }
    if (st === 'awaiting_helper') return S.questionForMe && S.question ? seniorQuestion() : progress(st, 2);
    if (st === 'done') {
      return `<div class="col" style="gap:16px">
        <div class="card" style="padding:28px;${f(26, 5)}">${esc(S.answer || 'Voilà, c\'est fait.')}</div>
        ${endNote('lock', "Votre écran n'est plus partagé.")}
        ${endNote('book', `${S.HelperName} peut en faire un automate. Vous le retrouverez dans « Mes automates » pour le refaire sans aide.`)}
      </div>`;
    }
    if (guardStopped(st)) {
      const who = (S.helpers[0] || {}).name || 'votre support';
      return `<div class="col" style="gap:20px;${f(23, 5)}">
        <div>Ne payez rien et ne donnez aucun code.</div>
        <div>Appelez ${esc(who)} à son numéro habituel.</div>
        ${S.guardAcknowledged ? "<div>Votre support a vu l'alerte et s'en occupe</div>" : ''}</div>`;
    }
    return '';
  }

  const canPause = (st) => st === 'active' || st === 'awaiting_helper' || S.paused;
  function pauseButton(height, size) {
    return `<button class="row press" data-act="pause" aria-label="${S.paused ? "Reprendre l'aide" : "Mettre l'aide en pause"}"
        style="justify-content:center;gap:12px;height:${height}px;border-radius:999px;background:var(--card);color:var(--ink);flex:1">
        ${icon(S.paused ? 'play' : 'pause', size - 4)}<span style="${f(size, 6)}">${S.paused ? 'Reprendre' : 'Pause'}</span></button>`;
  }
  function stopButton(height, size) {
    return `<button class="row press" data-act="stop" aria-label="Arrêter l'assistance (Échap)"
        style="justify-content:center;gap:14px;height:${height}px;border-radius:999px;background:var(--ink);color:#fff;flex:1">
        ${icon('stop', size - 4, '#fff')}<span style="${f(size, 6)}">Arrêter</span></button>`;
  }

  function session() {
    const st = S.state || 'planning';
    const sub = sessionSubtitle(st);
    const banner = S.sessionOpen ? `<div class="pillChip" style="align-self:flex-start;gap:10px;padding:10px 18px;${f(16, 6)}">
      <span class="dot" style="background:var(--accent)"></span>Écran partagé</div>` : '';
    const footer = (S.task && st !== 'stopped' && st !== 'awaiting_approval' && !(st === 'awaiting_helper' && S.questionForMe))
      ? `<div class="muted" style="${f(16, 4)};display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden">Votre demande : ${esc(S.task)}</div>` : '';
    const bottom = S.sessionOpen
      ? `<div class="row" style="gap:14px;width:100%">${canPause(st) ? pauseButton(70, 26) : ''}${stopButton(70, 26)}</div>`
      : pill("Retour à l'accueil", 'home', { height: 70, grow: true });
    const inner = `${banner}
      <div style="${f(guardStopped(st) ? 34 : 40, 6)};letter-spacing:-0.6px;line-height:1.12">${esc(sessionTitle(st))}</div>
      ${sub ? `<div class="fade" style="${f(24, 5)};color:${st === 'active' ? 'var(--ink)' : 'var(--muted)'}">${esc(sub)}</div>` : ''}
      <div class="scroll">${sessionContent(st)}</div>
      <div class="spacer"></div>${footer}`;
    const card = guardStopped(st)
      ? `<div class="col" style="padding:34px;gap:18px;border-radius:var(--rBig);background:var(--card);flex:1;min-height:0">${inner}</div>`
      : mint(inner, 34, 18);
    return card + `<div class="row" style="margin-top:18px">${bottom}</div>`;
  }

  // Petit encart pendant que Holo agit (MiniPanel du Mac) : la fenêtre se range
  // en bas à droite pour qu'on voie ce qu'il fait ; Pause et Arrêter restent là.
  function mini() {
    const st = S.state || 'planning';
    const title = S.paused && S.sessionOpen ? "L'aide est en pause" : ({ planning: 'Holo prépare la suite…',
      awaiting_approval: `${S.HelperName} vérifie`, active: `${S.carer} s'en occupe`,
      awaiting_helper: `${S.HelperName} vous aide`, done: "C'est fait !" }[st] || 'PapAI');
    return `<div class="col mini" style="gap:10px;padding:14px 16px">
      <div class="row" style="gap:10px">
        <span class="dot" style="background:${S.sessionOpen && !S.paused ? 'var(--accent)' : 'var(--muted)'}"></span>
        <span class="grow" style="${f(17, 6)};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(title)}</span>
        <button class="circle press" data-act="expand" aria-label="Ouvrir PapAI en grand"
          style="width:30px;height:30px;background:var(--bg)">${icon('expand', 14)}</button>
      </div>
      ${bar(st, 8)}
      <div class="row" style="gap:8px">${canPause(st) ? pauseButton(40, 15) : ''}${stopButton(40, 15)}</div>
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
      body = `<div class="accent" style="${f(18, 6)}">Étape ${i + 1} sur ${steps.length}</div>
        <div style="${f(36, 6)};letter-spacing:-0.4px;line-height:1.15">${esc(s.instruction || '')}</div>
        ${s.checkpoint ? `<div class="card" style="padding:18px;${f(19, 4)}">Vous devriez voir : ${esc(s.checkpoint)}</div>` : ''}
        ${img}`;
    }
    const last = i >= steps.length - 1;
    return mint(`<div class="muted" style="${f(18, 6)}">${esc(l.title)}</div>${body}`, 40, 20) +
      `<div class="row" style="gap:14px;margin-top:18px">
        ${pill('Fermer', 'closeLesson', { filled: false, height: 72 })}
        ${i > 0 ? pill('Précédent', 'prevStep', { filled: false, height: 72 }) : ''}
        ${pill(last ? 'Terminé' : 'Suivant', 'nextStep', { height: 72, grow: true })}
      </div>`;
  }

  // -------------------------------------------------------------- Onboarding
  const ONB = 4;  // la taille du texte se règle dans les réglages, pas à l'accueil
  function onboarding() {
    const step = S.onboardingStep;
    const dots = `<div class="row dots" style="gap:8px" aria-label="Étape ${step + 1} sur ${ONB}">` +
      Array.from({ length: ONB }, (_, i) => `<span class="d" style="width:${i === step ? 34 : 12}px;background:${i <= step ? 'var(--accent)' : 'var(--card)'}"></span>`).join('') + '</div>';
    const content = [onbWelcome, onbName, onbPermissions, () => helpersPanel(true)][step]();
    const label = step === 0 ? 'Commencer' : step === ONB - 1 ? (S.helpers.length ? 'Terminer' : 'Plus tard') : 'Continuer';
    return mint(`${dots}<div class="col" style="gap:22px;flex:1;min-height:0">${content}</div>`, 40, 22) +
      `<div class="row" style="gap:14px;margin-top:18px">
        ${step > 0 ? pill('Retour', 'onbBack', { filled: false, height: 78 }) : ''}
        ${pill(label, 'onbNext', { height: 78, grow: true })}
      </div>`;
  }
  const h1 = (text, size) => `<div style="${f(size || 44, 6)};letter-spacing:${size === 52 ? -0.8 : -0.6}px;line-height:1.1">${esc(text)}</div>`;
  const lead = (text, size) => `<div class="muted" style="${f(size || 21, 5)}">${esc(text)}</div>`;

  function onbWelcome() {
    return h1('Bienvenue sur PapAI', 52) +
      lead("Quand quelque chose ne marche pas sur l'ordinateur, vous appuyez sur un bouton et vous expliquez avec vos mots. Votre support est prévenu et vous aide, avec Holo, un assistant qui sait se servir de l'ordinateur.", 23) +
      promise('hand', "Rien ne bouge sur votre écran sans l'accord de votre support.", 20) +
      promise('stopCircle', 'Vous pouvez tout arrêter à tout moment.', 20) +
      promise('lock', "Votre écran n'est partagé que quand vous le demandez.", 20);
  }
  function onbName() {
    if (ui.name === null) ui.name = S.storedFirstName || '';
    return h1('Comment vous appelez-vous ?') +
      lead("Votre prénom suffit. C'est ainsi que PapAI vous dira bonjour.") +
      `<input id="name" class="field" placeholder="Votre prénom" value="${esc(ui.name)}" autocomplete="off"
        style="padding:22px 26px;${f(30, 6)}">`;
  }
  function onbTextSize() {
    const opts = S.textScales.map(([label, v]) => {
      const on = Math.abs(S.textScale - v) < 0.01;
      return `<button class="col press grow card" data-act="scale" data-arg="${v}" aria-pressed="${on}"
          style="height:190px;gap:10px;align-items:center;justify-content:center;
          box-shadow:${on ? '0 0 0 2px var(--accent), inset 0 0 0 2px var(--accent)' : 'none'}">
        <span style="font-size:${54 * v}px;font-weight:600">Aa</span>
        <span style="font-size:${20 * v}px;font-weight:500">${label}</span></button>`;
    }).join('');
    return h1('La taille du texte') +
      lead('Choisissez ce qui est le plus confortable à lire. Vous pourrez changer plus tard.') +
      `<div class="row" style="gap:16px">${opts}</div>`;
  }
  function permissionRow(title, detail) {
    return `<div class="card row" style="gap:18px;padding:20px">
      <span class="accent">${icon('checkCircle', 34)}</span>
      <div class="col grow" style="gap:4px"><div style="${f(22, 6)}">${esc(title)}</div>
      <div class="muted" style="${f(17, 4)}">${esc(detail)}</div></div></div>`;
  }
  function onbPermissions() {
    // Windows ne demande pas d'autorisation pour voir l'écran ni pour la souris :
    // même étape, mêmes engagements, déjà cochés.
    return h1('Deux autorisations, déjà prêtes') +
      lead("Sur Windows, rien à cocher : PapAI peut voir l'écran et utiliser la souris, mais seulement quand vous le demandez.") +
      permissionRow('Voir mon écran', 'Pour que Holo voie ce que vous voyez. Jamais sans votre demande.') +
      permissionRow('Utiliser la souris et le clavier', "Pour cliquer à votre place, uniquement après l'accord de votre support.");
  }

  // ------------------------------------------------------------ HelpersPanel
  function helpersPanel(onb) {
    const rows = S.helpers.map((h) => `<div class="card row" style="gap:14px;padding:14px">
        <span class="circle" style="width:46px;height:46px;background:var(--accent);color:#fff;${f(20, 6)}">${esc((h.name[0] || '').toUpperCase())}</span>
        <div class="col grow" style="gap:2px"><div style="${f(21, 6)}">${esc(h.name)}</div>
          ${h.relation ? `<div class="muted" style="${f(16, 4)}">${esc(cap(h.relation))}</div>` : ''}</div>
        ${onb ? '' : `<button class="circle press" data-act="removeHelper" data-arg="${esc(h.id)}" aria-label="Retirer ${esc(h.name)}"
          style="width:36px;height:36px;background:var(--bg)">${icon('xmark', 16)}</button>`}
      </div>`).join('');
    const add = S.pairCode ? '' :
      `<div>${pill(S.helpers.length ? 'Ajouter un autre support' : 'Ajouter un support', 'pair', { filled: !S.helpers.length, height: 60, disabled: !S.connected })}</div>
       ${S.connected ? '' : `<div class="muted" style="${f(16, 4)}">Connexion au serveur en cours…</div>`}`;
    const added = S.pairAdded ? `<div class="row accent" style="gap:8px;${f(19, 6)}">${icon('checkCircle', 22)}${esc(S.pairAdded)} fait maintenant partie de votre support.</div>` : '';
    const code = S.pairCode ? `<div class="card col" style="padding:18px 22px;gap:8px;align-items:center;flex:none">
        ${S.pairQR ? `<img src="${S.pairQR}" alt="QR code à scanner par votre support" style="width:170px;height:170px;image-rendering:pixelated">` : ''}
        <div class="muted" style="${f(16, 4)}">ou le code</div>
        <div style="font-size:${38 * S.textScale}px;font-weight:600;letter-spacing:4px;font-variant-numeric:tabular-nums;user-select:text">${esc(S.pairCode.slice(0, 3))} ${esc(S.pairCode.slice(3))}</div>
        <div class="muted" style="${f(15, 4)}">${S.pairLong ? 'Valable 24 heures' : 'Valable 10 minutes'}</div>
        ${S.pairURL ? `<button class="accent press" data-act="shareInvite" style="${f(17, 6)}">Envoyer par SMS, WhatsApp…</button>` : ''}
        ${ui.inviteCopied ? `<div class="accent" style="max-width:260px;text-align:center;${f(15, 6)}">${esc(ui.inviteCopied)}</div>` : ''}
        ${S.pairURL ? `<div class="muted" style="max-width:240px;text-align:center;word-break:break-all;user-select:text;${f(13, 4)}">Sans l'app PapAI : ${esc(S.pairURL)}</div>` : ''}
        <button class="muted" data-act="stopPair" style="${f(17, 6)}">Annuler</button>
      </div>` : '';
    return `<div class="row" style="align-items:flex-start;gap:28px">
      <div class="col grow" style="gap:20px">
        <div style="${f(onb ? 44 : 34, 6)};letter-spacing:-0.6px;line-height:1.1">${onb ? 'Qui va vous aider ?' : 'Mon support'}</div>
        <div class="muted" style="${f(20, 4)}">Votre fille, votre fils, un ami… S'il est à côté de vous, il scanne le code avec son téléphone. Sinon, envoyez-lui le lien par SMS ou WhatsApp. Vous pouvez en ajouter plusieurs.</div>
        ${added}${rows}${add}
      </div>${code}</div>`;
  }

  // ----------------------------------------------------------- RemoteRequest
  function remote() {
    const r = S.remoteRequest;
    return mint(`<div class="row accent" style="gap:12px">${icon('personWave', 28)}<span style="${f(20, 6)}">Proposition d'aide</span></div>
      <div style="${f(48, 6)};letter-spacing:-0.7px;line-height:1.1">${esc(r.from)} propose de vous aider</div>
      ${r.task ? `<div class="card" style="padding:24px;${f(26, 5)}">« ${esc(r.task)} »</div>` : ''}
      ${lead(`Si vous acceptez, PapAI va regarder votre écran. Rien ne bouge avant l'accord de ${r.from}, et vous pouvez arrêter à tout moment.`)}`, 40, 22) +
      `<div class="row" style="gap:14px;margin-top:18px">
        ${pill('Non merci', 'refuseRemote', { filled: false, height: 78, grow: true })}
        ${pill("Oui, j'accepte", 'acceptRemote', { height: 78, grow: true, disabled: !S.connected })}
      </div>`;
  }

  // ------------------------------------------------------------------ Feuilles
  function settingsSheet() {
    const field = (label, id, val, ph) => `<div class="col" style="gap:8px">
      <div class="muted" style="${f(15, 6)}">${label}</div>
      <input id="${id}" value="${esc(val)}" placeholder="${esc(ph)}" autocomplete="off"
        style="background:var(--card);border-radius:18px;padding:16px;${f(18, 5)}"></div>`;
    const seg = S.textScales.map(([label, v]) =>
      `<button class="${Math.abs(S.textScale - v) < 0.01 ? 'on' : ''}" data-act="scale" data-arg="${v}">${label}</button>`).join('');
    return `<div class="sheet col" style="width:520px;padding:32px;gap:18px;background:var(--bg)">
      <div style="${f(30, 6)}">Réglages</div>
      ${field('Prénom', 'setName', ui.settings.name, 'Jeanne')}
      ${field('Serveur', 'setServer', ui.settings.server, 'ws://localhost:8000/ws/bridge')}
      <div class="col" style="gap:8px"><div class="muted" style="${f(15, 6)}">Taille du texte</div><div class="seg">${seg}</div></div>
      <div class="row" style="gap:12px">
        ${pill(`Mon support (${S.helpers.length})`, 'openHelpers', { filled: false, height: 50 })}
        ${pill("Revoir l'accueil", 'replayOnboarding', { filled: false, height: 50 })}
        ${S.screenConsent ? pill("Retirer l'accord de partage", 'revokeConsent', { filled: false, height: 50 }) : ''}
      </div>
      <div class="row" style="gap:8px"><div class="spacer"></div>
        ${pill('Annuler', 'closeSheet', { filled: false, height: 50 })}
        ${pill('Enregistrer', 'saveSettings', { height: 50 })}
      </div></div>`;
  }
  function helpersSheet() {
    return `<div class="sheet col" style="width:820px;min-height:460px;padding:36px;gap:18px;background:var(--mint)">
      ${helpersPanel(false)}<div class="spacer"></div>
      <div class="row"><div class="spacer"></div>${pill('Fermer', 'closeHelpers', { height: 54 })}</div></div>`;
  }

  // Alerte du gardien (PROTOCOL.md) : elle passe devant tout.
  function alertSheet() {
    const a = S.alert, danger = a.level === 'danger';
    const tint = danger ? '#C8442F' : 'var(--accent)';
    return `<div class="sheet col" style="width:620px;padding:36px;gap:18px;background:var(--card)">
      <div class="row" style="gap:14px;color:${tint}">${icon('exclam', 30, tint)}
        <span style="${f(17, 6)}">${danger ? 'Attention' : 'Pour information'}</span></div>
      <div style="${f(30, 6)}">${esc(a.title)}</div>
      ${a.detail ? `<div class="muted" style="${f(19, 5)}">${esc(a.detail)}</div>` : ''}
      ${a.acknowledged ? `<div style="${f(20, 6)}">Votre support a vu l'alerte et s'en occupe</div>` : ''}
      ${a.blocked ? '' : `<div class="row"><div class="spacer"></div>${pill("J'ai compris", 'dismissAlert', { height: 56 })}</div>`}</div>`;
  }

  // ------------------------------------------------------------------- rendu
  function body() {
    if (!S.onboarded) return onboarding();
    if (S.remoteRequest) return remote();
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
    const compact = S.compact && S.screen === 'session' && S.onboarded && !S.remoteRequest;
    if (document.body) document.body.classList.toggle('compact', compact);
    document.getElementById('root').innerHTML = compact ? mini() : header() + `<div class="main">${body()}</div>`;
    document.getElementById('sheet').innerHTML =
      S.alert ? alertSheet() : ui.sheet === 'settings' ? settingsSheet()
        : ui.sheet === 'helpers' ? helpersSheet() : ui.sheet === 'addShortcut' ? addShortcutSheet() : '';
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
  function setStep(n) { S.onboardingStep = n; render(); call('set_onboarding_step', n); }
  function onbNext() {
    const step = S.onboardingStep;
    if (step === 1) {
      const n = (ui.name || '').trim();
      if (!n) { focus('name'); return; }
      call('set_first_name', n);
    }
    if (step >= ONB - 1) { call('finish_onboarding'); return; }
    setStep(step + 1);
  }
  function lessonNext() {
    const n = (S.lesson.steps || []).length;
    if (ui.lessonIndex >= n - 1) call('close_lesson'); else { ui.lessonIndex += 1; render(); }
  }

  const acts = {
    submit, mic: () => {
      if (!S.microPresent || S.dictation.phase === 'starting' || S.dictation.phase === 'transcribing') return;
      if (S.dictation.phase === 'idle' && ui.dictating) return;
      ui.warning = null; ui.dictating = true; render();
      Promise.resolve(call('dictation_toggle')).catch(() => { ui.dictating = false; render(); });
    },
    write: () => { ui.writing = true; render(); focus('req'); },
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
    openSettings: () => { ui.settings = { name: S.storedFirstName || S.firstName, server: S.server }; ui.sheet = 'settings'; render(); },
    closeSheet: () => { ui.sheet = null; render(); },
    dismissAlert: () => { if (!S.alert?.blocked) { S.alert = null; render(); call('dismiss_alert'); } },
    openHelpers: () => { ui.sheet = 'helpers'; render(); },
    closeHelpers: () => { call('stop_pairing'); ui.sheet = null; render(); },
    replayOnboarding: () => { ui.sheet = null; ui.name = null; call('reset_onboarding'); render(); },
    saveSettings: () => { call('save_settings', ui.settings.name, ui.settings.server); ui.sheet = null; render(); },
    scale: (v) => { S.textScale = parseFloat(v); render(); call('set_text_scale', parseFloat(v)); },
    shortcut: (id) => call('run_shortcut', id),
    lesson: (id) => call('open_lesson', id),
    cancelConsent: () => call('cancel_consent'),
    share: () => call('give_consent'),
    revokeConsent: () => { S.screenConsent = false; render(); call('revoke_consent'); },
    stop: () => call('stop'),
    pause: () => call('toggle_pause'),
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
    onbBack: () => setStep(Math.max(0, S.onboardingStep - 1)),
    onbNext,
    pair: () => { ui.inviteCopied = null; call('start_pairing'); },
    stopPair: () => { ui.inviteCopied = null; call('stop_pairing'); },
    shareInvite: () => Promise.resolve(call('copy_invitation')).then((ok) => {
      ui.inviteCopied = ok ? "Invitation copiée : collez-la dans un SMS, WhatsApp ou un mail."
        : "Copie impossible : recopiez le lien ci-dessous.";
      render();
    }),
    removeHelper: (id) => call('remove_helper', id),
    acceptRemote: () => call('accept_remote'),
    refuseRemote: () => call('refuse_remote'),
  };

  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]');
    if (!b || b.disabled) return;
    const fn = acts[b.dataset.act];
    if (fn) fn(b.dataset.arg);
  });
  document.addEventListener('input', (e) => {
    const t = e.target;
    if (t.id === 'req') { ui.request = t.value; autosize(t); }
    else if (t.id === 'name') ui.name = t.value;
    else if (t.id === 'seniorReply') {
      const was = !(ui.seniorText || '').trim(), now = !t.value.trim();
      ui.seniorText = t.value;
      if (was !== now) render();
    }
    else if (t.id === 'setName') ui.settings.name = t.value;
    else if (t.id === 'setServer') ui.settings.server = t.value;
  });
  // keyboardShortcut(.cancelAction) / (.defaultAction) des vues Mac
  document.addEventListener('keydown', (e) => {
    if (!S) return;
    const t = e.target;
    if (S.alert && (e.key === 'Enter' || e.key === 'Escape')) { e.preventDefault(); return; }
    if (e.key === 'Escape') {
      if (S.onboarded && S.screen === 'session' && S.sessionOpen) { ui.sheet = null; return acts.stop(); }
      if (ui.sheet) { ui.sheet === 'helpers' ? acts.closeHelpers() : acts.closeSheet(); return; }
      if (!S.onboarded) return;
      if (S.remoteRequest) return acts.refuseRemote();
      if (S.screen === 'consent') return acts.cancelConsent();
      if (S.screen === 'lesson') return acts.closeLesson();
      return;
    }
    if (e.key !== 'Enter' || e.shiftKey || ui.sheet) return;
    if (t && t.tagName === 'BUTTON') return;
    if (t && t.id === 'req') { e.preventDefault(); submit(); return; }
    if (t && t.id === 'seniorReply') { e.preventDefault(); acts.seniorReply(); return; }
    if (!S.onboarded) { e.preventDefault(); onbNext(); return; }
    if (S.remoteRequest) return;
    if (S.screen === 'consent' && S.connected) acts.share();
    else if (S.screen === 'lesson') lessonNext();
    else if (S.screen === 'session' && !S.sessionOpen) acts.home();
  });

  window.PapAI = {
    update(snap) {
      const was = S && S.screen;
      S = snap;
      if (!(S.homeShortcuts || []).some(a => a.personal)) ui.editingShortcuts = false;
      const m = S.dictation && S.dictation.message;
      if (m && m !== ui.lastDictMsg) ui.warning = m;
      if (m && S.dictation.phase === 'idle') ui.dictating = false;
      ui.lastDictMsg = m || null;
      if (S.onboarded) ui.name = null;
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
    expand_window: () => { S.compact = false; render(); },
    answer_senior: () => {},
    finish_onboarding: () => { S.onboarded = true; render(); },
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
        if (q.get('sheet')) {
          ui.sheet = q.get('sheet');
          ui.settings = { name: snap.firstName, server: snap.server };
        }
        if (q.get('dictation')) snap.dictation = { phase: q.get('dictation'), message: null };
        if (q.get('request')) ui.request = q.get('request');
        if (q.get('connected') === '0') snap.connected = false;
        window.PapAI.update(snap);
      });
    }
  }
  if (window.pywebview && window.pywebview.api) boot();
  else window.addEventListener('pywebviewready', boot);
  window.addEventListener('DOMContentLoaded', () => { if (!api) setTimeout(() => { if (!api && !S) boot(); }, 300); });
})();
