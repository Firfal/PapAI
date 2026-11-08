"""Recherche documentaire : données sourcées, jamais transmises à Holo."""

from __future__ import annotations

import html
import os
import re
from urllib.parse import urlsplit

import httpx

TIMEOUT_S = 12.0

# Refus avant tout envoi : mail, longue suite de chiffres (téléphone, carte, IBAN), adresse postale.
# Les noms ne se repèrent pas de façon fiable : la consigne de Holo et la carte du support les interdisent.
_NUM = r"\b\d{1,4}\s*(?i:bis|ter)?\s*,?\s*"
# Types de voie sans autre sens courant : le numéro suffit.
_VOIE = (r"(?i:rue|avenue|av|boulevard|bd|blvd|chemin|allée|allee|impasse|quai|résidence|residence"
         r"|hameau|lieu-dit|faubourg|fbg|sentier|esplanade|parvis|rond-point|lotissement|route|rte)\b")
# Mots qui ont aussi un autre sens (« 3 cours gratuits ») : il faut un nom propre après.
_VOIE_AMBIGUE = (r"(?:(?i:passage|square|villa|cité|cite|voie|traverse|montée)"
                 r"\s+(?:(?i:de|du|des|la|le|les)\s+){0,2}(?:(?i:d|l)['’])?[A-ZÀ-Ý]"
                 r"|(?i:cours|place)\s+(?:(?i:(?:du|des|de\s+la)\s+|(?:de\s+l|d)['’]\s*)\w+|[A-ZÀ-Ý])"
                 r"|(?i:place\s+de)\s+[A-ZÀ-Ý])")
_PERSONAL = re.compile(
    r"(?i:\S+@\S+\.\S+|\bFR\d{2})"
    rf"|{_NUM}{_VOIE}|{_NUM}{_VOIE_AMBIGUE}")
_NUMBER = re.compile(r"(?<!\w)\d(?:[\s./-]?\d){5,}")
_LONG_NUMBER = re.compile(r"(?<!\d)\d(?:[\s./-]*\d){8,}")
_PHONE = re.compile(r"(?<!\w)(?:0[1-9](?:[\s./-]?\d){8}|(?:\+|00)33[\s./-]?[1-9](?:[\s./-]?\d){8})(?!\d)")
_VERSION = re.compile(
    r"(?<![\w.])\d+(?:\.\d+)+(?![\w.])"
    r"|\b(?i:version|windows|macos|ios|android|python|chrome|firefox|office|ubuntu|debian)\s+v?\d+(?:\.\d+)*\b")


def personal(query: str) -> bool:
    if _PERSONAL.search(query) or _PHONE.search(query) or _LONG_NUMBER.search(query):
        return True
    return bool(_NUMBER.search(_VERSION.sub(" ", query)))


def enabled() -> bool:
    return bool(os.environ.get("LINKUP_API_KEY", "").strip())


def plain(value, limit: int) -> str:
    if not isinstance(value, str):
        return ""
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]*>", "", value))).strip()[:limit]


def source_url(value) -> str:
    if not isinstance(value, str) or len(value) > 2048:
        return ""
    try:
        u = urlsplit(value)
        if u.scheme in ("http", "https") and u.hostname and not u.username and not u.password:
            return value
    except ValueError:
        pass
    return ""


async def search(query: str) -> dict:
    key = os.environ.get("LINKUP_API_KEY", "").strip()
    if not key:
        return {"error": "disabled"}
    query = plain(query, 1000)
    if not query:
        return {"error": "empty_query"}
    if personal(query):
        return {"error": "personal_data"}
    base = os.environ.get("LINKUP_BASE_URL", "https://api.linkup.so").rstrip("/")
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT_S, follow_redirects=False) as client:
            response = await client.post(f"{base}/v1/search", headers={"Authorization": f"Bearer {key}"},
                                         json={"q": query, "depth": "standard", "outputType": "sourcedAnswer"})
            response.raise_for_status()
            try:
                data = response.json()
            except ValueError:
                return {"error": "invalid_response"}
        if not isinstance(data, dict):
            return {"error": "invalid_response"}
        summary = plain(data.get("answer"), 8000)
        sources = []
        for item in (data.get("sources") or [])[:10]:
            if not isinstance(item, dict):
                continue
            url = source_url(item.get("url"))
            if url:
                sources.append({"name": plain(item.get("name"), 200), "url": url,
                                "excerpt": plain(item.get("snippet", item.get("description", "")), 1000)})
        if not summary or not sources:
            return {"error": "invalid_response"}
        return {"summary": summary, "sources": sources}
    except httpx.TimeoutException:
        return {"error": "timeout"}
    except (httpx.HTTPError, ValueError, TypeError, AttributeError):
        return {"error": "unavailable"}
