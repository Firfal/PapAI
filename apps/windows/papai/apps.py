"""Applications connues, résolues dans Program Files ou Windows, jamais par .lnk."""

from __future__ import annotations

import base64
import io
import os
import subprocess
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
    if sys.platform != 'win32':
        return []
    out = []
    for app_id, label, relative in CATALOG:
        path = program_path(relative)
        if path:
            out.append({"id": app_id, "path": app_id, "label": label,
                        "executable": str(path), "icon": icon_data_url(str(path))})
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CLASSES_ROOT, 'ms-photos'):
            out.insert(0, {"id": "photos", "path": "photos", "label": "Photos", "icon": None})
    except OSError:
        pass
    return out


# Identifiants fermés, jamais un chemin fourni par une tuile ou un fichier .lnk.
CATALOG = (
    ('outlook', 'Mail', 'Microsoft Office/root/Office16/OUTLOOK.EXE'),
    ('edge', 'Microsoft Edge', 'Microsoft/Edge/Application/msedge.exe'),
    ('chrome', 'Google Chrome', 'Google/Chrome/Application/chrome.exe'),
    ('firefox', 'Firefox', 'Mozilla Firefox/firefox.exe'),
    ('thunderbird', 'Mail', 'Mozilla Thunderbird/thunderbird.exe'),
    ('word', 'Word', 'Microsoft Office/root/Office16/WINWORD.EXE'),
    ('excel', 'Excel', 'Microsoft Office/root/Office16/EXCEL.EXE'),
    ('explorer', 'Explorateur', '@windows/explorer.exe'),
)


def windows_directory() -> Path:
    import ctypes
    buf = ctypes.create_unicode_buffer(32768)
    if not ctypes.windll.kernel32.GetWindowsDirectoryW(buf, len(buf)):
        raise OSError('Dossier Windows introuvable')
    return Path(buf.value)


def program_path(relative: str) -> Path | None:
    if relative.startswith('@windows/'):
        roots, relative = [windows_directory()], relative.removeprefix('@windows/')
    else:
        roots = [Path(os.environ[v]) for v in ('ProgramW6432', 'ProgramFiles', 'ProgramFiles(x86)') if os.environ.get(v)]
    for root in roots:
        try:
            path = root / relative
            resolved = path.resolve(strict=True)
            if path.is_file() and resolved == root.resolve() / relative:
                return resolved
        except (OSError, RuntimeError):
            continue
    return None


def foreground_executable() -> str | None:
    if sys.platform != 'win32':
        return None
    import ctypes
    from ctypes import wintypes
    user, kernel = ctypes.windll.user32, ctypes.windll.kernel32
    user.GetForegroundWindow.restype = wintypes.HWND
    user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    pid = wintypes.DWORD()
    user.GetWindowThreadProcessId(user.GetForegroundWindow(), ctypes.byref(pid))
    handle = kernel.OpenProcess(0x1000, False, pid.value)
    if not handle:
        return None
    try:
        buf, n = ctypes.create_unicode_buffer(32768), wintypes.DWORD(32768)
        return buf.value if kernel.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(n)) else None
    finally:
        kernel.CloseHandle(handle)


def foreground_id(catalog: list[dict], active: str | None) -> str | None:
    if not active:
        return None
    for app in catalog:
        if app.get('executable') and os.path.normcase(app['executable']) == os.path.normcase(active):
            return app['id']
    if sys.platform == 'win32' and any(a['id'] == 'photos' for a in catalog):
        try:
            path = Path(active).resolve(strict=True)
            for variable in ('ProgramW6432', 'ProgramFiles'):
                if not os.environ.get(variable):
                    continue
                relative = path.relative_to(Path(os.environ[variable]).resolve() / 'WindowsApps')
                if relative.parts[0].startswith('Microsoft.Windows.Photos_') and path.name.lower() in ('photos.exe', 'microsoft.photos.exe'):
                    return 'photos'
        except (OSError, ValueError, RuntimeError):
            pass
    return None


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
        shell32.SHGetFileInfoW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, ctypes.POINTER(SHFILEINFOW), wintypes.UINT, wintypes.UINT]
        shell32.SHGetFileInfoW.restype = ctypes.c_size_t
        user32.GetDC.argtypes = [wintypes.HWND]
        user32.GetDC.restype = wintypes.HDC
        user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
        user32.DestroyIcon.argtypes = [wintypes.HICON]
        user32.DrawIconEx.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int, wintypes.HICON,
                                     ctypes.c_int, ctypes.c_int, wintypes.UINT, wintypes.HBRUSH, wintypes.UINT]
        gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
        gdi32.CreateCompatibleDC.restype = wintypes.HDC
        gdi32.CreateDIBSection.argtypes = [wintypes.HDC, ctypes.c_void_p, wintypes.UINT,
                                         ctypes.POINTER(ctypes.c_void_p), wintypes.HANDLE, wintypes.DWORD]
        gdi32.CreateDIBSection.restype = wintypes.HANDLE
        gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HANDLE]
        gdi32.SelectObject.restype = wintypes.HANDLE
        gdi32.DeleteObject.argtypes = [wintypes.HANDLE]
        gdi32.DeleteDC.argtypes = [wintypes.HDC]
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
    """Résout de nouveau un identifiant du catalogue avant chaque ouverture."""
    app = next((a for a in installed() if a['id'] == path), None)
    if app is None:
        return False, "Cette application n'est pas disponible sur cet ordinateur."
    try:
        if app['id'] == 'photos':
            os.startfile('ms-photos:')
        else:
            subprocess.Popen([app['executable']], shell=False)
    except OSError:
        return False, "Je n'arrive pas à ouvrir cette application."
    return True, app['label']
