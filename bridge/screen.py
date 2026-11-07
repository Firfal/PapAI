"""Capture d'écran et actionneurs, sur le PC de la personne aidée.

Partagé par le pont (bridge.py) et par le harnais de visée (holo_agent.py).
Aucune dépendance au réseau ni au modèle : ce module ne sait qu'observer et agir.
"""

from __future__ import annotations

import base64
import io
import os
import time
from pathlib import Path
from typing import Callable

import mss
import pyautogui
from PIL import Image, ImageDraw

FRAMES_DIR = Path(__file__).resolve().parent.parent / "frames"

# Largeur de la capture envoyée au modèle : économise des tokens sans dégrader
# la visée (mesuré : erreur de 1 à 7 px sur des cibles de barre des tâches).
SEND_WIDTH = 1280

pyautogui.FAILSAFE = True   # souris dans le coin haut-gauche = arrêt immédiat
pyautogui.PAUSE = 0.3


class Screen:
    """Un seul moniteur, choisi explicitement."""

    def __init__(self, index: int | None = None) -> None:
        self.sct = mss.mss()
        physical = self.sct.monitors[1:]  # [0] = bureau virtuel, pas un écran réel

        if index is None:
            env = os.environ.get("HOLO_MONITOR", "").strip()
            index = int(env) if env.isdigit() else None

        if index is None:
            # L'écran principal Windows n'est pas toujours monitors[1] : c'est lui
            # qui porte l'origine (0, 0) de pyautogui, donc le seul sur lequel les
            # coordonnées de clic sont fiables.
            index = next(
                (i for i, m in enumerate(physical, start=1) if m.get("is_primary")), 1
            )

        if not 1 <= index <= len(physical):
            raise SystemExit(
                f"HOLO_MONITOR={index} invalide : {len(physical)} écran(s) détecté(s)."
            )

        self.index = index
        self.monitor = self.sct.monitors[index]
        self.width = self.monitor["width"]
        self.height = self.monitor["height"]
        self.origin_x = self.monitor["left"]
        self.origin_y = self.monitor["top"]
        self.warnings: list[str] = []

        if len(physical) > 1:
            self.warnings.append(
                f"{len(physical)} écrans détectés — l'agent ne voit que l'écran {index} "
                f"({self.width}x{self.height} en {self.origin_x},{self.origin_y}). "
                f"Forcer avec HOLO_MONITOR=<n>."
            )
            if not self.monitor.get("is_primary", True):
                self.warnings.append(
                    "Cet écran n'est pas l'écran principal Windows : clics et failsafe "
                    "risquent d'être décalés."
                )

    def grab(self, frame_id: str, save: bool = False, mask: tuple | None = None) -> str:
        """`mask` : rectangle en pixels écran absolus, peint avant l'envoi.

        Sert à retirer la fenêtre CarePilot de ce que voit le modèle. Sans ça,
        il la prend pour un élément du bureau et finit par cliquer dessus —
        observé en conditions réelles : il a fermé sa propre fenêtre d'arrêt.
        """
        raw = self.sct.grab(self.monitor)
        img = Image.frombytes("RGB", raw.size, raw.bgra, "raw", "BGRX")

        if mask is not None:
            x0, y0, x1, y1 = mask
            box = (
                max(0, x0 - self.origin_x),
                max(0, y0 - self.origin_y),
                min(img.width, x1 - self.origin_x),
                min(img.height, y1 - self.origin_y),
            )
            if box[2] > box[0] and box[3] > box[1]:
                ImageDraw.Draw(img).rectangle(box, fill=(24, 24, 24))

        if img.width > SEND_WIDTH:
            ratio = SEND_WIDTH / img.width
            img = img.resize((SEND_WIDTH, int(img.height * ratio)), Image.LANCZOS)
        if save:
            FRAMES_DIR.mkdir(exist_ok=True)
            img.save(FRAMES_DIR / f"{frame_id}.png", format="PNG")
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return base64.b64encode(buf.getvalue()).decode()

    def to_pixels(self, x: int, y: int) -> tuple[int, int]:
        """[0,1000] normalisé -> pixels écran.

        Le ratio d'aspect est conservé au redimensionnement, donc la projection
        sur les dimensions du moniteur est directe.
        """
        return (
            self.origin_x + round(x / 1000 * self.width),
            self.origin_y + round(y / 1000 * self.height),
        )


class ProtectedZone(Exception):
    """Action visant l'interface de sécurité : refusée, sans arrêter la session."""


def execute_action(
    screen: Screen,
    name: str,
    args: dict,
    stop_check: Callable[[], bool] | None = None,
    protected: tuple | None = None,
) -> str:
    """Joue une action sur la machine.

    `stop_check` est consulté juste avant de bouger quoi que ce soit : c'est la
    garantie d'arrêt, et elle est locale. Elle ne dépend ni du réseau ni du
    serveur, qui peuvent être lents ou morts au moment où la personne aidée
    appuie sur « Arrêter ».
    """
    if stop_check is not None and stop_check():
        raise PermissionError("Arrêt demandé par la personne aidée.")

    def guard(px: int, py: int) -> None:
        """La fenêtre CarePilot n'est pas cliquable par l'agent.

        Le bouton ARRÊTER et la croix de fermeture appartiennent à la personne
        aidée. Masquer la fenêtre dans la capture ne suffit pas : le refus doit
        être appliqué ici, sur des coordonnées, quoi que le modèle ait cru voir.
        """
        if protected is None:
            return
        x0, y0, x1, y1 = protected
        if x0 <= px <= x1 and y0 <= py <= y1:
            raise ProtectedZone(
                "Action refusée : cette zone appartient à la fenêtre CarePilot, "
                "que seule la personne aidée peut manipuler."
            )

    if name in ("click", "double_click"):
        px, py = screen.to_pixels(args["x"], args["y"])
        guard(px, py)
        pyautogui.moveTo(px, py, duration=0.2)
        pyautogui.click(clicks=2 if name == "double_click" else 1)
        return f"{name} à ({px}, {py}) sur « {args.get('element', '')} »"

    if name == "type_text":
        pyautogui.write(args["text"], interval=0.03)
        return f"texte tapé : {args['text']!r}"

    if name == "press_key":
        keys = [k.strip().lower() for k in args["keys"].split("+")]
        if len(keys) > 1:
            pyautogui.hotkey(*keys)
        else:
            pyautogui.press(keys[0])
        return f"touche : {args['keys']}"

    if name == "scroll":
        px, py = screen.to_pixels(args["x"], args["y"])
        guard(px, py)
        pyautogui.scroll(-500 if args["direction"] == "down" else 500, x=px, y=py)
        return f"scroll {args['direction']}"

    if name == "wait":
        time.sleep(2)
        return "attente 2 s"

    return f"outil inconnu : {name}"
