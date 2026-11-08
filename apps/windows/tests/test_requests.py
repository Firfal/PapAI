"""Mes demandes : lecture réseau et relance par le chemin existant."""
import io
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from papai.model import Model


class Requests(unittest.TestCase):
    def model(self):
        with patch('papai.model.settings.load', return_value={"server": "ws://localhost:8000/k/poste/ws/bridge"}):
            return Model(demo="")

    def test_parse_empty_and_error(self):
        m = self.model()
        row = {"id": "r", "task": "Imprimer", "status": "resolu", "created": 100,
               "solution": {"kind": "automate", "lesson": "a", "title": "Imprimer"}, "relaunch": "a"}
        with patch('papai.model.urllib.request.urlopen', return_value=io.BytesIO(json.dumps({"requests": [row, None, {}]}).encode())) as fetch:
            m.refresh_requests()
        fetch.assert_called_once_with('http://localhost:8000/k/poste/requests', timeout=5)
        self.assertEqual(m.requests, [row])
        self.assertFalse(m.requests_error)
        for payload in ({"requests": []}, {"requests": "incorrect"}, [], None):
            with patch('papai.model.urllib.request.urlopen', return_value=io.BytesIO(json.dumps(payload).encode())):
                m.refresh_requests()
            self.assertEqual(m.requests, [])
            self.assertEqual(m.requests_error, payload != {"requests": []})
        with patch('papai.model.urllib.request.urlopen', side_effect=TimeoutError):
            m.refresh_requests()
        self.assertTrue(m.snapshot()['requestsError'])
        self.assertFalse(m.snapshot()['requestsLoading'])

    def test_relaunch_only_available_automation_and_no_ticket_argument(self):
        m = self.model()
        m.requests = [{"id": "r", "relaunch": "a"}, {"id": "waiting", "relaunch": None}]
        m.run_automation = Mock()
        self.assertIsNone(m.snapshot()['requests'][0]['relaunch'])
        m.relaunch_request('r')
        m.relaunch_request('missing')
        m.relaunch_request('waiting')
        m.run_automation.assert_not_called()
        m.lessons = [{"id": "a", "actions": [{"do": "open_settings", "page": "printers"}]}]
        self.assertEqual(m.snapshot()['requests'][0]['relaunch'], 'a')
        m.relaunch_request('r')
        m.run_automation.assert_called_once_with('a')
        m.lessons = []
        m.relaunch_request('r')
        m.run_automation.assert_called_once_with('a')

    def test_open_loads_in_thread_each_time(self):
        m = self.model()
        with patch('papai.model.threading.Thread') as thread:
            m.open_requests()
            self.assertTrue(m.requests_open)
            self.assertTrue(m.snapshot()['requestsLoading'])
            thread.assert_called_once_with(target=m.refresh_requests, daemon=True)
            thread.return_value.start.assert_called_once_with()
            m.close_requests()
            self.assertFalse(m.requests_open)
            m.open_requests()
            self.assertEqual(thread.call_count, 2)

    def test_demo(self):
        m = Model(demo='requests')
        m.start()
        self.assertEqual(len(m.snapshot()['requests']), 4)
        self.assertEqual(m.snapshot()['requests'][0]['relaunch'], 'print')
        self.assertEqual(m.screen, 'home')

    def test_tickets_changed_refreshes_only_open_sheet(self):
        m = self.model()
        with patch('papai.model.threading.Thread') as thread:
            m._handle({'type': 'tickets_changed'})
            thread.assert_not_called()
            m.requests_open = True
            m._handle({'type': 'tickets_changed'})
            thread.assert_called_once_with(target=m.refresh_requests, daemon=True)
            thread.return_value.start.assert_called_once_with()

    def test_api_delegates(self):
        from papai.app import Api
        api = Api.__new__(Api)
        api._model = Mock()
        api.open_requests()
        api.close_requests()
        api.relaunch_request('r')
        api._model.open_requests.assert_called_once_with()
        api._model.close_requests.assert_called_once_with()
        api._model.relaunch_request.assert_called_once_with('r')


if __name__ == '__main__':
    unittest.main()
