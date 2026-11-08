"""Pré-traitement de la demande : Holo fait préciser une demande floue avant le ticket.

Serveur temporaire en mode en ligne, avec le faux Holo. « J'ai besoin d'aide »
appelle une question ; la réponse donne un ticket à l'objet formel, qui garde
les mots d'origine et les précisions. Une app qui n'annonce pas `clarify`
continue comme avant.

    python tests/test_clarification.py
"""
from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
from pathlib import Path

import websockets

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import test_appairage_code as base_test  # noqa: E402
from test_tickets import attendre, drain, tickets  # noqa: E402
from backend import clarify  # noqa: E402

check, http = base_test.check, base_test.http
VAGUE = "J'ai besoin d'aide"


def regles() -> None:
    for t in (VAGUE, "ça marche pas", "Bonjour, pouvez-vous m'aider svp", "imprimante"):
        check(f"demande vague repérée : « {t} »", clarify.vague(t))
    for t in ("Imprimer un document", "Le Wi-Fi ne marche plus", "Je ne retrouve plus le dossier de la comptabilité"):
        check(f"demande précise laissée telle quelle : « {t} »", not clarify.vague(t))
    p = clarify.nettoyer([{"q": "Quoi ?", "a": "L'imprimante"}, {"q": "", "a": "x"}, "texte", {"q": "A", "a": "B"}, {"q": "C", "a": "D"}])
    check("précisions bornées et nettoyées", p == [{"q": "Quoi ?", "a": "L'imprimante"}, {"q": "A", "a": "B"}])
    check("contexte vide pour une demande déjà formelle", clarify.contexte("Imprimer", "Imprimer", []) == "")
    check("contexte : mots d'origine et précisions",
          clarify.contexte("Imprimante : impression impossible", VAGUE, p[:1])
          == f"Demande de l'utilisateur : « {VAGUE} »\nQuoi ? → L'imprimante")

    async def panne(_):
        raise OSError("Holo injoignable")
    vrai, clarify._holo = clarify._holo, panne
    try:
        r = asyncio.run(clarify.evaluer(VAGUE))
        check("Holo injoignable, demande vide : une question générale quand même",
              not r["clair"] and r["question"] == clarify.QUESTION_GENERALE and r["options"])
        r = asyncio.run(clarify.evaluer("Imprimer un document"))
        check("Holo injoignable, demande précise : elle part telle quelle", r == {"clair": True, "objet": "Imprimer un document"})
        r = asyncio.run(clarify.evaluer(VAGUE, [{"q": "Quoi ?", "a": "L'imprimante ne marche plus"}]))
        check("Holo injoignable après une réponse : le ticket porte la réponse", r["objet"] == "L'imprimante ne marche plus")
        r = asyncio.run(clarify.evaluer("Imprimante", [{"q": "Quoi ?", "a": "Ça ne marche plus"}]))
        check("Holo injoignable : un mot utile de la demande reste dans l'objet", "Imprimante" in r["objet"])
        longue = "Bonjour, excusez-moi de vous déranger, j'ai un souci avec l'imprimante depuis ce matin au bureau"
        r = asyncio.run(clarify.evaluer(longue, [{"q": "Quoi ?", "a": "Bourrage papier"}]))
        check("Holo injoignable : la réponse reste visible après une longue demande", "Bourrage papier" in r["objet"])
        r = asyncio.run(clarify.evaluer(VAGUE, [], force=True))
        check("« Envoyer quand même » ne repose jamais de question", r["clair"])
    finally:
        clarify._holo = vrai


async def parcours(base: str) -> None:
    wsb = base.replace("http://", "ws://")
    st, o = http(f"{base}/orgs", {"name": "Acme"})
    st, a = http(f"{base}/spaces", {"org": o["enroll_token"], "name": "Poste compta"})
    key = a["key"]
    async with websockets.connect(a["bridge_url"]) as wa:
        await wa.send(json.dumps({"type": "hello", "os": "windows", "clarify": True}))
        await drain(wa, 0.5)

        await wa.send(json.dumps({"type": "help_request", "task": VAGUE}))
        q = await attendre(wa, "clarify", 10)
        check("« J'ai besoin d'aide » : Holo pose une question avec des réponses prêtes",
              q is not None and q["question"] and len(q["options"]) >= 2 and q["round"] == 1 and q["max"] == 2)
        check("pas de ticket tant que la demande n'est pas précisée", tickets(base, key) == [])
        await wa.send(json.dumps({"type": "clarify_answer", "text": "L'imprimante ne marche plus"}))
        t = await attendre(wa, "ticket_queued", 10)
        check("réponse donnée : ticket à l'objet formel", t is not None and t["task"] == "Imprimante : impression impossible")
        lst = tickets(base, key)
        check("le ticket garde les mots d'origine et la précision",
              len(lst) == 1 and lst[0]["demande"] == VAGUE
              and lst[0]["precisions"] == [{"q": q["question"], "a": "L'imprimante ne marche plus"}])

        await wa.send(json.dumps({"type": "help_request", "task": "Imprimer un document"}))
        t = await attendre(wa, "ticket_queued", 10)
        check("demande précise : pas de question, ticket aussitôt", t is not None and t["task"] == "Imprimer un document")
        check("demande précise : rien à garder en plus", "demande" not in tickets(base, key)[0])

        await wa.send(json.dumps({"type": "help_request", "task": VAGUE}))
        await attendre(wa, "clarify", 10)
        await wa.send(json.dumps({"type": "clarify_answer", "skip": True}))
        t = await attendre(wa, "ticket_queued", 10)
        check("« Envoyer quand même » : le ticket part sans précision", t is not None and t["task"] == VAGUE)

        await wa.send(json.dumps({"type": "help_request", "task": VAGUE}))
        await attendre(wa, "clarify", 10)
        await wa.send(json.dumps({"type": "clarify_cancel"}))
        await wa.send(json.dumps({"type": "clarify_answer", "text": "Le Wi-Fi"}))
        check("demande annulée : aucune réponse ne crée de ticket",
              not [m for m in await drain(wa, 1.5) if m.get("type") in ("ticket_queued", "clarify")] and len(tickets(base, key)) == 3)

    # L'ordinateur se reconnecte pendant la question : elle est reposée, la réponse aboutit.
    async with websockets.connect(a["bridge_url"]) as wa:
        await wa.send(json.dumps({"type": "hello", "os": "windows", "clarify": True}))
        await drain(wa, 0.5)
        await wa.send(json.dumps({"type": "help_request", "task": VAGUE}))
        await attendre(wa, "clarify", 10)
    async with websockets.connect(a["bridge_url"]) as wa:
        await wa.send(json.dumps({"type": "hello", "os": "windows", "clarify": True}))
        q = await attendre(wa, "clarify", 5)
        check("reconnexion : la question de Holo est reposée", q is not None and q["question"])
        await wa.send(json.dumps({"type": "clarify_answer", "text": "Le Wi-Fi"}))
        check("reconnexion : la réponse ouvre le ticket", await attendre(wa, "ticket_queued", 10) is not None)

        await wa.send(json.dumps({"type": "hello", "os": "windows"}))
        await drain(wa, 0.3)
        await wa.send(json.dumps({"type": "help_request", "task": VAGUE}))
        t = await attendre(wa, "ticket_queued", 10)
        check("app sans `clarify` : comportement d'avant, ticket aussitôt", t is not None and t["task"] == VAGUE)

        # Barre de recherche du Mac : la question passe par le brouillon `kind: request`.
        st, d = http(f"{base}/k/{key}/automations/draft", {"kind": "request", "text": VAGUE, "os": "mac"})
        check("brouillon d'une demande vague : une question, pas de plan",
              st == 200 and d.get("clarify", {}).get("question") and "steps" not in d)
        prec = [{"q": d["clarify"]["question"], "a": "L'imprimante"}]
        st, d = http(f"{base}/k/{key}/automations/draft",
                     {"kind": "request", "text": VAGUE, "os": "mac", "precisions": prec})
        check("brouillon précisé : plan et objet formel",
              st == 200 and d.get("steps") and d.get("objet") == "Imprimante : impression impossible"
              and d.get("demande") == VAGUE and d.get("precisions") == prec)
        plan = {k: d[k] for k in ("title", "description", "goal", "steps", "platforms", "warning")}
        st, r = http(f"{base}/k/{key}/tickets", {"task": d["objet"], "demande": VAGUE, "precisions": prec, "automate": plan})
        tk = r.get("ticket", {}) if st == 200 else {}
        check("demande d'automate : le ticket garde l'objet, les mots d'origine et la précision",
              tk.get("task") == d["objet"] and tk.get("demande") == VAGUE and tk.get("precisions") == prec)

        # Support connecté : la demande précisée ouvre l'assistance.
        await wa.send(json.dumps({"type": "hello", "os": "windows", "clarify": True}))
        async with websockets.connect(f"{wsb}/k/{key}/ws/aidant/{key}") as ha:
            await drain(ha, 0.5)
            await drain(wa, 0.5)
            await wa.send(json.dumps({"type": "help_request", "task": VAGUE}))
            await attendre(wa, "clarify", 10)
            await wa.send(json.dumps({"type": "clarify_answer", "text": "L'imprimante"}))
            s = await attendre(wa, "session", 10)
            check("support connecté : l'assistance démarre sur la demande précisée", s is not None and s.get("ticket"))
            t = next((x for x in tickets(base, key) if s and x["id"] == s.get("ticket")), {})
            check("le ticket de l'assistance garde la précision",
                  t.get("task") == "Imprimante : impression impossible" and t.get("demande") == VAGUE)
            await wa.send(json.dumps({"type": "stop"}))
            await drain(wa, 1)

            # Annuler juste après la dernière réponse : aucune assistance ne reste ouverte.
            await wa.send(json.dumps({"type": "help_request", "task": VAGUE}))
            await attendre(wa, "clarify", 10)
            await wa.send(json.dumps({"type": "clarify_answer", "text": "L'imprimante"}))
            await asyncio.sleep(0.3)
            await wa.send(json.dumps({"type": "clarify_cancel"}))
            await drain(wa, 1.5)
            check("Annuler après la réponse : aucune assistance en cours",
                  not [x for x in tickets(base, key) if x["status"] == "en_cours"])


if __name__ == "__main__":
    regles()
    port = base_test.port_libre()
    holo = subprocess.Popen([sys.executable, str(Path(__file__).with_name("faux_holo.py")), str(port)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.environ["HOLO_BASE_URL"] = f"http://127.0.0.1:{port}/v1/"
    base_test.parcours = parcours
    base_test.politique = lambda: None  # contrôles de liaison : dans test_appairage_code.py
    try:
        base_test.main()
    finally:
        holo.terminate()
