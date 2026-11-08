"""Classement des URL du navigateur selon les sites validés."""

import re
import unicodedata
from urllib.parse import urlsplit

_NEUTRAL = {"about:blank", "chrome://newtab/", "edge://newtab/",
            "chrome-error://chromewebdata/"}


def _host(value):
    value = value.lower().removesuffix(".")
    if not value or value.endswith("."):
        return None
    try:
        host = ".".join(
            ("xn--" + unicodedata.normalize("NFC", label).encode("punycode").decode("ascii"))
            if not label.isascii() else label
            for label in value.split(".")
        )
    except (UnicodeError, ValueError):
        return None
    if len(host) > 253 or any(
        not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
        for label in host.split(".")
    ):
        return None
    # Chrome interprète aussi les formes IPv4 abrégées, octales et hexadécimales.
    last = host.rsplit(".", 1)[-1]
    if re.fullmatch(r"[0-9]+|0x[0-9a-f]+", last):
        return None
    return host


def host_of(url):
    if not isinstance(url, str) or any(
        c.isspace() or unicodedata.category(c) in ("Cc", "Cf") or c == "\\" for c in url
    ):
        return None
    try:
        parsed = urlsplit(url)
        if (parsed.scheme.lower() != "https" or not parsed.netloc
                or parsed.username is not None or parsed.password is not None
                or parsed.port not in (None, 443)):
            return None
        authority = parsed.netloc
        if ":" in authority and authority.rsplit(":", 1)[1] != "443":
            return None
        return _host(parsed.hostname or "")
    except (ValueError, UnicodeError):
        return None


def classify(url, sites, hosts=()):
    if isinstance(url, str) and (url in _NEUTRAL or url.startswith("chrome-search://")):
        if not any(c.isspace() or unicodedata.category(c) in ("Cc", "Cf") or c == "\\" for c in url):
            return "neutre"
    host = host_of(url)
    if host is None:
        return "hors"
    if any(host == site or host.endswith("." + site)
           for raw in sites if isinstance(raw, str) for site in [_host(raw)] if site):
        return "ok"
    if any(host == _host(raw) for raw in hosts if isinstance(raw, str)):
        return "ok"
    return "hors"
