"""Faux Holo local, compatible OpenAI, pour tester sans clé H Company.

    python tests/faux_holo.py [port] [chaines|objets|casse]
    HOLO_BASE_URL=http://127.0.0.1:8999/v1/ HAI_API_KEY=stub-key python -m backend.app

Il répond à trois sortes de demandes : un plan `{"steps":[...]}`, la boucle
d'outils (deux clics puis `answer`) et un brouillon de fiche. Par défaut, la
fiche a des étapes en simples chaînes, comme le vrai Holo le fait parfois.
"""

from __future__ import annotations

import json
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8999
FICHE = sys.argv[2] if len(sys.argv) > 2 else "chaines"


def texte(messages: list) -> str:
    out = []
    for m in messages:
        c = m.get("content")
        if isinstance(c, str):
            out.append(c)
        elif isinstance(c, list):
            out += [p.get("text", "") for p in c if isinstance(p, dict)]
    return "\n".join(out)


def fiche() -> str:
    if FICHE == "casse":
        return "Désolé, je ne peux pas."
    etapes = ["Ouvrez le Finder.", "Choisissez Images dans la colonne de gauche."]
    if FICHE == "objets":
        etapes = [{"instruction": e, "checkpoint": "", "frame": ""} for e in etapes]
    return json.dumps({"title": "Retrouver mes photos", "steps": etapes}, ensure_ascii=False)


def reponse(corps: dict) -> dict:
    messages = corps.get("messages", [])
    message: dict = {"role": "assistant", "content": None}
    if corps.get("tools"):
        n = sum(1 for m in messages if m.get("role") == "assistant")
        if n < 2:
            nom, args = "click", {"element": "dossier Noël 2025", "x": 530, "y": 245}
        else:
            nom, args = "answer", {"content": "Voici vos photos de Noël."}
        message["tool_calls"] = [{
            "id": f"appel-{n}", "type": "function",
            "function": {"name": nom, "arguments": json.dumps(args, ensure_ascii=False)},
        }]
    else:
        consigne = texte(messages)
        if '"clair"' in consigne:
            # Pré-traitement de la demande (backend/clarify.py) : « j'ai besoin d'aide » appelle une question.
            utilisateur = consigne[consigne.find("Demande : «"):]
            demande = re.search(r"Demande : « (.*?) »", utilisateur, re.S)
            demande = demande.group(1) if demande else ""
            if "→" not in utilisateur and "ne peux plus" not in utilisateur and re.search(r"besoin d.aide|marche pas", demande, re.I):
                message["content"] = json.dumps({"clair": False, "question": "Qu'est-ce qui ne marche pas ?",
                                                 "options": ["L'imprimante", "Le Wi-Fi", "Un fichier"]}, ensure_ascii=False)
            elif "imprimante" in utilisateur.lower():
                message["content"] = '{"clair": true, "objet": "Imprimante : impression impossible"}'
            else:
                message["content"] = json.dumps({"clair": True, "objet": demande[:80]}, ensure_ascii=False)
        elif '"platforms"' in consigne and "automate" in consigne:
            # Brouillon d'automate (backend/automate_draft.py), ici pour une demande tapée.
            message["content"] = json.dumps({"title": "Réinstaller l'imprimante", "description": "Remet l'imprimante en service.",
                                             "goal": "Réinstaller l'imprimante du bureau",
                                             "steps": ["Ouvrir les Réglages", "Choisir Imprimantes", "Ajouter l'imprimante du bureau"],
                                             "platforms": ["mac", "windows"], "warning": ""}, ensure_ascii=False)
        elif '"instruction"' in consigne:
            message["content"] = fiche()
        elif '"folder"' in consigne:
            message["content"] = '{"folder": "pictures", "subfolder": "Noël 2025"}'
        else:
            etapes = ["Ouvrir le Finder", "Aller dans Images", "Ouvrir Noël 2025"]
            # Consigne « Étape N : remplacer « … » par « … » » de l'iPhone : appliquée.
            for n, _, nouveau in re.findall(r"Étape (\d+) : remplacer « (.+?) » par « (.+?) »", consigne):
                if 1 <= int(n) <= len(etapes):
                    etapes[int(n) - 1] = nouveau
            message["content"] = json.dumps({"steps": etapes}, ensure_ascii=False)
    return {
        "id": "faux", "object": "chat.completion", "created": int(time.time()),
        "model": corps.get("model", "faux-holo"),
        "choices": [{"index": 0, "message": message,
                     "finish_reason": "tool_calls" if corps.get("tools") else "stop"}],
        "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
    }


class Holo(BaseHTTPRequestHandler):
    def do_POST(self) -> None:  # noqa: N802
        corps = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        brut = json.dumps(reponse(corps), ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(brut)))
        self.end_headers()
        self.wfile.write(brut)

    def log_message(self, *_) -> None:
        pass


if __name__ == "__main__":
    print(f"faux Holo sur http://127.0.0.1:{PORT}/v1/ (fiche : {FICHE})", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Holo).serve_forever()
