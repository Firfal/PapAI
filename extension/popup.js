"use strict";

const formulaire = document.getElementById("liaison");
const protege = document.getElementById("protege");
const message = document.getElementById("message");
const serveur = document.getElementById("serveur");
const serveurLabel = document.getElementById("serveur-label");
const autreServeur = document.getElementById("autre-serveur");
const serveurParDefaut = "https://papai-450417131702.europe-west1.run.app";

async function afficher() {
  const etat = await chrome.storage.local.get(["server", "token", "message"]);
  formulaire.hidden = Boolean(etat.token);
  protege.hidden = !etat.token;
  serveur.value = etat.server || serveurParDefaut;
  const serveurPersonnalise = Boolean(etat.server && etat.server !== serveurParDefaut);
  serveur.hidden = serveurLabel.hidden = !serveurPersonnalise;
  autreServeur.hidden = Boolean(etat.token);
  autreServeur.textContent = serveurPersonnalise ? "Masquer l'adresse" : "Autre serveur";
  message.textContent = etat.message || "";
}

autreServeur.addEventListener("click", () => {
  const afficherServeur = serveur.hidden;
  serveur.hidden = serveurLabel.hidden = !afficherServeur;
  autreServeur.textContent = afficherServeur ? "Masquer l'adresse" : "Autre serveur";
  if (afficherServeur) serveur.focus();
});

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
    if (adresse.protocol === "http:" && !["127.0.0.1", "localhost"].includes(adresse.hostname.toLowerCase())) {
      throw new Error("Le serveur doit utiliser HTTPS, sauf sur 127.0.0.1 ou localhost.");
    }
    if (adresse.protocol === "https:" &&
        adresse.origin !== "https://papai-450417131702.europe-west1.run.app" &&
        !await chrome.permissions.request({origins: [adresse.origin + "/*"]})) {
      throw new Error("Autorisez l'accès à ce serveur pour continuer.");
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
