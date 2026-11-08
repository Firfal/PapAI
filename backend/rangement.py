"""Rangement guidé des dossiers : Documents, Téléchargements ou Bureau.

L'ordinateur n'envoie que des noms de fichiers, jamais leur contenu. Holo
propose un dossier pour chaque nom, le plan liste chaque déplacement et passe
par la validation du support, comme tout plan. Seuls des déplacements partent
ensuite vers l'ordinateur, qui revérifie tout avant d'agir (voir
`apps/mac/Sources/Rangement.swift`) et garde le journal pour l'annulation.
"""

from __future__ import annotations

import asyncio
import json
import re
from collections.abc import Awaitable, Callable

from .sessions import Refused, Session

FOLDERS = {"documents": "Documents", "downloads": "Téléchargements", "desktop": "Bureau"}
MAX_FILES = 200
MAX_NAME = 255
MAX_CATEGORIES = 12
EXECUTE_TIMEOUT_S = 120.0

# Dossiers proposés d'office ; Holo peut en nommer d'autres s'ils restent sûrs.
CATEGORIES = ["Factures", "Contrats", "Relevés", "Impôts", "Images", "Vidéos", "Musique",
              "Installateurs", "Archives", "Tableaux", "Présentations", "Textes", "PDF"]

_BY_EXT = {
    "Images": {"jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp", "raw", "svg"},
    "Vidéos": {"mov", "mp4", "m4v", "avi", "mkv", "wmv"},
    "Musique": {"mp3", "m4a", "aac", "wav", "flac", "aiff", "ogg"},
    "Installateurs": {"dmg", "pkg", "mpkg", "exe", "msi"},
    "Archives": {"zip", "rar", "7z", "gz", "tgz", "bz2", "xz", "tar"},
    "Tableaux": {"xls", "xlsx", "numbers", "csv", "ods"},
    "Présentations": {"ppt", "pptx", "key", "odp"},
    "Textes": {"doc", "docx", "pages", "odt", "rtf", "txt", "md"},
}
_BY_WORD = [
    ("Factures", re.compile(r"factur|invoice|avoir", re.I)),
    ("Contrats", re.compile(r"contrat|bail|avenant|contract", re.I)),
    ("Impôts", re.compile(r"imp[oô]t|avis[ _-]?d[ _-]?imposition|taxe", re.I)),
    ("Relevés", re.compile(r"relev[eé]|rib\b|bulletin|fiche[ _-]?de[ _-]?paie", re.I)),
]

_SAFE_CATEGORY = re.compile(r"[0-9A-Za-zÀ-ÖØ-öø-ÿ][0-9A-Za-zÀ-ÖØ-öø-ÿ '’&_-]{0,39}")

PROMPT = (
    "Tu ranges un dossier de l'ordinateur. Tu ne vois que des noms de fichiers, "
    "jamais leur contenu. Pour chaque nom, choisis un dossier de rangement parmi : "
    + ", ".join(CATEGORIES) + ". Tu peux proposer un autre nom de dossier court s'il "
    "est plus clair (lettres, chiffres, espaces). Laisse de côté un fichier dont le "
    "nom ne dit rien. Réponds seulement en JSON : "
    '{"moves": {"nom exact du fichier": "Dossier"}}.'
)


class TidyError(ValueError):
    pass


def safe_name(name) -> bool:
    """Un nom de fichier simple, à la racine du dossier choisi."""
    return (isinstance(name, str) and 0 < len(name) <= MAX_NAME and "/" not in name
            and "\\" not in name and "\x00" not in name and not name.startswith(".")
            and name.strip() == name and name not in (".", ".."))


def safe_category(name) -> bool:
    return isinstance(name, str) and bool(_SAFE_CATEGORY.fullmatch(name)) and name.strip() == name


def parse_request(raw) -> dict:
    """`help_request.tidy` : `{"folder": "documents", "files": ["…"]}`."""
    if not isinstance(raw, dict):
        raise TidyError("Demande de rangement illisible.")
    folder = raw.get("folder")
    if folder not in FOLDERS:
        raise TidyError("Seuls Documents, Téléchargements et Bureau peuvent être rangés.")
    files = raw.get("files")
    if not isinstance(files, list) or len(files) > MAX_FILES:
        raise TidyError(f"{MAX_FILES} fichiers au plus.")
    if not all(safe_name(f) for f in files) or len(set(files)) != len(files):
        raise TidyError("Nom de fichier refusé.")
    existing = raw.get("folders") or []
    if not isinstance(existing, list):
        existing = []
    return {"folder": folder, "files": files,
            "folders": [d for d in existing if safe_category(d)][:50]}


def guess(name: str) -> str | None:
    """Rangement sans Holo, d'après le nom seul."""
    for category, pattern in _BY_WORD:
        if pattern.search(name):
            return category
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    for category, exts in _BY_EXT.items():
        if ext in exts:
            return category
    return "PDF" if ext == "pdf" else None


def build_moves(files: list[str], proposal) -> list[dict]:
    """Ne garde que les déplacements sûrs : noms reçus, dossiers au nom simple.
    Un fichier sans dossier proposé (ou mal proposé) reste où il est."""
    mapping = proposal if isinstance(proposal, dict) else {}
    moves, categories = [], []
    for name in files:
        target = mapping.get(name)
        if not safe_category(target):
            continue
        if target not in categories:
            if len(categories) >= MAX_CATEGORIES:
                continue
            categories.append(target)
        moves.append({"from": name, "to": target})
    return moves


def fallback(files: list[str]) -> dict:
    return {f: g for f in files if (g := guess(f))}


def plan_steps(moves: list[dict], folder: str) -> list[str]:
    where = FOLDERS[folder]
    return [f"Déplacer « {m['from']} » dans {where}/{m['to']}" for m in moves]


def _parse_holo(raw: str):
    m = re.search(r"\{.*\}", raw or "", re.S)
    data = json.loads(m.group(0)) if m else {}
    moves = data.get("moves") if isinstance(data, dict) else None
    return moves if isinstance(moves, dict) else None


async def ask_holo(session: Session, files: list[str], folders: list[str], note: str) -> dict:
    """Noms de fichiers seulement : ni image de l'écran, ni contenu."""
    from papai_tools import MODEL, TEMPERATURE
    from .agent import client

    listing = "\n".join(files)
    user = f"Demande : « {session.task} »\nFichiers :\n{listing}"
    if folders:
        user += "\nDossiers déjà présents : " + ", ".join(folders)
    if note:
        user += f"\nPrécision du support : {note}"
    resp = await asyncio.to_thread(
        client.chat.completions.create, model=MODEL, temperature=TEMPERATURE,
        messages=[{"role": "system", "content": PROMPT}, {"role": "user", "content": user}],
    )
    session.record_usage(getattr(resp, "usage", None))
    return _parse_holo(resp.choices[0].message.content or "")


async def propose(session: Session, tidy: dict, note: str = "", ask=None) -> list[dict]:
    ask = ask or ask_holo
    try:
        proposal = await ask(session, tidy["files"], tidy["folders"], note)
    except Exception as e:  # noqa: BLE001 — Holo indisponible : rangement d'après les extensions
        session.log("tidy_holo_failed", error=type(e).__name__)
        proposal = None
    moves = build_moves(tidy["files"], proposal) if proposal else []
    if not moves:
        moves = build_moves(tidy["files"], fallback(tidy["files"]))
    return moves


def summary(result: dict | None, folder: str) -> str:
    where = FOLDERS[folder]
    if not result:
        return f"Le rangement de {where} n'a pas pu se faire. Rien n'a été déplacé sans votre accord."
    moved = int(result.get("moved") or 0)
    if moved == 0:
        return f"Aucun fichier n'a été déplacé dans {where}."
    s = "s" if moved > 1 else ""
    text = f"{moved} fichier{s} rangé{s} dans {where}. Rien n'a été supprimé."
    renamed = int(result.get("renamed") or 0)
    if renamed:
        text += f" {renamed} renommé{'s' if renamed > 1 else ''} avec « (2) » pour ne rien écraser."
    return text + " « Annuler le rangement » remet tout comme avant."


async def run(session: Session, link, broadcast: Callable[[dict], Awaitable[None]],
              check_request: Callable[..., Awaitable[bool]], raw, ask=None) -> None:
    """Même cycle qu'une demande : plan, validation du support, exécution."""
    notes: list[str] = []
    try:
        try:
            tidy = parse_request(raw)
        except TidyError as e:
            session.log("tidy_refused", reason=str(e))
            session.finish(str(e))
            await broadcast({"type": "answer", "content": str(e)})
            return
        if await check_request(session, session.task, "request"):
            return
        session.log("tidy", folder=tidy["folder"], files=len(tidy["files"]))
        while True:
            await broadcast(session.status())
            moves = await propose(session, tidy, " ; ".join(notes), ask)
            if not session.is_open:
                return
            if not moves:
                text = f"Rien à ranger dans {FOLDERS[tidy['folder']]} : aucun nom de fichier ne suggère de dossier."
                session.finish(text)
                await broadcast({"type": "answer", "content": text})
                return
            steps = plan_steps(moves, tidy["folder"])
            if await check_request(session, "\n".join([session.task, *notes, *steps]), "plan"):
                return
            decision = session.propose_plan(steps)
            await broadcast(session.status())
            print(f"[session {session.id}] rangement proposé : {len(moves)} déplacement(s)")
            result = await decision
            if result is None or not session.is_open:
                return
            kind, note = result
            if kind == "approve":
                break
            if kind == "refuse":
                session.stop(by="proche")
                await broadcast(session.status())
                return
            notes.append(note)
        await broadcast(session.status())
        data = await link._request({"type": "tidy_execute", "folder": tidy["folder"], "moves": moves},
                                   timeout=EXECUTE_TIMEOUT_S)
        if not session.is_open:
            return
        if data is None or data.get("refused"):
            session.log("tidy_refused", reason=str((data or {}).get("result", "sans réponse"))[:200])
            session.stop(by="pont")
            await broadcast(session.status())
            return
        session.log("tidy_done", moved=int(data.get("moved") or 0), renamed=int(data.get("renamed") or 0),
                    skipped=int(data.get("skipped") or 0))
        text = summary(data, tidy["folder"])
        session.finish(text)
        await broadcast({"type": "answer", "content": text})
    except Refused as e:
        session.log("refused", reason=str(e))
    except asyncio.CancelledError:
        session.stop(by="annulation")
        raise
    finally:
        await broadcast(session.status())
