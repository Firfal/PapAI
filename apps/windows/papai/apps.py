"""Les applications de la personne, trouvées dans le menu Démarrer.

L'app Mac affiche six applications par identifiant de paquet (Mail, Photos,
Safari, FaceTime, Finder, Calendrier). Windows n'a pas d'équivalent stable :
on cherche dans les raccourcis du menu Démarrer, ce que la personne voit
elle-même. Repris du prototype (`archive/windows-7-nov`), avec les icônes.
"""

from __future__ import annotations

import base64
import io
import os
import sys
from pathlib import Path

# Six entrées, dans l'ordre du Mac.
CANDIDATS = [
    ("Mail", ("outlook", "courrier", "mail", "thunderbird")),
    ("Photos", ("photos",)),
    ("Internet", ("microsoft edge", "google chrome", "firefox", "opera")),
    ("Visio", ("whatsapp", "skype", "zoom", "teams")),
    ("Explorateur", ("explorateur de fichiers", "file explorer", "explorer")),
    ("Calendrier", ("calendrier", "calendar")),
]

# Un raccourci dont le nom contient l'un de ces mots n'est jamais l'application :
# sans ce filtre, « Zoom » tombe sur « Uninstall Zoom Workplace ».
EXCLUS = (
    "uninstall", "désinstall", "desinstall", "remove", "repair", "réparer",
    "readme", "lisez-moi", "help", "aide", "documentation", "licence", "license",
    "settings", "paramètres", "config", "manager", "updater", "mise à jour",
)


def menus() -> tuple[Path, ...]:
    out = []
    for var in ("APPDATA", "PROGRAMDATA"):
        v = os.environ.get(var)
        if v:
            out.append(Path(v) / "Microsoft/Windows/Start Menu/Programs")
    return tuple(out)


def match(noms: list[tuple[str, str]]) -> list[dict]:
    """(nom en minuscules, chemin) -> [{label, path}] dans l'ordre de CANDIDATS.
    Un nom qui EST le motif gagne contre un nom qui le contient."""
    trouves: dict[str, tuple[int, str]] = {}
    for nom, chemin in noms:
        if any(mot in nom for mot in EXCLUS):
            continue
        for libelle, motifs in CANDIDATS:
            for rang, motif in enumerate(motifs):
                if nom == motif:
                    score = 0
                elif nom.startswith(motif + " ") or nom.endswith(" " + motif):
                    score = 1
                elif f" {motif} " in f" {nom} ":
                    score = 2
                else:
                    continue
                score = score * 10 + rang
                if libelle not in trouves or score < trouves[libelle][0]:
                    trouves[libelle] = (score, chemin)
                break
    return [{"label": l, "path": trouves[l][1]} for l, _ in CANDIDATS if l in trouves]


def installed() -> list[dict]:
    noms: list[tuple[str, str]] = []
    for racine in menus():
        if not racine.is_dir():
            continue
        try:
            noms += [(p.stem.lower(), str(p)) for p in racine.rglob("*.lnk")]
        except OSError:
            continue
    apps = match(noms)
    for a in apps:
        a["icon"] = icon_data_url(a["path"])
    return apps


def icon_data_url(path: str) -> str | None:
    """Icône du raccourci en PNG (data URL), comme NSWorkspace.icon sur le Mac.
    None si Windows ne la donne pas : l'interface garde alors l'initiale."""
    if sys.platform != "win32":
        return None
    try:
        import ctypes
        from ctypes import wintypes

        from PIL import Image

        class SHFILEINFOW(ctypes.Structure):
            _fields_ = [("hIcon", wintypes.HICON), ("iIcon", ctypes.c_int),
                        ("dwAttributes", wintypes.DWORD), ("szDisplayName", wintypes.WCHAR * 260),
                        ("szTypeName", wintypes.WCHAR * 80)]

        class BITMAPINFOHEADER(ctypes.Structure):
            _fields_ = [("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG),
                        ("biHeight", wintypes.LONG), ("biPlanes", wintypes.WORD),
                        ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                        ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", wintypes.LONG),
                        ("biYPelsPerMeter", wintypes.LONG), ("biClrUsed", wintypes.DWORD),
                        ("biClrImportant", wintypes.DWORD)]

        shell32, user32, gdi32 = ctypes.windll.shell32, ctypes.windll.user32, ctypes.windll.gdi32
        info = SHFILEINFOW()
        if not shell32.SHGetFileInfoW(path, 0, ctypes.byref(info), ctypes.sizeof(info), 0x100):
            return None  # SHGFI_ICON (grande icône, 32 px)
        size = 32
        hdc = user32.GetDC(None)
        mem = gdi32.CreateCompatibleDC(hdc)
        bmi = BITMAPINFOHEADER(ctypes.sizeof(BITMAPINFOHEADER), size, -size, 1, 32, 0, 0, 0, 0, 0, 0)
        bits = ctypes.c_void_p()
        dib = gdi32.CreateDIBSection(hdc, ctypes.byref(bmi), 0, ctypes.byref(bits), None, 0)
        old = gdi32.SelectObject(mem, dib)
        user32.DrawIconEx(mem, 0, 0, info.hIcon, size, size, 0, None, 3)
        raw = ctypes.string_at(bits, size * size * 4)
        gdi32.SelectObject(mem, old)
        gdi32.DeleteObject(dib)
        gdi32.DeleteDC(mem)
        user32.ReleaseDC(None, hdc)
        user32.DestroyIcon(info.hIcon)
        img = Image.frombuffer("RGBA", (size, size), raw, "raw", "BGRA", 0, 1)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()
    except Exception:  # noqa: BLE001
        return None


def launch(path: str) -> tuple[bool, str]:
    """N'ouvre qu'un raccourci du menu Démarrer, jamais un exécutable quelconque."""
    cible = Path(path or "")
    if cible.suffix.lower() != ".lnk" or not cible.is_file():
        return False, "Cette application n'est plus installée."
    if not any(str(cible).lower().startswith(str(r).lower()) for r in menus()):
        return False, "Raccourci hors du menu Démarrer."
    try:
        os.startfile(str(cible))  # noqa: S606 — raccourci du menu Démarrer
    except OSError as e:
        return False, str(e)
    return True, str(cible)
