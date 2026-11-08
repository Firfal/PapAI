"""Aperçu de l'interface dans un navigateur, sans Windows ni serveur.

    python -m papai.preview [port]
    puis http://127.0.0.1:8765/?demo=home   (ou consent, planning,
    awaiting_approval, active, awaiting_helper, done, stopped, lesson, remote,
    home_no_org, requests ; `&sheet=settings` pour les Réglages)

Les états viennent de `Model` en mode démonstration (les mêmes que PAPAI_DEMO).
Sert aux captures de la PR et à travailler le dessin depuis n'importe quel OS.
"""

from __future__ import annotations

import json
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from .model import Model
from .home_shortcuts import HomeShortcuts

UI = Path(__file__).resolve().parent.parent / "ui"


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        u = urlparse(self.path)
        if u.path == "/state.json":
            query = parse_qs(u.query)
            demo = (query.get("demo") or ["home"])[0]
            m = Model(demo=demo)
            m.prefs = {}
            m.start()
            snap = m.snapshot()
            if demo in ('home_empty', 'home_shortcuts'):
                snap['lessons'] = []
            snap['microPresent'] = (query.get('mic') or ['1'])[0] != '0'
            snap['homeShortcuts'] = HomeShortcuts(demo=True).snapshot()
            if demo != 'home_shortcuts':
                snap['homeShortcuts'] = [t for t in snap['homeShortcuts'] if not t.get('personal')]
            body = json.dumps(snap, ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def log_message(self, *a) -> None:
        pass


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    srv = ThreadingHTTPServer(("127.0.0.1", port), partial(Handler, directory=str(UI)))
    print(f"Aperçu : http://127.0.0.1:{port}/?demo=home", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
