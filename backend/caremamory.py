"""CareMemory : transformer une session réussie en fiche pédagogique.

Le point du produit n'est pas de rejouer des clics, c'est d'expliquer la logique
d'une manipulation à quelqu'un qui devra la refaire seul. On donne donc au modèle
la trajectoire en texte — ce qu'il a visé, pas où il a cliqué — et on lui demande
une fiche courte, dans des mots que la personne aidée comprend.

Rien n'est écrit sur disque avant qu'un proche ait validé la fiche.
"""

from __future__ import annotations

import base64
import json
import re
import time
from pathlib import Path

from carepilot_tools import MODEL, TEMPERATURE, make_client, observation

from .sessions import Session

LESSONS_DIR = Path(__file__).parent.parent / "lessons"

client = make_client()

PROMPT = """Tu rédiges une fiche pour une personne âgée peu à l'aise avec Windows,
à partir d'une manipulation qu'un assistant vient de réussir sur son ordinateur.

Objectif : qu'elle puisse refaire la manipulation SEULE la prochaine fois.

Règles de rédaction :
- 2 à 4 étapes. Jamais plus. Regroupe les clics qui vont ensemble.
- Explique la LOGIQUE, pas la suite des clics. « Ouvrez l'Explorateur de fichiers,
  puis choisissez Images dans la colonne de gauche » et non « cliquez en bas à
  gauche puis à 300 pixels ».
- Pas de coordonnées, pas de pixels, pas de vocabulaire technique.
- Vouvoie. Phrases courtes. Une seule action par étape.
- Pour chaque étape, donne un repère visuel : ce qu'elle doit voir à l'écran une
  fois l'étape réussie.
- Ignore les tâtonnements de l'assistant : ne garde que le chemin qui a marché.
- Écris dans un français simple et entièrement correct. Aucun mot anglais :
  écris « ouvrir » et non « opening », « intitulé » et non « labeled ».

Réponds UNIQUEMENT par un objet JSON, sans texte autour :
{"title": "...", "steps": [{"instruction": "...", "checkpoint": "...", "frame": "..."}]}

`title` commence par un verbe à l'infinitif, par exemple « Retrouver mes photos ».
`frame` reprend un identifiant de capture de la liste fournie, celui qui illustre
le mieux l'étape."""


def _trajectory(session: Session) -> str:
    """La trajectoire réussie, en texte, telle qu'on la donne au modèle."""
    lines = [f"Demande de la personne : « {session.task} »", "", "Ce que l'assistant a fait :"]
    for e in session.journal:
        if e["kind"] == "tool_call":
            args = e.get("args", {})
            target = args.get("element") or args.get("keys") or args.get("text") or ""
            frame = e.get("frame", "")
            lines.append(f"- [{e['tool']}] {target}" + (f"   (capture {frame})" if frame else ""))
        elif e["kind"] == "helper_reply":
            lines.append(f"- Le proche a précisé : {e.get('text','')}")
        elif e["kind"] == "answer":
            lines.append(f"\nRésultat annoncé : {e.get('content','')}")

    ids = [fid for fid in session.frames]
    lines.append("")
    lines.append("Identifiants de capture disponibles : " + ", ".join(ids))
    return "\n".join(lines)


SHORTCUT_PROMPT = """Regarde cette capture d'écran Windows, prise à la fin d'une manipulation réussie.

Si un dossier est ouvert dans l'Explorateur de fichiers, dis LEQUEL des dossiers
personnels de Windows il s'agit, et éventuellement dans quel sous-dossier on se
trouve :
{"folder": "pictures", "subfolder": "Photos vacances"}

`folder` vaut obligatoirement l'une de ces valeurs, et rien d'autre :
downloads, pictures, documents, desktop, videos, music.

`subfolder` est le NOM du sous-dossier ouvert, sans aucun chemin ni barre
oblique. Laisse-le vide si on est directement dans le dossier personnel.

N'écris JAMAIS de chemin complet, jamais de lettre de lecteur, jamais
« C:\\Users\\... » : c'est l'ordinateur qui sait où sont ses dossiers.

Si aucun dossier n'est ouvert, ou si tu hésites, réponds : {"folder": "none"}

Ne réponds QUE par cet objet JSON, sans aucun texte autour. Ne devine pas."""

KNOWN_FOLDERS = {"downloads", "pictures", "documents", "desktop", "videos", "music"}


async def _extract_shortcut(session: Session) -> dict | None:
    """Le chemin atteint à la fin, s'il est lisible.

    C'est ce qui permettra de refaire la manipulation sans rejouer un seul clic :
    on retient la destination, pas le trajet. Un chemin inventé par le modèle ne
    coûte rien — le pont vérifie qu'il existe avant d'ouvrir quoi que ce soit.
    """
    import asyncio

    if not session.frames:
        return None
    last_b64 = list(session.frames.values())[-1]
    try:
        resp = await asyncio.to_thread(
            client.chat.completions.create,
            model=MODEL,
            messages=[
                {"role": "system", "content": SHORTCUT_PROMPT},
                observation(last_b64),
            ],
            temperature=TEMPERATURE,
        )
        data = _parse(resp.choices[0].message.content or "")
    except Exception as e:  # noqa: BLE001 — pas de raccourci, la fiche reste utilisable
        session.log("shortcut_failed", error=f"{type(e).__name__}: {e}")
        return None

    folder = str(data.get("folder", "")).strip().lower()
    if folder not in KNOWN_FOLDERS:
        return None

    # Un NOM de sous-dossier, jamais un chemin : le modèle a tendance à
    # reconstituer des « C:\\Users\\... » qu'il invente.
    sub = str(data.get("subfolder") or "").strip()
    if any(c in sub for c in '\\/:*?"<>|') or sub in (".", ".."):
        sub = ""
    return {"folder": folder, "subfolder": sub}


def _parse(raw: str) -> dict:
    """Le modèle encadre parfois son JSON de texte ou de balises Markdown."""
    m = re.search(r"\{.*\}", raw, re.S)
    if not m:
        raise ValueError("aucun JSON dans la réponse du modèle")
    return json.loads(m.group(0))


async def draft_lesson(session: Session) -> dict:
    """Produit un brouillon de fiche. Non validé, non écrit sur disque."""
    import asyncio

    resp = await asyncio.to_thread(
        client.chat.completions.create,
        model=MODEL,
        messages=[
            {"role": "system", "content": PROMPT},
            {"role": "user", "content": _trajectory(session)},
        ],
        temperature=TEMPERATURE,
    )
    data = _parse(resp.choices[0].message.content or "")

    raw_steps = data.get("steps")
    steps = []
    for s in raw_steps if isinstance(raw_steps, list) else []:
        if len(steps) == 4:
            break
        # Le modèle renvoie parfois de simples phrases au lieu d'objets.
        if isinstance(s, str):
            s = {"instruction": s}
        if not isinstance(s, dict):
            continue
        instruction = str(s.get("instruction", "")).strip()
        if not instruction:
            continue
        frame = str(s.get("frame") or "")
        steps.append(
            {
                "instruction": instruction,
                "checkpoint": str(s.get("checkpoint", "")).strip(),
                # On ne fait pas confiance à l'identifiant renvoyé : il doit
                # exister parmi les captures réellement prises.
                "frame": frame if frame in session.frames else "",
            }
        )
    if not steps:
        raise ValueError("fiche sans étape exploitable")

    lesson = {
        "id": f"lesson-{int(time.time())}",
        "title": str(data.get("title", session.task)).strip(),
        "task": session.task,
        "session": session.id,
        "os": "Windows",
        "approved_by_helper": False,
        "created_at": time.time(),
        "steps": steps,
        # Raccourci déterministe : refaire la manipulation sans rejouer un clic.
        "shortcut": await _extract_shortcut(session),
    }
    session.log("lesson_drafted", title=lesson["title"], steps=len(steps))
    return lesson


def approve_and_save(lesson: dict, session: Session) -> dict:
    """Validation par le proche : c'est seulement ici qu'on écrit sur disque.

    Les captures des étapes retenues sont enregistrées, et elles seules.
    """
    lesson["approved_by_helper"] = True
    lesson["approved_at"] = time.time()

    folder = LESSONS_DIR / lesson["id"]
    folder.mkdir(parents=True, exist_ok=True)

    for i, step in enumerate(lesson["steps"], start=1):
        b64 = session.frames.get(step.get("frame", ""))
        if not b64:
            step["image"] = ""
            continue
        name = f"step-{i}.png"
        (folder / name).write_bytes(base64.b64decode(b64))
        step["image"] = name

    (folder / "lesson.json").write_text(
        json.dumps(lesson, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    session.log("lesson_approved", id=lesson["id"])
    return lesson


def list_lessons() -> list[dict]:
    if not LESSONS_DIR.exists():
        return []
    out = []
    for f in sorted(LESSONS_DIR.glob("*/lesson.json")):
        try:
            out.append(json.loads(f.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError):
            continue
    return sorted(out, key=lambda x: x.get("approved_at", 0), reverse=True)
