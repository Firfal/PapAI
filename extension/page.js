"use strict";

(() => {
  let hote = null;
  let surveillance = null;
  let verdictAffiche = "";

  function fermer() {
    surveillance?.disconnect();
    surveillance = null;
    hote?.remove();
    hote = null;
    verdictAffiche = "";
  }

  function extraitVisible() {
    const morceaux = [];
    const parcours = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
    let noeud;
    let longueur = 0;
    while ((noeud = parcours.nextNode()) && longueur < 4000) {
      const parent = noeud.parentElement;
      if (!parent || parent.closest("input, textarea, select, option, [contenteditable], script, style, noscript, [hidden], [aria-hidden='true']")) continue;
      const style = getComputedStyle(parent);
      if (!parent.getClientRects().length || style.visibility !== "visible" || style.opacity === "0") continue;
      const texte = noeud.textContent.replace(/\s+/g, " ").trim();
      if (texte) { morceaux.push(texte); longueur += texte.length; }
    }
    return morceaux.join(" ").replace(/\s+/g, " ").trim().slice(0, 2000);
  }

  function signaler() {
    const signal = document.createElement("span");
    signal.className = "signal";
    signal.setAttribute("aria-hidden", "true");
    signal.textContent = "!";
    return signal;
  }

  function afficher(avis) {
    if (avis.verdict === "sur") { fermer(); return; }
    if (!["douteux", "arnaque"].includes(avis.verdict) || verdictAffiche === avis.verdict) return;
    fermer();
    verdictAffiche = avis.verdict;
    const danger = avis.verdict === "arnaque";
    hote = document.createElement("div");
    const racine = hote.attachShadow({mode: "closed"});
    const style = document.createElement("style");
    style.textContent = `
      :host { all: initial !important; display: block !important; position: fixed !important;
        inset: ${danger ? "0" : "auto 20px 20px auto"} !important;
        width: ${danger ? "100vw" : "min(440px, calc(100vw - 32px))"} !important;
        height: ${danger ? "100vh" : "auto"} !important;
        z-index: 2147483647 !important; margin: 0 !important; padding: 0 !important;
        border: 0 !important; opacity: 1 !important; visibility: visible !important;
        pointer-events: auto !important; }
      * { box-sizing: border-box; }
      section { font: 22px/1.5 ui-rounded, "SF Pro Rounded", -apple-system, system-ui, "Segoe UI", sans-serif;
        color: #111312; background: #FFFFFF; padding: 22px 28px; }
      .danger { width: 100%; height: 100%; overflow: auto; display: flex; align-items: center;
        justify-content: center; text-align: center; background: #EEF0EE; padding: 24px; }
      .carte { width: min(100%, 680px); margin: auto; padding: 40px 36px; border-radius: 36px;
        background: #FFFFFF; box-shadow: 0 12px 40px #11131218; }
      .signal { display: grid; place-items: center; flex: none; width: 58px; height: 58px;
        border-radius: 50%; color: #FFFFFF; background: #C8442F; font-size: 36px; line-height: 1;
        font-weight: 800; }
      .marque { margin-top: 22px; font-size: 19px; font-weight: 650; color: #7A807C; }
      h1 { font-size: clamp(30px, 4vw, 44px); line-height: 1.2; margin: 20px 0; }
      p { margin: 20px 0; font-size: 24px; }
      button { font: inherit; cursor: pointer; }
      .quitter { display: block; margin: 30px auto 18px; border: 0; border-radius: 999px;
        background: #111312; color: #FFFFFF; font-weight: 700; padding: 18px 32px; min-height: 64px; }
      .continuer { min-height: 44px; border: 0; background: transparent; color: #7A807C;
        text-decoration: underline; font-size: 17px; padding: 12px 16px; }
      .banniere { display: flex; align-items: center; gap: 16px; border-left: 6px solid #C8442F;
        border-radius: 28px; background: #FFFFFF; box-shadow: 0 8px 28px #11131218;
        padding: 18px 20px; font-size: 17px; }
      .banniere .signal { width: 42px; height: 42px; font-size: 27px; }
      .banniere > span:not(.signal) { flex: 1; }
      .fermer { min-height: 44px; border: 1px solid #7A807C; border-radius: 999px; color: #111312;
        background: #FFFFFF; padding: 9px 18px; font-size: 16px; }
      :focus-visible { outline: 3px solid #C8442F; outline-offset: 4px; }
    `;
    racine.append(style);
    const section = document.createElement("section");
    section.className = danger ? "danger" : "banniere";
    section.setAttribute("role", danger ? "alertdialog" : "status");
    if (danger) {
      section.setAttribute("aria-modal", "true");
      section.setAttribute("aria-labelledby", "titre");
      const carte = document.createElement("div");
      carte.className = "carte";
      const icone = signaler();
      const marque = document.createElement("div");
      marque.className = "marque";
      marque.textContent = "PapAI Gardien";
      const titre = document.createElement("h1");
      titre.id = "titre";
      titre.textContent = "Attention, ce site peut être une arnaque.";
      const detail = document.createElement("p");
      detail.textContent = "Ne donnez rien. Appelez " + (avis.proche || "votre proche") + ".";
      const quitter = document.createElement("button");
      quitter.className = "quitter";
      quitter.textContent = "Quitter ce site";
      quitter.addEventListener("click", () => chrome.runtime.sendMessage({type: "quitter_site"}));
      const continuer = document.createElement("button");
      continuer.className = "continuer";
      continuer.textContent = "Je connais ce site, continuer";
      continuer.addEventListener("click", fermer);
      carte.append(icone, marque, titre, detail, quitter, continuer);
      section.append(carte);
      section.addEventListener("keydown", (evenement) => {
        if (evenement.key === "Tab") {
          evenement.preventDefault();
          (racine.activeElement === quitter ? continuer : quitter).focus();
        }
      });
    } else {
      const texte = document.createElement("span");
      texte.textContent = "Prudence : ce site est inconnu. Ne donnez pas vos codes ni votre carte.";
      const bouton = document.createElement("button");
      bouton.className = "fermer";
      bouton.textContent = "Fermer";
      bouton.addEventListener("click", fermer);
      section.append(signaler(), texte, bouton);
    }
    racine.append(section);
    document.documentElement.append(hote);
    if (danger) {
      surveillance = new MutationObserver(() => {
        if (hote && !hote.isConnected) document.documentElement.append(hote);
      });
      surveillance.observe(document.documentElement, {childList: true});
      racine.querySelector("button").focus();
    }
  }

  chrome.runtime.onMessage.addListener((message, expediteur, repondre) => {
    if (expediteur.id !== chrome.runtime.id) return;
    if (message.type === "extrait_site") {
      repondre({domaine: location.hostname.toLowerCase().replace(/\.$/, ""),
        titre: document.title.slice(0, 300), texte: extraitVisible()});
    }
    if (message.type === "avis_site" && message.domaine === location.hostname.toLowerCase().replace(/\.$/, "")) afficher(message);
  });
  chrome.runtime.sendMessage({type: "page_prete"}).catch(() => {});
})();
