"""Un aidant connecté apparaît dans « Mes proches » ; la phrase de Holo pour l'aidant."""
from backend.agent import describe_doing
from backend.family import Family


def test_aidant_connecte_ajoute_une_fois(tmp_path):
    f = Family(tmp_path / "family.json")
    h = f.connect("", "Quentin", "son fils")
    assert h and len(f.helpers) == 1
    # Même prénom, autre connexion : pas de doublon.
    assert f.connect("", "quentin")["id"] == h["id"]
    assert f.connect(h["id"], "Quentin R.")["name"] == "Quentin R."
    assert len(f.helpers) == 1
    assert f.public({h["id"]})[0]["online"] is True
    assert Family(tmp_path / "family.json").helpers[0]["id"] == h["id"]


def test_prenom_vide_refuse(tmp_path):
    assert Family(tmp_path / "f.json").connect("x", "  ") is None


def test_phrase_depuis_la_reflexion():
    assert describe_doing("Je vais ouvrir la Calculatrice. Ensuite…", "click", {}) == "Je vais ouvrir la Calculatrice."


def test_phrase_depuis_l_action():
    assert describe_doing("", "click", {"element": "le bouton 8"}) == "Holo clique sur le bouton 8"
    assert describe_doing("Clicking the button", "type_text", {"text": "96"}) == "Holo écrit « 96 »"


def test_liste_rendue_par_l_ordinateur(tmp_path):
    f = Family(tmp_path / "vide.json")   # serveur redémarré, disque vierge
    assert f.restore([{"id": "ab12", "name": "Brans", "relation": "son fils"}, {"id": "", "name": "x"}, "bad"])
    assert [h["name"] for h in f.helpers] == ["Brans"]
    assert not f.restore([{"id": "ab12", "name": "Brans"}])   # déjà là : rien en double
