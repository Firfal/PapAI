"""Tickets : chaque demande d'assistance laisse une trace pour le support.

Serveur temporaire en mode en ligne. Sans support connecté, la demande attend
(ticket « en attente ») ; dès qu'un support se connecte, elle est reproposée à
la personne aidée ; elle peut fixer un rendez-vous et elle est rappelée à
l'heure dite ; le support prend le ticket, la session s'y rattache ; le service
IT voit les tickets de tous ses postes.

    python tests/test_tickets.py
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import tempfile
import time
from pathlib import Path

import websockets

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import test_appairage_code as base_test  # noqa: E402
from backend.tickets import Tickets  # noqa: E402

check, http = base_test.check, base_test.http


async def drain(w, t=1.0) -> list:
    out = []
    try:
        while True:
            out.append(json.loads(await asyncio.wait_for(w.recv(), t)))
    except asyncio.TimeoutError:
        return out


async def attendre(w, kind: str, t=6.0) -> dict | None:
    fin = time.time() + t
    while time.time() < fin:
        try:
            m = json.loads(await asyncio.wait_for(w.recv(), max(0.1, fin - time.time())))
        except asyncio.TimeoutError:
            return None
        if m.get("type") == kind:
            return m
    return None


def tickets(base: str, key: str) -> list:
    st, r = http(f"{base}/k/{key}/tickets")
    return r.get("tickets", []) if st == 200 else []


def stockage() -> None:
    p = Path(tempfile.mkdtemp()) / "tickets.json"
    t = Tickets(p).open("Imprimer", "personne", status="en_attente")
    relu = Tickets(p).get(t["id"])
    check("un ticket survit au redémarrage du serveur", relu is not None and relu["number"] == 1)
    check("numéros qui se suivent", Tickets(p).open("Wi-Fi", "personne")["number"] == 2)
    seq = iter(range(41, 50))
    Tickets(p).renumber(lambda: next(seq))
    check("le poste rejoint une organisation : ses tickets sont renumérotés",
          sorted(t["number"] for t in Tickets(p).all()) == [41, 42])


async def parcours(base: str) -> None:
    wsb = base.replace("http://", "ws://")
    st, o = http(f"{base}/orgs", {"name": "Acme"})
    st, a = http(f"{base}/spaces", {"org": o["enroll_token"], "name": "Poste compta"})
    key = a["key"]
    async with websockets.connect(a["bridge_url"]) as wa:
        await wa.send(json.dumps({"type": "hello", "os": "windows"}))
        await drain(wa, 0.5)

        await wa.send(json.dumps({"type": "help_request", "task": "Imprimer un document"}))
        q = await attendre(wa, "ticket_queued")
        check("aucun support connecté : la demande attend, avec un numéro",
              q is not None and q["number"] == 1 and q["task"] == "Imprimer un document")
        lst = tickets(base, key)
        check("le ticket est enregistré « en attente »",
              len(lst) == 1 and lst[0]["status"] == "en_attente" and lst[0]["source"] == "personne")
        tid = lst[0]["id"]

        async with websockets.connect(f"{wsb}/k/{key}/ws/aidant/{key}") as ha:
            hello = json.loads(await asyncio.wait_for(ha.recv(), 5))
            check("le support voit qu'une demande attend", hello.get("tickets_waiting") == 1)
            r = await attendre(wa, "remote_request")
            check("un support arrive : la demande est reproposée à la personne",
                  r is not None and r.get("ticket") == tid and r.get("task") == "Imprimer un document")

            await wa.send(json.dumps({"type": "remote_answer", "accepted": False, "ticket": tid}))
            await asyncio.sleep(0.3)
            t = tickets(base, key)[0]
            check("pas disponible : le ticket reste en attente, avec une note",
                  t["status"] == "en_attente" and t["notes"])

            await wa.send(json.dumps({"type": "ticket_schedule", "ticket": tid, "at": time.time() - 10}))
            check("rendez-vous dans le passé : refusé", (await attendre(wa, "ticket_refused")) is not None)
            await wa.send(json.dumps({"type": "ticket_schedule", "ticket": tid, "at": time.time() + 2.5}))
            s = await attendre(wa, "ticket_scheduled")
            check("la personne fixe un rendez-vous", s is not None and tickets(base, key)[0]["status"] == "rdv")
            r = await attendre(wa, "remote_request", 8)
            check("à l'heure du rendez-vous, la personne est rappelée", r is not None and r.get("rdv") is True)
            due = await attendre(ha, "ticket_due", 2)
            check("et le support aussi", due is not None and due.get("number") == 1)
            await wa.send(json.dumps({"type": "remote_answer", "accepted": False, "ticket": tid}))
            await asyncio.sleep(0.3)

            st, r = http(f"{base}/k/{key}/tickets/{tid}", {"action": "note", "by": "Claire", "text": "Pilote à vérifier"})
            check("le support ajoute une note", st == 200 and r["ticket"]["notes"][-1]["by"] == "Claire")
            st, r = http(f"{base}/k/{key}/tickets/{tid}", {"action": "take", "by": "Claire"})
            p = await attendre(wa, "remote_request")
            check("le support prend le ticket : la personne reçoit sa proposition",
                  st == 200 and p is not None and p["from"] == "Claire" and p["ticket"] == tid)
            await wa.send(json.dumps({"type": "help_request", "task": p["task"], "requested_by": "Claire", "ticket": tid}))
            sess = await attendre(wa, "session")
            t = tickets(base, key)[0]
            check("la session se rattache au ticket, sans en ouvrir un autre",
                  sess is not None and sess.get("ticket") == tid and len(tickets(base, key)) == 1
                  and t["session"] == sess["id"] and t["status"] == "en_cours" and t["assignee"] == "Claire")
            st, _ = http(f"{base}/k/{key}/tickets/{tid}", {"action": "close", "by": "Claire"})
            check("pas de clôture pendant la session", st == 409)

            await wa.send(json.dumps({"type": "stop"}))
            await asyncio.sleep(0.8)
            t = tickets(base, key)[0]
            check("session arrêtée : le ticket est « à reprendre »", t["status"] == "a_reprendre")
            st, r = http(f"{base}/k/{key}/tickets/{tid}", {"action": "close", "by": "Claire", "text": "Réglé par téléphone"})
            check("le support clôt le ticket", st == 200 and r["ticket"]["status"] == "resolu"
                  and r["ticket"]["closed_by"] == "Claire")

            await wa.send(json.dumps({"type": "help_request", "task": "Le Wi-Fi ne marche plus"}))
            sess = await attendre(wa, "session")
            lst = tickets(base, key)
            check("support connecté : la session démarre tout de suite, avec son ticket",
                  sess is not None and len(lst) == 2 and lst[0]["number"] == 2 and lst[0]["status"] == "en_cours")
            await wa.send(json.dumps({"type": "stop"}))
            await asyncio.sleep(0.3)

        st, r = http(f"{base}/o/{o['support_token']}/tickets")
        st2, b = http(f"{base}/spaces", {"org": o["enroll_token"], "name": "Poste accueil"})
        async with websockets.connect(b["bridge_url"]) as wb2:
            await wb2.send(json.dumps({"type": "hello", "os": "windows"}))
            await drain(wb2, 0.3)
            await wb2.send(json.dumps({"type": "help_request", "task": "Écran noir"}))
            q2 = await attendre(wb2, "ticket_queued")
        check("numéro unique dans toute l'organisation", q2 is not None and q2["number"] == 3)
        st, r = http(f"{base}/o/{o['support_token']}/tickets")
        r["tickets"] = [x for x in r.get("tickets", []) if x["space"] == key]
        check("le service IT voit les tickets de ses postes",
              st == 200 and len(r["tickets"]) == 2 and all(x["poste"] == "Poste compta" for x in r["tickets"]))
        st, r = http(f"{base}/o/{o['support_token']}/tickets/{key}/{tid}", {"action": "reopen", "by": "IT"})
        check("le service IT rouvre un ticket", st == 200 and r["ticket"]["status"] == "en_attente")
        st, _ = http(f"{base}/o/{o['enroll_token']}/tickets")
        check("le jeton d'inscription ne voit pas les tickets", st == 404)

    st, seul = http(f"{base}/spaces", {})
    st, _ = http(f"{base}/o/{o['support_token']}/tickets/{seul['key']}/{tid}", {"action": "close"})
    check("pas de ticket d'un poste hors organisation", st == 404)
    async with websockets.connect(seul["bridge_url"]) as wb:
        await wb.send(json.dumps({"type": "hello", "os": "windows"}))
        await drain(wb, 0.5)
        await wb.send(json.dumps({"type": "help_request", "task": "Ranger le bureau"}))
        sess = await attendre(wb, "session")
        check("ordinateur sans aucun support : la session démarre comme avant", sess is not None and sess.get("ticket"))
        await wb.send(json.dumps({"type": "stop"}))


if __name__ == "__main__":
    os.environ["PAPAI_RDV_TICK_S"] = "0.5"
    os.environ["PAPAI_RDV_MIN_S"] = "1"
    stockage()
    base_test.parcours = parcours
    base_test.main()
