"use strict";

const formulaire = document.getElementById("liaison");
const protege = document.getElementById("protege");
const message = document.getElementById("message");
const serveur = document.getElementById("serveur");

async function afficher() {
  const etat = await chrome.storage.local.get(["server", "token", "message"]);
  formulaire.hidden = Boolean(etat.token);
  protege.hidden = !etat.token;
  serveur.value = etat.server || "";
  message.textContent = etat.message || "";
}

formulaire.addEventListener("submit", async (evenement) => {
  evenement.preventDefault();
  const bouton = document.getElementById("lier");
  bouton.disabled = true;
  message.textContent = "Liaison en cours…";
  try {
    const adresse = new URL(serveur.value.trim());
    if (!["http:", "https:"].includes(adresse.protocol) || adresse.username || adresse.password ||
        adresse.search || adresse.hash || !["", "/"].includes(adresse.pathname)) {
      throw new Error("Indiquez l'adresse du serveur, sans clé, chemin ni paramètres.");
    }
    const reponse = await fetch(adresse.origin + "/ext/pair", {
      method: "POST", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({code: document.getElementById("code").value.trim()}),
      credentials: "omit", redirect: "error", signal: AbortSignal.timeout(15000)
    });
    const resultat = await reponse.json();
    if (!reponse.ok || typeof resultat.token !== "string" || !resultat.token) {
      throw new Error(resultat.error || "Ce code n'a pas pu être associé. Demandez-en un nouveau.");
    }
    await chrome.storage.local.clear();
    await chrome.storage.local.set({server: adresse.origin, token: resultat.token});
    document.getElementById("code").value = "";
    await afficher();
  } catch (erreur) {
    message.textContent = erreur instanceof TypeError || erreur.name === "TimeoutError"
      ? "Le serveur ne répond pas. Vérifiez son adresse et votre connexion."
      : erreur.message;
  } finally {
    bouton.disabled = false;
  }
});

document.getElementById("delier").addEventListener("click", async () => {
  await chrome.storage.local.clear();
  await chrome.storage.session.clear();
  await afficher();
});

chrome.storage.onChanged.addListener((changements, zone) => {
  if (zone === "local" && (changements.token || changements.message)) afficher();
});
afficher();
