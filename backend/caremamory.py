"""CareMemory : transformer une session réussie en fiche pédagogique.

Le point du produit n'est pas de rejouer des clics, c'est d'expliquer la logique
d'une manipulation à quelqu'un qui devra la refaire seul. On donne donc au modèle
la trajectoire en texte — ce qu'il a visé, pas où il a cliqué — et les vraies
captures d'écran de la session, et on lui demande une fiche courte, dans des mots
que la personne aidée comprend. Chaque étape est illustrée par une de ces captures,
jamais par une image fabriquée.

Rien n'est écrit sur disque avant qu'un proche ait validé la fiche.
"""

from __future__ import annotations

import base64
import json
import re
import time
from pathlib import Path

from papai_tools import MODEL, TEMPERATURE, make_client, observation

from .sessions import Session

def lessons_dir() -> Path:
    """Les fiches et automatismes de l'espace en cours."""
    from . import space
    return space.current().lessons_dir


client = make_client()

# Holo accepte 5 images par requête.
MAX_LESSON_FRAMES = 4

PROMPT = """Tu rédiges une fiche pour une personne peu à l'aise avec l'informatique,
à partir d'une manipulation qu'un assistant vient de réussir sur son ordinateur.
Tu reçois la liste des actions et de vraies captures de son écran, prises pendant
la manipulation.

Objectif : qu'elle puisse refaire la manipulation SEULE la prochaine fois.

Règles de rédaction :
- 2 à 4 étapes. Jamais plus. Regroupe les clics qui vont ensemble.
- Explique la LOGIQUE, pas la suite des clics. « Ouvrez l'Explorateur de fichiers,
  puis choisissez Images dans la colonne de gauche » et non « cliquez en bas à
  gauche puis à 300 pixels ».
- Pas de coordonnées, pas de pixels, pas de vocabulaire technique.
- Vouvoie. Phrases courtes. Une seule action par étape.
- Pour chaque étape, donne un repère visuel : ce qu'elle doit voir à l'écran une
  fois l'étape réussie. Prends-le dans les captures, n'invente rien.
- Ignore les tâtonnements de l'assistant : ne garde que le chemin qui a marché.
- Écris dans un français simple et entièrement correct. Aucun mot anglais :
  écris « ouvrir » et non « opening », « intitulé » et non « labeled ».

Réponds UNIQUEMENT par un objet JSON, sans texte autour :
{"title": "...", "steps": [{"instruction": "...", "checkpoint": "...", "frame": "..."}]}

`title` commence par un verbe à l'infinitif, par exemple « Retrouver mes photos ».
`frame` reprend l'identifiant de la capture jointe qui montre l'écran une fois
l'étape réussie."""


def _trajectory(session: Session, ids: list[str]) -> str:
    """La trajectoire réussie, en texte, telle qu'on la donne au modèle."""
    lines = [f"Demande de la personne : « {session.task} »", "", "Ce que l'assistant a fait :"]
    for e in session.journal:
        if e["kind"] == "tool_call":
            args = e.get("args", {})
            target = args.get("element") or args.get("keys") or args.get("text") or ""
            frame = e.get("frame", "")
            lines.append(f"- [{e['tool']}] {target}" + (f"   (capture {frame})" if frame else ""))
        elif e["kind"] == "helper_reply":
            lines.append(f"- Le support a précisé : {e.get('text','')}")
        elif e["kind"] == "answer":
            lines.append(f"\nRésultat annoncé : {e.get('content','')}")

    lines.append("")
    lines.append("Captures jointes : " + ", ".join(ids))
    return "\n".join(lines)


def _session_frames(session: Session) -> list[str]:
    """Les captures de la session encore en mémoire, dans l'ordre des actions.

    La dernière capture (l'écran à la fin) est toujours incluse : c'est souvent
    elle qui montre le résultat que la personne doit retrouver.
    """
    ids: list[str] = []
    for e in session.journal:
        f = e.get("frame") if e["kind"] == "tool_call" else None
        if f and f in session.frames and f not in ids:
            ids.append(f)
    if session.frames:
        last = next(reversed(session.frames))
        if last not in ids:
            ids.append(last)
    return ids


def _spread(ids: list[str], n: int) -> list[str]:
    """n identifiants répartis sur toute la session, le dernier toujours gardé."""
    if n <= 0 or not ids:
        return []
    if len(ids) <= n:
        return list(ids)
    if n == 1:
        return [ids[-1]]
    return [ids[round(i * (len(ids) - 1) / (n - 1))] for i in range(n)]


def _with_frames(text: str, ids: list[str], session: Session) -> dict:
    content: list[dict] = [{"type": "text", "text": text}]
    for fid in ids:
        content.append({"type": "text", "text": f"\nCapture {fid} :"})
        content.append(
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{session.frames[fid]}"}}
        )
    return {"role": "user", "content": content}


SHORTCUT_PROMPT = """Regarde cette capture d'écran {os}, prise à la fin d'une manipulation réussie.

Si un dossier est ouvert dans {explorer}, dis LEQUEL des dossiers
personnels de l'ordinateur il s'agit (Téléchargements, Images, Documents, Bureau,
Vidéos, Musique), et éventuellement dans quel sous-dossier on se
trouve :
{"folder": "pictures", "subfolder": "Photos vacances"}

`folder` vaut obligatoirement l'une de ces valeurs, et rien d'autre :
downloads, pictures, documents, desktop, videos, music.

`subfolder` est le NOM du sous-dossier ouvert, sans aucun chemin ni barre
oblique. Laisse-le vide si on est directement dans le dossier personnel.

N'écris JAMAIS de chemin complet, jamais de lettre de lecteur, jamais
« C:\\Users\\... » ni « /Users/... » : c'est l'ordinateur qui sait où sont ses dossiers.

Si aucun dossier n'est ouvert, ou si tu hésites, réponds : {"folder": "none"}

Ne réponds QUE par cet objet JSON, sans aucun texte autour. Ne devine pas."""

def _is_mac(os_name: str) -> bool:
    return (os_name or "").lower() in ("macos", "mac", "darwin")


def _shortcut_prompt(os_name: str) -> str:
    # .replace et non .format : le texte contient des accolades JSON.
    mac = _is_mac(os_name)
    return (SHORTCUT_PROMPT.replace("{os}", "Mac" if mac else "Windows")
            .replace("{explorer}", "une fenêtre du Finder" if mac else "l'Explorateur de fichiers"))


KNOWN_FOLDERS = {"downloads", "pictures", "documents", "desktop", "videos", "music"}


async def _extract_shortcut(session: Session, os_name: str = "windows") -> dict | None:
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
                {"role": "system", "content": _shortcut_prompt(os_name)},
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


async def draft_lesson(session: Session, os_name: str = "windows") -> dict:
    """Produit un brouillon de fiche. Non validé, non écrit sur disque."""
    import asyncio

    available = _session_frames(session)
    if not available:
        raise ValueError("aucune capture d'écran dans la session")
    shown = _spread(available, MAX_LESSON_FRAMES)

    resp = await asyncio.to_thread(
        client.chat.completions.create,
        model=MODEL,
        messages=[
            {"role": "system", "content": PROMPT},
            _with_frames(_trajectory(session, shown), shown, session),
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
    # Toute étape a sa capture : si Holo n'en a pas choisi une valable, on prend,
    # parmi celles qu'il a vues, celle qui correspond à sa place dans la session.
    # La toute première montre l'écran avant toute action : on s'en passe quand
    # il reste au moins une capture par étape.
    pool = shown[1:] if len(shown) > len(steps) else shown
    fallback = _spread(pool, len(steps))
    for i, step in enumerate(steps):
        if not step["frame"]:
            step["frame"] = fallback[min(i, len(fallback) - 1)]

    lesson = {
        "id": f"lesson-{int(time.time())}",
        "title": str(data.get("title", session.task)).strip(),
        "task": session.task,
        "session": session.id,
        "os": "macOS" if _is_mac(os_name) else "Windows",
        "approved_by_helper": False,
        "created_at": time.time(),
        "steps": steps,
        # Raccourci déterministe : refaire la manipulation sans rejouer un clic.
        "shortcut": await _extract_shortcut(session, os_name),
    }
    session.log("lesson_drafted", title=lesson["title"], steps=len(steps))
    return lesson


def approve_and_save(lesson: dict, session: Session) -> dict:
    """Validation par le proche : c'est seulement ici qu'on écrit sur disque.

    Les captures des étapes retenues sont enregistrées, et elles seules.
    """
    lesson["approved_by_helper"] = True
    lesson["approved_at"] = time.time()

    folder = lessons_dir() / lesson["id"]
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
    if not lessons_dir().exists():
        return []
    out = []
    for f in sorted(lessons_dir().glob("*/lesson.json")):
        try:
            out.append(json.loads(f.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError):
            continue
    return sorted(out, key=lambda x: x.get("approved_at", 0), reverse=True)
