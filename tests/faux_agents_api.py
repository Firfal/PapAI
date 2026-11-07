"""Faux Agents API de H, local, pour tester l'agent navigateur sans clé.

Sur le modèle de tests/faux_holo.py. Il répond aux routes `api/v2/sessions`
du SDK `hai_agents` et joue un agent web scripté :

- "simple"   : ouvre le site (étape 1), une capture, clique (étape 2), répond ;
- "question" : comme "simple", mais appelle ask_helper avant de cliquer ;
- "long"     : agit sans fin, pour essayer pause, reprise et arrêt.

    python tests/faux_agents_api.py [port]
    HAI_AGENTS_BASE_URL=http://127.0.0.1:8998 HAI_API_KEY=stub-key ...
"""
from __future__ import annotations

import datetime as dt
import json
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FRAME = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
PAS_S = 0.1


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _agent(data: dict) -> dict:
    return {"type": "AgentEvent", "timestamp": _now(), "data": data}


class FauxSession:
    def __init__(self, sid: str, corps: dict, scenario: str) -> None:
        self.id = sid
        self.corps = corps
        self.scenario = scenario
        self.status = "running"
        self.events: list[dict] = []
        self.pending: list[dict] = []
        self.tool_results: list = []
        self.messages: list = []
        self.cond = threading.Condition()
        threading.Thread(target=self._jouer, daemon=True).start()

    def push(self, ev: dict) -> None:
        with self.cond:
            self.events.append(ev)
            self.cond.notify_all()

    def _attendre(self) -> bool:
        """Un pas d'agent, sauf en pause. False si la session est finie."""
        time.sleep(PAS_S)
        while True:
            with self.cond:
                if self.status in ("interrupted", "completed", "failed"):
                    return False
                if self.status != "paused":
                    return True
                self.cond.wait(0.05)

    def _action(self, etape: int, outil: str, args: dict) -> None:
        self.push(_agent({"kind": "policy_event", "content": f"Étape {etape} : j'avance.",
                          "tool_reqs": [{"tool_name": outil, "args": args, "id": f"a{len(self.events)}"}]}))

    def _jouer(self) -> None:
        self.push({"type": "AgentStartedEvent", "timestamp": _now(), "data": {}})
        if not self._attendre():
            return
        self._action(1, "navigate", {"url": "https://meteofrance.com/previsions-meteo-france/paris/75000"})
        self.push(_agent({"kind": "observation_event", "type": "screenshot",
                          "image": {"type": "base64", "source": FRAME, "media_type": "image/png"}}))
        if self.scenario == "long":
            n = 0
            while self._attendre():
                n += 1
                self._action(1, "scroll", {"direction": "down"})
            return
        if self.scenario == "question":
            if not self._attendre():
                return
            appel = {"tool_name": "ask_helper", "args": {"question": "Faut-il accepter les cookies ?"}, "id": "q1"}
            with self.cond:
                self.pending = [appel]
                self.status = "awaiting_tool_results"
            self.push({"type": "ActiveStateChangeEvent", "timestamp": _now(),
                       "data": {"state": "awaiting_tool_results", "pending_tool_calls": [appel]}})
            with self.cond:
                while not self.tool_results and self.status == "awaiting_tool_results":
                    self.cond.wait(0.05)
                if self.status != "awaiting_tool_results":
                    return
                self.pending = []
                self.status = "running"
            self.push({"type": "ActiveStateChangeEvent", "timestamp": _now(), "data": {"state": "running"}})
        if not self._attendre():
            return
        self._action(2, "click", {"element": "Paris"})
        if not self._attendre():
            return
        self.push(_agent({"kind": "answer_event", "answer": "La météo de Paris est affichée à l'écran."}))
        with self.cond:
            self.status = "completed"
            self.cond.notify_all()


class FauxAgentsAPI:
    def __init__(self, scenario: str = "simple") -> None:
        self.scenario = scenario
        self.sessions: dict[str, FauxSession] = {}
        self.appels: list[tuple[str, str]] = []
        api = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a) -> None:  # noqa: D401
                pass

            def _json(self, code: int, obj=None) -> None:
                body = b"" if obj is None else json.dumps(obj).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def _corps(self):
                n = int(self.headers.get("Content-Length", 0) or 0)
                return json.loads(self.rfile.read(n) or b"{}") if n else {}

            def _route(self, methode: str) -> None:
                u = urllib.parse.urlparse(self.path)
                q = urllib.parse.parse_qs(u.query)
                parts = [p for p in u.path.split("/") if p]
                api.appels.append((methode, u.path))
                if parts[:3] != ["api", "v2", "sessions"]:
                    return self._json(404, {"detail": "inconnu"})
                if self.headers.get("Authorization", "") != "Bearer stub-key":
                    return self._json(401, {"detail": "clé"})
                if methode == "POST" and len(parts) == 3:
                    corps = self._corps()
                    sid = f"h{len(api.sessions) + 1}"
                    api.sessions[sid] = FauxSession(sid, corps, api.scenario)
                    return self._json(200, {"id": sid, "status": {"status": "running"}, "created_at": _now(), "request": corps})
                s = api.sessions.get(parts[3]) if len(parts) > 3 else None
                if s is None:
                    return self._json(404, {"detail": "session"})
                action = parts[4] if len(parts) > 4 else ""
                if methode == "GET" and action == "changes":
                    debut = int(q.get("from_index", ["0"])[0])
                    attente = min(float(q.get("wait_for_seconds", ["0"])[0]), 0.5)
                    with s.cond:
                        if len(s.events) <= debut and attente:
                            s.cond.wait(attente)
                        nouveaux = s.events[debut:]
                        st = s.status
                    if not nouveaux:
                        return self._json(204)
                    return self._json(200, {"status": st, "new_events": nouveaux, "first_index": debut})
                if methode == "GET" and action == "status":
                    with s.cond:
                        return self._json(200, {"status": s.status, "pending_tool_calls": s.pending})
                if methode == "POST" and action in ("pause", "resume"):
                    with s.cond:
                        if s.status in ("running", "paused", "awaiting_tool_results"):
                            s.status = "paused" if action == "pause" else "running"
                        s.cond.notify_all()
                    return self._json(200, {"id": s.id, "status": s.status})
                if methode == "POST" and action == "tool_results":
                    corps = self._corps()
                    with s.cond:
                        s.tool_results.append(corps)
                        s.cond.notify_all()
                    return self._json(200, {})
                if methode == "POST" and action == "messages":
                    corps = self._corps()
                    with s.cond:
                        s.messages.append(corps)
                        if s.status == "paused":
                            s.status = "running"
                        s.cond.notify_all()
                    return self._json(200, {})
                if methode == "DELETE" and not action:
                    with s.cond:
                        s.status = "interrupted"
                        s.cond.notify_all()
                    return self._json(200, {"id": s.id, "status": "interrupted"})
                return self._json(404, {"detail": "route"})

            def do_GET(self) -> None:  # noqa: N802
                self._route("GET")

            def do_POST(self) -> None:  # noqa: N802
                self._route("POST")

            def do_DELETE(self) -> None:  # noqa: N802
                self._route("DELETE")

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.server.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def fermer(self) -> None:
        self.server.shutdown()
        self.server.server_close()

    def a_appele(self, methode: str, fin: str) -> bool:
        return any(m == methode and p.endswith(fin) for m, p in self.appels)


if __name__ == "__main__":
    api = FauxAgentsAPI(sys.argv[2] if len(sys.argv) > 2 else "simple")
    print(f"Faux Agents API sur {api.url}")
    threading.Event().wait()
