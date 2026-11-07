"use strict";

const connus = fetch(chrome.runtime.getURL("sites_connus.json")).then((r) => r.json());
const enCours = new Set();

function domaineHttp(adresse) {
  try {
    const url = new URL(adresse);
    return ["http:", "https:"].includes(url.protocol)
      ? url.hostname.toLowerCase().replace(/^\[|\]$/g, "").replace(/\.$/, "") : "";
  } catch {
    return "";
  }
}

function ignorerDomaine(domaine, serveur) {
  const hote = domaine.toLowerCase().replace(/^\[|\]$/g, "").replace(/\.$/, "");
  if (["localhost", "127.0.0.1", "::1"].includes(hote)) return true;
  const octets = hote.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)?.slice(1).map(Number);
  if (octets && octets.every((octet) => octet <= 255)) {
    const [premier, deuxieme] = octets;
    if (premier === 10 || (premier === 172 && deuxieme >= 16 && deuxieme <= 31) ||
        (premier === 192 && deuxieme === 168)) return true;
  }
  const hoteServeur = domaineHttp(serveur || "");
  return Boolean(hote && hoteServeur && hote === hoteServeur);
}

async function estConnu(domaine) {
  const sites = await connus;
  if (sites.exceptions_exactes.includes(domaine)) return true;
  if (sites.exclusions.some((parent) => domaine === parent || domaine.endsWith("." + parent))) return false;
  return sites.connus.some((parent) => domaine === parent || domaine.endsWith("." + parent));
}

async function appliquer(onglet, navigation, avis) {
  const liaison = await chrome.storage.local.get("token");
  if (!liaison.token) return;
  await chrome.tabs.sendMessage(onglet, {type: "avis_site", domaine: navigation.domaine,
    verdict: avis.verdict, proche: avis.proche || "votre proche"}, {documentId: navigation.documentId});
}

async function analyser(onglet) {
  const cle = "onglet:" + onglet;
  const navigation = (await chrome.storage.session.get(cle))[cle];
  if (!navigation?.attente || enCours.has(navigation.documentId)) return;
  enCours.add(navigation.documentId);
  try {
    const liaison = await chrome.storage.local.get(["server", "token"]);
    if (!liaison.server || !liaison.token || ignorerDomaine(navigation.domaine, liaison.server)) return;
    const cleCache = "avis:" + navigation.domaine;
    const cache = (await chrome.storage.local.get(cleCache))[cleCache];
    let avis = cache?.expire > Date.now() ? cache : null;
    if (!avis) {
      const page = await chrome.tabs.sendMessage(onglet, {type: "extrait_site"}, {documentId: navigation.documentId});
      if (!page || page.domaine !== navigation.domaine) return;
      const reponse = await fetch(liaison.server + "/ext/site", {
        method: "POST", credentials: "omit", redirect: "error",
        headers: {"Content-Type": "application/json", Authorization: "Bearer " + liaison.token},
        body: JSON.stringify({domain: navigation.domaine, title: page.titre.slice(0, 300), text: page.texte.slice(0, 2000)}),
        signal: AbortSignal.timeout(25000)
      });
      if ((await chrome.storage.local.get("token")).token !== liaison.token) return;
      if (reponse.status === 401) {
        await chrome.storage.local.clear();
        await chrome.storage.local.set({server: liaison.server,
          message: "La liaison avec PapAI a été perdue. Demandez un nouveau code dans les Réglages de PapAI."});
        return;
      }
      if (!reponse.ok) return;
      avis = await reponse.json();
      if (!["sur", "douteux", "arnaque"].includes(avis.verdict)) return;
      const duree = avis.verdict === "sur" ? 24 * 3600000 : 3600000;
      avis = {verdict: avis.verdict, proche: typeof avis.proche === "string" ? avis.proche.slice(0, 40) : "votre proche",
        expire: Date.now() + duree};
      await chrome.storage.local.set({[cleCache]: avis});
    }
    const actuel = (await chrome.storage.session.get(cle))[cle];
    if (actuel?.documentId !== navigation.documentId) return;
    await appliquer(onglet, navigation, avis);
    await chrome.storage.session.set({[cle]: {...navigation, attente: false}});
  } catch {
    // Une page fermée ou un serveur indisponible ne vaut pas un avis rassurant.
  } finally {
    enCours.delete(navigation.documentId);
  }
}

chrome.webNavigation.onCommitted.addListener(async (details) => {
  if (details.frameId !== 0) return;
  const domaine = domaineHttp(details.url);
  const cle = "onglet:" + details.tabId;
  const precedent = (await chrome.storage.session.get(cle))[cle];
  const cleCache = "avis:" + domaine;
  const liaison = await chrome.storage.local.get(["server", cleCache]);
  const cache = liaison[cleCache];
  const attente = Boolean(domaine && !ignorerDomaine(domaine, liaison.server) && !(await estConnu(domaine)) &&
    (domaine !== precedent?.domaine || cache?.expire > Date.now()));
  await chrome.storage.session.set({[cle]: {domaine, documentId: details.documentId, attente}});
  if (attente) setTimeout(() => analyser(details.tabId), 1800);
});

chrome.webNavigation.onCompleted.addListener((details) => {
  if (details.frameId === 0) analyser(details.tabId);
});

chrome.tabs.onRemoved.addListener((onglet) => chrome.storage.session.remove("onglet:" + onglet));
chrome.runtime.onMessage.addListener((message, expediteur) => {
  if (expediteur.id !== chrome.runtime.id || !expediteur.tab || expediteur.frameId !== 0) return;
  if (message.type === "page_prete") analyser(expediteur.tab.id);
  if (message.type === "quitter_site") {
    chrome.tabs.update(expediteur.tab.id, {url: "about:blank"});
  }
});
