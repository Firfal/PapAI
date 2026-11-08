"""Garde-fous purs et Win32 simulé, sans geste sur le bureau."""

import asyncio
import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from papai import core
from papai.bridge import Bridge
from papai.model import Model


class SafetyTests(unittest.TestCase):
    def test_verdicts(self):
        for verdict in (core.pointer_verdict, core.keyboard_verdict):
            for name in core.SENSITIVE_PROCESSES:
                for variant in (name, name.upper() + '.EXE', 'C:\\Apps\\' + name + '.exe'):
                    with self.subTest(variant=variant):
                        self.assertIsNotNone(verdict(12, variant, own_pid=42))
            for name in ('explorer.exe', 'msedge.exe', 'notepad.exe'):
                self.assertIsNone(verdict(12, name, own_pid=42))
            self.assertIsNotNone(verdict(42, 'python.exe', own_pid=42))
            self.assertIsNotNone(verdict(os.getpid(), 'python.exe'))
            self.assertIsNotNone(verdict(12, None, own_pid=42))
            self.assertIsNotNone(verdict(0, '', own_pid=42))

    def api(self):
        api = Mock()
        api.foreground.return_value = 1
        api.password_focused.return_value = False
        api.at_point.return_value = 1
        api.identity.side_effect = lambda hwnd: {
            1: (10, 'ApplicationFrameHost.exe'), 2: (11, 'SystemSettings.exe'),
            3: (12, 'notepad.exe'), 4: (42, 'papai.exe'), 5: (13, None),
        }.get(hwnd, (0, None))
        api.children.return_value = [2]
        api.next_visible.return_value = [4, 3]
        return api

    def test_hosted_windows(self):
        api = self.api()
        safety = core.DesktopSafety(api, own_pid=42)
        self.assertIsNotNone(safety.window_reason(1))
        api.children.assert_called_with(1)
        for child in (3, 5):
            api.children.return_value = [child]
            self.assertEqual(safety.window_reason(1) is None, child == 3)
        api.children.return_value = []
        self.assertIsNotNone(safety.window_reason(1))
        api.children.return_value = [1]
        self.assertIsNotNone(safety.window_reason(1))
        api.children.return_value = [3, 2]
        self.assertIsNotNone(safety.window_reason(1))

    def test_password_focus_win32(self):
        api = core.Win32Targets.__new__(core.Win32Targets)
        api.user = Mock()
        api.user.GetWindowThreadProcessId.return_value = 71

        def gui_info(thread, info):
            self.assertEqual(thread, 71)
            self.assertEqual(info._obj.cbSize, core.ctypes.sizeof(info._obj))
            info._obj.hwndFocus = 123
            return True

        api.user.GetGUIThreadInfo.side_effect = gui_info
        for style, expected in ((0x20, True), (0x500100A0, True), (0x50010080, False)):
            api.user.GetWindowLongW.return_value = style
            self.assertEqual(api.password_focused(3), expected)
            api.user.GetWindowLongW.assert_called_with(123, -16)
        api.user.GetGUIThreadInfo.side_effect = lambda thread, info: True
        self.assertFalse(api.password_focused(3))
        api.user.GetGUIThreadInfo.return_value = False
        api.user.GetGUIThreadInfo.side_effect = None
        with self.assertRaises(core.SensitiveTarget):
            api.password_focused(3)

    def test_password_rechecked_per_character(self):
        api = self.api()
        api.foreground.return_value = 3
        safety = core.DesktopSafety(api, own_pid=42)
        api.password_focused.return_value = True
        with self.assertRaisesRegex(core.SensitiveTarget, "un champ protégé attend une saisie confidentielle"):
            safety.check_keyboard()
        api.password_focused.side_effect = [False, False, True]
        fake = Mock()
        with patch.dict(sys.modules, {'pyautogui': fake}), patch.object(core, 'WINDOWS', False):
            with self.assertRaises(core.SensitiveTarget):
                core.run_action('type_text', {'text': 'AB'}, None, core.StopGate(), safety=safety)
        self.assertEqual(fake.write.call_args_list, [unittest.mock.call('A')])

    def test_pointer_and_keyboard(self):
        api = self.api()
        safety = core.DesktopSafety(api, own_pid=42)
        with self.assertRaises(core.SensitiveTarget):
            safety.check_pointer(4, 5)
        api.at_point.assert_called_with(4, 5)
        with self.assertRaises(core.SensitiveTarget):
            safety.check_keyboard()
        api.foreground.return_value = 3
        safety.check_keyboard()
        self.assertEqual(safety.previous, 3)
        api.foreground.return_value = 4
        api.activate.side_effect = lambda hwnd: setattr(api.foreground, 'return_value', hwnd)
        safety.sleep = Mock()
        safety.prepare_keyboard()
        api.activate.assert_called_with(3)
        safety.sleep.assert_called_once_with(0.2)

    def test_keyboard_fallback_and_failed_activation(self):
        api = self.api()
        api.foreground.return_value = 4
        safety = core.DesktopSafety(api, own_pid=42, sleep=Mock())
        with self.assertRaises(core.SensitiveTarget):
            safety.prepare_keyboard()
        api.activate.assert_called_once_with(3)
        api.activate.side_effect = lambda hwnd: setattr(api.foreground, 'return_value', hwnd)
        safety.prepare_keyboard()
        self.assertEqual(api.foreground(), 3)

    def test_preview_and_typing_focus_change(self):
        core.DesktopSafety().check_pointer(1, 2)
        core.DesktopSafety().prepare_keyboard()
        safety = Mock()
        safety.check_keyboard.side_effect = [None, core.SensitiveTarget('focus sensible')]
        fake = Mock()
        with patch.dict(sys.modules, {'pyautogui': fake}), patch.object(core, 'WINDOWS', False):
            with self.assertRaises(core.SensitiveTarget):
                core.run_action('type_text', {'text': 'AB'}, None, core.StopGate(), safety=safety)
        safety.prepare_keyboard.assert_called_once()
        self.assertEqual(fake.write.call_args_list, [unittest.mock.call('A')])

    def test_pointer_rechecked_before_click(self):
        safety = Mock()
        safety.check_pointer.side_effect = [None, core.SensitiveTarget('autorisation')]
        screen = Mock()
        screen.to_pixels.return_value = (10, 20)
        fake = Mock()
        with patch.dict(sys.modules, {'pyautogui': fake}), patch.object(core.time, 'sleep'):
            with self.assertRaises(core.SensitiveTarget):
                core.run_action('click', {}, screen, core.StopGate(), safety=safety)
        fake.click.assert_not_called()


class BridgeSafetyTests(unittest.IsolatedAsyncioTestCase):
    async def test_sensitive_results(self):
        messages = []
        ws = Mock()

        async def send(raw):
            messages.append(json.loads(raw))
        ws.send = send
        for error in (core.SensitiveTarget('raison simple'), core.ProtectedZone()):
            bridge = Bridge('', core.StopGate(), Mock, lambda m: None, lambda ok: None,
                            lambda text: None, runner=Mock(side_effect=error))
            bridge.last_status = {'plan_approved': True, 'state': 'active'}
            await bridge._execute(ws, 'r', {'name': 'click'})
            message = messages[-1]
            self.assertEqual(message['blocked'], 'sensitive')
            self.assertIs(message['refused'], False)
            self.assertTrue(message['result'].startswith('Action refusée par PapAI : '))
            self.assertTrue(message['result'].endswith(
                ". Ne réessaie pas : appelle ask_helper pour que le support s'en occupe."))

    async def test_model_alert_blocks_until_dismissed(self):
        model = Model(demo='home')
        runner = Mock(return_value='fait')
        bridge = Bridge('', model.gate, Mock, model._handle, lambda ok: None,
                        lambda text: None, runner=runner, alert_visible=lambda: model.alert is not None)
        bridge.last_status = {'plan_approved': True, 'state': 'active'}
        messages = []
        ws = Mock()

        async def send(raw):
            messages.append(json.loads(raw))
        ws.send = send
        for level in ('info', 'attention'):
            await bridge._handle(ws, {'type': 'alert', 'level': level})
            await bridge._execute(ws, 'r', {'name': 'click'})
            self.assertIs(messages[-1]['refused'], True)
            runner.assert_not_called()
            self.assertTrue(model.gate.is_stopped)
        model.dismiss_alert()
        await bridge._execute(ws, 'r', {'name': 'click'})
        self.assertIs(messages[-1]['refused'], True)
        runner.assert_not_called()
        model.gate.reset()
        await bridge._execute(ws, 'r', {'name': 'click'})
        self.assertIs(messages[-1]['refused'], False)
        runner.assert_called_once()

    async def test_alerte_pendant_la_frappe_arrete_les_caracteres_suivants(self):
        for level in ('info', 'attention'):
            messages = []
            ws = Mock()

            async def send(raw):
                messages.append(json.loads(raw))
            ws.send = send
            bridge = Bridge('', core.StopGate(), Mock, lambda m: None, lambda ok: None,
                            lambda text: None, runner=lambda *args: core.run_action(*args, safety=Mock()))
            bridge.last_status = {'plan_approved': True, 'state': 'active'}
            loop = asyncio.get_running_loop()
            fake = Mock()
            fake.write.side_effect = lambda text: asyncio.run_coroutine_threadsafe(
                bridge._handle(ws, {'type': 'alert', 'level': level}), loop).result(timeout=2)
            with patch.dict(sys.modules, {'pyautogui': fake}), patch.object(core, 'WINDOWS', False):
                await bridge._execute(ws, 'r', {'name': 'type_text', 'args': {'text': 'AB'}})
            self.assertEqual(fake.write.call_args_list, [unittest.mock.call('A')])
            self.assertIs(messages[-1]['refused'], True)

    async def test_alerte_avant_un_geste_empeche_son_depart(self):
        for name in ('click', 'double_click', 'scroll', 'press_key', 'type_text'):
            gate = core.StopGate()
            safety = Mock()
            safety.check_pointer.side_effect = lambda *args: gate.raise_stop()
            safety.prepare_keyboard.side_effect = gate.raise_stop
            fake = Mock()
            screen = Mock()
            screen.to_pixels.return_value = (10, 20)
            with patch.dict(sys.modules, {'pyautogui': fake}), patch.object(core, 'WINDOWS', False):
                with self.assertRaises(core.Stopped):
                    core.run_action(name, {'keys': 'enter', 'text': 'A'}, screen, gate, safety=safety)
            fake.moveTo.assert_not_called()
            fake.click.assert_not_called()
            fake.scroll.assert_not_called()
            fake.press.assert_not_called()
            fake.write.assert_not_called()


if __name__ == '__main__':
    unittest.main()
