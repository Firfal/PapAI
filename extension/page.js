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
        inset: 0 !important; z-index: 2147483647 !important; margin: 0 !important; padding: 0 !important;
        border: 0 !important; opacity: 1 !important; visibility: visible !important;
        width: 100vw !important; height: ${danger ? "100vh" : "max-content"} !important; }
      * { box-sizing: border-box; }
      section { font: 22px/1.5 ui-rounded, "SF Pro Rounded", -apple-system, system-ui, "Segoe UI", sans-serif;
        color: #111312; background: #FFF8F0; padding: 22px 28px; }
      .danger { width: 100%; height: 100vh; overflow: auto; display: flex; align-items: center;
        justify-content: center; text-align: center; }
      .carte { width: min(100%, 720px); margin: auto; padding: 32px 12px; }
      .marque { font-size: 22px; font-weight: 700; color: #2F6B4A; }
      h1 { font-size: clamp(30px, 4vw, 46px); line-height: 1.2; margin: 24px 0; }
      p { margin: 20px 0; font-size: 28px; }
      button { font: inherit; cursor: pointer; }
      .quitter { display: block; margin: 30px auto 18px; border: 0; border-radius: 999px;
        background: #2F6B4A; color: white; font-weight: 700; padding: 18px 32px; min-height: 64px; }
      .continuer { border: 0; background: transparent; color: #2F6B4A; text-decoration: underline;
        font-size: 18px; padding: 14px; }
      .banniere { display: flex; align-items: center; gap: 20px; background: #E2F2E7;
        box-shadow: 0 3px 12px #11131222; font-size: 19px; }
      .banniere span { flex: 1; }
      .fermer { border: 1px solid #2F6B4A; border-radius: 999px; color: #2F6B4A;
        background: white; padding: 10px 18px; font-size: 17px; }
      :focus-visible { outline: 3px solid #2E9E5B; outline-offset: 4px; }
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
      carte.append(marque, titre, detail, quitter, continuer);
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
      section.append(texte, bouton);
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
