"""Vérifie les mêmes cas d'URL sur le serveur et dans l'app Windows."""

import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from backend import site_check

spec = importlib.util.spec_from_file_location(
    "windows_site_check", ROOT / "apps/windows/papai/site_check.py")
windows = importlib.util.module_from_spec(spec)
spec.loader.exec_module(windows)

cases = json.loads((ROOT / "tests/site_check_cases.json").read_text())
total = failures = 0
for name, module in (("backend", site_check), ("Windows", windows)):
    for index, case in enumerate(cases, 1):
        result = module.classify(case["url"], case["sites"], case["hosts"])
        total += 1
        if result != case["attendu"]:
            failures += 1
            print(f"ÉCHEC {name} cas {index} : {result}, attendu {case['attendu']}")
    print(f"{name} : {len(cases)} cas vérifiés")
    for url in (None, 42, [], {}):
        total += 1
        if module.classify(url, []) != "hors" or module.host_of(url) is not None:
            failures += 1
            print(f"ÉCHEC {name} : URL non textuelle")
    for url, expected in (("https://AMELI.FR.:443/a", "ameli.fr"),
                          ("https://аmeli.fr", "xn--meli-43d.fr"),
                          ("https://ameli.fr:80", None)):
        total += 1
        if module.host_of(url) != expected:
            failures += 1
            print(f"ÉCHEC {name} : extraction de l'hôte")
    chain = ["https://ameli.fr", "https://connexion.ameli.fr", "https://evil.com"]
    total += 1
    if [module.classify(url, ["ameli.fr"]) for url in chain] != ["ok", "ok", "hors"]:
        failures += 1
        print(f"ÉCHEC {name} : chaîne de redirections")
print(f"{'ÉCHEC' if failures else 'OK'} : {total - failures}/{total} contrôles, {failures} échec(s)")
sys.exit(bool(failures))
