"""Accueil local : catalogue d'applications, dossiers ordinaires et compteurs privés."""

from __future__ import annotations

import json
import os
import subprocess
import threading
import uuid
from pathlib import Path

from . import apps, settings
from .core import known_folder

FORBIDDEN = {'.exe', '.bat', '.cmd', '.ps1', '.lnk', '.vbs', '.msi', '.scr',
             '.com', '.pif', '.cpl', '.msc', '.hta', '.url', '.appref-ms', '.wsf', '.wsh'}
IMAGES = {'.jpg', '.jpeg', '.png', '.heic', '.webp', '.gif', '.tiff', '.bmp'}
MESSAGE_ID = 'action:new-message'


def valid_folder(value: str | Path, *, reject_links=False) -> Path | None:
    try:
        raw = str(value)
        path = Path(raw)
        if not path.is_absolute() or raw.startswith(('\\\\', '//')) or '\x00' in raw:
            return None
        if any(p.suffix.lower() in FORBIDDEN for p in (path, *path.parents)):
            return None
        if reject_links and any(p.is_symlink() or getattr(p.lstat(), 'st_file_attributes', 0) & 0x400
                                for p in (path, *path.parents)):
            return None
        target = path.resolve(strict=True)
        if str(target).startswith(('\\\\', '//')):
            return None
        if any(p.suffix.lower() in FORBIDDEN for p in (target, *target.parents)):
            return None
        return target if target.is_dir() else None
    except (OSError, ValueError, RuntimeError):
        return None


def open_folder(path: str | Path) -> bool:
    target = valid_folder(path)
    if target is None or os.name != 'nt':
        return False
    try:
        subprocess.Popen([str(apps.windows_directory() / 'explorer.exe'), str(target)], shell=False)
        return True
    except OSError:
        return False


def has_photos(folder: Path) -> bool:
    try:
        return any(p.suffix.lower() in IMAGES and p.is_file() for p in folder.iterdir())
    except OSError:
        return False


def open_new_message() -> bool:
    if os.name != 'nt':
        return False
    try:
        os.startfile('mailto:')
        return True
    except OSError:
        return False


class HomeShortcuts:
    def __init__(self, *, storage: Path | None = None, catalog=apps.installed,
                 folders=known_folder, foreground=apps.foreground_executable, demo=False):
        self._lock = threading.RLock()
        self._storage = storage or settings._path().with_name('home-shortcuts.json')
        self._catalog, self._folders, self._foreground = catalog, folders, foreground
        self._demo = demo
        self._tiles = []
        self._targets = {}
        self._previous = None
        self._counts = {}
        self._personal = []
        self._last_photo = None
        if not demo:
            try:
                data = json.loads(self._storage.read_text(encoding='utf-8'))
                counts = data.get('counts', {})
                self._counts = {k: min(v, 10**9) for k, v in counts.items()
                                if isinstance(k, str) and type(v) is int and v >= 0}
                self._personal = [p for p in data.get('personal', [])
                                  if isinstance(p, dict) and isinstance(p.get('path'), str)
                                  and isinstance(p.get('id'), str)][:4]
                self._last_photo = data.get('lastPhoto') if isinstance(data.get('lastPhoto'), str) else None
            except (OSError, ValueError, AttributeError, TypeError):
                pass
        self.refresh()

    def snapshot(self) -> list[dict]:
        with self._lock:
            return [dict(t) for t in self._tiles]

    def _save(self):
        if self._demo:
            return
        try:
            self._storage.parent.mkdir(parents=True, exist_ok=True)
            tmp = self._storage.with_suffix('.tmp')
            tmp.write_text(json.dumps({'counts': self._counts, 'personal': self._personal,
                                      'lastPhoto': self._last_photo}, ensure_ascii=False), encoding='utf-8')
            tmp.replace(self._storage)
        except OSError:
            pass

    def _add_message(self):
        self._tiles.append(dict(id=MESSAGE_ID, label='Nouveau message', symbol='compose'))
        self._targets[MESSAGE_ID] = ('message', None)

    def refresh(self):
        with self._lock:
            if self._demo:
                labels = [('Mail', 'mail'), ('Photos', 'photos'), ('Microsoft Edge', 'globe'),
                          ('Images', 'folder'), ('Documents', 'doc'), ('Téléchargements', 'download'),
                          ('Comptabilité 2025', 'folder'), ('Projets', 'folder')]
                self._tiles = [dict(id=f'demo-{i}', label=n, symbol=s, personal=i == 7)
                               for i, (n, s) in enumerate(labels)]
                self._add_message()
                return
            catalog = self._catalog()
            active = self._foreground()
            # Un passage au premier plan, pas chaque seconde passée dans l'application.
            key = apps.foreground_id(catalog, active)
            if key and key != self._previous:
                self._counts[key] = self._counts.get(key, 0) + 1
                self._save()
            self._previous = key
            ranked = sorted(catalog, key=lambda a: -self._counts.get(a['id'], 0))[:3]
            self._tiles, self._targets = [], {}
            for a in ranked:
                tid = 'app:' + a['id']
                self._tiles.append(dict(id=tid, label=a['label'], icon=a.get('icon'), symbol='app'))
                self._targets[tid] = ('app', a['id'])
            seen = set()

            def folder_tile(path, label=None, personal=None, symbol='folder'):
                target = valid_folder(path) if path else None
                if target is None:
                    if personal:
                        self._tiles.append(dict(id=personal, label=Path(path).name or 'Dossier indisponible',
                                                symbol=symbol, personal=True))
                    return
                if target in seen:
                    return
                seen.add(target)
                if not personal:
                    personal = next((p['id'] for p in self._personal if valid_folder(p['path']) == target), None)
                tid = personal or 'folder:' + str(target)
                self._tiles.append(dict(id=tid, label=label or target.name,
                                        symbol=symbol, personal=bool(personal)))
                self._targets[tid] = ('folder', str(target))

            for name, label in [('pictures', 'Images'), ('documents', 'Documents'), ('downloads', 'Téléchargements')]:
                folder_tile(self._folders(name), label)
            pictures = self._folders('pictures')
            recent = valid_folder(self._last_photo) if self._last_photo else None
            if recent is None and pictures and valid_folder(pictures):
                try:
                    candidates = [p for p in pictures.iterdir() if not p.name.startswith('.')
                                  and valid_folder(p) and has_photos(p)]
                    recent = max(candidates, key=lambda p: p.stat().st_mtime, default=None)
                except OSError:
                    pass
            folder_tile(recent, symbol='photos')
            for p in self._personal:
                folder_tile(p['path'], personal=p['id'])
            self._add_message()

    def add_folder(self, path) -> bool:
        with self._lock:
            target = valid_folder(path)
            if target is None:
                return False
            if any(t == ('folder', str(target)) for t in self._targets.values()):
                return True
            if len(self._personal) >= 4:
                return False
            self._personal.append({'id': str(uuid.uuid4()), 'path': str(target)})
            self._save()
            self.refresh()
            return True

    def remove(self, tid):
        with self._lock:
            self._personal = [p for p in self._personal if p['id'] != tid]
            if self._demo:
                self._tiles = [t for t in self._tiles if not (t['id'] == tid and t.get('personal'))]
            self._save()
            if not self._demo:
                self.refresh()

    def open(self, tid) -> tuple[bool, str]:
        with self._lock:
            kind, target = self._targets.get(tid, (None, None))
            if kind == 'message':
                ok = open_new_message()
                return ok, '' if ok else "Je n'arrive pas à ouvrir un nouveau message dans votre messagerie."
            if kind == 'app':
                return apps.launch(target)
            if kind == 'folder' and open_folder(target):
                folder = valid_folder(target)
                if folder and has_photos(folder):
                    self._last_photo = str(folder)
                    self._save()
                return True, ''
            return False, "Ce dossier n'est pas disponible ou ne peut pas être ouvert en toute sécurité."
