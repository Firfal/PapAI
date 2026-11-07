"""Organisation IT : jeton d'inscription des postes, jeton support, automatismes partagés.

Serveur temporaire en mode en ligne (PAPAI_PUBLIC=1). Le service IT crée son
organisation, deux postes s'inscrivent avec le jeton, un troisième rejoint après
coup ; le support liste tous les postes sans appairage et importe un automatisme
une fois pour tous.

    python tests/test_organisation.py
"""
from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

import websockets

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_appairage_code as base_test  # noqa: E402

check, http = base_test.check, base_test.http
RACINE = base_test.RACINE


def lire(url: str):
    return http(url)


async def parcours(base: str) -> None:
    wsb = base.replace("http://", "ws://")
    st, o = http(f"{base}/orgs", {"name": "Acme"})
    check("le service IT crée son organisation et reçoit deux jetons",
          st == 200 and o["enroll_token"] != o["support_token"] and o["support_url"].endswith(o["support_token"]))
    st, _ = http(f"{base}/orgs", {})
    check("une organisation sans nom est refusée", st == 400)

    st, a = http(f"{base}/spaces", {"org": o["enroll_token"], "name": "Poste compta"})
    st2, b = http(f"{base}/spaces", {"org": o["enroll_token"], "name": "Poste accueil"})
    check("un poste s'inscrit avec le jeton d'inscription", st == 200 and st2 == 200 and a.get("org") == "Acme")
    st, _ = http(f"{base}/spaces", {"org": "ins-faux"})
    check("jeton d'inscription inconnu : refusé", st == 403)
    st, seul = http(f"{base}/spaces", {})
    check("un ordinateur seul reste possible", st == 200 and "org" not in seul)

    st, lst = lire(f"{base}/o/{o['support_token']}/spaces")
    keys = {s["key"] for s in lst.get("spaces", [])} if st == 200 else set()
    check("le jeton support liste tous les postes, pas les autres", keys == {a["key"], b["key"]})
    check("chaque poste a son nom d'inscription", {s["name"] for s in lst["spaces"]} == {"Poste compta", "Poste accueil"})
    st, _ = lire(f"{base}/o/{o['enroll_token']}/spaces")
    check("le jeton d'inscription ne liste pas les postes", st == 404)
    st, page = lire(f"{base}/o/{o['support_token']}")
    check("page de l'organisation servie", st == 200 and "<html" in str(page).lower())

    pack = json.loads((RACINE / "automations" / "google-moteur-de-recherche.papai").read_text("utf-8"))
    async with websockets.connect(a["bridge_url"]) as wa:
        st, les = http(f"{base}/o/{o['support_token']}/automations", pack)
        check("automatisme importé pour l'organisation", st == 200 and les["id"].startswith("imp-"))
        vu = []
        try:
            while True:
                vu.append(json.loads(await asyncio.wait_for(wa.recv(), 2)))
        except asyncio.TimeoutError:
            pass
        check("le poste connecté est prévenu", any(m.get("type") == "lessons_changed" for m in vu))
    ids = lambda k: {x.get("id") for x in lire(f"{base}/k/{k}/lessons")[1]}  # noqa: E731
    check("l'automatisme arrive sur chaque poste", les["id"] in ids(a["key"]) and les["id"] in ids(b["key"]))
    check("mais pas sur un ordinateur hors organisation", les["id"] not in ids(seul["key"]))

    st, c = http(f"{base}/spaces", {"org": o["enroll_token"], "name": "Nouveau poste"})
    check("un poste inscrit plus tard reçoit le catalogue", les["id"] in ids(c["key"]))

    st, r = http(f"{base}/k/{seul['key']}/org", {"org": o["enroll_token"], "name": "Poste rejoint"})
    check("un poste déjà installé rejoint l'organisation", st == 200 and r.get("org") == "Acme"
          and les["id"] in ids(seul["key"]))
    st, o2 = http(f"{base}/orgs", {"name": "Autre"})
    st, _ = http(f"{base}/k/{seul['key']}/org", {"org": o2["enroll_token"]})
    check("un poste ne change pas d'organisation en douce", st == 409)
    codes = [http(f"{base}/spaces", {"org": o2["enroll_token"]})[0] for _ in range(6)]
    check("inscriptions plafonnées par organisation", codes[:5] == [200] * 5 and codes[5] == 429)
    st, _ = http(f"{base}/k/{base_test.CLE}/org", {"org": o["enroll_token"]})
    check("l'espace historique reste seul", st == 409)

    req = __import__("urllib.request").request.Request(
        f"{base}/o/{o['support_token']}/automations/{les['id']}", method="DELETE")
    with __import__("urllib.request").request.urlopen(req, timeout=10) as resp:
        ok = resp.status == 200
    check("retiré pour l'organisation : retiré de chaque poste",
          ok and all(les["id"] not in ids(k) for k in (a["key"], b["key"], c["key"], seul["key"])))
    st, lst = lire(f"{base}/o/{o['support_token']}/automations")
    check("catalogue de l'organisation vide", st == 200 and lst == [])


if __name__ == "__main__":
    __import__("os").environ["PAPAI_ORG_ENROLLS_PER_HOUR"] = "5"
    base_test.parcours = parcours
    base_test.main()
