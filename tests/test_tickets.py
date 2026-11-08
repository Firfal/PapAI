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
from backend.tickets import Tickets, solution  # noqa: E402

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

    tk = Tickets(Path(tempfile.mkdtemp()) / "tickets.json")
    wifi = tk.open("Le Wi-Fi ne marche plus", "personne")
    check("même demande dite autrement : le ticket ouvert est retrouvé",
          tk.same("Wi-Fi coupé depuis ce matin") is wifi)
    check("demande différente : aucun ticket retrouvé", tk.same("Imprimer une photo") is None)
    dossier = tk.open("Je ne retrouve plus le dossier de la comptabilité", "personne")
    tk.update(dossier, status="resolu", end="done", plan=["Ouvrir Documents", "Ouvrir Comptabilité 2025"])
    check("demande déjà réglée : retrouvée, avec ses étapes",
          tk.same("Je n'arrive pas à retrouver le dossier comptabilité") is dossier
          and solution(dossier)["steps"] == ["Ouvrir Documents", "Ouvrir Comptabilité 2025"])
    tk.update(dossier, updated=int(time.time()) - 100 * 86400)
    dossier["updated"] = dossier["resolved"] = int(time.time()) - 100 * 86400
    check("réglée il y a plus de 90 jours : oubliée", tk.same("dossier de la comptabilité") is None)
    tk.note(wifi, "Claire", "Vérifier le pilote")
    wifi["notes"][-1]["t"] -= 60
    tk.update(wifi, status="resolu", closed_by="Claire")
    check("note de diagnostic avant la clôture : pas présentée comme la solution", solution(wifi)["note"] == "")
    auto = tk.open("Imprimer une photo", "automatisme")
    check("les tickets d'automates ne comptent pas", auto and tk.same("Imprimer une photo") is None)


async def parcours(base: str) -> None:
    wsb = base.replace("http://", "ws://")
    st, o = http(f"{base}/orgs", {"name": "Acme"})
    st, a = http(f"{base}/spaces", {"org": o["enroll_token"], "name": "Poste compta"})
    key = a["key"]
    st, automate = http(f"{base}/o/{o['support_token']}/automations", {
        "papai": 1, "title": "Imprimer un document", "description": "Configurer une imprimante",
        "publisher": "Service IT", "platforms": ["windows"],
        "actions": [{"do": "open_settings", "page": "printers"}],
    })
    check("le support importe un automate pour le poste",
          st == 200 and automate.get("id") and automate.get("title") == "Imprimer un document")
    async with websockets.connect(a["bridge_url"]) as wa:
        await wa.send(json.dumps({"type": "hello", "os": "windows"}))
        await drain(wa, 0.5)

        await wa.send(json.dumps({"type": "help_request", "task": "Imprimer un document"}))
        q = await attendre(wa, "ticket_queued")
        check("aucun support connecté : la demande attend, avec un numéro",
              q is not None and q["number"] == 1 and q["task"] == "Imprimer un document")
        proposed = [{"id": automate["id"], "title": automate["title"]}]
        check("ticket_queued propose l'automate correspondant",
              q is not None and q.get("suggestions") == proposed)
        lst = tickets(base, key)
        check("le ticket est enregistré « en attente »",
              len(lst) == 1 and lst[0]["status"] == "en_attente" and lst[0]["source"] == "personne")
        tid = lst[0]["id"]
        check("les suggestions sont gardées dans le ticket",
              lst[0].get("suggestions") == proposed and lst[0].get("suggestion_lancee") is None)

        await wa.send(json.dumps({"type": "ticket_automate_launched", "ticket": tid, "lesson": "imp-not-proposed"}))
        await asyncio.sleep(0.2)
        t = tickets(base, key)[0]
        check("un automate non proposé ne peut pas être enregistré",
              t.get("suggestion_lancee") is None and not any("Automate proposé lancé" in n.get("text", "")
                                                              for n in t.get("notes", [])))

        await wa.send(json.dumps({"type": "ticket_automate_launched", "ticket": tid, "lesson": automate["id"]}))
        for _ in range(20):
            t = tickets(base, key)[0]
            if t.get("suggestion_lancee") == automate["id"]:
                break
            await asyncio.sleep(0.1)
        check("l'automate proposé lancé est noté sans fermer le ticket",
              t.get("suggestion_lancee") == automate["id"] and t["status"] == "en_attente"
              and any(n.get("text") == f"Automate proposé lancé : {automate['title']}" for n in t.get("notes", [])))

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
            await asyncio.sleep(0.5)
            wifi = tickets(base, key)[0]

            await wa.send(json.dumps({"type": "help_request", "task": "Wi-Fi coupé depuis ce matin"}))
            ex = await attendre(wa, "ticket_exists")
            lst = tickets(base, key)
            check("même demande, ticket encore ouvert : signalée, sans nouveau ticket",
                  ex is not None and ex["ticket"] == wifi["id"] and ex["number"] == 2
                  and ex["status"] == "a_reprendre" and len(lst) == 2)
            check("le support voit que la demande a été refaite",
                  any(n["text"] == "Demandé à nouveau par l’utilisateur." for n in lst[0]["notes"]))

            await wa.send(json.dumps({"type": "help_request", "task": "Je n'arrive plus à imprimer mon document"}))
            sol = await attendre(wa, "ticket_solved")
            check("même demande, ticket réglé : la solution est renvoyée, sans nouveau ticket",
                  sol is not None and sol["ticket"] == tid and sol["solution"]["note"] == "Réglé par téléphone"
                  and sol["solution"]["by"] == "Claire" and len(tickets(base, key)) == 2)

            await wa.send(json.dumps({"type": "help_request", "task": "Imprimer un document", "reopen": tid}))
            sess = await attendre(wa, "session")
            t = next(x for x in tickets(base, key) if x["id"] == tid)
            check("le problème est revenu : le même ticket est rouvert et suit la nouvelle assistance",
                  sess is not None and sess.get("ticket") == tid and len(tickets(base, key)) == 2
                  and t["status"] == "en_cours" and not t.get("closed_by")
                  and t["notes"][-1]["text"] == "Le problème est revenu."
                  and "Réglé par téléphone" in t.get("reprise", ""))
            await wa.send(json.dumps({"type": "stop"}))
            await asyncio.sleep(0.5)

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

        await wa.send(json.dumps({"type": "help_request", "task": "Wi-Fi coupé depuis ce matin", "new": True}))
        q = await attendre(wa, "ticket_queued")
        check("« c'est une autre demande » : un nouveau ticket est ouvert",
              q is not None and q["ticket"] != wifi["id"] and len(tickets(base, key)) == 3)

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

    st, o2 = http(f"{base}/orgs", {"name": "Poste avec automate local"})
    st, local_space = http(f"{base}/spaces", {"org": o2["enroll_token"], "name": "Poste local"})
    local_key = local_space["key"]
    st, local_automation = http(f"{base}/k/{local_key}/automations", {
        "papai": 1, "title": "Imprimer le document du scanner", "description": "Configurer l'imprimante",
        "publisher": "Utilisateur", "platforms": ["windows"],
        "actions": [{"do": "open_settings", "page": "printers"}],
    })
    st, org_automations = http(f"{base}/o/{o2['support_token']}/automations")
    check("l'automate de test est importé dans l'espace, pas dans l'organisation",
          st == 200 and local_automation.get("id", "").startswith("imp-") and local_automation.get("actions")
          and all(x.get("id") != local_automation["id"] for x in org_automations))
    async with websockets.connect(local_space["bridge_url"]) as ws:
        await ws.send(json.dumps({"type": "hello", "os": "windows"}))
        await drain(ws, 0.5)
        await ws.send(json.dumps({"type": "help_request", "task": "Imprimer le document du scanner"}))
        local_queued = await attendre(ws, "ticket_queued")
        data_dir = base_test.TEST_DATA_DIR
        assert data_dir is not None
        manifest = next(
            path for path in (data_dir / "spaces").glob("*/space.json")
            if json.loads(path.read_text(encoding="utf-8")).get("key") == local_key
        )
        lesson_id = "lesson-ticket-no-actions"
        lesson_dir = manifest.parent / "lessons" / lesson_id
        lesson_dir.mkdir(parents=True, exist_ok=True)
        (lesson_dir / "lesson.json").write_text(json.dumps({
            "id": lesson_id,
            "title": "Retrouver les paramètres du bureau",
            "task": "Retrouver les paramètres du bureau",
            "steps": [{"instruction": "Ouvrir les paramètres du bureau", "checkpoint": "", "frame": ""}],
            "approved_by_helper": True,
            "approved_at": time.time(),
        }, ensure_ascii=False), encoding="utf-8")
        st, saved_lessons = http(f"{base}/k/{local_key}/lessons")
        check("l'automate enregistré sans actions est dans le catalogue de l'espace",
              st == 200 and any(x.get("id") == lesson_id and not x.get("actions") for x in saved_lessons))
        await ws.send(json.dumps({"type": "help_request", "task": "Retrouver les paramètres du bureau"}))
        no_action_queued = await attendre(ws, "ticket_queued")
    check("un automate importé seulement dans l'espace est proposé au poste d'organisation",
          local_queued is not None and local_queued.get("suggestions") == [
              {"id": local_automation["id"], "title": local_automation["title"]}
          ])
    check("un automate enregistré sans actions n'est pas proposé dans ticket_queued",
          no_action_queued is not None and no_action_queued.get("suggestions") == [])


if __name__ == "__main__":
    os.environ["PAPAI_RDV_TICK_S"] = "0.5"
    os.environ["PAPAI_RDV_MIN_S"] = "1"
    stockage()
    base_test.parcours = parcours
    base_test.main()
