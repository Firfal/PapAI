"""Recherche documentaire : données sourcées, jamais transmises à Holo."""

from __future__ import annotations

import html
import os
import re
from urllib.parse import urlsplit

import httpx

TIMEOUT_S = 12.0


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
    base = os.environ.get("LINKUP_BASE_URL", "https://api.linkup.so").rstrip("/")
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT_S, follow_redirects=False) as client:
            response = await client.post(f"{base}/v1/search", headers={"Authorization": f"Bearer {key}"},
                                         json={"q": query, "depth": "standard", "outputType": "sourcedAnswer"})
            response.raise_for_status()
            data = response.json()
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
