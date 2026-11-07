"""Relier un support avec le seul code à 6 chiffres, sans adresse ni clé.

Serveur temporaire en mode en ligne (PAPAI_PUBLIC=1) : l'ordinateur se connecte
avec la clé, le support ne connaît que le code tapé et reçoit `server` et `key`.

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


async def parcours(base: str) -> None:
    wsb = base.replace("http://", "ws://")
    try:
        async with websockets.connect(f"{wsb}/ws/bridge") as w:
            await asyncio.wait_for(w.recv(), 5)
        check("en ligne, l'ordinateur sans clé reste refusé", False)
    except Exception:  # noqa: BLE001
        check("en ligne, l'ordinateur sans clé reste refusé", True)

    async with websockets.connect(f"{wsb}/k/{CLE}/ws/bridge", max_size=2**24) as w:
        st, page = http(f"{base}/p")
        check("page de saisie du code ouverte sans clé", st == 200 and "<html" in str(page).lower())
        c = await code(w)
        faux = f"{(int(c) + 1) % 1_000_000:06d}"
        st, r = http(f"{base}/p/{faux}", {"name": "Claire", "relation": "sa fille"})
        check("mauvais code refusé", st == 400 and not r.get("ok"))
        st, r = http(f"{base}/p/{c}", {"name": "Claire", "relation": "sa fille"})
        check("le code seul suffit : le support est relié", st == 200 and r.get("ok"))
        check("la réponse donne l'adresse et la clé", r.get("key") == CLE and r.get("server") == base)
        st, r = http(f"{base}/p/{c}", {"name": "Intrus", "relation": "?"})
        check("un code ne sert qu'une fois", st == 400)

        c = await code(w, long=True)
        faux = f"{(int(c) + 1) % 1_000_000:06d}"
        for _ in range(5):
            http(f"{base}/p/{faux}", {"name": "X", "relation": ""})
        st, r = http(f"{base}/p/{c}", {"name": "Claire", "relation": ""})
        check("5 essais faux invalident le code (pas de force brute)", st == 400 and not r.get("ok"))


def main() -> None:
    tmp = Path(tempfile.mkdtemp(prefix="papai-code-"))
    shutil.copytree(RACINE / "backend", tmp / "backend", ignore=shutil.ignore_patterns("__pycache__", "family.json"))
    for module in RACINE.glob("*.py"):
        shutil.copy(module, tmp)
    port = port_libre()
    base = f"http://127.0.0.1:{port}"
    env = {**os.environ, "HAI_API_KEY": "faux", "PAPAI_PUBLIC": "1", "PAPAI_AIDANT_KEY": CLE,
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
