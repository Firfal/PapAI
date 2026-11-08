"""Exécute les types Foundation du parseur iOS sans cible XCTest."""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "apps/ios/Sources/Pairing.swift").read_text().split("private let relations:")[0]
source = source.replace("import SwiftUI", "import Foundation").replace("import AVFoundation", "")
checks = r'''
let token = "Abc_def-1234567890123456"
for route in ["/p/123456", "/i/" + token, "/k/key/p/123456"] {
    let url = "https://trusted.example" + route
    var wrapper = URLComponents(string: "papai://pair")!
    wrapper.queryItems = [URLQueryItem(name: "u", value: url), URLQueryItem(name: "n", value: "Jeanne")]
    for text in [url, wrapper.string!] {
        let link = PairLink.parse(text)!
        assert(link.endpoint(code: "") == url, text)
        assert(!link.isManual)
    }
    assert(PairLink.parse(wrapper.string!)!.senior == "Jeanne")
}
assert(PairLink(base: "https://trusted.example/k/old", code: nil).endpoint(code: "654321") == "https://trusted.example/p/654321")
for route in ["/i/short", "/i/" + String(repeating: "a", count: 129), "/i/abcdefghijklmnopqrstuv!", "/i/abcdefghijklmnopqrstuv/extra", "/extra/p/123456", "/p/1234567", "/p/１２３４５６"] {
    assert(PairLink.parse("https://trusted.example" + route) == nil, route)
}
for url in ["", "papai://open?u=https://trusted.example/p/123456", "papai://pair?u=papai://pair", "http://public.example/p/123456", "https://user@trusted.example/p/123456"] {
    assert(PairLink.parse(url) == nil, url)
}
assert(PairLink.parse("http://127.0.0.1:8000/i/" + token) != nil)
assert(PairLink.parse("https://" + PairServer.officialHost + "/i/" + token)!.isOfficial)
assert(!PairLink.parse("https://trusted.example/i/" + token)!.isOfficial)
for status in [200, 400, 403, 408, 409, 429] {
    for refused in [false, true] {
        assert(PairServer.needsNew(status: status, refused: refused) == (status == 408 || status == 409 || (status == 403 && refused)))
    }
}
print("OK : parsing iOS (3 routes, refus, origine manuelle, serveur officiel), refus/délai.")
'''
with tempfile.TemporaryDirectory() as directory:
    script = Path(directory) / "main.swift"
    script.write_text(source + checks)
    subprocess.run(["swift", "-enable-bare-slash-regex", "-DDEBUG", str(script)], check=True)
