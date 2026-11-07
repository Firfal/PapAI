"""Route de dictée : python tests/test_transcribe.py http://127.0.0.1:8000 demo
Serveur lancé SANS GLADIA_API_KEY : mauvaise clé -> 404, bonne clé -> 503."""
import sys
import urllib.error
import urllib.request

base, cle = sys.argv[1], sys.argv[2]


def post(k):
    r = urllib.request.Request(f"{base}/k/{k}/transcribe", data=b"RIFFxxxx",
                               headers={"Content-Type": "audio/wav"}, method="POST")
    try:
        return urllib.request.urlopen(r).status, ""
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


code, _ = post("mauvaise-cle")
assert code == 404, code
code, corps = post(cle)
assert code == 503 and "gladia_absent" in corps, (code, corps)
print("OK : 404 sans bonne clé, 503 gladia_absent sans clé Gladia")
