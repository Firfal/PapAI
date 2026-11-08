"""Gladia live local, sans clé réelle : python tests/faux_gladia.py [port]."""
import json
import sys

import uvicorn
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse


class FauxGladia:
    def __init__(self):
        self.app = FastAPI()
        self.mode = "normal"
        self.configs = []
        self.audio = []
        self.stops = 0
        self.closed = 0
        self.app.post("/v2/live")(self.init)
        self.app.websocket("/audio")(self.stream)

    async def init(self, request: Request):
        self.configs.append((request.headers.get("x-gladia-key"), await request.json()))
        if self.mode == "init_error":
            return JSONResponse({"error": "secret-fournisseur"}, status_code=503)
        return {"id": "simule", "url": f"ws://{request.headers['host']}/audio?token=secret-fournisseur"}

    async def stream(self, ws: WebSocket):
        await ws.accept()
        try:
            if self.mode == "disconnect":
                return
            if self.mode == "error":
                await ws.send_json({"type": "error", "message": "secret-fournisseur"})
                return
            if self.mode == "silent":
                while True:
                    await ws.receive_bytes()
            n = 0
            while True:
                event = await ws.receive()
                if event["type"] == "websocket.disconnect":
                    return
                if event.get("bytes") is not None:
                    self.audio.append(event["bytes"])
                    n += 1
                    await ws.send_json(self.transcript("phrase-1", "Bonjour" if n == 1 else "Bonjour les photos", False))
                else:
                    assert json.loads(event["text"]) == {"type": "stop_recording"}
                    self.stops += 1
                    if self.mode == "no_final":
                        while (await ws.receive())["type"] != "websocket.disconnect":
                            pass
                        return
                    await ws.send_json({"type": "end_recording", "data": {"recording_duration": 1}})
                    await ws.send_json(self.transcript("phrase-1", "Bonjour les photos.", True))
                    await ws.send_json(self.transcript("phrase-2", "Merci.", True))
                    await ws.send_json({"type": "end_session"})
                    return
        except WebSocketDisconnect:
            pass
        finally:
            self.closed += 1
            await ws.close()

    @staticmethod
    def transcript(ident, text, final):
        return {"type": "transcript", "data": {"id": ident, "is_final": final,
                "utterance": {"text": text, "start": 0, "end": 1}}}


if __name__ == "__main__":
    uvicorn.run(FauxGladia().app, host="127.0.0.1", port=int(sys.argv[1]) if len(sys.argv) > 1 else 8998)
