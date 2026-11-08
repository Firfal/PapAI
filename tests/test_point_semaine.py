"""Point de la semaine pour le support (carte « Cette semaine »).

Agrégats des 7 derniers jours calculés par `ticket_stats.week`, renvoyés dans
`stats()["week"]` par `/k/<clé>/tickets/stats` et `/o/<support_token>/tickets/stats`.

    python tests/test_point_semaine.py
"""
from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

import websockets

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import test_appairage_code as base_test  # noqa: E402
from backend import ticket_stats as ts  # noqa: E402

check, http = base_test.check, base_test.http
H, J = 3600, 86400
NOW = 1_794_000_000.0


def t(task: str, age_j: float, **kw) -> dict:
    created = NOW - age_j * J
    d = {"id": f"{task}-{age_j}", "number": 1, "task": task, "source": "personne", "status": "nouveau",
         "created": created, "updated": created}
    d.update(kw)
    return d


def resolu(task: str, age_j: float, duree_h: float, **kw) -> dict:
    created = NOW - age_j * J
    return t(task, age_j, status="resolu", resolved=created + duree_h * H, updated=created + duree_h * H, **kw)


def agregats() -> None:
    rows = [
        resolu("Le Wi-Fi ne marche plus", 1, 2),
        resolu("Plus d'internet", 2, 4),
        t("Box éteinte", 3),
        resolu("L'imprimante ne répond pas", 4, 1),
        t("Mot de passe oublié", 5),
        t("Mon e-mail a disparu", 6),
        resolu("Remettre l'imprimante", 0.5, 0.25, source="automatisme", automation="imp-1"),
        resolu("Remettre l'imprimante", 1.5, 0.25, source="automatisme", automation="imp-1"),
        resolu("Rétablir le Wi-Fi", 2.5, 0.5, source="automatisme"),
        # Arrivé il y a 10 jours, réglé il y a 2 jours : compte dans les réglées, pas dans les reçues.
        resolu("Le scanner bloque", 10, 8 * 24),
        # Hors de la semaine : ni reçu ni réglé.
        resolu("Le Wi-Fi saute", 20, 1),
        t("Wi-Fi lent", 9),
    ]
    w = ts.week(rows, now=NOW)
    check("reçues : créées dans les 7 jours", w["count"] == 9)
    check("réglées : résolues dans les 7 jours, même arrivées avant", w["resolved"] == 7)
    check("part réglée par un automate", w["by_automate"] == 3 and w["automate_share"] == round(3 / 7, 3))
    moy = (2 + 4 + 1 + 0.25 + 0.25 + 0.5 + 8 * 24) * H / 7
    check("temps moyen des réglées", w["mean_resolution_s"] == round(moy)
          and w["resolution_total_s"] == round(moy * 7))
    check("trois catégories en tête, dans l'ordre",
          [(c["id"], c["count"]) for c in w["top"]] == [("wifi", 4), ("imprimante", 3), ("comptes", 1)]
          and w["top"][0]["label"] == "Wi-Fi et réseau")
    check("catégories complètes pour fusionner plusieurs utilisateurs", set(w["by"]) == set(ts.IDS))
    check("automate le plus utile : celui qui a réglé le plus",
          w["automate"] == {"key": "imp-1", "title": "Remettre l'imprimante", "count": 2}
          and [a["count"] for a in w["automates"]] == [2, 1])
    check("automate sans identifiant : repéré par son titre", w["automates"][1]["key"] == "titre:Rétablir le Wi-Fi")
    check("début de la période", w["since"] == "2026-10-30" and w["days"] == 7)
    vide = ts.week([], now=NOW)
    check("semaine vide", vide["count"] == 0 and vide["resolved"] == 0 and vide["automate_share"] == 0.0
          and vide["mean_resolution_s"] is None and vide["top"] == [] and vide["automate"] is None
          and vide["suggestion"] is None)
    futur = ts.week([t("Wi-Fi", -1)], now=NOW)
    check("ticket daté dans le futur ignoré", futur["count"] == 0)

    many = [t(f"Le Wi-Fi ne marche plus ({i})", i * 0.5) for i in range(6)]
    s = ts.stats(many, now=NOW)
    check("même calcul que les statistiques : semaine incluse", s["week"] == ts.week(many, NOW, s["suggestions"]))
    sug = s["week"]["suggestion"]
    check("suggestion d'automate quand une catégorie revient souvent",
          sug and sug["category"] == "wifi" and sug["text"] == "6 demandes Wi-Fi ce mois-ci : créer un automate ?"
          and sug["draft"]["title"] == "Rétablir le Wi-Fi")
    check("pas de suggestion sous le seuil", ts.stats(many[:4], now=NOW)["week"]["suggestion"] is None)


async def attendre(w, kind: str, t_s: float = 6.0) -> dict | None:
    try:
        while True:
            m = json.loads(await asyncio.wait_for(w.recv(), t_s))
            if m.get("type") == kind:
                return m
    except asyncio.TimeoutError:
        return None


async def parcours(base: str) -> None:
    st, o = http(f"{base}/orgs", {"name": "Acme"})
    st, a = http(f"{base}/spaces", {"org": o["enroll_token"], "name": "Poste accueil"})
    key = a["key"]
    async with websockets.connect(a["bridge_url"]) as wa:
        await wa.send(json.dumps({"type": "hello", "os": "mac"}))
        await asyncio.sleep(0.5)
        for task in ("Le Wi-Fi ne marche plus", "L'imprimante ne répond pas", "Plus d'internet du tout"):
            await wa.send(json.dumps({"type": "help_request", "task": task}))
            check(f"demande reçue : « {task[:20]} »", await attendre(wa, "ticket_queued") is not None)
    st, s = http(f"{base}/k/{key}/tickets/stats")
    w = s.get("week") or {}
    check("route du poste : carte de la semaine", st == 200 and w.get("count") == 3
          and [c["id"] for c in w.get("top", [])] == ["wifi", "imprimante"])
    st, s = http(f"{base}/o/{o['support_token']}/tickets/stats")
    check("route de l'organisation : carte de la semaine", st == 200 and s.get("week", {}).get("count") == 3)
    st, _ = http(f"{base}/o/{o['enroll_token']}/tickets/stats")
    check("jeton d'inscription refusé (orgs.auth)", st == 404)
    st, _ = http(f"{base}/k/mauvaise-cle/tickets/stats")
    check("mauvaise clé refusée", st == 404)
    st, page = http(f"{base}/ticket_stats.js")
    check("carte servie au navigateur", st == 200 and "renderWeek" in str(page))


def main() -> None:
    agregats()
    base_test.parcours = parcours
    base_test.main()


if __name__ == "__main__":
    main()
