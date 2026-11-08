"""Cibles des automatismes, sans ouvrir de fenêtre."""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from papai import core, home_shortcuts


class ShortcutTests(unittest.TestCase):
    def test_shared_rule(self):
        cases = json.loads((Path(__file__).resolve().parents[3] / 'tests/subfolder_cases.json').read_text())
        for case in cases:
            with self.subTest(name=case['name']):
                self.assertEqual(core.valid_subfolder(case['name']) is not None, case['valid'])

    def test_open_explorer(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            target = base / 'Noël 2025'
            target.mkdir()
            with patch.object(core, 'known_folder', return_value=base), patch.object(core, 'WINDOWS', True), \
                    patch('papai.apps.windows_directory', return_value=Path('/Windows')), \
                    patch('subprocess.Popen') as launch:
                self.assertTrue(core.open_shortcut({'folder': 'pictures', 'subfolder': 'Noël 2025'})[0])
                launch.assert_called_once_with(['/Windows/explorer.exe', str(target.resolve())], shell=False)
                launch.reset_mock()
                self.assertTrue(core.open_shortcut({'folder': 'pictures', 'subfolder': ''})[0])
                launch.assert_called_once()
                launch.reset_mock()
                for name in ('Facture.app', '{Photos}', '../Photos', 'absent'):
                    self.assertFalse(core.open_shortcut({'folder': 'pictures', 'subfolder': name})[0])
                launch.assert_not_called()

    def test_links_reparse_and_escape(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as elsewhere:
            base = Path(directory).resolve()
            (base / 'Lien').symlink_to(elsewhere, target_is_directory=True)
            with patch.object(core, 'known_folder', return_value=base), patch('subprocess.Popen') as launch:
                self.assertFalse(core.open_shortcut({'folder': 'pictures', 'subfolder': 'Lien'})[0])
                with patch.object(home_shortcuts, 'valid_folder', return_value=Path(elsewhere)):
                    self.assertFalse(core.open_shortcut({'folder': 'pictures', 'subfolder': 'Lien'})[0])
                launch.assert_not_called()
            target = base / 'Jonction'
            target.mkdir()
            original = Path.lstat

            def lstat(path, *args, **kwargs):
                if path == target:
                    return SimpleNamespace(st_mode=0o40755, st_file_attributes=0x400)
                return original(path, *args, **kwargs)

            with patch.object(Path, 'lstat', lstat), patch.object(core, 'known_folder', return_value=base):
                self.assertIsNone(home_shortcuts.valid_folder(target, reject_links=True))
                self.assertFalse(core.open_shortcut({'folder': 'pictures', 'subfolder': 'Jonction'})[0])

    def test_launch_error(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(core, 'known_folder', return_value=Path(directory).resolve()), \
                patch.object(core, 'WINDOWS', True), patch('papai.apps.windows_directory', return_value=Path('/Windows')), \
                patch('subprocess.Popen', side_effect=OSError('indisponible')):
            self.assertEqual(core.open_shortcut({'folder': 'pictures'}), (False, 'indisponible'))


if __name__ == '__main__':
    unittest.main()
