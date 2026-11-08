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
import threading
import time
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ["PAPAI_HOME"] = tempfile.mkdtemp()

from papai import apps, core, settings  # noqa: E402
from papai.app import Api  # noqa: E402
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
    api = Api.__new__(Api)
    api._model = Mock()
    method = getattr(api, "run_suggested_automation", None)
    check(callable(method), "l'API expose le lancement d'un automate suggéré")
    method("auto-1", "ticket-1")
    check(api._model.run_suggested_automation.call_args.args == ("auto-1", "ticket-1"),
          "l'API transmet l'automate et son ticket au modèle")

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

    # Parité Mac : Pause, question à la personne, encart pendant que Holo agit.
    out, compacts = [], []

    class FakeBridge:
        def send(self, payload): out.append(payload)
        def ask_help(self, task, requested_by=None): pass
        def stop(self): pass

    m = Model(demo="", on_compact=compacts.append)
    m.bridge = FakeBridge()
    m.helpers = [{"id": "1", "name": "Claire", "relation": ""}]
    m.ask_help("Mes photos")
    m._apply_status({"state": "active", "plan_approved": True, "helper_name": "Théo"})
    check(m.compact and compacts == [True], "Holo agit : la fenêtre devient l'encart")
    check(m.snapshot()["carer"] == "Théo", "l'encart dit qui s'occupe de l'aide")
    m.expand_window()
    check(not m.compact and compacts == [True, False], "agrandir : la grande fenêtre revient")
    m.toggle_pause()
    check(out[-1] == {"type": "pause"} and m.snapshot()["paused"], "Pause envoyée au serveur")
    m.toggle_pause()
    check(out[-1] == {"type": "resume"} and not m.paused, "Reprendre envoyé au serveur")
    m._apply_status({"state": "awaiting_helper", "paused": False,
                     "question": {"question": "Ordinateur ou clé USB ?", "options": ["Ordinateur", "Clé USB"],
                                  "to": "senior"}})
    snap = m.snapshot()
    check(snap["questionForMe"] and snap["questionOptions"] == ["Ordinateur", "Clé USB"] and not m.compact,
          "question posée à la personne : grande fenêtre et réponses proposées")
    m.answer_senior("  Clé USB ")
    check(out[-1] == {"type": "senior_answer", "text": "Clé USB"}, "réponse de la personne envoyée")
    m.answer_senior("   ")
    check(out[-1]["text"] == "Clé USB", "réponse vide ignorée")
    m._apply_status({"state": "awaiting_helper", "question": {"question": "?", "to": "helper"}})
    check(not m.question_for_me and m.compact, "question pour l'aidant : encart, la personne attend")
    m.send_dictation("Le dossier de la comptabilité", final=True)
    check(out[-1] == {"type": "dictation", "text": "Le dossier de la comptabilité", "final": True}, "dictée transmise à l'aidant")
    m.stop()
    check(not m.compact and compacts[-1] is False, "Arrêter : la grande fenêtre revient")
    m.toggle_pause()
    check(out[-1]["type"] == "dictation", "pas de Pause hors session")
    m._handle({"type": "alert", "level": "danger", "title": "x", "alert_id": "a1"})
    m._handle({"type": "alert_acknowledged", "alert_id": "a1"})
    check(m.snapshot()["guardAcknowledged"], "accusé du proche gardé pour l'écran de fin")

    # Ticket : sans support disponible, la demande attend ; rendez-vous ; reprise.
    asks = []

    class TicketBridge(FakeBridge):
        def ask_help(self, task, requested_by=None, ticket=None): asks.append((task, requested_by, ticket))

    t = Model(demo="", on_compact=lambda _c: None)
    t.bridge = TicketBridge()
    t.ask_help("Imprimer")
    suggestions = [{"id": "auto-1", "title": "Imprimer une facture"}]
    t.lessons = [{"id": "auto-1", "title": "Imprimer une facture", "platforms": ["windows"],
                  "actions": [{"do": "open_settings", "page": "printers"}]}]
    t._handle({"type": "ticket_queued", "ticket": "t1", "number": 4, "task": "Imprimer",
               "suggestions": suggestions})
    snap = t.snapshot()
    check(snap["queued"]["number"] == 4 and snap["queued"]["show"] and snap["screen"] == "home" and not snap["sessionOpen"],
          "aucun support disponible : la demande attend, retour à l'accueil")
    check(snap["queued"]["suggestions"] == suggestions and snap["queued"]["suggestion_lancee"] is None,
          "l'automate suggéré est transmis à l'écran d'attente")
    with patch("papai.model.play_actions", return_value=(True, "")):
        t.run_suggested_automation("auto-1", "t1")
        fin = time.time() + 2
        while t.automation_running is not None and time.time() < fin:
            time.sleep(0.01)
    check(out[-1] == {"type": "ticket_automate_launched", "ticket": "t1", "lesson": "auto-1"}
          and t.queued["suggestion_lancee"] == "auto-1",
          "Lancer démarre l'automate et signale son ticket")

    pending = Model(demo="", on_compact=lambda _c: None)
    pending.prefs["screenConsent"] = False
    pending.lessons = [{"id": "holo-1", "title": "Configurer l'imprimante", "platforms": ["windows"],
                        "actions": [{"do": "holo", "goal": "Configurer l'imprimante"}]}]
    pending._handle({"type": "ticket_queued", "ticket": "t-consent", "number": 5, "task": "Imprimer",
                     "suggestions": [{"id": "holo-1", "title": "Configurer l'imprimante"}]})
    pending.run_suggested_automation("holo-1", "t-consent")
    check(pending.screen == "consent" and pending.queued and not pending.queued["show"]
          and pending.pending_automation_ticket == "t-consent",
          "l'attente se ferme au consentement et le ticket reste en attente de lancement")

    t.schedule_ticket("demain9")
    check(out[-1]["type"] == "ticket_schedule" and out[-1]["ticket"] == "t1" and out[-1]["at"] > time.time(),
          "rendez-vous demandé au serveur")
    t._handle({"type": "ticket_scheduled", "ticket": "t1", "at": 123})
    t.close_queued()
    check(t.queued["rdv"] == 123 and not t.snapshot()["queued"]["show"], "rendez-vous gardé, l'accueil revient")
    t._handle({"type": "remote_request", "from": "Claire", "task": "Imprimer", "ticket": "t1", "rdv": True})
    check(t.snapshot()["remoteRequest"]["rdv"], "à l'heure du rendez-vous : proposition affichée")
    t.refuse_remote()
    check(out[-1] == {"type": "remote_answer", "accepted": False, "ticket": "t1"}, "pas disponible : le ticket est signalé")
    t._handle({"type": "remote_request", "from": "Claire", "task": "Imprimer", "ticket": "t1"})
    t.accept_remote()
    check(asks[-1] == ("Imprimer", "Claire", "t1"), "accepté : la session reprend le ticket")

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

    # Protection en temps réel : activée par défaut, rien ne part quand elle est coupée.
    check(settings.protection_on({}) and not settings.protection_on({"realtimeProtection": False}),
          "protection en temps réel activée par défaut")
    signals = []

    class GuardWS:
        async def send(self, raw): signals.append(json.loads(raw))

    b = Bridge("", core.StopGate(), FakeScreen, lambda m: None, lambda ok: None, lambda s: None,
               guard=lambda: {"type": "guard", "processes": ["AnyDesk"], "window": "", "url": ""})
    b.protection = lambda: False
    asyncio.run(b._send_guard(GuardWS()))
    check(signals == [], "protection coupée : aucun signal du gardien n'est envoyé")
    b.protection = lambda: True
    asyncio.run(b._send_guard(GuardWS()))
    check(len(signals) == 1 and signals[0]["processes"] == ["AnyDesk"], "protection activée : signal envoyé")

    sent_p = []

    class ProfileBridge:
        def send(self, payload): sent_p.append(payload)

    pm = Model(demo="")
    pm.bridge = ProfileBridge()
    check(pm.snapshot()["realtimeProtection"] is True, "Réglages : protection affichée activée")
    pm.set_realtime_protection(False)
    check(settings.load().get("realtimeProtection") is False and not pm.snapshot()["realtimeProtection"],
          "protection coupée gardée sur le disque")
    check(sent_p and sent_p[-1].get("type") == "profile" and sent_p[-1]["protection"] is False,
          "le serveur apprend que la protection est coupée")
    check(Model(demo="").realtime_protection is False, "l'état survit au redémarrage de l'app")
    pm.set_realtime_protection(True)

    m = Model(demo="home")
    m.start()
    m._handle({"type": "alert", "level": "danger", "title": "Arnaque", "detail": "N'appelez pas."})
    check(m.snapshot()["alert"]["title"] == "Arnaque", "alerte du gardien affichée")
    check(m.gate.is_stopped and m.state == "stopped", "alerte danger : verrou local et état arrêté")
    m.dismiss_alert()
    check(m.snapshot()["alert"] is None, "alerte fermée")
    check(m.gate.is_stopped, "fermer l'alerte ne baisse pas le verrou")
    m._handle({"type": "alert", "level": "danger", "alert_id": "g1", "blocked": True})
    m._apply_status({"state": "stopped", "stopped_by": "gardien"})
    check(m.snapshot()["stoppedBy"] == "gardien", "cause d'arrêt conservée pour l'écran de fin")
    m.dismiss_alert()
    check(m.alert is not None, "alerte bloquante non fermable localement")
    m._handle({"type": "alert_acknowledged", "alert_id": "g1", "acknowledged_by": "Quentin"})
    check(m.alert["acknowledged"] is True, "prise en charge anonyme affichée pour la bonne alerte")
    m._handle({"type": "alert_cleared", "alert_id": "autre"})
    check(m.alert is not None, "un effacement d'une autre alerte est ignoré")
    m._handle({"type": "alert_cleared", "alert_id": "g1"})
    m._handle({"type": "alert_acknowledged", "alert_id": "g1", "acknowledged_by": "Quentin"})
    check(m.alert is None and m.gate.is_stopped, "effacement sans reprise ; accusé tardif ignoré")

    async def guard_during_action(name):
        started, release, finished = threading.Event(), threading.Event(), threading.Event()
        fake = Mock()

        def wait_for_alert(*args):
            started.set()
            if not release.wait(3):
                raise TimeoutError("alerte non reçue")

        if name == "click":
            fake.moveTo.side_effect = wait_for_alert
        else:
            fake.write.side_effect = wait_for_alert

        def runner(*args):
            try:
                return core.run_action(*args)
            finally:
                finished.set()

        b = Bridge("", core.StopGate(), FakeScreen, lambda m: None,
                   lambda ok: None, lambda s: None, runner=runner)
        b.last_status = {"state": "active", "plan_approved": True}
        act = {"name": name, "args": {"x": 10, "y": 10, "text": "ABCD"}}
        with patch.dict(sys.modules, {"pyautogui": fake}), patch.object(core, "WINDOWS", False):
            await b._handle(WS(), {"type": "execute", "req": "guard", "action": act})
            check(await asyncio.to_thread(started.wait, 3), f"{name} engagé avant l'alerte")
            tasks = list(b._executions)
            await b._handle(WS(), {"type": "alert", "level": "info"})
            check(b.gate.is_stopped and not tasks[0].cancelling(), "info : verrou levé avant le geste suivant")
            await b._handle(WS(), {"type": "alert", "level": "danger"})
            check(b.gate.is_stopped and tasks[0].cancelling(), "danger : verrou levé et execute annulé")
            await b._execute(WS(), "apres", act)
            check(sent[-1]["refused"], "execute ultérieur refusé")
            b.gate.reset()
            release.set()
            await asyncio.gather(*tasks, return_exceptions=True)
            check(await asyncio.to_thread(finished.wait, 3), "le fil d'action s'est arrêté")
            check(not fake.click.called and fake.write.call_count == (1 if name == "type_text" else 0),
                  f"{name} : aucun geste suivant après l'alerte, même après reset")
            check(not b._executions, "tâche execute libérée")

    asyncio.run(guard_during_action("click"))
    asyncio.run(guard_during_action("type_text"))

    async def blocked_attention():
        b = Bridge("", core.StopGate(), FakeScreen, lambda m: None,
                   lambda ok: None, lambda s: None)
        await b._handle(WS(), {"type": "alert", "level": "attention", "blocked": True})
        check(b.gate.is_stopped, "avis Holo bloquant : verrou levé même au niveau attention")

    asyncio.run(blocked_attention())

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
              and (Path(d) / "Lettre Acme (avant PapAI).dotx").is_file(),
              "modèle déjà présent : gardé à côté, jamais écrasé")
        core.install_templates([("Lettre Acme.dotx", b"PK\x03\x04v3")], Path(d))
        check((Path(d) / "Lettre Acme (avant PapAI 2).dotx").read_bytes().endswith(b"v2"),
              "deux remplacements de suite : chaque ancienne version est gardée")
        real_replace = core.os.replace
        core.os.replace = lambda *a: (_ for _ in ()).throw(PermissionError("ouvert dans Word"))
        try:
            check(core.install_templates([("Lettre Acme.dotx", b"PK\x03\x04v4")], Path(d))[0] is False,
                  "échec d'installation remonté")
        finally:
            core.os.replace = real_replace
        check(sorted(p.name for p in Path(d).iterdir()) == sorted(
                  ["Lettre Acme.dotx", "Lettre Acme (avant PapAI).dotx", "Lettre Acme (avant PapAI 2).dotx"]),
              "échec d'installation : ni fichier temporaire ni sauvegarde en trop")
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


class FakeWinreg:
    """Registre simulé : `HKLM` et `HKCU\\SOFTWARE\\Policies\\PapAI`."""
    HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER, REG_SZ, REG_EXPAND_SZ, REG_DWORD = "HKLM", "HKCU", 1, 2, 4

    def __init__(self, values: dict) -> None:
        self.values = values

    def OpenKey(self, root, path):  # noqa: N802
        if path != settings.POLICY_KEY or root not in self.values:
            raise OSError("clé absente")
        vals = self.values[root]

        class Key:
            def __enter__(self): return vals
            def __exit__(self, *a): return False
        return Key()

    def QueryValueEx(self, key, name):  # noqa: N802
        if name not in key:
            raise OSError("valeur absente")
        v = key[name]
        return v, (self.REG_DWORD if isinstance(v, int) else self.REG_SZ)


def entreprise() -> None:
    """Poste d'entreprise : nom du compte Windows, organisation par stratégie de groupe,
    aucune liaison possible depuis le poste."""
    check(settings.policy() == {} or sys.platform == "win32", "hors Windows : pas de lecture du registre")
    fake = FakeWinreg({
        "HKLM": {"OrgToken": "ins-jeton-machine", "Server": "https://papai.acme.fr", "Role": 3},
        "HKCU": {"OrgToken": "ins-jeton-utilisateur", "DisplayName": "Jeanne Martin", "Role": "Comptabilité"},
    })
    with patch.object(settings.sys, "platform", "win32"), patch.dict(sys.modules, {"winreg": fake}):
        pol = settings.policy()
        check(pol == {"OrgToken": "ins-jeton-machine", "Server": "https://papai.acme.fr",
                      "DisplayName": "Jeanne Martin", "Role": "Comptabilité"},
              "stratégie ordinateur (HKLM) avant stratégie utilisateur (HKCU), valeurs non texte ignorées")
        os.environ["PAPAI_ORG"] = "ins-jeton-de-repli"
        try:
            check(settings.org_token() == "ins-jeton-machine", "jeton de la stratégie avant PAPAI_ORG")
        finally:
            os.environ.pop("PAPAI_ORG", None)
        check(settings.enroll_base() == "https://papai.acme.fr", "serveur d'inscription donné par la stratégie")
        check(settings.display_name() == "Jeanne", "« Bonjour Jeanne » : premier mot du nom imposé")
        check(settings.machine_name().startswith("Jeanne Martin · Comptabilité"), "le support voit nom et service")
        saved = os.environ.pop("PAPAI_SERVER", None)
        try:
            settings.save({"server": "wss://papai-officiel/k/cle/ws/bridge"})
            check(settings.needs_space(), "stratégie vers un autre serveur : nouvel espace sur celui-ci")
            settings.save({"server": "wss://papai.acme.fr/k/cle/ws/bridge"})
            check(not settings.needs_space(), "espace déjà sur le serveur de la stratégie : rien à refaire")
        finally:
            settings.save({"server": ""})
            if saved is not None:
                os.environ["PAPAI_SERVER"] = saved
        fake.values = {"HKCU": {"OrgToken": "pas-un-jeton", "Server": "wss://srv/k/cle/ws/bridge"}}
        check(settings.org_token() == "" and settings.enroll_base() == settings.OFFICIAL_HTTP,
              "jeton mal formé et adresse avec clé ignorés")

    with patch.object(settings, "policy", lambda: {}), \
            patch.object(settings, "_windows_display_name", lambda: "Martin, Jeanne"):
        check(settings.display_name() == "Jeanne", "nom d'annuaire « Martin, Jeanne » : Jeanne")
    with patch.object(settings, "policy", lambda: {}), \
            patch.object(settings, "_windows_display_name", lambda: ""), \
            patch.object(settings, "_login_name", lambda: "jean.dupont"):
        check(settings.display_name() == "Jean", "sans nom complet : identifiant Windows, premier mot")
    with patch.object(settings, "policy", lambda: {}), \
            patch.object(settings, "_windows_display_name", lambda: ""), \
            patch.object(settings, "_login_name", lambda: ""):
        check(settings.display_name() == "", "aucun nom : « Bonjour » seul")

    sent = []
    with patch.object(settings, "display_name", lambda: "Jeanne"):
        m = Model()
    m._send = sent.append
    snap = m.snapshot()
    check(snap["firstName"] == "Jeanne", "le nom vient de Windows, rien à saisir")
    check(not any(k.startswith(("pair", "onboard")) or k == "storedFirstName" for k in snap),
          "plus d'accueil en étapes, de prénom saisi ni de liaison dans l'état")
    for gone in ("set_first_name", "start_pairing", "copy_invitation", "answer_pair", "finish_onboarding",
                 "save_settings", "remove_helper"):
        check(not hasattr(m, gone), f"parcours particulier retiré : {gone}")
    m._send_profile()
    check(sent[-1] == {"type": "profile", "protection": True, "name": "Jeanne"}, "le support lit le nom Windows")
    m._handle({"type": "pair_confirm", "req": 7, "name": "Intrus", "relation": "Service informatique"})
    check(sent[-1] == {"type": "pair_decision", "req": 7, "accept": False} and "pairRequest" not in m.snapshot(),
          "code tapé sur un téléphone : refusé d'office, rien à l'écran")
    n = len(sent)
    m._handle({"type": "pair_code", "code": "482913", "url": "https://h/p/482913"})
    check(len(sent) == n and "pairCode" not in m.snapshot(), "aucun code de liaison affiché")
    check(not m.org_configured or settings.org_token(), "sans jeton : poste non configuré")
    m.prefs["orgName"] = "Acme"
    check(m.snapshot()["orgConfigured"] and m.snapshot()["orgName"] == "Acme", "organisation rattachée visible")
    demo = Model(demo="home")
    demo.start()
    check(demo.snapshot()["orgName"] == "Acme" and demo.snapshot()["firstName"] == "Jeanne", "démo : Jeanne chez Acme")

    # Premier lancement sans serveur réglé : l'espace est créé, l'adresse gardée.
    saved = os.environ.pop("PAPAI_SERVER", None)
    try:
        settings.save({"server": ""})
        m = Model()
        check(settings.needs_space(m.prefs), "aucun serveur réglé : il faut un espace")
        m._provision = lambda: "wss://srv/k/cle-de-test-123/ws/bridge"
        m._create_space()
        check(m.server_url == "wss://srv/k/cle-de-test-123/ws/bridge" and not settings.needs_space(m.prefs),
              "l'espace créé est gardé : plus rien à régler")
        check(settings.provision("http://127.0.0.1:9", timeout=1) is None, "serveur injoignable : pas d'espace")
        check(settings._on_base("wss://papai.run.app/k/cle/ws/bridge", "http://localhost:8071")
              == "ws://localhost:8071/k/cle/ws/bridge", "pont recalé sur le serveur de la stratégie")
        settings.save({"server": ""})
        m = Model()
        essais, attentes = iter([None, None, "wss://srv/k/cle-apres-coupure/ws/bridge"]), []
        m._provision = lambda: next(essais)
        m._create_space(wait=attentes.append)
        check(m.server_url == "wss://srv/k/cle-apres-coupure/ws/bridge" and attentes == [5, 10],
              "hors ligne au premier lancement : l'espace est créé au retour du réseau")
        settings.save({"server": ""})
        m = Model()

        def choisi_pendant():
            settings.save({"server": "ws://mon-serveur:8000/ws/bridge"})
            return "wss://srv/k/cle-officielle/ws/bridge"
        m._provision = choisi_pendant
        m._create_space(wait=lambda _: None)
        check(settings.load().get("server") == "ws://mon-serveur:8000/ws/bridge",
              "un serveur choisi pendant la création n'est pas écrasé")

        # Poste d'entreprise : jeton d'inscription déposé par le service IT.
        os.environ["PAPAI_ORG"] = "ins-jeton-de-test"
        check(settings.org_token() == "ins-jeton-de-test", "jeton d'organisation lu dans PAPAI_ORG")
        settings.save({"server": "", "orgJoined": "", "orgName": ""})
        m = Model()

        def inscrit():
            m._org_name = "Acme"
            return "wss://srv/k/cle-poste-acme/ws/bridge"
        m._provision = inscrit
        m._create_space(wait=lambda _: None)
        check(m.prefs.get("orgJoined") == "ins-jeton-de-test" and m.snapshot()["orgName"] == "Acme",
              "premier lancement avec jeton : le poste est inscrit dans l'organisation")
        check(not m._org_pending(), "jeton déjà utilisé : rien de plus à faire")
        settings.save({"server": "wss://srv/k/cle-poste-seul/ws/bridge", "orgJoined": "", "orgName": ""})
        m = Model()
        check(m._org_pending(), "poste déjà installé + jeton déposé : il doit rejoindre l'organisation")
        essais, attentes = iter([None, "Acme"]), []
        m._join = lambda tok: next(essais)
        m._join_org(wait=attentes.append)
        check(settings.load().get("orgName") == "Acme" and attentes == [5],
              "hors ligne : le poste rejoint l'organisation au retour du réseau")
        settings.save({"orgJoined": "", "orgName": ""})
        m = Model()
        m._join = lambda tok: ""
        m._join_org(wait=lambda _: (_ for _ in ()).throw(AssertionError("ne doit pas réessayer")))
        check(not settings.load().get("orgName"), "jeton refusé par le serveur : pas de nouvel essai")
        m = Model()
        reel, envois = settings.provision, []

        def refuse(org="", info=None, **_):
            envois.append(org)
            if org:
                info.update({"error": "Jeton d'organisation inconnu.", "status": 403})
                return None
            return "wss://srv/k/cle-hors-org/ws/bridge"
        settings.provision = refuse
        try:
            url = m._provision()
        finally:
            settings.provision = reel
        check(url == "wss://srv/k/cle-hors-org/ws/bridge" and envois == ["ins-jeton-de-test", ""] and not m._org_name,
              "jeton refusé à l'inscription : le poste a quand même son espace, hors organisation")
        os.environ["PAPAI_ORG"] = "pas-un-jeton"
        check(settings.org_token() == "", "jeton mal formé ignoré")
        os.environ.pop("PAPAI_ORG", None)
    finally:
        os.environ.pop("PAPAI_ORG", None)
        settings.save({"server": "", "orgJoined": "", "orgName": ""})
        if saved is not None:
            os.environ["PAPAI_SERVER"] = saved


if __name__ == "__main__":
    unit()
    entreprise()
    if "--serveur" in sys.argv:
        with_server()
    print(f"{ok} vérifications passées")
