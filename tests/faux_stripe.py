"""Serveur Stripe local, sans paiement ni clé réelle."""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs


class FauxStripe:
    def __init__(self):
        self.requests = []
        self.fail = False
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                self.respond()

            def do_POST(self):
                self.respond()

            def respond(self):
                data = parse_qs(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode())
                owner.requests.append((self.path, data))
                valid = self.headers.get("Authorization") == "Bearer sk_test_local"
                status = 200 if valid and not owner.fail else 401
                if self.path == "/v1/prices/price_test":
                    result = {"unit_amount": 1200, "currency": "eur", "recurring": {"interval": "month"}}
                elif self.path == "/v1/checkout/sessions":
                    result = {"url": "https://checkout.stripe.test/session"}
                elif self.path == "/v1/billing_portal/sessions":
                    result = {"url": "https://billing.stripe.test/portal"}
                else:
                    status, result = 404, {}
                raw = json.dumps(result).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = "http://127.0.0.1:" + str(self.server.server_port)

    def __enter__(self):
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
