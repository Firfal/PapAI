"""Abonnement Stripe test : python tests/test_abonnement.py (aucun service externe)."""
import hashlib
import hmac
import json
import os
import socket
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import uvicorn
from fastapi import FastAPI

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from backend import billing, orgs
from faux_stripe import FauxStripe


class Abonnement(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.org_patch = patch.object(orgs, "ORGS_DIR", Path(self.tmp.name) / "orgs")
        self.org_patch.start()
        self.registry = orgs.Orgs()
        self.org = self.registry.create("Entreprise test")
        self.seats = [1, 2, 3]
        self.fake = FauxStripe().__enter__()
        self.env = patch.dict(os.environ, {"STRIPE_SECRET_KEY": "sk_test_local", "STRIPE_PRICE_ID": "price_test",
                                          "STRIPE_WEBHOOK_SECRET": "whsec_local", "STRIPE_API_BASE": self.fake.url})
        self.env.start()
        app = FastAPI()
        billing.install(app, self.registry.by_support, lambda o: self.seats, "https://papai.test",
                        self.registry.get, lambda: self.registry._by_id.values())
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.base = "http://127.0.0.1:" + str(self.sock.getsockname()[1])
        self.server = uvicorn.Server(uvicorn.Config(app, log_level="critical"))
        self.thread = threading.Thread(target=self.server.run, kwargs={"sockets": [self.sock]}, daemon=True)
        self.thread.start()
        for _ in range(200):
            if self.server.started:
                break
            time.sleep(.01)
        self.assertTrue(self.server.started)
        self.path = "/o/" + self.org.support

    def tearDown(self):
        self.server.should_exit = True
        self.thread.join(10)
        self.sock.close()
        self.env.stop()
        self.fake.__exit__()
        self.org_patch.stop()
        self.tmp.cleanup()

    def request(self, path, data=None, headers=None):
        req = Request(self.base + path, data=data, headers=headers or {})
        try:
            response = urlopen(req, timeout=5)
        except HTTPError as e:
            response = e
        with response:
            raw = response.read().decode()
            try:
                raw = json.loads(raw)
            except ValueError:
                pass
            return response.status, raw

    def event(self, kind="checkout.session.completed", obj=None, timestamp=None, signature=None, live=False):
        raw = json.dumps({"type": kind, "livemode": live, "data": {"object": obj if obj is not None else {
            "client_reference_id": self.org.id, "customer": "cus_test", "subscription": "sub_test"}}}).encode()
        t = str(int(time.time()) if timestamp is None else timestamp)
        sig = hmac.new(b"whsec_local", t.encode() + b"." + raw, hashlib.sha256).hexdigest()
        return self.request("/stripe/webhook", raw, {"Stripe-Signature": signature or f"t={t},v1=wrong,v1={sig}"})

    def test_non_configure_et_live(self):
        for key in ("", "sk_live_refuse", "rk_live_refuse", "invalide"):
            os.environ["STRIPE_SECRET_KEY"] = key
            self.assertEqual(self.request(self.path + "/abonnement")[0], 200)
            self.assertFalse(self.request(self.path + "/billing")[1]["disponible"])
            self.assertEqual(self.request(self.path + "/billing/checkout", b"")[0], 503)
        self.assertEqual(self.fake.requests, [])
        os.environ["STRIPE_SECRET_KEY"] = "sk_test_local"
        os.environ["STRIPE_PRICE_ID"] = ""
        self.assertFalse(self.request(self.path + "/billing")[1]["disponible"])

    def test_prix_checkout_et_cache(self):
        status, data = self.request(self.path + "/billing")
        self.assertEqual(status, 200)
        self.assertTrue(data["disponible"])
        self.assertEqual(data["prix"], {"unit_amount": 1200, "currency": "eur", "interval": "month"})
        self.assertEqual(data["postes"], 3)
        self.request(self.path + "/billing")
        self.assertEqual(len(self.fake.requests), 1)
        self.assertEqual(self.request(self.path + "/billing/checkout", b"")[1], {"url": "https://checkout.stripe.test/session"})
        fields = self.fake.requests[-1][1]
        self.assertEqual(fields["line_items[0][quantity]"], ["3"])
        self.assertEqual(fields["mode"], ["subscription"])
        for name in ("client_reference_id", "metadata[org]", "subscription_data[metadata][org]"):
            self.assertEqual(fields[name], [self.org.id])
        self.assertTrue(fields["success_url"][0].endswith("/abonnement"))
        self.seats.clear()
        self.assertEqual(self.request(self.path + "/billing")[1]["postes"], 0)
        self.request(self.path + "/billing/checkout", b"")
        self.assertEqual(self.fake.requests[-1][1]["line_items[0][quantity]"], ["1"])

    def test_webhook_et_portail_persistants(self):
        self.assertEqual(self.request(self.path + "/billing/portal", b"")[0], 409)
        self.assertEqual(self.event()[0], 200)
        state = self.request(self.path + "/billing")[1]
        self.assertTrue(state["abonne"])
        self.assertNotIn("customer", state)
        self.assertEqual(billing.read(self.registry.get(self.org.id))["customer"], "cus_test")
        self.assertEqual(self.request(self.path + "/billing/portal", b"")[1], {"url": "https://billing.stripe.test/portal"})
        self.request(self.path + "/billing/checkout", b"")
        self.assertEqual(self.fake.requests[-1][1]["customer"], ["cus_test"])
        for status in ("past_due", "trialing", "active", "unpaid"):
            self.assertEqual(self.event("customer.subscription.updated", {"id": "sub_test", "status": status})[0], 200)
            self.assertEqual(self.request(self.path + "/billing")[1]["abonne"], status in {"active", "trialing"})
        self.assertEqual(self.event("customer.subscription.deleted", {"id": "sub_test"})[0], 200)
        self.assertFalse(self.request(self.path + "/billing")[1]["abonne"])

    def test_webhook_registre_en_memoire(self):
        (self.org.folder / "org.json").unlink()
        self.assertEqual(self.event()[0], 200)
        self.assertTrue(billing.read(self.org)["abonne"])
        self.assertEqual(self.event("customer.subscription.updated", {
            "id": "sub_autre", "customer": "cus_test", "status": "past_due"})[0], 200)
        self.assertFalse(billing.read(self.org)["abonne"])

    def test_signatures_et_corps(self):
        self.assertEqual(self.event(signature=f"t={int(time.time())},v1=bad")[0], 400)
        self.assertEqual(self.event(live=True)[0], 400)
        self.assertEqual(self.event(timestamp=int(time.time()) - 301)[0], 400)
        self.assertEqual(self.event(timestamp=int(time.time()) + 301)[0], 400)
        self.assertEqual(self.request("/stripe/webhook", b"{}")[0], 400)
        self.assertEqual(self.request("/stripe/webhook", b"x" * 262145)[0], 413)
        os.environ["STRIPE_WEBHOOK_SECRET"] = ""
        self.assertEqual(self.event()[0], 503)
        self.assertFalse(billing.read(self.org).get("abonne", False))

    def test_inconnus_et_erreur_stripe(self):
        for suffix in ("/abonnement", "/billing", "/billing/checkout", "/billing/portal"):
            self.assertEqual(self.request("/o/inconnu" + suffix, b"" if suffix.endswith(("checkout", "portal")) else None)[0], 404)
        self.assertEqual(self.event(obj={"client_reference_id": "inconnue"})[0], 200)
        self.assertEqual(self.event("inconnu", {})[0], 200)
        self.assertEqual(self.event("customer.subscription.created", {"id": "sub_new", "metadata": {"org": self.org.id}, "status": "trialing"})[0], 200)
        self.assertTrue(billing.read(self.org)["abonne"])
        self.fake.fail = True
        self.assertFalse(self.request(self.path + "/billing")[1]["disponible"])
        self.assertEqual(self.request(self.path + "/billing/checkout", b"")[0], 502)


if __name__ == "__main__":
    unittest.main(verbosity=2)
