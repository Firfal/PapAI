"""Tests de l'app Windows, lancables sous Linux (sans Windows ni écran).

    python apps/windows/tests/test_windows_app.py            # tests unitaires
    python apps/windows/tests/test_windows_app.py --serveur  # + parcours réel

Avec --serveur, il faut un serveur local et le faux Holo :
    python tests/faux_holo.py
    HOLO_BASE_URL=http://127.0.0.1:8999/v1/ HAI_API_KEY=stub-key PAPAI_AIDANT_KEY=demo python -m backend.app
Le test joue l'app (Model + Bridge réels, capture et clics simulés) et l'aidant.
"""

from __future__ import annotations

import asyncio
import base64
import io
import json
import os
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ["PAPAI_HOME"] = tempfile.mkdtemp()

from papai import apps, core, settings  # noqa: E402
from papai.bridge import Bridge, wait_until  # noqa: E402
from papai.model import Model  # noqa: E402

ok = 0


def check(cond: bool, label: str) -> None:
    global ok
    print(("ok   " if cond else "ÉCHEC ") + label)
    if not cond:
        sys.exit(1)
    ok += 1


class FakeScreen:
    width, height, left, top = 1920, 1080, 0, 0
    to_pixels = core.Screen.to_pixels

    def grab(self, mask=None):
        from PIL import Image

        buf = io.BytesIO()
        Image.new("RGB", (1280, 720), (30, 90, 160)).save(buf, format="PNG")
        return base64.b64encode(buf.getvalue()).decode(), 1280, 720


def unit() -> None:
    g = core.StopGate()
    check(not g.is_stopped, "verrou baissé au départ")
    g.raise_stop()
    check(g.is_stopped, "verrou levé")
    p = g.pin()
    g.reset()
    check(p.is_stopped and not g.is_stopped, "un geste d'avant l'arrêt ne reprend pas après une nouvelle demande")
    g.raise_stop()
    s = FakeScreen()
    check(s.to_pixels(500, 500) == (960, 540), "[0,1000] -> pixels")
    check(s.to_pixels("x", None) == (0, 0), "coordonnées invalides -> 0")
    try:
        core.run_action("click", {"x": 1, "y": 1}, s, g)
        check(False, "action refusée verrou levé")
    except core.Stopped:
        check(True, "action refusée verrou levé (avant tout geste)")
    check(core.describe_action("press_key", {"keys": "cmd+space"}) == "J'ouvre la recherche de Windows",
          "phrase simple pour cmd+space")
    found = apps.match([("uninstall zoom workplace", "a"), ("zoom workplace", "b"),
                        ("microsoft edge", "c"), ("google chrome", "d"), ("photos", "e")])
    by = {a["label"]: a["path"] for a in found}
    check(by.get("Visio") == "b", "jamais le raccourci de désinstallation")
    check(by.get("Internet") == "c", "Edge avant Chrome")
    check(core.open_shortcut({"folder": "pictures", "subfolder": "../x"})[0] is False, "sous-dossier « .. » refusé")
    check(core.open_shortcut({"folder": "/etc"})[0] is False, "dossier inconnu refusé")

    m = Model(demo="active")
    m.start()
    check(m.snapshot()["state"] == "active" and m.snapshot()["sessionOpen"], "démo : session active")
    m.stop()
    check(m.gate.is_stopped and m.state == "stopped", "Arrêter : verrou local + état arrêté (sans serveur)")
    m._apply_status({"state": "active", "plan_approved": True})
    check(m.state == "stopped", "un status tardif ne relance pas une session arrêtée")

    # Bridge sans serveur : exécutions refusées sans plan validé, puis après arrêt.
    sent = []

    class WS:
        async def send(self, raw):
            sent.append(json.loads(raw))

    calls = []
    b = Bridge("ws://127.0.0.1:1/ws/bridge", core.StopGate(), FakeScreen, lambda m: None,
               lambda ok: None, lambda s: None, runner=lambda *a: calls.append(a) or "fait")
    act = {"name": "click", "args": {"x": 10, "y": 10}}

    async def scenario():
        await b._execute(WS(), "1", act)
        b.last_status = {"state": "awaiting_approval", "plan_approved": False}
        await b._execute(WS(), "2", act)
        b.last_status = {"state": "active", "plan_approved": True}
        await b._execute(WS(), "3", act)
        b.gate.raise_stop()
        await b._execute(WS(), "4", act)
        await b._capture(WS(), "5")

    asyncio.run(scenario())
    check(sent[0]["refused"] and sent[1]["refused"], "execute refusé sans plan validé")
    check(not sent[2]["refused"] and len(calls) == 1, "execute joué une fois le plan validé")
    check(sent[3]["refused"] and len(calls) == 1, "execute refusé après Arrêter")
    check(len(sent) == 4, "aucune capture envoyée après Arrêter")

    check(core.guard_signals() is None or core.guard_signals()["type"] == "guard", "guard_signals hors Windows")

    m = Model(demo="home")
    m.start()
    m._handle({"type": "alert", "level": "danger", "title": "Arnaque", "detail": "N'appelez pas."})
    check(m.snapshot()["alert"]["title"] == "Arnaque", "alerte du gardien affichée")
    m.dismiss_alert()
    check(m.snapshot()["alert"] is None, "alerte fermée")

    m = Model(demo="home")
    m.request_consent("Mes photos")
    check(m.screen == "consent", "première demande : écran d'accord du partage")
    m.give_consent()
    check(m.screen == "session" and m.snapshot()["screenConsent"], "accord donné et gardé")
    m.back_home()
    m.request_consent("Mes courriels")
    check(m.screen == "session" and m.task == "Mes courriels", "demande suivante : l'accord n'est pas redemandé")
    m.revoke_consent()
    m.back_home()
    m.request_consent("Mes photos")
    check(m.screen == "consent", "accord retiré dans Réglages : redemandé")

    # Automatismes importés : actions de premier niveau, jamais de commande.
    g = core.StopGate()
    check(not core.play_actions({"actions": [{"do": "shell", "cmd": "del"}]}, bytes, g)[0],
          "action inconnue (shell) refusée")
    check(not core.open_https("http://exemple.fr")[0] and not core.open_https("https://a:b@x.fr")[0],
          "lien : https seul, sans identifiant")
    check(not core.open_settings("regedit")[0], "page de Réglages hors liste refusée")
    check(not core.template_name_ok("../x.dotx") and not core.template_name_ok("macro.docm")
          and core.template_name_ok("Lettre Acme.dotx"), "modèles : nom simple, sans macros")
    with tempfile.TemporaryDirectory() as d:
        ok, _ = core.install_templates([("Lettre Acme.dotx", b"PK\x03\x04x")], Path(d))
        check(ok and (Path(d) / "Lettre Acme.dotx").is_file(), "modèle Word copié")
        check(not core.install_templates([("faux.dotx", b"MZ")], Path(d))[0], "fichier non Office refusé")
        core.install_templates([("Lettre Acme.dotx", b"PK\x03\x04v2")], Path(d))
        check((Path(d) / "Lettre Acme.dotx").read_bytes().endswith(b"v2")
              and len(list(Path(d).glob("Lettre Acme (avant PapAI *).dotx"))) == 1,
              "modèle déjà présent : gardé à côté, jamais écrasé")
    if not core.WINDOWS:
        check(not core.antivirus_scan()[0], "scan antivirus : seulement sous Windows")
    g.raise_stop()
    check(core.play_actions({"actions": [{"do": "open_url", "url": "https://x.fr"}]}, bytes, g)
          == (False, "Arrêté."), "Arrêter : aucune action d'automatisme jouée")

    m = Model(demo="home")
    m.revoke_consent()
    m.lessons = [{"id": "imp-000000000001", "title": "Google", "platforms": ["windows"],
                  "actions": [{"do": "holo", "goal": "Remettre Google", "steps": ["a"]}]},
                 {"id": "imp-000000000002", "title": "Mac seul", "platforms": ["mac"],
                  "actions": [{"do": "open_settings", "page": "printers"}]}]
    m.run_shortcut("imp-000000000002")
    check(m.screen == "home" and "autre ordinateur" in (m.notice or ""), "automatisme d'une autre plateforme refusé")
    m.lessons.append({"id": "imp-000000000003", "title": "Long", "platforms": ["windows"],
                      "actions": [{"do": "open_url", "url": "https://x.fr"}]})
    m.automation_running = "Scan"
    m.run_shortcut("imp-000000000003")
    check(m.snapshot()["automationRunning"] == "Scan", "un seul automatisme à la fois, Arrêter visible")
    m.stop()
    check(m.gate.is_stopped, "Arrêter depuis l'accueil lève le verrou de l'automatisme")
    m.automation_running = None
    m.run_shortcut("imp-000000000001")
    check(m.screen == "consent", "automatisme avec Holo : accord du partage d'abord")
    m.give_consent()
    check(wait_until(lambda: m.screen == "session" and m.task == "Remettre Google", 3),
          "puis lancé en un clic, sans validation d'un aidant")


def with_server(base: str = "http://127.0.0.1:8000", key: str = "demo") -> None:
    import websockets

    ws_base = base.replace("http", "ws", 1)
    os.environ["PAPAI_SERVER"] = ws_base + "/ws/bridge"
    played = []

    def runner(name, args, screen, gate, protected):
        if gate.is_stopped:
            raise core.Stopped()
        played.append(name)
        return f"{name} simulé"

    m = Model(demo="")
    m.demo = None
    m.start(screen_factory=FakeScreen, runner=runner)
    check(wait_until(lambda: m.connected, 10), "connexion au pont /ws/bridge (hello os=windows)")

    async def aidant():
        async with websockets.connect(f"{ws_base}/ws/aidant/{key}", max_size=2**24) as ws:
            async def until(pred, t):
                end = time.time() + t
                while time.time() < end:
                    try:
                        msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=end - time.time()))
                    except asyncio.TimeoutError:
                        break
                    if pred(msg):
                        return msg
                return None

            m.request_consent("Je ne retrouve plus mes photos")
            check(m.screen == "consent" and not played, "écran de consentement, rien ne bouge")
            m.give_consent()
            check(settings.load().get("screenConsent") is True, "accord de partage enregistré sur le disque")
            st = await until(lambda x: x.get("type") == "status" and x.get("state") == "awaiting_approval", 60)
            check(st is not None and bool(st.get("plan")), "plan proposé à l'aidant")
            await asyncio.sleep(1)
            check(not played, "aucune action avant validation du plan")
            check(m.state == "awaiting_approval", "l'app affiche « vérifie le plan »")
            await ws.send(json.dumps({"type": "approve_plan"}))
            await until(lambda x: x.get("type") == "status" and x.get("state") in ("active", "done"), 30)
            await asyncio.to_thread(wait_until, lambda: bool(played) or m.state == "done", 60)
            check(bool(played), f"actions jouées après validation : {played}")
            m.stop()
            n = len(played)
            st = await until(lambda x: x.get("type") == "status" and x.get("state") == "stopped", 15)
            check(st is not None, "le serveur reçoit stop et passe en « stopped »")
            await asyncio.sleep(2)
            check(len(played) == n and m.state == "stopped", "plus rien ne bouge après Arrêter")

    asyncio.run(aidant())


if __name__ == "__main__":
    unit()
    if "--serveur" in sys.argv:
        with_server()
    print(f"{ok} vérifications passées")
