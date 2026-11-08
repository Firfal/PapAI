"""Rangement guidé des dossiers, côté serveur : contrôles sans clé H.

    python tests/test_rangement.py
"""

from __future__ import annotations

import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("HAI_API_KEY", "test")

from backend import rangement as r  # noqa: E402
from backend.sessions import Registry, State  # noqa: E402

ok = fails = 0


def check(label, cond, detail=""):
    global ok, fails
    if cond:
        ok += 1
        print(f"  OK      {label}")
    else:
        fails += 1
        print(f"  ECHEC   {label}  {detail}")


def refused(raw) -> bool:
    try:
        r.parse_request(raw)
    except r.TidyError:
        return True
    return False


FILES = ["facture_edf_mars.pdf", "Contrat location.pdf", "IMG_2041.HEIC", "GoogleChrome.dmg",
         "notes", "rapport.pdf", "budget.xlsx", "inconnu.xyz"]

# --- demande reçue de l'ordinateur
check("dossier Documents accepté", r.parse_request({"folder": "documents", "files": FILES})["folder"] == "documents")
check("dossier hors liste refusé", refused({"folder": "library", "files": []}))
check("chemin à la place du dossier refusé", refused({"folder": "/System", "files": []}))
check("plus de 200 fichiers refusés", refused({"folder": "desktop", "files": [f"f{i}.txt" for i in range(201)]}))
check("200 fichiers acceptés", not refused({"folder": "desktop", "files": [f"f{i}.txt" for i in range(200)]}))
for bad in ["../secret.txt", "sous/dossier.pdf", ".cache", "", "a\x00b", "..", "x\\y.pdf", " espace.pdf"]:
    check(f"nom refusé : {bad!r}", refused({"folder": "documents", "files": [bad]}))
check("doublon refusé", refused({"folder": "documents", "files": ["a.pdf", "a.pdf"]}))
check("files non liste refusé", refused({"folder": "documents", "files": "a.pdf"}))
check("demande non dict refusée", refused("documents"))
req = r.parse_request({"folder": "documents", "files": ["a.pdf"], "folders": ["Factures", "../x", ".Trash"]})
check("dossiers existants filtrés", req["folders"] == ["Factures"], req["folders"])

# --- devinette sans Holo
guess = r.fallback(FILES)
check("facture reconnue", guess.get("facture_edf_mars.pdf") == "Factures", guess)
check("contrat reconnu", guess.get("Contrat location.pdf") == "Contrats", guess)
check("photo reconnue", guess.get("IMG_2041.HEIC") == "Images", guess)
check("installateur reconnu", guess.get("GoogleChrome.dmg") == "Installateurs", guess)
check("tableur reconnu", guess.get("budget.xlsx") == "Tableaux", guess)
check("fichier sans indice laissé en place", "inconnu.xyz" not in guess and "notes" not in guess, guess)

# --- propositions de Holo filtrées
moves = r.build_moves(["a.pdf", "b.pdf", "c.pdf", "d.pdf"], {
    "a.pdf": "Factures", "b.pdf": "../Library", "c.pdf": "/tmp", "d.pdf": ".cache", "zz.pdf": "Factures"})
check("seuls les dossiers au nom simple passent", moves == [{"from": "a.pdf", "to": "Factures"}], moves)
many = {f"f{i}.txt": f"Dossier {i}" for i in range(20)}
moves = r.build_moves(list(many), many)
check("12 dossiers au plus", len({m["to"] for m in moves}) == r.MAX_CATEGORIES, len(moves))
check("plan : une étape par déplacement",
      r.plan_steps([{"from": "a.pdf", "to": "Factures"}], "downloads") == ["Déplacer « a.pdf » dans Téléchargements/Factures"])


# --- cycle complet : plan, validation, exécution
class FakeLink:
    def __init__(self, reply):
        self.sent = []
        self.reply = reply

    async def _request(self, payload, timeout=20.0):
        self.sent.append(payload)
        return self.reply


async def no_alert(session, text, source):
    return False


def run_cycle(decisions, reply=None, ask=None, files=FILES, alert=None):
    async def go():
        s = Registry().create("range mes documents")
        s.grant_consent()
        link = FakeLink(reply if reply is not None else {"moved": 5, "renamed": 1, "skipped": 0})
        seen, holo = [], []

        async def broadcast(m):
            seen.append(m)

        async def fake_ask(session, names, folders, note):
            holo.append({"names": list(names), "note": note})
            return {"facture_edf_mars.pdf": "Factures"} if note else None

        task = asyncio.create_task(r.run(s, link, broadcast, alert or no_alert,
                                         {"folder": "documents", "files": files}, ask=ask or fake_ask))
        for d in decisions:
            for _ in range(200):
                await asyncio.sleep(0)
                if s.state is State.AWAITING_APPROVAL:
                    break
            s.decide_plan(*d)
        await asyncio.wait_for(task, 2)
        return s, link, seen, holo
    return asyncio.run(go())


s, link, seen, holo = run_cycle([("approve", "")])
check("plan proposé à la validation avant toute action", any(e["kind"] == "plan_proposed" for e in s.journal))
check("plan : chaque déplacement listé", len(s.plan) == 6 and all(p.startswith("Déplacer « ") for p in s.plan), s.plan)
check("Holo ne reçoit que des noms", holo[0]["names"] == FILES)
check("après validation, un seul ordre tidy_execute", [m["type"] for m in link.sent] == ["tidy_execute"], link.sent)
check("ordre : déplacements seulement", all(set(m) == {"from", "to"} for m in link.sent[0]["moves"]))
check("assistance terminée", s.state is State.DONE, s.state)
answer = [m["content"] for m in seen if m.get("type") == "answer"]
check("message de fin : rien supprimé, annulation possible",
      answer and "Rien n'a été supprimé" in answer[0] and "Annuler le rangement" in answer[0], answer)

s, link, seen, holo = run_cycle([("refuse", "")])
check("plan refusé : rien n'est envoyé", link.sent == [] and s.state is State.STOPPED, (link.sent, s.state))

s, link, seen, holo = run_cycle([("refine", "factures seulement"), ("approve", "")])
check("précision transmise à Holo", holo[-1]["note"] == "factures seulement", holo)
check("nouveau plan après précision", s.plan == ["Déplacer « facture_edf_mars.pdf » dans Documents/Factures"], s.plan)
check("exécution du plan précisé", link.sent[0]["moves"] == [{"from": "facture_edf_mars.pdf", "to": "Factures"}])

s, link, seen, holo = run_cycle([("approve", "")], reply={"refused": True, "result": "Arrêt"})
check("refus de l'ordinateur : assistance arrêtée", s.state is State.STOPPED, s.state)

s, link, seen, holo = run_cycle([], files=["notes", "inconnu.xyz"])
check("rien à ranger : pas de plan, pas d'ordre", link.sent == [] and s.state is State.DONE and not s.plan)


async def alert(session, text, source):
    session.stop(by="gardien")
    return True

s, link, seen, holo = run_cycle([], alert=alert)
check("alerte du gardien : rien n'est envoyé", link.sent == [] and s.state is State.STOPPED)


async def broken(*a):
    raise RuntimeError("Holo indisponible")

s, link, seen, holo = run_cycle([("approve", "")], ask=broken)
check("Holo indisponible : plan d'après les extensions", len(s.plan) == 6 and link.sent, s.plan)


async def invalid():
    s = Registry().create("range")
    s.grant_consent()
    link = FakeLink({})

    async def b(m):
        pass
    await r.run(s, link, b, no_alert, {"folder": "/System", "files": []})
    return s, link

s, link = asyncio.run(invalid())
check("demande invalide : assistance close sans ordre", link.sent == [] and s.state is State.DONE)

print(f"\n{ok} contrôles passés, {fails} échec(s)")
sys.exit(1 if fails else 0)
