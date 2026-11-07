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
fails = 0


def check(label: str, cond: object) -> None:
    global fails
    print(("ok   " if cond else "FAIL ") + label)
    fails += 0 if cond else 1


def port_libre() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def http(url: str, body: dict | None = None) -> tuple[int, dict | str]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
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


async def post(url: str, body: dict):
    return await asyncio.to_thread(http, url, body)


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
        vus_b: list = []
        tb = asyncio.create_task(repondre(wb, True, vus_b))
        st, r = await post(f"{base}/p/{cb}", {"name": "Claire", "relation": "Service informatique"})
        check("le code seul retrouve le bon espace, accepté sur l'ordinateur",
              st == 200 and r.get("ok") and r.get("key") == b["key"] and r.get("server") == base)
        check("l'ordinateur a vu qui demandait à devenir son support",
              len(vus_b) == 1 and vus_b[0]["name"] == "Claire")
        st, r = await post(f"{base}/p/{cb}", {"name": "Intrus", "relation": "?"})
        check("un code ne sert qu'une fois", st == 400)
        tb.cancel()

        ca = await code(wa)
        ta = asyncio.create_task(repondre(wa, False, []))
        st, r = await post(f"{base}/p/{ca}", {"name": "Intrus", "relation": ""})
        check("refusé sur l'ordinateur : pas de liaison", st == 403 and not r.get("ok"))
        ta.cancel()

        c0 = await code(w0)
        st, r = http(f"{base}/k/{CLE}/p/{c0}", {"name": "Paul", "relation": ""})
        check("lien avec clé (QR, SMS) : sans confirmation", st == 200 and r.get("key") == CLE)

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

        codes = []
        for _ in range(12):
            codes.append(http(f"{base}/p/000001", {"name": "X", "relation": ""})[0])
        check("trop de codes faux : bloqué (pas de force brute)", codes[0] == 400 and codes[-1] == 429)

    async with websockets.connect(f"{wsb}/k/cle-revenue-apres-redeploiement/ws/bridge") as w:
        await w.send(json.dumps({"type": "pair_start"}))
        m = json.loads(await asyncio.wait_for(w.recv(), 5))
        check("clé inconnue bien formée : l'ordinateur retrouve un espace", m.get("type") in ("helpers", "pair_code"))


def main() -> None:
    tmp = Path(tempfile.mkdtemp(prefix="papai-code-"))
    shutil.copytree(RACINE / "backend", tmp / "backend", ignore=shutil.ignore_patterns("__pycache__", "family.json"))
    for module in RACINE.glob("*.py"):
        shutil.copy(module, tmp)
    port = port_libre()
    base = f"http://127.0.0.1:{port}"
    env = {**os.environ, "HAI_API_KEY": "faux", "PAPAI_PUBLIC": "1", "PAPAI_AIDANT_KEY": CLE,
           "PAPAI_DATA_DIR": str(tmp / "data"),
           "PORT": str(port), "PAPAI_PUBLIC_URL": base}
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
