"""Abonnement entreprise Stripe, exclusivement en mode test.

GET /o/{token}/abonnement sert la page ; GET /o/{token}/billing donne
disponibilité, prix et état. POST .../billing/checkout et .../billing/portal
renvoient une URL Stripe. POST /stripe/webhook reçoit les événements signés.
Les identifiants Stripe restent dans billing.json, séparé de l'organisation.
"""
from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import os
import tempfile
import time
from pathlib import Path
from urllib.parse import quote, urlencode
from urllib.request import Request as URLRequest, urlopen

from fastapi import HTTPException, Request
from fastapi.responses import FileResponse

from . import orgs


def config():
    key = os.environ.get("STRIPE_SECRET_KEY", "")
    price = os.environ.get("STRIPE_PRICE_ID", "")
    return key if key.startswith(("sk_test_", "rk_test_")) else "", price


def read(org):
    try:
        value = json.loads((org.folder / "billing.json").read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def write(org, value):
    org.folder.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=org.folder, prefix=".billing-")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(value, f)
        os.replace(name, org.folder / "billing.json")
    finally:
        if os.path.exists(name):
            os.unlink(name)


def stripe(path, data=None):
    key, price = config()
    if not key or not price:
        raise HTTPException(503, "Abonnement bientôt disponible")
    req = URLRequest(os.environ.get("STRIPE_API_BASE", "https://api.stripe.com").rstrip("/") + path,
                     data=None if data is None else urlencode(data).encode(),
                     headers={"Authorization": "Bearer " + key,
                              "Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urlopen(req, timeout=10) as response:
            result = json.load(response)
        if not isinstance(result, dict):
            raise ValueError()
        return result
    except Exception:
        raise HTTPException(502, "Service d'abonnement temporairement indisponible") from None


def install(app, find_org, members, public_url):
    prices = {}

    def get_org(token):
        org = find_org(token)
        if org is None:
            raise HTTPException(404, "Lien invalide.")
        return org

    @app.get("/o/{token}/abonnement")
    async def page(token: str):
        get_org(token)
        return FileResponse(Path(__file__).parent / "static" / "abonnement.html")

    @app.get("/o/{token}/billing")
    async def billing(token: str):
        org = get_org(token)
        state = read(org)
        key, price = config()
        result = {"disponible": False, "postes": len(members(org)),
                  "abonne": bool(state.get("abonne")), "statut": state.get("statut", "inactif")}
        if key and price:
            cache_key = (key, price, os.environ.get("STRIPE_API_BASE", ""))
            try:
                cached = prices.get(cache_key)
                if not cached or cached[0] < time.monotonic():
                    p = await asyncio.to_thread(stripe, "/v1/prices/" + quote(price, safe=""))
                    amount, currency, interval = p["unit_amount"], p["currency"], p["recurring"]["interval"]
                    if not isinstance(amount, int) or amount < 0 or interval != "month":
                        raise ValueError()
                    cached = (time.monotonic() + 60, {"unit_amount": amount, "currency": currency, "interval": interval})
                    prices[cache_key] = cached
                result.update(disponible=True, prix=cached[1])
            except (HTTPException, KeyError, TypeError, ValueError):
                pass
        return result

    @app.post("/o/{token}/billing/checkout")
    async def checkout(token: str):
        org = get_org(token)
        _, price = config()
        back = public_url.rstrip("/") + "/o/" + quote(token, safe="") + "/abonnement"
        data = {"mode": "subscription", "line_items[0][price]": price,
                "line_items[0][quantity]": max(1, len(members(org))),
                "client_reference_id": org.id, "metadata[org]": org.id,
                "subscription_data[metadata][org]": org.id,
                "success_url": back, "cancel_url": back}
        if read(org).get("customer"):
            data["customer"] = read(org)["customer"]
        response = await asyncio.to_thread(stripe, "/v1/checkout/sessions", data)
        if not isinstance(response.get("url"), str):
            raise HTTPException(502, "Réponse d'abonnement invalide")
        return {"url": response["url"]}

    @app.post("/o/{token}/billing/portal")
    async def portal(token: str):
        org = get_org(token)
        customer = read(org).get("customer")
        if not customer:
            raise HTTPException(409, "Aucun abonnement à gérer")
        response = await asyncio.to_thread(stripe, "/v1/billing_portal/sessions", {
            "customer": customer, "return_url": public_url.rstrip("/") + "/o/" + quote(token, safe="") + "/abonnement"})
        if not isinstance(response.get("url"), str):
            raise HTTPException(502, "Réponse d'abonnement invalide")
        return {"url": response["url"]}

    @app.post("/stripe/webhook")
    async def webhook(request: Request):
        secret = os.environ.get("STRIPE_WEBHOOK_SECRET", "")
        if not secret:
            raise HTTPException(503, "Webhook indisponible")
        raw = bytearray()
        async for chunk in request.stream():
            raw.extend(chunk)
            if len(raw) > 262144:
                raise HTTPException(413, "Événement trop volumineux")
        try:
            parts = [p.strip().split("=", 1) for p in request.headers.get("Stripe-Signature", "").split(",")]
            timestamp = next(v for k, v in parts if k == "t")
            expected = hmac.new(secret.encode(), timestamp.encode() + b"." + raw, hashlib.sha256).hexdigest()
            if abs(time.time() - int(timestamp)) > 300 or not any(
                    k == "v1" and hmac.compare_digest(v, expected) for k, v in parts):
                raise ValueError()
            event = json.loads(raw)
            obj = event["data"]["object"]
            kind = event["type"]
            if not isinstance(obj, dict) or not isinstance(kind, str):
                raise ValueError()
        except (ValueError, TypeError, KeyError, StopIteration):
            raise HTTPException(400, "Signature ou événement invalide") from None
        if event.get("livemode"):
            raise HTTPException(400, "Seul le mode test est accepté")
        if kind not in {"checkout.session.completed", "customer.subscription.created",
                        "customer.subscription.updated", "customer.subscription.deleted"}:
            return {"ok": True}
        registry = orgs.Orgs()
        metadata = obj.get("metadata") or {}
        oid = obj.get("client_reference_id") if kind == "checkout.session.completed" else None
        oid = oid or (metadata.get("org") if isinstance(metadata, dict) else None)
        org = registry.get(oid) if isinstance(oid, str) else None
        if org is None and not oid:
            for candidate in registry._by_id.values():
                state = read(candidate)
                if (obj.get("id") and obj["id"] == state.get("subscription")) or (
                        obj.get("customer") and obj["customer"] == state.get("customer")):
                    org = candidate
                    break
        if org:
            state = read(org)
            if obj.get("customer"):
                state["customer"] = obj["customer"]
            if kind == "checkout.session.completed":
                state.update(subscription=obj.get("subscription"), abonne=True, statut="active")
            else:
                status = "canceled" if kind.endswith(".deleted") else obj.get("status", "inactif")
                state.update(subscription=obj.get("id"), statut=status, abonne=status in {"active", "trialing"})
            write(org, state)
        return {"ok": True}
