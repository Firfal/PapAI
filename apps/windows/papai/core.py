"""Ce que PapAI fait sur la machine : regarder, agir, et s'arrêter.

Portage Windows de `apps/mac/Sources/Core.swift`. Mêmes règles, mêmes messages,
mêmes refus — seules les API changent : mss au lieu de ScreenCaptureKit,
pyautogui au lieu de CGEvent, les dossiers connus de Windows au lieu de
FileManager.
"""

from __future__ import annotations

import base64
import ctypes
import io
import os
import threading
import time
from ctypes import wintypes
from pathlib import Path

import mss
import pyautogui
from PIL import Image, ImageDraw

# Largeur de la capture envoyée : assez pour viser juste, assez petit pour
# ne pas gonfler le contexte du modèle.
SEND_WIDTH = 1280

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.25


class StopGate:
    """Le verrou d'arrêt, lu avant chaque action.

    Il est local et vaut même hors ligne : un arrêt qui serait seulement un
    message envoyé au serveur ne serait pas une garantie.
    """

    def __init__(self) -> None:
        self._stopped = threading.Event()

    def raise_stop(self) -> None:
        self._stopped.set()

    def reset(self) -> None:
        self._stopped.clear()

    @property
    def is_stopped(self) -> bool:
        return self._stopped.is_set()


class Stopped(Exception):
    """Arrêt demandé : l'action n'a pas eu lieu."""


class ProtectedZone(Exception):
    """L'action visait la fenêtre PapAI, que l'agent ne peut pas toucher."""


# --------------------------------------------------------------- l'écran


class Screen:
    """Le moniteur principal, et lui seul."""

    def __init__(self) -> None:
        self.sct = mss.mss()
        physique = self.sct.monitors[1:]
        # L'écran principal n'est pas toujours monitors[1] : c'est celui qui
        # porte l'origine des coordonnées, donc le seul où un clic tombe juste.
        self.index = next(
            (i for i, m in enumerate(physique, start=1) if m.get("is_primary")), 1
        )
        m = self.sct.monitors[self.index]
        self.width, self.height = m["width"], m["height"]
        self.origin_x, self.origin_y = m["left"], m["top"]
        self.monitor = m
        self.multiple = len(physique) > 1

    def grab(self, masque: tuple | None = None) -> tuple[str, int, int]:
        """Rend (png_b64, largeur, hauteur). `masque` efface la fenêtre PapAI.

        Sans ce masque, le modèle prend l'interface pour un élément du bureau
        et finit par cliquer dessus — observé : il a fermé sa propre fenêtre
        d'arrêt.
        """
        brut = self.sct.grab(self.monitor)
        img = Image.frombytes("RGB", brut.size, brut.bgra, "raw", "BGRX")

        if masque is not None:
            x0, y0, x1, y1 = masque
            boite = (
                max(0, x0 - self.origin_x), max(0, y0 - self.origin_y),
                min(img.width, x1 - self.origin_x), min(img.height, y1 - self.origin_y),
            )
            if boite[2] > boite[0] and boite[3] > boite[1]:
                ImageDraw.Draw(img).rectangle(boite, fill=(24, 24, 24))

        if img.width > SEND_WIDTH:
            ratio = SEND_WIDTH / img.width
            img = img.resize((SEND_WIDTH, int(img.height * ratio)), Image.LANCZOS)

        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return base64.b64encode(buf.getvalue()).decode(), self.width, self.height

    def to_pixels(self, x: float, y: float) -> tuple[int, int]:
        """[0, 1000] normalisé -> pixels écran, comme le fait le Mac."""
        return (
            self.origin_x + round(x / 1000 * self.width),
            self.origin_y + round(y / 1000 * self.height),
        )


def window_rect(titre: str) -> tuple | None:
    """Où se trouve notre propre fenêtre, pour l'exclure des captures et des clics."""
    hwnd = ctypes.windll.user32.FindWindowW(None, titre)
    if not hwnd:
        return None
    r = wintypes.RECT()
    if not ctypes.windll.user32.GetWindowRect(hwnd, ctypes.byref(r)):
        return None
    return (r.left, r.top, r.right, r.bottom)


# -------------------------------------------------------------- les actions


def run_action(nom: str, args: dict, screen: Screen, gate: StopGate,
               protege: tuple | None = None) -> str:
    """Joue une action. Le verrou est consulté juste avant de bouger."""
    if gate.is_stopped:
        raise Stopped()

    def viser(x, y) -> tuple[int, int]:
        px, py = screen.to_pixels(float(x or 0), float(y or 0))
        if protege is not None:
            a, b, c, d = protege
            if a <= px <= c and b <= py <= d:
                raise ProtectedZone()
        return px, py

    if nom in ("click", "double_click"):
        px, py = viser(args.get("x"), args.get("y"))
        pyautogui.moveTo(px, py, duration=0.2)
        if gate.is_stopped:
            raise Stopped()
        pyautogui.click(clicks=2 if nom == "double_click" else 1)
        return f"{nom} à ({px}, {py})"

    if nom == "type_text":
        texte = str(args.get("text") or "")
        pyautogui.write(texte, interval=0.03)
        return f"texte tapé : {texte!r}"

    if nom == "press_key":
        touches = [k.strip().lower() for k in str(args.get("keys") or "").split("+") if k.strip()]
        if not touches:
            return "aucune touche"
        # Le Mac reçoit « cmd+… » ; sur Windows l'équivalent est « ctrl+… ».
        touches = ["ctrl" if k in ("cmd", "command", "meta") else k for k in touches]
        if len(touches) > 1:
            pyautogui.hotkey(*touches)
        else:
            pyautogui.press(touches[0])
        return f"touche : {'+'.join(touches)}"

    if nom == "scroll":
        px, py = viser(args.get("x"), args.get("y"))
        pyautogui.scroll(-500 if args.get("direction") == "down" else 500, x=px, y=py)
        return f"scroll {args.get('direction')}"

    if nom == "wait":
        time.sleep(2)
        return "attente 2 s"

    return f"action inconnue : {nom}"


def describe_action(nom: str, args: dict) -> str:
    """Ce que la personne aidée lit pendant que ça travaille.

    Jamais le nom de l'outil du modèle : une phrase.
    """
    cible = str(args.get("element") or "").strip()
    if nom in ("click", "double_click"):
        verbe = "Double-clic" if nom == "double_click" else "Clic"
        return f"{verbe} sur {cible}" if cible else f"{verbe} sur l'écran"
    if nom == "type_text":
        t = str(args.get("text") or "").strip()
        return f"Saisie de « {t} »" if t else "Saisie au clavier"
    if nom == "press_key":
        k = str(args.get("keys") or "").strip()
        return f"Touche {k}" if k else "Appui sur une touche"
    if nom == "scroll":
        return "Défilement de la page"
    if nom == "wait":
        return "Un instant…"
    return "Recherche en cours…"


# ----------------------------------------------------------- les raccourcis

# Dossiers personnels par identifiant officiel Windows. Jamais « C:\\Users\\… » :
# ce chemin casse sous un autre compte, et quand OneDrive redirige le dossier.
KNOWN_FOLDERS = {
    "downloads": ("Téléchargements", "{374DE290-123F-4565-9164-39C4925E467B}"),
    "pictures": ("Images", "{33E28130-4E1E-4676-835A-98395C3BC3BB}"),
    "documents": ("Documents", "{FDD39AD0-238F-46AF-ADB4-6C85480369C7}"),
    "desktop": ("Bureau", "{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}"),
    "videos": ("Vidéos", "{18989B1D-99B5-455B-841C-AB7C74E4DDFC}"),
    "music": ("Musique", "{4BD8D571-6D19-48D3-BE97-422220080E43}"),
}


def known_folder(nom: str) -> Path | None:
    """Demande à Windows où se trouve réellement ce dossier, maintenant."""
    entree = KNOWN_FOLDERS.get((nom or "").strip().lower())
    if entree is None:
        return None

    class GUID(ctypes.Structure):
        _fields_ = [("a", wintypes.DWORD), ("b", wintypes.WORD),
                    ("c", wintypes.WORD), ("d", ctypes.c_byte * 8)]

    g = GUID()
    if ctypes.windll.ole32.CLSIDFromString(entree[1], ctypes.byref(g)) != 0:
        return None
    sortie = ctypes.c_wchar_p()
    if ctypes.windll.shell32.SHGetKnownFolderPath(
        ctypes.byref(g), 0, None, ctypes.byref(sortie)
    ) != 0:
        return None
    try:
        return Path(sortie.value)
    finally:
        ctypes.windll.ole32.CoTaskMemFree(sortie)


def open_shortcut(shortcut: dict | None) -> tuple[bool, str]:
    """Ouvre le dossier enregistré d'un automatisme.

    Le modèle ne fournit jamais de chemin : un dossier connu du système, et au
    plus un nom de sous-dossier. Si le dossier n'existe plus, on n'invente rien.
    """
    sc = shortcut or {}
    base = known_folder(str(sc.get("folder") or ""))
    if base is None:
        return False, "Aucun raccourci enregistré."

    sous = str(sc.get("subfolder") or "").strip()
    if sous:
        if any(c in sous for c in '\\/:*?"<>|') or sous in (".", ".."):
            return False, "Nom de dossier invalide."
        base = base / sous

    if not base.is_dir():
        quoi = f"« {sous} »" if sous else "Ce dossier"
        return False, f"{quoi} n'existe plus sur cet ordinateur."

    try:
        os.startfile(str(base))  # noqa: S606 — un dossier, ouvert dans l'Explorateur
    except OSError as e:
        return False, str(e)
    return True, str(base)
