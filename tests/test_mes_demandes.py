"""Vue utilisateur : isolation des postes, solutions texte et autorisations."""
import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import test_appairage_code as base_test
from backend.tickets import Tickets, for_user

check, http = base_test.check, base_test.http
FIELDS = {"id", "number", "created", "updated", "task", "status", "solution", "relaunch", "decision"}


def projections():
    lesson = {"id": "auto", "title": "Titre courant", "image": "capture.png"}
    t = {"id": "t", "task": "Imprimer", "status": "resolu", "automation": "auto",
         "suggestion_lancee": "autre", "notes": ["interne"], "tokens": 123,
         "end": "done", "plan": ["Ouvrir", {"image": "capture.png"}],
         "linkup_answer": {"content": "Réponse", "query": "secret", "by": "IT",
                           "sources": [{"title": "Source", "url": "https://example.org", "image": "x"}]}}
    r = for_user(t, [lesson])
    check("automate prioritaire et titre courant", r["solution"] == {
        "kind": "automate", "lesson": "auto", "title": "Titre courant"} and r["relaunch"] == "auto")
    check("automate retiré : pas de relance", for_user(t, [])["relaunch"] is None)
    check("non résolu : pas de relance", for_user({**t, "status": "en_attente"}, [lesson])["relaunch"] is None)
    attente = for_user({"id": "s", "task": "Imprimer", "status": "en_attente", "suggestion_lancee": "auto"}, [lesson])
    check("automate suggéré lancé, demande en attente : pas présenté comme solution",
          attente["solution"] is None and attente["relaunch"] is None)
    echec = for_user({"status": "a_reprendre", "automation": "auto"}, [lesson])
    check("automate interrompu : pas présenté comme solution", echec["solution"] is None and echec["relaunch"] is None)
    del t["automation"], t["suggestion_lancee"]
    r = for_user(t, [])
    check("réponse validée prioritaire sur plan, sources filtrées", r["solution"] == {
        "kind": "answer", "text": "Réponse", "sources": [{"title": "Source", "url": "https://example.org"}]})
    del t["linkup_answer"]
    check("plan exécuté texte uniquement", for_user(t, [])["solution"] == {"kind": "plan", "steps": ["Ouvrir"]})
    check("plan non exécuté masqué", for_user({**t, "end": "stopped"}, [])["solution"] is None)
    check("ticket vide et plan vide", for_user({}, [])["solution"] is None
          and for_user({"end": "done", "plan": []}, [])["solution"] is None)
    check("valeurs imbriquées rejetées", for_user({"task": {"image": "x"}, "created": {"token": "x"}}, [])["task"] == "")


async def parcours(base):
    _, org = http(f"{base}/orgs", {"name": "Acme"})
    postes = [http(f"{base}/spaces", {"org": org["enroll_token"], "name": name})[1]
              for name in ("Alpha", "Beta")]
    _, automate = http(f"{base}/o/{org['support_token']}/automations", {
        "papai": 1, "title": "Imprimer", "publisher": "IT", "platforms": ["windows"],
        "actions": [{"do": "open_settings", "page": "printers"}]})
    _, empty = http(f"{base}/spaces", {})
    check("poste sans demande", http(f"{base}/k/{empty['key']}/requests") == (200, {"requests": []}))
    ids = []
    for index, poste in enumerate(postes):
        manifest = next(p for p in (base_test.TEST_DATA_DIR / "spaces").glob("*/space.json")
                        if json.loads(p.read_text())["key"] == poste["key"])
        store = Tickets(manifest.parent / "tickets.json")
        own_ids = []
        for n in range(105):
            t = store.open(f"Texte privé {index} demande {n}", "personne")
            store.update(t, created=n, notes=[{"text": "note secrète"}], tokens=900,
                         assignee="IT", screenshot="capture.png", linkup_query="secret")
            if n == 104:
                store.update(t, automation=automate["id"], status="resolu")
            elif n == 103:
                store.update(t, end="done", plan=["Ouvrir les réglages", {"image": "capture.png"}])
            elif n == 102:
                store.update(t, linkup_answer={"content": "Réponse validée", "query": "interne",
                             "sources": [{"title": "Source", "url": "https://example.org", "image": "capture.png"}]})
            own_ids.append(t["id"])
        ids.append(own_ids)
    for index, poste in enumerate(postes):
        st, data = http(f"{base}/k/{poste['key']}/requests")
        rows = data["requests"]
        check(f"poste {index} : 100 plus récentes", st == 200 and [r["id"] for r in rows] == ids[index][::-1][:100])
        check(f"poste {index} : aucun id ni texte de l'autre", not set(ids[1-index]) & {r["id"] for r in rows}
              and f"Texte privé {1-index}" not in json.dumps(data, ensure_ascii=False))
        check(f"poste {index} : automate existant relançable", rows[0]["relaunch"] == automate["id"]
              and rows[0]["solution"] == {"kind": "automate", "lesson": automate["id"], "title": "Imprimer"})
        check(f"poste {index} : plan exécuté", rows[1]["solution"] == {"kind": "plan", "steps": ["Ouvrir les réglages"]})
        check(f"poste {index} : réponse validée", rows[2]["solution"] == {"kind": "answer", "text": "Réponse validée",
              "sources": [{"title": "Source", "url": "https://example.org"}]})
        check(f"poste {index} : liste blanche sans capture ni secrets", all(set(r) == FIELDS for r in rows)
              and not any(word in json.dumps(data).lower() for word in
                          ("image", "png", "jpg", "data:", "screenshot", "note secr", "token", "linkup_query")))
    check("clé inconnue refusée", http(f"{base}/k/inconnue/requests") == (404, {"error": "Lien invalide."}))
    _, support = http(f"{base}/o/{org['support_token']}/supports", {"name": "Alice"})
    _, spaces = http(f"{base}/o/{support['token']}/spaces")
    derived = spaces["spaces"][0]["key"]
    check("clé dérivée refusée", derived not in [p["key"] for p in postes]
          and http(f"{base}/k/{derived}/requests") == (404, {"error": "Lien invalide."}))
    req = urllib.request.Request(f"{base}/o/{org['support_token']}/automations/{automate['id']}", method="DELETE")
    with urllib.request.urlopen(req) as response:
        check("retrait de l'automate", response.status == 200)
    _, data = http(f"{base}/k/{postes[0]['key']}/requests")
    check("automate retiré : solution conservée sans relance", data["requests"][0]["relaunch"] is None
          and data["requests"][0]["solution"]["lesson"] == automate["id"])


if __name__ == "__main__":
    projections()
    base_test.parcours = parcours
    base_test.main()
