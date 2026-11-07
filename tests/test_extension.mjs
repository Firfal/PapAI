// PAPAI_PLAYWRIGHT=/chemin/vers/playwright/index.mjs node tests/test_extension.mjs
import assert from "node:assert/strict";
import {fileURLToPath} from "node:url";
import {mkdir, mkdtemp, rm} from "node:fs/promises";
import {join} from "node:path";
import {homedir} from "node:os";

const {chromium} = await import(process.env.PAPAI_PLAYWRIGHT || "playwright");
const extension = fileURLToPath(new URL("../extension", import.meta.url));
const profil = await mkdtemp(join(homedir(), ".papai-gardien-test-"));
const captures = process.env.PAPAI_SCREENSHOT_DIR || "";
const serveur = process.env.PAPAI_TEST_SERVER || "http://127.0.0.1:8000";
let controles = 0;
function check(nom, condition) {
  assert.ok(condition, nom);
  controles++;
  console.log("  OK      " + nom);
}
async function capture(page, nom) {
  if (!captures) return;
  await mkdir(captures, {recursive: true});
  await page.screenshot({path: join(captures, nom), fullPage: true});
}
const navigateur = await chromium.launchPersistentContext(profil, {
  channel: "chromium", headless: true,
  args: [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`]
});
try {
  const worker = navigateur.serviceWorkers()[0] || await navigateur.waitForEvent("serviceworker");
  const identifiant = new URL(worker.url()).host;
  await worker.evaluate(() => {
    const initial = fetch;
    globalThis.appelsSites = [];
    globalThis.fetch = (...args) => {
      if (typeof args[0] === "string" && args[0].endsWith("/ext/site")) appelsSites.push(JSON.parse(args[1].body));
      return initial(...args);
    };
  });
  check("sites.google.com/x n'est pas connu", !(await worker.evaluate(async () =>
    estConnu(new URL("https://sites.google.com/x").hostname))));
  check("abc.free.fr n'est pas connu", !(await worker.evaluate(() => estConnu("abc.free.fr"))));
  check("www.google.com est connu", await worker.evaluate(() => estConnu("www.google.com")));
  check("adresses locales et IPv4 privées ignorées par l'extension", await worker.evaluate(() =>
    ["localhost", "127.0.0.1", "::1", "10.1.2.3", "172.16.0.1", "172.31.255.254",
      "192.168.1.2"].every((domaine) => ignorerDomaine(domaine, ""))));
  check("hôte du serveur lié ignoré par l'extension", await worker.evaluate(() =>
    ignorerDomaine("papai.example", "https://papai.example:8000")));
  const pont = new WebSocket(serveur.replace("http", "ws") + "/ws/bridge");
  const code = await new Promise((resolve, reject) => {
    pont.onopen = () => pont.send(JSON.stringify({type: "ext_pair_start"}));
    pont.onerror = reject;
    pont.onmessage = (evenement) => {
      const message = JSON.parse(evenement.data);
      if (message.type === "ext_pair_code") resolve(message.code);
    };
  });
  const popup = await navigateur.newPage();
  await popup.setViewportSize({width: 420, height: 760});
  await popup.goto(`chrome-extension://${identifiant}/popup.html`);
  await popup.locator("#autre-serveur").waitFor({state: "visible"});
  check("serveur officiel prérempli et caché", await popup.locator("#serveur").inputValue() ===
    "https://papai-450417131702.europe-west1.run.app" && await popup.locator("#serveur").isHidden());
  check("code de liaison à six chiffres", await popup.locator("#code").getAttribute("pattern") === "[0-9]{6}" &&
    await popup.locator("#code").getAttribute("maxlength") === "6");
  await capture(popup, "popup-vide.png");
  await popup.locator("#autre-serveur").click();
  await popup.locator("#serveur").fill("http://example.com");
  await popup.locator("#code").fill("123456");
  await popup.locator("#lier").click();
  await popup.waitForFunction(() => document.getElementById("message").textContent.includes("HTTPS"));
  check("le popup refuse un serveur HTTP public", true);
  await popup.locator("#serveur").fill(serveur);
  await popup.locator("#code").fill(code);
  await popup.locator("#lier").click();
  await popup.locator("#protege").waitFor({state: "visible"});
  check("liaison réelle depuis l'extension, sans ajout CORS", true);
  await capture(popup, "popup-relie.png");
  pont.close();
  const page = await navigateur.newPage();
  const demoPage = await navigateur.newPage();
  const suffixe = Date.now();
  await navigateur.route("http://**/*", (route) => {
    if (route.request().url().startsWith(serveur)) return route.continue();
    if (route.request().url().includes("/normal")) {
      return route.fulfill({contentType: "text/html", body: "<!doctype html><title>Actualités</title><p>Le programme des activités du quartier.</p>"});
    }
    return route.fulfill({contentType: "text/html", body: `<!doctype html><title>Urgent : votre paiement</title>
      <p>Achetez un coupon Transcash immédiatement.</p>
      <input value="SECRET_CHAMP"><input type="password" value="SECRET_MOTDEPASSE">
      <textarea>SECRET_ZONE</textarea><div contenteditable>SECRET_EDITABLE</div>
      <p style="display:none">SECRET_CACHE</p>`});
  });
  await demoPage.goto(serveur + "/a/" + (process.env.PAPAI_TEST_KEY || "demo"));
  await demoPage.waitForFunction(() => document.getElementById("lost").hidden);
  await worker.evaluate(async () => chrome.storage.local.set({server: "https://papai.example"}));
  await page.goto("http://papai.example/page");
  await page.waitForLoadState("load");
  await page.waitForTimeout(150);
  check("l'hôte du serveur lié ne génère pas d'avis", (await worker.evaluate(() => appelsSites.length)) === 0);
  await worker.evaluate(async (serveur) => chrome.storage.local.set({server: serveur}), serveur);
  const adressesLocales = ["localhost", "127.0.0.1", "[::1]", "10.1.2.3", "172.16.0.1",
    "172.31.255.254", "192.168.1.2"];
  const avantAdressesLocales = await worker.evaluate(() => appelsSites.length);
  for (const adresse of adressesLocales) {
    await page.goto(`http://${adresse}/page`);
    await page.waitForLoadState("load");
  }
  await page.waitForTimeout(150);
  check("les hôtes locaux et IP privées ne génèrent pas d'avis",
    (await worker.evaluate(() => appelsSites.length)) === avantAdressesLocales);
  await page.goto(`http://ameli.fr/?secret=PARAMETRE_PRIVE`);
  await page.waitForLoadState("load");
  check("site connu sans requête", (await worker.evaluate(() => appelsSites.length)) === 0);
  const domaine = `boutique-${suffixe}.xyz`;
  await page.goto(`http://${domaine}/compte?secret=PARAMETRE_PRIVE`);
  await page.waitForFunction(() => document.activeElement?.tagName === "DIV" && !document.activeElement.shadowRoot);
  check("voile en Shadow DOM fermé", true);
  await capture(page, "voile.png");
  await demoPage.locator("#alertCall").waitFor({state: "visible"});
  check("/a/demo affiche « Je m'en occupe »",
    await demoPage.locator("#alertCall").textContent() === "Je m'en occupe");
  check("/a/demo affiche « C'est normal » pour une alerte environnement",
    await demoPage.locator("#alertOk").textContent() === "C'est normal");
  demoPage.on("dialog", (dialog) => dialog.accept());
  await demoPage.locator("#alertOk").click();
  await demoPage.locator("#alert").waitFor({state: "hidden"});
  let appels = await worker.evaluate(() => appelsSites);
  check("domaine seul et aucun champ transmis", appels.length === 1 && appels[0].domain === domaine &&
    !JSON.stringify(appels).includes("SECRET_") && !JSON.stringify(appels).includes("PARAMETRE_PRIVE"));
  check("extrait borné", appels[0].text.length <= 2000 && appels[0].title.length <= 300);
  const dureeDanger = await worker.evaluate(async (domaine) => (await chrome.storage.local.get("avis:" + domaine))["avis:" + domaine].expire - Date.now(), domaine);
  check("cache danger une heure", dureeDanger > 3500000 && dureeDanger <= 3600000);
  await page.reload();
  await page.waitForFunction(() => document.activeElement?.tagName === "DIV" && !document.activeElement.shadowRoot);
  check("voile réappliqué depuis le cache", (await worker.evaluate(() => appelsSites.length)) === 1);
  await page.keyboard.press("Tab");
  await page.keyboard.press("Enter");
  check("continuer retire le voile", await page.evaluate(() => document.activeElement === document.body));
  await page.reload();
  await page.waitForFunction(() => document.activeElement?.tagName === "DIV");
  await page.keyboard.press("Enter");
  await page.waitForURL("about:blank");
  check("quitter ouvre une page vide", true);
  const cleCache = "avis:doute-" + suffixe + ".test";
  await worker.evaluate(async ({cleCache}) => {
    await chrome.storage.local.set({[cleCache]: {verdict: "douteux", expire: Date.now() + 3600000}});
  }, {cleCache});
  await page.goto(`http://doute-${suffixe}.test/`);
  // Le contenu fermé ne se lit pas depuis la page : observer seulement son hôte.
  await page.waitForFunction(() => [...document.documentElement.children].some((e) => e.tagName === "DIV"));
  check("bannière issue du cache sans requête", (await worker.evaluate(() => appelsSites.length)) === 1);
  await capture(page, "banniere.png");
  const avisSur = popup.evaluate((domaine) => new Promise((resolve, reject) => {
    const cle = "avis:" + domaine;
    const delai = setTimeout(() => reject(new Error("Avis sûr non reçu")), 15000);
    chrome.storage.onChanged.addListener(function recevoir(changements, zone) {
      if (zone === "local" && changements[cle]?.newValue) {
        clearTimeout(delai);
        chrome.storage.onChanged.removeListener(recevoir);
        resolve(changements[cle].newValue.expire - Date.now());
      }
    });
  }), `normal-${suffixe}.test`);
  await page.goto(`http://normal-${suffixe}.test/normal`);
  const dureeSur = await avisSur;
  check("cache sûr 24 heures", dureeSur > 86300000 && dureeSur <= 86400000);
  await popup.locator("#delier").click();
  await popup.locator("#liaison").waitFor({state: "visible"});
  check("Retirer la protection efface jeton et cache",
    await worker.evaluate(async () => Object.keys(await chrome.storage.local.get(null)).length === 0));
  await worker.evaluate(async (serveur) => chrome.storage.local.set({server: serveur, token: "jeton-inconnu-test"}), serveur);
  await page.goto(`http://inconnu-${suffixe}.test/`);
  await popup.waitForFunction(() => document.getElementById("message").textContent.includes("perdue"));
  check("401 délie et explique le problème", (await popup.locator("#message").textContent()).includes("perdue"));
  await worker.evaluate(async () => chrome.storage.local.clear());
  await page.goto(`http://nonlie-${suffixe}.test/`);
  await page.waitForLoadState("load");
  check("non lié sans requête", (await worker.evaluate(() => appelsSites.length)) === 3);
  await demoPage.close();
  console.log(`\n${controles} contrôles extension réussis, 0 échec`);
} finally {
  await navigateur.close();
  await rm(profil, {recursive: true, force: true});
}
