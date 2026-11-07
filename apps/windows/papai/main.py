"""PapAI pour Windows : la fenêtre de la personne aidée.

Portage de l'app Mac. Même protocole (`PROTOCOL.md`), mêmes écrans, même
vocabulaire. Le rendu passe par WebView2, ce qui permet de reprendre à
l'identique le dessin « Soin » du Mac plutôt que de l'approximer.

    python -m papai.main
    PAPAI_SERVER=ws://localhost:8000/ws/bridge   (défaut)
    PAPAI_PRENOM=Jeanne   PAPAI_AIDANT=Quentin
"""

from __future__ import annotations

import asyncio
import json
import os
import queue
import threading
import time
import urllib.request
from pathlib import Path

import webview
import websockets

from .core import (
    ProtectedZone, Screen, StopGate, Stopped,
    describe_action, known_folder, open_shortcut, run_action, window_rect,
)

UI = Path(__file__).resolve().parent.parent / "ui" / "index.html"
TITRE = "PapAI"
SERVEUR = os.environ.get("PAPAI_SERVER", "ws://localhost:8000/ws/bridge").strip()
PRENOM = os.environ.get("PAPAI_PRENOM", "Jeanne").strip() or "Jeanne"
AIDANT = os.environ.get("PAPAI_AIDANT", "Quentin").strip() or "Quentin"
RECONNEXION_S = 3

# Le gardien n'envoie que du texte, jamais l'écran. Voir PROTOCOL.md.
GUARD_PERIODE_S = 8


def http_base() -> str:
    s = SERVEUR.replace("wss://", "https://").replace("ws://", "http://")
    return s[: -len("/ws/bridge")].rstrip("/") if s.endswith("/ws/bridge") else s.rstrip("/")


gate = StopGate()
vers_ui: queue.Queue = queue.Queue()
_ws = None
_boucle: asyncio.AbstractEventLoop | None = None
_fenetre = None
_protege: tuple | None = None


def js(fn: str, *args) -> None:
    """Appelle `window.papai.<fn>`. La vue n'a aucune autorité, elle affiche."""
    if _fenetre is None:
        return
    try:
        charge = ", ".join(json.dumps(a, ensure_ascii=False) for a in args)
        _fenetre.evaluate_js(f"window.papai.{fn}({charge})")
    except Exception:  # noqa: BLE001 — fenêtre fermée pendant l'appel
        pass


# ------------------------------------------------------------------ réseau


def envoyer(charge: dict) -> None:
    """Appelé depuis le thread de l'interface."""
    if _boucle is None or _ws is None:
        return

    async def _envoi():
        try:
            await _ws.send(json.dumps(charge))
        except Exception:  # noqa: BLE001
            pass

    asyncio.run_coroutine_threadsafe(_envoi(), _boucle)


async def gardien(ws, screen: Screen) -> None:
    """Trois signaux textuels, en continu. Rien d'autre ne quitte la machine."""
    import ctypes

    while True:
        await asyncio.sleep(GUARD_PERIODE_S)
        try:
            tampon = ctypes.create_unicode_buffer(512)
            hwnd = ctypes.windll.user32.GetForegroundWindow()
            ctypes.windll.user32.GetWindowTextW(hwnd, tampon, 512)
            processus = await asyncio.to_thread(_processus)
            await ws.send(json.dumps({
                "type": "guard", "processes": processus,
                "window": tampon.value, "url": "",
            }))
        except Exception:  # noqa: BLE001 — la veille ne doit jamais casser la session
            pass


def _processus() -> list[str]:
    import subprocess

    try:
        sortie = subprocess.run(
            ["tasklist", "/fo", "csv", "/nh"],
            capture_output=True, text=True, timeout=5,
            creationflags=0x08000000,  # pas de fenêtre noire qui clignote
        ).stdout
    except Exception:  # noqa: BLE001
        return []
    noms = []
    for ligne in sortie.splitlines():
        if ligne.startswith('"'):
            noms.append(ligne.split('","')[0].strip('"').removesuffix(".exe"))
    return noms


async def reseau() -> None:
    global _ws, _protege
    screen = Screen()
    if screen.multiple:
        print(f"[papai] plusieurs écrans — seul l'écran {screen.index} est partagé", flush=True)
    print(f"[papai] écran {screen.width}x{screen.height}", flush=True)

    while True:
        try:
            async with websockets.connect(SERVEUR, max_size=16 * 1024 * 1024) as ws:
                _ws = ws
                await ws.send(json.dumps({"type": "hello", "os": "windows"}))
                vers_ui.put(("connexion", True))
                # Comme sur le Mac : PAPAI_AUTOTASK lance une demande dès la
                # connexion, pour essayer sans cliquer.
                auto = os.environ.get("PAPAI_AUTOTASK", "").strip()
                if auto and not getattr(reseau, "_auto_fait", False):
                    reseau._auto_fait = True
                    gate.reset()
                    await ws.send(json.dumps({"type": "help_request", "task": auto}))
                    print(f'[papai] demande automatique : {auto}', flush=True)
                veille = asyncio.create_task(gardien(ws, screen))
                try:
                    async for brut in ws:
                        await traiter(ws, screen, json.loads(brut))
                finally:
                    veille.cancel()
        except Exception as e:  # noqa: BLE001 — serveur absent ou coupé
            _ws = None
            vers_ui.put(("connexion", False))
            print(f"[papai] hors ligne ({type(e).__name__})", flush=True)
            await asyncio.sleep(RECONNEXION_S)


async def traiter(ws, screen: Screen, m: dict) -> None:
    t = m.get("type")

    if t == "capture":
        if gate.is_stopped:
            await ws.send(json.dumps({"type": "frame", "req": m["req"]}))
            return
        b64, w, h = await asyncio.to_thread(screen.grab, _protege)
        await ws.send(json.dumps({
            "type": "frame", "req": m["req"], "frame_id": f"{int(time.time()*1000):x}",
            "png_b64": b64, "width": w, "height": h,
        }))

    elif t == "execute":
        action = m.get("action", {})
        nom, args = action.get("name", ""), action.get("args", {})

        # Le refus est décidé ici, sur la machine pilotée.
        if gate.is_stopped:
            await ws.send(json.dumps({
                "type": "result", "req": m["req"], "refused": True,
                "result": "Arrêt demandé par la personne aidée.",
            }))
            return

        vers_ui.put(("action", describe_action(nom, args)))
        try:
            resultat = await asyncio.to_thread(run_action, nom, args, screen, gate, _protege)
            refuse = False
        except Stopped:
            resultat, refuse = "Arrêt demandé par la personne aidée.", True
        except ProtectedZone:
            # Refus ciblé : l'agent l'apprend et poursuit, la session survit.
            resultat, refuse = "Cette zone appartient à la fenêtre PapAI.", False
        except Exception as e:  # noqa: BLE001
            resultat, refuse = f"échec : {type(e).__name__}", True
        await ws.send(json.dumps({
            "type": "result", "req": m["req"], "result": resultat, "refused": refuse,
        }))

    elif t == "status":
        vers_ui.put(("etat", m))
    elif t == "answer":
        vers_ui.put(("reponse", m.get("content", "")))
    elif t == "alert":
        vers_ui.put(("alerte", m))
    elif t == "session":
        print(f"[papai] session {m.get('id')}", flush=True)


def demarrer_reseau() -> None:
    def tourner() -> None:
        global _boucle
        _boucle = asyncio.new_event_loop()
        asyncio.set_event_loop(_boucle)
        _boucle.run_until_complete(reseau())

    threading.Thread(target=tourner, daemon=True).start()


# --------------------------------------------------------- pont avec la vue


class Api:
    """Tout ce que la vue a le droit de demander."""

    def contexte(self) -> dict:
        # L'état de connexion est rendu ici aussi : la vue démarre après que
        # le réseau s'est annoncé, et elle écrasait sinon un « connecté » déjà
        # reçu par un « pas joignable » de départ.
        return {"prenom": PRENOM, "aidant": AIDANT, "connected": _ws is not None}

    def ask_help(self, task: str) -> dict:
        gate.reset()
        envoyer({"type": "help_request", "task": (task or "").strip()[:200]})
        return {"ok": True}

    def stop(self) -> dict:
        # Le verrou local d'abord : plus aucune action, même si le serveur est
        # injoignable. Le serveur est prévenu ensuite.
        gate.raise_stop()
        envoyer({"type": "stop"})
        return {"ok": True}

    def refresh(self) -> dict:
        """Demande le contenu de l'accueil. Rend la main tout de suite.

        Le travail se fait dans un fil, et le résultat revient par `js()`.
        Une méthode d'API qui fait du réseau bloque la vue : WebView2 attend la
        réponse de Python pendant que Python attend de pouvoir injecter du
        JavaScript, et les deux colonnes de l'accueil restaient vides, sans la
        moindre erreur.
        """
        threading.Thread(target=self._remplir, daemon=True).start()
        return {"ok": True}

    def _remplir(self) -> None:
        try:
            js("raccourcis", self.lessons())
        except Exception as e:  # noqa: BLE001
            print(f"[papai] raccourcis : {type(e).__name__}", flush=True)
            js("raccourcis", [])
        try:
            js("applications", self.folders(), self.apps())
        except Exception as e:  # noqa: BLE001
            print(f"[papai] applications : {type(e).__name__}", flush=True)

    def lessons(self) -> list:
        try:
            with urllib.request.urlopen(f"{http_base()}/lessons", timeout=5) as r:
                fiches = json.loads(r.read().decode())
        except Exception as e:  # noqa: BLE001 — serveur absent : pas de raccourcis
            print(f"[papai] raccourcis indisponibles : {type(e).__name__}", flush=True)
            return []
        for f in fiches:
            for etape in f.get("steps") or []:
                etape["image_data"] = self._image(f["id"], etape.get("image", ""))
        return fiches

    def _image(self, fiche: str, nom: str) -> str:
        if not nom:
            return ""
        try:
            import base64

            with urllib.request.urlopen(f"{http_base()}/lessons/{fiche}/{nom}", timeout=5) as r:
                return base64.b64encode(r.read()).decode()
        except Exception:  # noqa: BLE001
            return ""

    def run_shortcut(self, shortcut: dict) -> dict:
        ok, detail = open_shortcut(shortcut)
        if not ok:
            # Le serveur prévient l'aidant : un raccourci cassé est une
            # information pour lui, pas seulement un message à l'écran.
            envoyer({"type": "automation_failed",
                     "title": str(shortcut.get("title") or "Un raccourci"),
                     "detail": detail})
        return {"ok": ok, "detail": detail}

    def apps(self) -> list:
        """Les applications courantes présentes sur cette machine."""
        from .shortcuts_apps import installees

        return installees()

    def open_app(self, chemin: str) -> dict:
        from .shortcuts_apps import lancer

        ok, detail = lancer(chemin)
        return {"ok": ok, "detail": detail}

    def folders(self) -> list:
        out = []
        from .core import KNOWN_FOLDERS

        for cle, (libelle, _) in KNOWN_FOLDERS.items():
            p = known_folder(cle)
            if p and p.is_dir():
                out.append({"key": cle, "label": libelle})
        return out

    def open_folder(self, cle: str) -> dict:
        ok, detail = open_shortcut({"folder": cle})
        return {"ok": ok, "detail": detail}


# ------------------------------------------------------------------ fenêtre


def _pompe() -> None:
    """Draine les messages du réseau vers la vue, et suit notre propre fenêtre."""
    global _protege
    while True:
        try:
            _protege = window_rect(TITRE)
        except Exception:  # noqa: BLE001
            pass
        try:
            while True:
                genre, valeur = vers_ui.get_nowait()
                if genre == "connexion":
                    js("connexion", bool(valeur))
                elif genre == "etat":
                    js("etat", valeur)
                elif genre == "action" and not gate.is_stopped:
                    js("action", valeur)
                elif genre == "reponse":
                    js("reponse", valeur)
                elif genre == "alerte":
                    js("alerte", valeur)
        except queue.Empty:
            pass
        time.sleep(0.12)


def main() -> None:
    global _fenetre
    demarrer_reseau()
    _fenetre = webview.create_window(
        TITRE, UI.as_uri(), js_api=Api(),
        width=1180, height=820, min_size=(900, 680),
        background_color="#EEF0EE",
    )

    def ferme() -> None:
        # Fermer la fenêtre, c'est arrêter : rien ne continue sans elle.
        gate.raise_stop()
        envoyer({"type": "stop"})

    _fenetre.events.closed += ferme
    threading.Thread(target=_pompe, daemon=True).start()
    webview.start()


if __name__ == "__main__":
    main()
