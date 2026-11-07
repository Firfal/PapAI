"""Accueil Windows sans matériel : python -m unittest discover -s apps/windows/tests."""

import io
import json
import struct
import sys
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from papai import apps
from papai.dictation import Dictation, SilenceDetector
from papai.home_shortcuts import FORBIDDEN, HomeShortcuts, open_folder, valid_folder
from papai.mic_presence import MicPresence, microphone_present


class Folders(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.photos = self.root / 'Images'
        self.photos.mkdir()

    def home(self, **kw):
        return HomeShortcuts(storage=self.root / 'local.json', catalog=lambda: [],
                             folders=lambda k: self.photos if k == 'pictures' else None,
                             foreground=lambda: None, **kw)

    def test_refuses_files_and_disguised_directories(self):
        for suffix in FORBIDDEN:
            with self.subTest(suffix=suffix):
                f = self.root / ('attaque' + suffix.upper())
                f.write_text('test')
                self.assertIsNone(valid_folder(f))
                d = self.root / ('dossier' + suffix)
                d.mkdir()
                self.assertIsNone(valid_folder(d))
                child = d / 'enfant'
                child.mkdir()
                self.assertIsNone(valid_folder(child))
        self.assertIsNone(valid_folder('relatif'))
        self.assertIsNone(valid_folder('https://example.com'))
        self.assertIsNone(valid_folder('//serveur/partage'))
        self.assertIsNone(valid_folder('absent'))

    def test_links_checked_at_add_and_open(self):
        bad = self.root / 'attaque.exe'
        bad.mkdir()
        link = self.root / 'ordinaire'
        link.symlink_to(bad, target_is_directory=True)
        self.assertIsNone(valid_folder(link))
        good = self.root / 'valide'
        good.mkdir()
        home = self.home()
        self.assertTrue(home.add_folder(good))
        tid = next(t['id'] for t in home.snapshot() if t.get('personal'))
        good.rmdir()
        good.symlink_to(bad, target_is_directory=True)
        with patch('papai.home_shortcuts.subprocess.Popen') as launch:
            self.assertFalse(home.open(tid)[0])
            launch.assert_not_called()

    def test_limits_duplicates_removal_and_local_reload(self):
        home = self.home()
        self.assertTrue(home.add_folder(self.photos))
        for i in range(4):
            d = self.root / str(i)
            d.mkdir()
            self.assertTrue(home.add_folder(d))
            self.assertTrue(home.add_folder(d))
        fifth = self.root / 'cinquieme'
        fifth.mkdir()
        self.assertFalse(home.add_folder(fifth))
        loaded = self.home()
        personal = [t for t in loaded.snapshot() if t.get('personal')]
        self.assertEqual(len(personal), 4)
        loaded.remove(personal[0]['id'])
        self.assertTrue(loaded.add_folder(fifth))
        self.assertEqual(len([t for t in loaded.snapshot() if t.get('personal')]), 4)
        with patch('papai.home_shortcuts.open_folder') as launch:
            self.assertFalse(loaded.open(str(fifth))[0])
            launch.assert_not_called()

    def test_recent_photos_and_three_known_folders(self):
        for n in ['Documents', 'Téléchargements']:
            (self.root / n).mkdir()
        album = self.photos / 'Noël 2025'
        album.mkdir()
        (album / 'image.jpg').write_bytes(b'image')
        home = HomeShortcuts(storage=self.root / 'local.json', catalog=lambda: [],
                             folders=lambda k: self.root / {'pictures': 'Images', 'documents': 'Documents',
                                                           'downloads': 'Téléchargements'}[k], foreground=lambda: None)
        self.assertEqual([t['label'] for t in home.snapshot()], ['Images', 'Documents', 'Téléchargements', 'Noël 2025'])

    def test_usage_foreground_transitions_local_only(self):
        active = ['a']
        catalog = lambda: [dict(id=k, label=k, executable=k) for k in ['a', 'b', 'c', 'd']]
        home = HomeShortcuts(storage=self.root / 'local.json', catalog=catalog,
                             folders=lambda k: None, foreground=lambda: active[0])
        home.refresh()
        active[0] = 'd'
        home.refresh()
        home.refresh()
        active[0] = 'unknown.exe'
        home.refresh()
        active[0] = 'd'
        home.refresh()
        data = json.loads((self.root / 'local.json').read_text())
        self.assertEqual(data['counts'], {'a': 1, 'd': 2})
        self.assertEqual(home.snapshot()[0]['id'], 'app:d')
        self.assertNotIn('unknown.exe', (self.root / 'local.json').read_text())

    def test_no_file_or_start_menu_shortcut_launch(self):
        with patch('papai.apps.installed', return_value=[dict(id='edge', label='Internet', executable='known.exe')]), \
             patch('papai.apps.subprocess.Popen') as launch:
            for value in [str(self.root / 'evil.exe'), 'evil.bat', 'evil.cmd', 'evil.ps1', 'evil.lnk',
                          'evil.vbs', 'evil.msi', 'evil.scr', '../edge', 'edge --command']:
                self.assertFalse(apps.launch(value)[0])
            launch.assert_not_called()
            self.assertTrue(apps.launch('edge')[0])
            launch.assert_called_once_with(['known.exe'], shell=False)

    def test_open_uses_explorer_not_file_associations(self):
        with patch('papai.home_shortcuts.os.name', 'nt'), \
             patch('papai.home_shortcuts.apps.windows_directory', return_value=self.root), \
             patch('papai.home_shortcuts.valid_folder', return_value=self.photos), \
             patch('papai.home_shortcuts.subprocess.Popen') as launch:
            self.assertTrue(open_folder(self.photos))
            launch.assert_called_once_with([str(self.root / 'explorer.exe'), str(self.photos)], shell=False)


class Microphone(unittest.TestCase):
    def test_hotplug_only_notifies_on_changes(self):
        values = iter([False, False, True, True, False])
        calls = []
        mic = MicPresence(calls.append, probe=lambda: next(values))
        self.assertFalse(mic.present)
        for _ in range(4):
            mic.refresh()
        self.assertEqual(calls, [True, False])
        mic.close()

    def test_demo_overrides_are_explicit(self):
        with patch.dict('os.environ', {'PAPAI_DEMO': 'home', 'PAPAI_DEMO_MIC': '1', 'PAPAI_NOMIC': '0'}):
            self.assertTrue(microphone_present())
            with patch.dict('os.environ', {'PAPAI_NOMIC': '1'}):
                self.assertFalse(microphone_present())
        with patch('papai.mic_presence.sys.platform', 'linux'), patch.dict('os.environ', {}, clear=True):
            self.assertFalse(microphone_present())


class Voice(unittest.TestCase):
    def test_silence_after_voice_and_empty_timeout(self):
        detector = SilenceDetector()
        for _ in range(5):
            self.assertFalse(detector.feed(2000, .1))
        for _ in range(17):
            self.assertFalse(detector.feed(20, .1))
        self.assertTrue(detector.feed(20, .1))
        empty = SilenceDetector()
        for _ in range(79):
            self.assertFalse(empty.feed(20, .1))
        self.assertTrue(empty.feed(20, .11))
        self.assertEqual(empty.voice, 0)

    def record(self, levels, *, text='Mes photos', cancel=False, error=False):
        phases, result = [], []
        d = Dictation(lambda p, m: phases.append((p, m)), result.append)
        self.addCleanup(d.close)
        def stream(**kw):
            class Stream:
                def __enter__(self):
                    if error:
                        raise OSError('micro retiré')
                    for level in levels:
                        kw['callback'](struct.pack('<h', level) * 1600, 1600, None, False)
                    if cancel:
                        d.cancel()
                def __exit__(self, *args): pass
            return Stream()
        sd = Mock(RawInputStream=stream)
        with patch('papai.dictation.sys.platform', 'win32'), patch.dict(sys.modules, {'sounddevice': sd}), \
             patch.object(d, '_transcribe', return_value=text) as transcribe:
            d._record('http://127.0.0.1')
        return d, phases, result, transcribe

    def test_finishes_once_with_wav_after_silence(self):
        d, phases, result, transcribe = self.record([2000] * 5 + [20] * 20)
        self.assertEqual(result, ['Mes photos'])
        self.assertEqual(d.phase, 'idle')
        self.assertEqual([p for p, _ in phases], ['listening', 'transcribing', 'idle'])
        transcribe.assert_called_once()
        with wave.open(io.BytesIO(transcribe.call_args.args[1])) as wav:
            self.assertEqual((wav.getframerate(), wav.getnchannels(), wav.getsampwidth()), (16000, 1, 2))

    def test_no_text_or_audio_sent_for_silence_cancel_and_error(self):
        for levels, options in [([20] * 82, {}), ([2000] * 5, {'cancel': True}), ([], {'error': True})]:
            with self.subTest(options=options):
                d, phases, result, transcribe = self.record(levels, **options)
                self.assertEqual(result, [])
                transcribe.assert_not_called()
                self.assertEqual(d.phase, 'idle')
                self.assertTrue(phases[-1][1])

    def test_start_and_stop_are_serialized(self):
        d = Dictation(Mock(), Mock())
        self.addCleanup(d.close)
        with patch.object(d._pool, 'submit') as submit:
            d.toggle('local')
            d.toggle('local')
            self.assertEqual(d.run_id, 1)
            submit.assert_called_once()
            d._set('listening')
            d.toggle('local')
            d.toggle('local')
            self.assertTrue(d._stop.is_set())
            submit.assert_called_once()


if __name__ == '__main__':
    unittest.main()
