"""Le gardien sur l'ordinateur : il compare lui-même et ne renvoie au serveur que
ce qui correspond aux règles reçues (`guard_rules`, PROTOCOL.md). Sans règles,
rien ne part. Le serveur décide de l'alerte (`backend/guard.py`).
"""
from __future__ import annotations

import re


def host_of(url: str) -> str:
    u = re.sub(r"^[a-z][a-z0-9+.-]*://", "", str(url or "").strip().lower())
    u = re.split(r"[/?#]", u, maxsplit=1)[0].rsplit("@", 1)[-1]
    if u.startswith("["):
        return u[1:].split("]", 1)[0]
    return u.split(":", 1)[0].strip(".") if u.count(":") <= 1 else u


def distance(a: str, b: str) -> int:
    if abs(len(a) - len(b)) > 2:
        return 3
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def site_to_report(url: str, rules: dict) -> bool:
    """Vrai si le site mérite l'avis du serveur : adresse IP, caractères trompeurs,
    ou nom proche d'une marque ou de l'entreprise hors de leurs vrais domaines."""
    h = host_of(url)
    if not h:
        return False
    if ":" in h or re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}", h) or "xn--" in h or not h.isascii():
        return True
    if any(h == d or h.endswith("." + d) for d in rules.get("official") or []):
        return False
    parts = [p for p in re.split(r"[.-]", h) if p]
    return any(k in p or (len(k) >= 5 and distance(p, k) <= 2)
               for k in rules.get("keywords") or [] for p in parts)


def signals(names: list[str], title: str, url: str, rules: dict | None) -> dict | None:
    """Le message `guard` réduit à ce qui correspond, ou None si rien ne correspond."""
    if not rules:
        return None
    tools = [t for t in rules.get("tools") or [] if isinstance(t, str)]
    procs = [n for n in names if any(t in n.lower() for t in tools)]
    window = title if any(re.search(p, (title or "").lower()) for p in rules.get("titles") or []) else ""
    site = ""
    if url and site_to_report(url, rules):
        site = "https://" + host_of(url)
    if not (procs or window or site):
        return None
    return {"type": "guard", "processes": procs, "window": window, "url": site}
