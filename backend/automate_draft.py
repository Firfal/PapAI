"""Brouillon d'automate à partir d'une source fournie par le support.

Deux sources, un seul résultat :
  - un document (tutoriel en texte : .txt, .md, ou le texte d'un PDF extrait
    sur le poste du support) ;
  - un enregistrement fait par le support sur son poste : quelques captures
    clés (5 au plus, Holo n'en accepte pas davantage) et, s'il a parlé, la
    transcription de sa voix.

Holo en tire l'INTENTION, jamais une suite de clics : un objectif, des étapes
décrites et le système pour lequel le tutoriel est écrit. C'est ce qui permet
de le rejouer ailleurs, Holo regardant l'écran. Le brouillon n'est écrit nulle
part : il pré-remplit le formulaire, et rien n'est actif chez la personne
aidée tant que le support ne l'a pas créé (= validé).
"""

from __future__ import annotations

import asyncio
import base64
import binascii
import json
import re

from papai_tools import MODEL, TEMPERATURE, make_client

MAX_TEXT = 20_000
MAX_FRAMES = 5
MAX_FRAME_BYTES = 2_000_000
MAX_NARRATION = 4_000

PROMPT = """Tu prépares un « automate » pour PapAI : une tâche informatique qu'un
assistant (Holo) refera plus tard sur l'ordinateur d'une personne peu à l'aise
avec l'informatique, en regardant son écran.

On te donne une source : {source}

Extrais-en l'INTENTION, pas une suite de clics :
- `title` : verbe à l'infinitif, court (« Se connecter au Wi-Fi »).
- `description` : une phrase simple qui dit ce que fait l'automate.
- `goal` : l'objectif donné à Holo, précis et autonome (il ne verra pas la source).
- `steps` : 2 à 6 étapes décrites en français simple, une action par étape,
  avec le repère à l'écran quand c'est utile. Pas de coordonnées, pas de pixels.
- `platforms` : les systèmes pour lesquels la source est valable, parmi "mac"
  et "windows". Si la source ne parle que d'un système, ne mets que celui-là.
- `warning` : vide, ou une phrase courte si la source est ambiguë, dépend d'une
  version précise d'un logiciel, ou demande un mot de passe (PapAI ne retient
  jamais d'identifiant : la personne le tapera elle-même).

Si la source ne contient aucun tutoriel exploitable, renvoie {{"error": "..."}}
avec une phrase qui explique pourquoi.

Réponds UNIQUEMENT par un objet JSON, sans texte autour :
{{"title": "...", "description": "...", "goal": "...", "steps": ["..."], "platforms": ["mac"], "warning": ""}}"""


class DraftError(ValueError):
    pass


_client = None


def _get_client():
    global _client
    if _client is None:
        _client = make_client()
    return _client


def _parse(raw: str) -> dict:
    m = re.search(r"\{.*\}", raw or "", re.S)
    if not m:
        raise DraftError("Holo n'a pas renvoyé de brouillon lisible.")
    try:
        return json.loads(m.group(0))
    except ValueError:
        raise DraftError("Holo n'a pas renvoyé de brouillon lisible.") from None


def build_messages(req: dict) -> list[dict]:
    """Vérifie la demande et prépare les messages pour Holo."""
    kind = str(req.get("kind", "")).strip()
    if kind == "document":
        text = str(req.get("text", "")).strip()
        if len(text) < 20:
            raise DraftError("Le document est vide ou trop court.")
        name = str(req.get("name", "")).strip()[:120]
        source = f"un document{f' (« {name} »)' if name else ''}, ci-dessous."
        return [
            {"role": "system", "content": PROMPT.format(source=source)},
            {"role": "user", "content": text[:MAX_TEXT]},
        ]
    if kind == "recording":
        frames = req.get("frames") or []
        if not isinstance(frames, list) or not frames:
            raise DraftError("L'enregistrement ne contient aucune capture.")
        narration = str(req.get("narration", "")).strip()[:MAX_NARRATION]
        content: list[dict] = [{"type": "text", "text":
            "Captures clés, dans l'ordre." + (f"\n\nCe que le support a dit en le faisant : « {narration} »" if narration else
                                               "\n\nLe support n'a pas commenté l'enregistrement.")}]
        for i, f in enumerate(frames[:MAX_FRAMES], 1):
            b64 = str(f.get("b64", "") if isinstance(f, dict) else f)
            mime = str(f.get("mime", "image/jpeg") if isinstance(f, dict) else "image/jpeg")
            if mime not in ("image/jpeg", "image/png"):
                raise DraftError("Captures : JPEG ou PNG seulement.")
            try:
                data = base64.b64decode(b64, validate=True)
            except (binascii.Error, ValueError):
                raise DraftError(f"Capture {i} illisible.") from None
            if not data or len(data) > MAX_FRAME_BYTES:
                raise DraftError(f"Capture {i} vide ou trop lourde.")
            content.append({"type": "text", "text": f"\nCapture {i} :"})
            content.append({"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}})
        source = ("un enregistrement d'écran fait par le support sur son propre ordinateur : "
                  "des captures clés et sa narration éventuelle.")
        return [{"role": "system", "content": PROMPT.format(source=source)},
                {"role": "user", "content": content}]
    raise DraftError("Source inconnue : document ou enregistrement.")


def clean(data: dict) -> dict:
    """Ne garde que des champs sûrs, de la bonne forme."""
    if data.get("error") and not data.get("steps"):
        raise DraftError(str(data["error"])[:300])
    steps = data.get("steps") if isinstance(data.get("steps"), list) else []
    out_steps = []
    for s in steps:
        if isinstance(s, dict):
            s = s.get("instruction", "")
        s = str(s or "").strip()
        if s:
            out_steps.append(s[:300])
        if len(out_steps) == 6:
            break
    if not out_steps:
        raise DraftError("Aucune étape exploitable dans la source.")
    platforms = [p for p in (data.get("platforms") or []) if p in ("mac", "windows")] or ["mac", "windows"]
    title = str(data.get("title", "")).strip()[:120] or "Nouvel automate"
    return {
        "title": title,
        "description": str(data.get("description", "")).strip()[:600],
        "goal": str(data.get("goal", "")).strip()[:300] or title,
        "steps": out_steps,
        "platforms": sorted(set(platforms)),
        "warning": str(data.get("warning", "")).strip()[:300],
    }


async def draft(req: dict) -> dict:
    """Appelle Holo (consomme la clé H). Le brouillon n'est écrit nulle part."""
    messages = build_messages(req)
    resp = await asyncio.to_thread(
        _get_client().chat.completions.create,
        model=MODEL, messages=messages, temperature=TEMPERATURE,
    )
    return clean(_parse(resp.choices[0].message.content or ""))
