"""Relier un support avec le seul code à 6 chiffres, sans adresse ni clé.

Serveur temporaire en mode en ligne (PAPAI_PUBLIC=1) avec plusieurs espaces :
chaque ordinateur reçoit sa clé au premier lancement, le support ne connaît que
le code tapé, l'ordinateur accepte ce support, et la réponse donne `server` et `key`.

    python tests/test_appairage_code.py
"""
from __future__ import annotations

import asyncio
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

import websockets

RACINE = Path(__file__).resolve().parent.parent
CLE = "cle-de-test-appairage"
INVALIDE = "Ce code ne marche plus. Demandez un nouveau code sur l'ordinateur de la personne aidée."
fails = 0


def check(label: str, cond: object) -> None:
    global fails
    print(("ok   " if cond else "FAIL ") + label)
    fails += 0 if cond else 1


def port_libre() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def http(url: str, body: dict | None = None, headers: dict | None = None) -> tuple[int, dict | str]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            raw, st = r.read().decode(), r.status
    except urllib.error.HTTPError as e:
        raw, st = e.read().decode(), e.code
    try:
        return st, json.loads(raw)
    except ValueError:
        return st, raw


async def code(ws, long: bool = False) -> str:
    await ws.send(json.dumps({"type": "pair_start", **({"long": True} if long else {})}))
    while True:
        m = json.loads(await asyncio.wait_for(ws.recv(), 10))
        if m.get("type") == "pair_code":
            return m["code"]


async def repondre(ws, accept: bool, vus: list) -> None:
    """L'ordinateur aidé : accepte ou refuse le support qui a tapé son code."""
    while True:
        m = json.loads(await ws.recv())
        if m.get("type") == "pair_confirm":
            vus.append(m)
            await ws.send(json.dumps({"type": "pair_decision", "req": m["req"], "accept": accept}))


async def post(url: str, body: dict, headers: dict | None = None):
    return await asyncio.to_thread(http, url, body, headers)


async def recevoir(ws, kind: str) -> dict:
    while True:
        m = json.loads(await asyncio.wait_for(ws.recv(), 5))
        if m.get("type") == kind:
            return m


def sans_secret(r: dict) -> bool:
    return not any(k in r for k in ("server", "key", "aidant_url"))


def politique() -> None:
    sys.path.insert(0, str(RACINE))
    from backend.family import Family, PairingError, clean_label

    with tempfile.TemporaryDirectory() as folder:
        family = Family(Path(folder) / "family.json")
        c = family.new_code()
        family._expires = time.time() - 1
        try:
            family.check_code(c)
            check("code expiré : message uniforme", False)
        except PairingError as e:
            check("code expiré : message uniforme", str(e) == INVALIDE)
        c = family.new_code()
        family.consume_code(c)
        family._expires = time.time() - 1
        h = family.add_helper("Marc", "Fils")
        check("expiration pendant l'accord n'empêche pas l'ajout après consommation", h in family.helpers)
        c = family.new_code()
        for _ in range(100):
            try:
                family.check_code("faux")
            except PairingError:
                pass
        check("plafond global de 100 erreurs conservé", not family.code_valid(c))
        check("libellés limités, accents et ponctuation conservés", clean_label("Éléonore - O'Neil." + "a" * 50, 40) == ("Éléonore - O'Neil." + "a" * 50)[:40]
              and len(clean_label("Fils" * 20, 60)) == 60)


async def parcours(base: str) -> None:
    wsb = base.replace("http://", "ws://")
    try:
        async with websockets.connect(f"{wsb}/ws/bridge") as w:
            await asyncio.wait_for(w.recv(), 5)
        check("en ligne, l'ordinateur sans clé reste refusé", False)
    except Exception:  # noqa: BLE001
        check("en ligne, l'ordinateur sans clé reste refusé", True)

    st, a = http(f"{base}/spaces", {})
    st2, b = http(f"{base}/spaces", {})
    check("premier lancement : le serveur crée un espace et donne sa clé",
          st == 200 and st2 == 200 and a["key"] != b["key"] and a["bridge_url"].endswith(f"/k/{a['key']}/ws/bridge"))

    async with websockets.connect(f"{wsb}/k/{CLE}/ws/bridge", max_size=2**24) as w0, \
            websockets.connect(a["bridge_url"]) as wa, websockets.connect(b["bridge_url"]) as wb:
        st, page = http(f"{base}/p")
        check("page de saisie du code ouverte sans clé", st == 200 and "<html" in str(page).lower())

        cb = await code(wb)
        async with websockets.connect(f"{wsb}/k/{b['key']}/ws/aidant/{b['key']}") as connu:
            pending = asyncio.create_task(post(f"{base}/p/{cb}", {"name": "Cl<a>ire\n", "relation": 'Service &"informatique"'}))
            demande = await recevoir(wb, "pair_confirm")
            check("prénom et lien nettoyés avant confirmation", demande["name"] == "Claire" and demande["relation"] == "Service informatique")
            await wb.send(json.dumps({"type": "pair_decision", "req": demande["req"], "accept": True}))
            st, r = await pending
            check("le code seul retrouve le bon espace, accepté sur l'ordinateur",
                  st == 200 and r.get("ok") and r.get("key") == b["key"] and r.get("server") == base)
            notice = await recevoir(connu, "helper_added")
            check("support déjà connecté averti de l'ajout", notice["name"] == "Claire")
            helpers = await recevoir(wb, "helpers")
            check("support ajouté et helpers+added envoyé au pont", helpers.get("added") == "Claire" and any(h["id"] == r["id"] for h in helpers["helpers"]))
        st, r = await post(f"{base}/p/{cb}", {"name": "Intrus", "relation": "?"})
        uniforme = r
        check("un code ne sert qu'une fois, sans secret", st == 400 and r.get("error") == INVALIDE and sans_secret(r))

        ca = await code(wa)
        ta = asyncio.create_task(repondre(wa, False, []))
        st, r = await post(f"{base}/p/{ca}", {"name": "Intrus", "relation": ""})
        check("refusé sur l'ordinateur : pas de liaison", st == 403 and r.get("refused") is True and sans_secret(r)
              and r.get("error") == "La personne aidée a refusé. Rien n'a été partagé.")
        ta.cancel()
        await asyncio.gather(ta, return_exceptions=True)
        st, r = await post(f"{base}/p/{ca}", {"name": "Intrus"})
        check("refus : code consommé, message uniforme", st == 400 and r == uniforme)

        c0 = await code(w0)
        t0 = asyncio.create_task(repondre(w0, True, []))
        st, r = await post(f"{base}/k/{CLE}/p/{c0}", {"name": "Paul", "relation": ""})
        check("lien avec clé (QR, SMS) : confirmé sur l'ordinateur", st == 200 and r.get("key") == CLE)
        t0.cancel()
        await asyncio.gather(t0, return_exceptions=True)

        ct = await code(wa)
        pending = asyncio.create_task(post(f"{base}/k/{a['key']}/p/{ct}", {"name": "Attente"}))
        demande = await recevoir(wa, "pair_confirm")
        neuf = await code(wa)
        st, r = await post(f"{base}/p/{neuf}", {"name": "Deuxième"})
        check("une seule demande en attente par ordinateur", st == 400 and r == uniforme)
        st, r = await pending
        ferme = await recevoir(wa, "pair_confirm_closed")
        check("délai : 408 sans secret et fermeture corrélée", st == 408 and sans_secret(r) and ferme["req"] == demande["req"])
        st, r = await post(f"{base}/p/{ct}", {"name": "Attente"})
        check("délai : code consommé", st == 400 and r == uniforme)
        ta = asyncio.create_task(repondre(wa, True, []))
        st, r = await post(f"{base}/p/{neuf}", {"name": "Après délai"})
        check("demande nettoyée après délai", st == 200)
        ta.cancel()
        await asyncio.gather(ta, return_exceptions=True)

        st, r = http(f"{base}/k/{a['key']}/lessons")
        st0, r0 = http(f"{base}/k/{b['key']}/lessons")
        check("chaque espace a ses propres fiches", st == 200 and st0 == 200)

        async def drain(w, t=1.0):
            out = []
            try:
                while True:
                    out.append(json.loads(await asyncio.wait_for(w.recv(), t)))
            except asyncio.TimeoutError:
                return out
        async with websockets.connect(f"{wsb}/k/{a['key']}/ws/aidant/{a['key']}") as ha, \
                websockets.connect(f"{wsb}/k/{b['key']}/ws/aidant/{b['key']}") as hb:
            await drain(ha), await drain(hb)
            await wb.send(json.dumps({"type": "help_request", "task": "Imprimer un document"}))
            vus_a, vus_b2 = await asyncio.gather(drain(ha, 1.5), drain(hb, 1.5))
            check("une demande n'arrive qu'aux supports de son espace",
                  any(m.get("task") == "Imprimer un document" for m in vus_b2)
                  and not any("Imprimer" in json.dumps(m, ensure_ascii=False) for m in vus_a))
        try:
            async with websockets.connect(f"{wsb}/k/{a['key']}/ws/aidant/{b['key']}") as hx:
                m = json.loads(await asyncio.wait_for(hx.recv(), 5))
            check("la clé d'un espace n'ouvre pas un autre espace", m.get("type") == "refused")
        except Exception:  # noqa: BLE001
            check("la clé d'un espace n'ouvre pas un autre espace", True)

        bon = await code(wb)
        faux = "111111" if bon != "111111" else "222222"
        for route, ip in ((f"{base}/p/{faux}", "203.0.113.1"), (f"{base}/k/{b['key']}/p/{faux}", "203.0.113.2")):
            codes = [http(route, {"name": "X"}, {"X-Forwarded-For": f"1.2.3.{i}, {ip}"})[0] for i in range(11)]
            check("10 erreurs par IP, tête XFF ignorée : " + route.split(base)[1], codes == [400] * 10 + [429])
        tb = asyncio.create_task(repondre(wb, True, []))
        st, r = await post(f"{base}/p/{bon}", {"name": "Autre IP"}, {"X-Forwarded-For": "203.0.113.3"})
        check("10 erreurs n'invalident pas le bon code pour une autre IP", st == 200)
        tb.cancel()
        await asyncio.gather(tb, return_exceptions=True)

        headers = {"X-Forwarded-For": "203.0.113.4"}
        vides = [http(f"{base}/p/{faux}", {"name": '<>\n"&'}, headers) for _ in range(11)]
        st, r = http(f"{base}/p/{faux}", {"name": "X"}, headers)
        check("prénom vide nettoyé : 400 sans compter d'essai", all(s == 400 and r.get("error") == "Indiquez votre prénom." for s, r in vides) and st == 400)
        check("code faux et consommé : même message", r == uniforme)

    async with websockets.connect(a["bridge_url"]) as wa:
        absent = await code(wa)
    await asyncio.sleep(0.05)
    st, r = await post(f"{base}/p/{absent}", {"name": "Hors ligne"})
    check("ordinateur absent : 409 sans secret", st == 409 and sans_secret(r) and "n'est pas connecté" in r.get("error", ""))
    async with websockets.connect(a["bridge_url"]) as wa:
        ta = asyncio.create_task(repondre(wa, True, []))
        st, r = await post(f"{base}/p/{absent}", {"name": "De retour"})
        check("ordinateur absent : code conservé pour la reconnexion", st == 200)
        ta.cancel()
        await asyncio.gather(ta, return_exceptions=True)
        for remplace in (False, True):
            c = await code(wa)
            pending = asyncio.create_task(post(f"{base}/p/{c}", {"name": "Interrompu"}))
            await recevoir(wa, "pair_confirm")
            if remplace:
                nouveau = await websockets.connect(a["bridge_url"])
            else:
                await wa.close()
            st, r = await pending
            check("pont remplacé" if remplace else "pont déconnecté", st == 409 and sans_secret(r))
            if remplace:
                await nouveau.close()
            else:
                wa = await websockets.connect(a["bridge_url"])

    async with websockets.connect(a["bridge_url"]) as wa:
        await wa.send(json.dumps({"type": "hello"}))
        helpers = await recevoir(wa, "helpers")
        check("aucun support ajouté lors des échecs", not {"Intrus", "Attente", "Deuxième", "Hors ligne", "Interrompu"}.intersection(h["name"] for h in helpers["helpers"]))

    async with websockets.connect(f"{wsb}/k/cle-revenue-apres-redeploiement/ws/bridge") as w:
        await w.send(json.dumps({"type": "pair_start"}))
        m = json.loads(await asyncio.wait_for(w.recv(), 5))
        check("clé inconnue bien formée : l'ordinateur retrouve un espace", m.get("type") in ("helpers", "pair_code"))


def main() -> None:
    politique()
    tmp = Path(tempfile.mkdtemp(prefix="papai-code-"))
    shutil.copytree(RACINE / "backend", tmp / "backend", ignore=shutil.ignore_patterns("__pycache__", "family.json"))
    for module in RACINE.glob("*.py"):
        shutil.copy(module, tmp)
    port = port_libre()
    base = f"http://127.0.0.1:{port}"
    env = {**os.environ, "HAI_API_KEY": "faux", "PAPAI_PUBLIC": "1", "PAPAI_AIDANT_KEY": CLE,
           "PAPAI_DATA_DIR": str(tmp / "data"),
           "PORT": str(port), "PAPAI_PUBLIC_URL": base, "PAPAI_PAIR_CONFIRM_S": "1.5"}
    env.pop("GLADIA_API_KEY", None)
    log = open(tmp / "serveur.log", "w")
    serveur = subprocess.Popen([sys.executable, "-m", "backend.app"], cwd=tmp, env=env,
                               stdout=log, stderr=subprocess.STDOUT)
    try:
        for _ in range(60):
            try:
                urllib.request.urlopen(base + "/", timeout=2)
                break
            except urllib.error.HTTPError:
                break
            except OSError:
                if serveur.poll() is not None:
                    break
                time.sleep(0.5)
        if serveur.poll() is not None:
            print("Le serveur n'a pas démarré :\n" + (tmp / "serveur.log").read_text())
            sys.exit(1)
        asyncio.run(asyncio.wait_for(parcours(base), 60))
    finally:
        serveur.terminate()
        serveur.wait(10)
        if fails:
            print(f"\nJournal du serveur : {tmp / 'serveur.log'}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{'ÉCHEC' if fails else 'OK'} : {fails} échec(s)")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
