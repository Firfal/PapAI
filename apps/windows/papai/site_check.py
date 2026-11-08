"""Classement des URL du navigateur selon les sites validés."""

import re
import json
import threading
import time
import unicodedata
from urllib.request import ProxyHandler, build_opener
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


class SiteMonitor:
    """Surveille un navigateur CDP local ; aucun branchement au pont Windows."""

    def __init__(self, port, sites, callback, hosts=()):
        if not isinstance(port, int) or not 1 <= port <= 65535:
            raise ValueError("Port de débogage non valide")
        self.endpoint = f"http://127.0.0.1:{port}/json/list"
        self.callback = callback
        self._lock = threading.Lock()
        self._sites, self._hosts = list(sites), list(hosts)
        self._stop = threading.Event()
        self._thread = None
        self._last_report = {}
        self._opener = build_opener(ProxyHandler({}))

    def update_sites(self, sites, hosts=()):
        with self._lock:
            self._sites, self._hosts = list(sites), list(hosts)

    def poll(self):
        with self._lock:
            if not self._sites:
                return
        try:
            with self._opener.open(self.endpoint, timeout=0.4) as response:
                pages = json.load(response)
        except (OSError, ValueError):
            return
        if not isinstance(pages, list) or self._stop.is_set():
            return
        current = {page["url"] for page in pages if isinstance(page, dict)
                   and page.get("type") == "page" and isinstance(page.get("url"), str)}
        self._last_report = {url: at for url, at in self._last_report.items() if url in current}
        for page in pages:
            if not isinstance(page, dict) or page.get("type") != "page":
                continue
            url = page.get("url")
            with self._lock:
                outside = self._sites and classify(url, self._sites, self._hosts) == "hors"
            if (isinstance(url, str) and outside
                    and time.monotonic() - self._last_report.get(url, float("-inf")) >= 2):
                self._last_report[url] = time.monotonic()
                self.callback(url)

    def start(self):
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop.clear()
        self._last_report = {}
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _run(self):
        while not self._stop.is_set():
            self.poll()
            self._stop.wait(0.5)

    def stop(self):
        self._stop.set()
        if self._thread is not None and self._thread is not threading.current_thread():
            self._thread.join(timeout=1)
