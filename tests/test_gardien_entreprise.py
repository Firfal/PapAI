"""Gardien d'entreprise : l'IT déclare ses domaines et ses outils, l'ordinateur reçoit
les règles, l'outil déclaré se tait, le faux site bloque, la fausse alerte prévient
sans bloquer, et chaque alerte devient un ticket « Sécurité ».

    python tests/test_gardien_entreprise.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import websockets

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_appairage_code as base_test  # noqa: E402
from test_tickets import attendre, drain, tickets  # noqa: E402

http = base_test.http


def check(label: str, cond, detail=None) -> None:
    base_test.check(label if cond or detail is None else f"{label} : {detail}", bool(cond))


async def parcours(base: str) -> None:
    wsb = base.replace("http://", "ws://")
    st, o = http(f"{base}/orgs", {"name": "Acme"})
    tok = o["support_token"]
    st, sec = http(f"{base}/o/{tok}/security", {"domains": ["https://acme.fr/", "pas un domaine"],
                                                "remote_tools": ["TeamViewer", "rm -rf /"],
                                                "channels": ["01 23 45 67 89"]})
    check("l'IT déclare ses domaines, outils et canaux (nettoyés)", st == 200 and sec["security"] == {
        "domains": ["acme.fr"], "remote_tools": ["teamviewer"], "channels": ["01 23 45 67 89"]}, sec)
    st, _ = http(f"{base}/o/{o['enroll_token']}/security", {"domains": ["x.fr"]})
    check("le jeton d'inscription ne change pas la configuration", st in (403, 404), st)
    st, lu = http(f"{base}/o/{tok}/security")
    check("configuration relue", st == 200 and lu["security"]["domains"] == ["acme.fr"])

    st, a = http(f"{base}/spaces", {"org": o["enroll_token"], "name": "Poste compta"})
    key = a["key"]
    async with websockets.connect(a["bridge_url"]) as wa:
        await wa.send(json.dumps({"type": "hello", "os": "windows", "protection": True}))
        r = await attendre(wa, "guard_rules")
        check("l'ordinateur reçoit les règles à sa connexion", r is not None and "anydesk" in r["tools"]
              and "teamviewer" not in r["tools"] and "acme.fr" in r["official"] and "acme" in r["keywords"], r)
        async with websockets.connect(f"{wsb}/k/{key}/ws/aidant/{key}") as ha:
            await ha.recv()
            await drain(ha, 0.5)

            await wa.send(json.dumps({"type": "guard", "processes": ["TeamViewer"], "window": "", "url": ""}))
            check("outil déclaré par l'IT : silence", await attendre(wa, "alert", 1.5) is None)

            await wa.send(json.dumps({"type": "guard", "processes": [], "window": "", "url": "https://acmee.fr"}))
            al = await attendre(wa, "alert")
            check("faux site de l'entreprise : alerte bloquante", al is not None and al.get("blocked") is True, al)
            pa = await attendre(ha, "alert")
            check("le support la reçoit", pa is not None and pa.get("alert_id") == (al or {}).get("alert_id"))
            await ha.send(json.dumps({"type": "dismiss_alert", "alert_id": (al or {}).get("alert_id")}))
            await attendre(wa, "alert_cleared")

            await wa.send(json.dumps({"type": "guard", "processes": [], "url": "",
                                      "window": "Votre ordinateur est infecté, appelez ce numéro"}))
            al = await attendre(wa, "alert")
            check("fausse alerte virus hors assistance : prévient sans bloquer",
                  al is not None and al.get("blocked") is False and not al.get("alert_id"), al)
            av = await attendre(ha, "guard_advice")
            check("le support reçoit un avertissement", av is not None and av.get("level") == "danger", av)

    sec_t = [t for t in tickets(base, key) if t.get("category") == "securite" and t.get("source") == "gardien"]
    check("chaque alerte devient un ticket « Sécurité »", len(sec_t) == 2, [t.get("task") for t in sec_t])


if __name__ == "__main__":
    base_test.parcours = parcours
    base_test.main()
