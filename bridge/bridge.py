"""Application Windows de la personne aidée : pont + interface.

Un seul programme, volontairement. Le bouton « Arrêter » et le code qui bouge
la souris partagent la même mémoire : l'arrêt n'est pas un message envoyé au
serveur en espérant qu'il arrive, c'est un verrou local vérifié avant chaque
action. Le serveur est prévenu ensuite, par politesse.

    python -m bridge.bridge
"""

from __future__ import annotations

import asyncio
import io
import json
import os
import queue
import sys
import threading
import time
import tkinter as tk
import urllib.request
from pathlib import Path
from tkinter import font as tkfont

import websockets

from carepilot_tools import estimate_cost

from . import shortcuts
from .screen import ProtectedZone, Screen, execute_action

# Le pont est un CLIENT : il sort vers le serveur, rien n'entre sur le PC de la
# personne aidée. Aucune règle de pare-feu, aucun port ouvert, aucun réglage
# réseau à toucher chez elle — elle installe un logiciel, c'est tout.
# En production, cette adresse pointe vers le backend hébergé, en wss:// sur le
# port 443, qui passe partout (4G, Wi-Fi d'hôtel, réseau d'entreprise).
SERVER = os.environ.get("CAREPILOT_SERVER", "ws://localhost:8000/ws/bridge")

# Bandeau de suivi de consommation, utile pendant le developpement.
# CAREPILOT_DEV=0 pour la demo : la personne aidee n a rien a faire de ces chiffres.
DEV_MODE = os.environ.get("CAREPILOT_DEV", "1") != "0"

# Exemple affiché en gris dans le champ : il s'efface au premier clic.
PLACEHOLDER = "Par exemple : je ne retrouve pas mes photos"
# Pour une démo, CAREPILOT_TASK préremplit la demande en texte réel.
DEMO_TASK = os.environ.get("CAREPILOT_TASK", "").strip()
CONTEXT_LIMIT = 65_000   # free tier Models API

# Même serveur, en HTTP : sert à lire les fiches CareMemory et leurs captures.
HTTP_BASE = (
    SERVER.replace("wss://", "https://", 1)
    .replace("ws://", "http://", 1)
    .removesuffix("/ws/bridge")
)


def fetch_lessons() -> list:
    """Les fiches validées par un proche. Jamais les brouillons."""
    try:
        with urllib.request.urlopen(f"{HTTP_BASE}/lessons", timeout=5) as r:
            return json.loads(r.read().decode())
    except Exception as e:  # noqa: BLE001 — serveur absent : pas de fiches, pas d'erreur bloquante
        print(f"[pont] fiches indisponibles : {e}", flush=True)
        return []


# Dossiers connus de Windows, par leur identifiant officiel. On ne construit
# jamais « C:\\Users\\<nom>\\Images » : ce chemin casse sur une autre machine, sous
# un autre compte, et surtout quand Windows redirige Images ou Documents vers
# OneDrive — ce qui est le cas par défaut sur beaucoup de PC récents.
KNOWN_FOLDERS = {
    "downloads": "{374DE290-123F-4565-9164-39C4925E467B}",
    "pictures": "{33E28130-4E1E-4676-835A-98395C3BC3BB}",
    "documents": "{FDD39AD0-238F-46AF-ADB4-6C85480369C7}",
    "desktop": "{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}",
    "videos": "{18989B1D-99B5-455B-841C-AB7C74E4DDFC}",
    "music": "{4BD8D571-6D19-48D3-BE97-422220080E43}",
}


FOLDER_LABELS = {
    "downloads": "Téléchargements",
    "pictures": "Images",
    "documents": "Documents",
    "desktop": "Bureau",
    "videos": "Vidéos",
    "music": "Musique",
}


def known_folder(name: str) -> Path | None:
    """Demande à Windows où se trouve réellement ce dossier, maintenant."""
    guid = KNOWN_FOLDERS.get((name or "").strip().lower())
    if guid is None:
        return None
    import ctypes
    from ctypes import wintypes

    class GUID(ctypes.Structure):
        _fields_ = [("a", wintypes.DWORD), ("b", wintypes.WORD),
                    ("c", wintypes.WORD), ("d", ctypes.c_byte * 8)]

    g = GUID()
    if ctypes.windll.ole32.CLSIDFromString(guid, ctypes.byref(g)) != 0:
        return None
    out = ctypes.c_wchar_p()
    if ctypes.windll.shell32.SHGetKnownFolderPath(
        ctypes.byref(g), 0, None, ctypes.byref(out)
    ) != 0:
        return None
    try:
        return Path(out.value)
    finally:
        ctypes.windll.ole32.CoTaskMemFree(out)


def open_shortcut(shortcut: dict | None) -> tuple[bool, str]:
    """Ouvre la destination enregistrée d'une fiche.

    Le modèle ne fournit jamais un chemin : il nomme un dossier connu de Windows
    (« pictures ») et éventuellement un sous-dossier (« Photos vacances »). C'est
    le PC qui résout, au moment de l'ouverture, sur sa propre configuration.
    """
    sc = shortcut or {}
    base = known_folder(sc.get("folder", ""))
    if base is None:
        return False, "Aucun raccourci enregistré."

    sub = (sc.get("subfolder") or "").strip()
    if sub:
        # Un nom de dossier, pas un chemin : ni séparateur, ni remontée.
        if any(c in sub for c in '\\/:*?"<>|') or sub in (".", ".."):
            return False, "Nom de dossier invalide."
        target = base / sub
    else:
        target = base

    if not target.is_dir():
        quoi = f"« {sub} »" if sub else "Ce dossier"
        return False, f"{quoi} n'existe pas (ou plus) sur cet ordinateur."

    try:
        os.startfile(str(target))  # noqa: S606 — un dossier, ouvert dans l'Explorateur
        return True, str(target)
    except OSError as e:
        return False, str(e)


def fetch_image(lesson_id: str, name: str) -> bytes | None:
    try:
        with urllib.request.urlopen(f"{HTTP_BASE}/lessons/{lesson_id}/{name}", timeout=5) as r:
            return r.read()
    except Exception:  # noqa: BLE001
        return None
RECONNECT_DELAY_S = 3


def describe_action(name: str, args: dict) -> str:
    """Ce que la personne aidée lit pendant que l'agent travaille.

    « click — icône Explorateur » est le nom de l'outil du modèle, pas une
    phrase. Le journal technique reste imprimé dans la console ; la fenêtre,
    elle, s'adresse à quelqu'un qui veut juste savoir ce qui se passe sur son
    écran.
    """
    cible = str(args.get("element") or "").strip()
    if name in ("click", "double_click"):
        verbe = "Double-clic" if name == "double_click" else "Clic"
        return f"{verbe} sur {cible}" if cible else f"{verbe} sur l'écran"
    if name == "type_text":
        texte = str(args.get("text") or "").strip()
        return f"Saisie de « {texte} »" if texte else "Saisie au clavier"
    if name == "press_key":
        touches = str(args.get("keys") or "").strip()
        return f"Touche {touches}" if touches else "Appui sur une touche"
    if name == "scroll":
        return "Défilement de la page"
    if name == "wait":
        return "Un instant…"
    return "Recherche en cours…"


class StopGate:
    """Le verrou d'arrêt. Levé depuis l'interface, lu depuis la boucle réseau."""

    def __init__(self) -> None:
        self._stopped = threading.Event()

    def raise_stop(self) -> None:
        self._stopped.set()

    def reset(self) -> None:
        self._stopped.clear()

    def is_stopped(self) -> bool:
        return self._stopped.is_set()


class SelfWindow:
    """Où se trouve la fenêtre CarePilot, en pixels écran.

    Renseignée par le thread de l'interface, lue par le thread réseau : elle
    sert à la fois à masquer la fenêtre dans les captures et à refuser les
    clics qui la viseraient.
    """

    def __init__(self) -> None:
        self._rect: tuple | None = None
        self._lock = threading.Lock()

    def set(self, rect: tuple | None) -> None:
        with self._lock:
            self._rect = rect

    def get(self) -> tuple | None:
        with self._lock:
            return self._rect


gate = StopGate()
self_window = SelfWindow()
to_ui: queue.Queue = queue.Queue()
net_loop: asyncio.AbstractEventLoop | None = None
ws_conn = None


# ---------------------------------------------------------------- réseau


async def network(auto_task: str | None = None) -> None:
    global ws_conn
    screen = Screen()
    for w in screen.warnings:
        print("ATTENTION :", w)
    to_ui.put(("screen", f"écran {screen.index} — {screen.width}x{screen.height}"))

    while True:
        try:
            async with websockets.connect(SERVER, max_size=16 * 1024 * 1024) as ws:
                ws_conn = ws
                to_ui.put(("link", "connecté"))
                if auto_task:
                    # Mode essai : pas d'interface, la demande part toute seule.
                    # Le fichier STOP tient lieu de bouton « Arrêter ».
                    asyncio.create_task(watch_stop_file())
                    await ws.send(json.dumps({"type": "help_request", "task": auto_task}))
                    auto_task = None
                async for raw in ws:
                    msg = json.loads(raw)
                    await handle(ws, screen, msg)
        except Exception as e:  # noqa: BLE001 — serveur absent ou coupé
            ws_conn = None
            to_ui.put(("link", f"hors ligne ({type(e).__name__})"))
            await asyncio.sleep(RECONNECT_DELAY_S)


async def handle(ws, screen: Screen, msg: dict) -> None:
    kind = msg.get("type")

    if kind == "capture":
        if gate.is_stopped():
            await ws.send(json.dumps({"type": "frame", "req": msg["req"]}))
            return
        frame_id = f"{int(time.time() * 1000):x}"
        b64 = await asyncio.to_thread(screen.grab, frame_id, False, self_window.get())
        await ws.send(json.dumps({
            "type": "frame", "req": msg["req"], "frame_id": frame_id,
            "png_b64": b64, "width": screen.width, "height": screen.height,
        }))

    elif kind == "execute":
        action = msg.get("action", {})
        name, args = action.get("name", ""), action.get("args", {})

        # Le refus est décidé ici, sur la machine pilotée.
        if gate.is_stopped():
            await ws.send(json.dumps({
                "type": "result", "req": msg["req"], "refused": True,
                "result": "Arrêt demandé par la personne aidée.",
            }))
            return

        to_ui.put(("action", describe_action(name, args)))
        print(f"[pont] {name} {args}", flush=True)
        try:
            result = await asyncio.to_thread(
                execute_action, screen, name, args, gate.is_stopped, self_window.get()
            )
            refused = False
        except ProtectedZone as e:
            # Refus ciblé : l'agent l'apprend et continue, la session survit.
            result, refused = str(e), False
        except PermissionError as e:
            result, refused = str(e), True
        except Exception as e:  # noqa: BLE001
            result, refused = f"échec : {type(e).__name__}: {e}", True
        print(f"[pont]   -> {result}", flush=True)
        await ws.send(json.dumps({
            "type": "result", "req": msg["req"], "result": result, "refused": refused,
        }))

    elif kind == "pairing":
        to_ui.put(("pairing", msg.get("url", "")))

    elif kind == "invitation":
        to_ui.put(("invitation", msg.get("text", "")))

    elif kind == "session":
        to_ui.put(("session", msg.get("helper_url", "")))

    elif kind == "status":
        to_ui.put(("status", msg.get("state", "")))

    elif kind == "usage":
        to_ui.put(("usage", msg))


async def watch_stop_file() -> None:
    """En mode essai, un fichier STOP joue le rôle du bouton « Arrêter »."""
    stop_file = Path(__file__).resolve().parent.parent / "STOP"
    while True:
        if stop_file.exists() and not gate.is_stopped():
            gate.raise_stop()
            print("[pont] ARRÊT (fichier STOP) — plus aucune action ne passera", flush=True)
            if ws_conn is not None:
                try:
                    await ws_conn.send(json.dumps({"type": "stop"}))
                except Exception:  # noqa: BLE001
                    pass
        await asyncio.sleep(0.2)


def send_soon(payload: dict) -> None:
    """Appelé depuis le thread de l'interface."""
    if net_loop is None or ws_conn is None:
        return

    async def _send():
        try:
            await ws_conn.send(json.dumps(payload))
        except Exception:  # noqa: BLE001
            pass

    asyncio.run_coroutine_threadsafe(_send(), net_loop)


def start_network(auto_task: str | None = None) -> None:
    global net_loop

    def runner() -> None:
        global net_loop
        net_loop = asyncio.new_event_loop()
        asyncio.set_event_loop(net_loop)
        net_loop.run_until_complete(network(auto_task))

    threading.Thread(target=runner, daemon=True).start()


# ---------------------------------------------------------------- interface


class App:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        root.title("CarePilot")
        root.configure(bg="#11151c")
        root.attributes("-topmost", True)
        root.protocol("WM_DELETE_WINDOW", self.quit)

        # Tk dimensionne les polices en points, donc en suivant le DPI de
        # l'écran. Une géométrie en pixels fixes tronque tout sur un écran
        # HiDPI — et c'est le bouton « Demander de l'aide » qui disparaît en
        # premier. On met la fenêtre à la même échelle que son texte.
        self.scale = max(1.0, root.winfo_fpixels("1i") / 96.0)
        # La fenêtre s'adresse à quelqu'un qui lit mal de près : on monte les
        # corps de texte, et la fenêtre avec — sinon on reproduit le défaut
        # HiDPI déjà corrigé une fois, où le bouton principal sortait du cadre.
        w, h = int(460 * self.scale), int(620 * self.scale)
        root.geometry(f"{w}x{h}+40+40")
        root.minsize(w, h)

        self.big = tkfont.Font(family="Segoe UI", size=16, weight="bold")
        self.mid = tkfont.Font(family="Segoe UI", size=12)
        self.small = tkfont.Font(family="Segoe UI", size=10)

        self.frame_idle = tk.Frame(root, bg="#11151c")
        self.frame_live = tk.Frame(root, bg="#11151c")
        self.frame_list = tk.Frame(root, bg="#11151c")
        self.frame_step = tk.Frame(root, bg="#11151c")
        self.frame_choice = tk.Frame(root, bg="#11151c")
        self.frame_invite = tk.Frame(root, bg="#11151c")
        self.frame_pair = tk.Frame(root, bg="#11151c")
        self.pairing_url = ""
        self._pair_qr = None

        self.lessons: list = []
        self.lesson: dict | None = None
        self.step_i = 0
        # Captures des fiches, chargées une fois par fiche et gardées :
        # Tk ramasse toute image dont plus rien ne tient la référence.
        self._images: dict[str, dict] = {}

        self.build_idle()
        self.build_live()
        self.build_list()
        self.build_step()
        self.build_choice()
        self.build_invite()
        self.build_pair()
        self.show_idle()

        # Ce que voit la personne aidée : est-ce que c'est branché, oui ou non.
        # « link : connecté » et « écran 1 — 1920x1080 » sont des informations
        # de développement ; elles restent, mais derrière CAREPILOT_DEV.
        status = tk.Frame(root, bg="#11151c")
        status.pack(side="bottom", pady=4)
        # Un rond dessiné, pas le caractère « ● » : sa taille et son
        # alignement dépendent sinon de la police installée.
        d = int(10 * self.scale)
        self.link_dot = tk.Canvas(status, width=d, height=d, bg="#11151c",
                                  highlightthickness=0, bd=0)
        self.link_dot.pack(side="left", padx=(0, int(6 * self.scale)))
        self.dot = self.link_dot.create_oval(1, 1, d - 1, d - 1, fill="#7d8b9e", width=0)
        self.link = tk.Label(status, text="Connexion…", font=self.small,
                             bg="#11151c", fg="#7d8b9e")
        self.link.pack(side="left")

        self.screen_label = tk.Label(root, text="", font=self.small,
                                     bg="#11151c", fg="#7d8b9e")
        if DEV_MODE:
            self.screen_label.pack(side="bottom")

        # Bandeau de développement : consommation du modèle. À masquer pour la
        # démo (CAREPILOT_DEV=0) — la personne aidée n'a rien à faire de ça.
        self.usage_label = tk.Label(root, text="", font=self.small, bg="#11151c", fg="#7d8b9e")
        if DEV_MODE:
            self.usage_label.pack(side="bottom")
        self.root.after(100, self.pump)

    # ---------------------------------------------------------- écran d'accueil

    def build_idle(self) -> None:
        f = self.frame_idle
        # Deux ressorts de part et d'autre : le bloc reste au milieu quelle que
        # soit la hauteur de la fenêtre, au lieu de coller en haut d'un grand
        # vide.
        tk.Frame(f, bg="#11151c").pack(expand=True)
        tk.Label(f, text="Besoin d'aide sur votre ordinateur ?",
                 font=self.big, bg="#11151c", fg="#e9eef5").pack(pady=(0, 6))
        tk.Label(f, text="Expliquez en une phrase ce que vous cherchez.",
                 font=self.mid, bg="#11151c", fg="#93a1b3").pack()

        # Tk ne sait pas espacer l'intérieur d'un Entry : on l'entoure.
        box = tk.Frame(f, bg="#0c1016")
        box.pack(fill="x", padx=24, pady=14)
        self.entry = tk.Entry(box, font=self.mid, bg="#0c1016", fg="#7d8b9e",
                              insertbackground="#e9eef5", relief="flat",
                              highlightthickness=0, bd=0)
        self.entry.pack(fill="x", padx=12, pady=10)
        # Un exemple, pas une réponse déjà écrite : une phrase préremplie en
        # texte réel oblige la personne à l'effacer avant d'écrire la sienne.
        # CAREPILOT_TASK la préremplit quand on veut enchaîner une démo.
        self.entry.insert(0, DEMO_TASK or PLACEHOLDER)
        if DEMO_TASK:
            self.entry.config(fg="#e9eef5")
        self.entry.bind("<FocusIn>", self._entry_focus)
        self.entry.bind("<FocusOut>", self._entry_blur)
        self.entry.bind("<Return>", lambda _e: self.ask_help())

        self.consent = tk.IntVar(value=0)
        # La case porte le consentement : c'est le contrôle le plus important
        # de l'écran, il ne peut pas être le plus petit.
        self.chk = tk.Checkbutton(
            f, variable=self.consent, font=self.mid, bg="#11151c", fg="#93a1b3",
            selectcolor="#0c1016", activebackground="#11151c", activeforeground="#e9eef5",
            text="J'autorise le partage de mon écran pendant cette demande",
            wraplength=int(380 * self.scale), justify="left", cursor="hand2",
            command=lambda: self.consent_error.config(text=""),
        )
        self.chk.pack(padx=24, anchor="w")

        # Le refus doit désigner ce qui bloque. Faire clignoter le champ de
        # texte quand c'est la case qui manque envoie corriger au mauvais
        # endroit — c'est ce que faisait la version précédente.
        self.consent_error = tk.Label(f, text="", font=self.small, bg="#11151c",
                                      fg="#ffb020", wraplength=int(380 * self.scale),
                                      justify="left")
        self.consent_error.pack(padx=24, anchor="w")

        tk.Button(f, text="Demander de l'aide", font=self.big, relief="flat",
                  bg="#4da3ff", fg="#04121f", activebackground="#7cbcff",
                  cursor="hand2",
                  command=self.ask_help).pack(fill="x", padx=24, pady=(18, 8), ipady=10)

        # Ce que la personne ouvre le plus souvent, à portée immédiate. C'est
        # la moitié du produit : une bonne partie des demandes d'aide se
        # résument à « où est mon dossier », et n'ont pas besoin d'un agent.
        tk.Label(f, text="Ouvrir directement", font=self.small, bg="#11151c",
                 fg="#7d8b9e").pack(pady=(20, 6))
        self.quick_box = tk.Frame(f, bg="#11151c")
        self.quick_box.pack(fill="x", padx=24)

        self.quick_msg = tk.Label(f, text="", font=self.small, bg="#11151c",
                                  fg="#ffb020", wraplength=int(380 * self.scale))
        self.quick_msg.pack(padx=24, pady=(6, 0))

        self.btn_lessons = tk.Button(
            f, text="Refaire quelque chose", font=self.mid, relief="flat",
            bg="#1a2029", fg="#e9eef5", activebackground="#2b3440", cursor="hand2",
            command=self.show_list,
        )
        self.btn_lessons.pack(fill="x", padx=24, ipady=8)

        # Désactivé tant que le serveur n'a pas envoyé le lien permanent :
        # c'est ce que `pump` réactive en recevant « pairing ».
        self.btn_invite = tk.Button(
            f, text="Inviter un proche", font=self.mid, relief="flat",
            bg="#1a2029", fg="#e9eef5", activebackground="#2b3440", cursor="hand2",
            disabledforeground="#7d8b9e", state="disabled",
            command=self.show_pair,
        )
        self.btn_invite.pack(fill="x", padx=24, pady=(8, 0), ipady=8)
        tk.Frame(f, bg="#11151c").pack(expand=True)

    def fill_quick(self) -> None:
        """Remplit la grille des dossiers et applications, les plus ouverts d'abord."""
        for w in self.quick_box.winfo_children():
            w.destroy()
        try:
            items = shortcuts.frequent(8)
        except Exception as e:  # noqa: BLE001 — l'accueil doit rester utilisable
            print("[pont] raccourcis indisponibles : " + str(e), flush=True)
            return
        for i, item in enumerate(items):
            b = tk.Button(
                self.quick_box, text=item["label"], font=self.mid, relief="flat",
                bg="#1a2029", fg="#e9eef5", activebackground="#2b3440", cursor="hand2",
                command=lambda it=item: self.open_quick(it),
            )
            b.grid(row=i // 2, column=i % 2, sticky="ew", padx=3, pady=3, ipady=8)
        self.quick_box.grid_columnconfigure(0, weight=1, uniform="q")
        self.quick_box.grid_columnconfigure(1, weight=1, uniform="q")

    def open_quick(self, item: dict) -> None:
        """La personne ouvre elle-même. Aucun agent, aucune capture, aucun réseau."""
        ok, detail = shortcuts.launch(item)
        if ok:
            self.quick_msg.config(text=f"{item['label']} est ouvert.", fg="#35c08a")
            self.root.after(4000, lambda: self.quick_msg.config(text=""))
            self.fill_quick()   # l'ordre suit l'usage
        else:
            self.quick_msg.config(text=detail, fg="#ffb020")

    def _entry_focus(self, _event=None) -> None:
        if self.entry.get() == PLACEHOLDER:
            self.entry.delete(0, "end")
        self.entry.config(fg="#e9eef5")

    def _entry_blur(self, _event=None) -> None:
        if not self.entry.get().strip():
            self.entry.delete(0, "end")
            self.entry.insert(0, PLACEHOLDER)
            self.entry.config(fg="#7d8b9e")

    # ---------------------------------------------------------- écran de session

    def build_live(self) -> None:
        f = self.frame_live
        self.banner = tk.Label(f, text="  ÉCRAN PARTAGÉ  ", font=self.big,
                               bg="#ff5c5c", fg="#ffffff")
        self.banner.pack(fill="x", pady=(0, 10))

        tk.Frame(f, bg="#11151c").pack(expand=True)
        self.doing = tk.Label(f, text="Recherche en cours…", font=self.mid,
                              bg="#11151c", fg="#e9eef5",
                              wraplength=int(390 * self.scale))
        self.doing.pack(pady=4)

        # Le lien porte un jeton de 32 caractères : personne ne le recopie à la
        # main sur un téléphone. Le proche scanne.
        self.qr_label = tk.Label(f, bg="#11151c")
        self.qr_label.pack(pady=6)
        self._qr_image = None  # référence gardée, sinon Tk la ramasse

        self.helper_url = tk.Label(f, text="", font=self.small, bg="#11151c",
                                   fg="#4da3ff", wraplength=int(370 * self.scale))
        self.helper_url.pack(pady=4)

        tk.Button(f, text="ARRÊTER", font=self.big, relief="flat",
                  bg="#ff5c5c", fg="#ffffff", activebackground="#ff8a8a", cursor="hand2",
                  command=self.stop).pack(fill="x", padx=24, pady=16, ipady=14)

        tk.Label(f, text="Vous pouvez arrêter à tout moment. Rien ne continuera.",
                 font=self.small, bg="#11151c", fg="#93a1b3").pack()
        tk.Frame(f, bg="#11151c").pack(expand=True)

    # ------------------------------------------------- CareMemory : les fiches

    def build_list(self) -> None:
        f = self.frame_list
        tk.Label(f, text="Refaire quelque chose", font=self.big,
                 bg="#11151c", fg="#e9eef5").pack(pady=(20, 4))
        tk.Label(f, text="Des manipulations que vous avez déjà faites,\nexpliquées pas à pas.",
                 font=self.mid, bg="#11151c", fg="#93a1b3", justify="center").pack(pady=(0, 10))
        # Les fiches s'accumulent : au-delà de cinq ou six, une liste figée
        # cache les dernières sans rien laisser paraître.
        wrap = tk.Frame(f, bg="#11151c")
        wrap.pack(fill="both", expand=True, padx=24)
        self.list_canvas = tk.Canvas(wrap, bg="#11151c", highlightthickness=0, bd=0)
        bar = tk.Scrollbar(wrap, orient="vertical", command=self.list_canvas.yview,
                           bg="#2b3440", activebackground="#3a4654",
                           troughcolor="#11151c", relief="flat", bd=0,
                           elementborderwidth=0, highlightthickness=0, width=12)
        self.list_canvas.configure(yscrollcommand=bar.set)
        self.list_canvas.pack(side="left", fill="both", expand=True)
        bar.pack(side="right", fill="y")

        self.list_box = tk.Frame(self.list_canvas, bg="#11151c")
        win = self.list_canvas.create_window((0, 0), window=self.list_box, anchor="nw")
        self.list_box.bind(
            "<Configure>",
            lambda _e: self.list_canvas.configure(scrollregion=self.list_canvas.bbox("all")),
        )
        self.list_canvas.bind(
            "<Configure>", lambda e: self.list_canvas.itemconfigure(win, width=e.width)
        )
        # bind_all : la molette doit marcher où que soit le pointeur, y compris
        # au-dessus d'un bouton de la liste. D'où le garde sur l'écran affiché.
        self.list_canvas.bind_all("<MouseWheel>", self._wheel)
        tk.Button(f, text="Retour", font=self.mid, relief="flat", bg="#1a2029",
                  fg="#93a1b3", activebackground="#2b3440", cursor="hand2",
                  command=self.show_idle).pack(fill="x", padx=24, pady=14, ipady=8)

    def _wheel(self, event) -> None:
        if self.frame_list.winfo_ismapped():
            self.list_canvas.yview_scroll(int(-event.delta / 120), "units")

    def build_step(self) -> None:
        f = self.frame_step
        self.step_title = tk.Label(f, text="", font=self.mid, bg="#11151c", fg="#93a1b3")
        self.step_title.pack(pady=(16, 2))
        self.step_num = tk.Label(f, text="", font=self.big, bg="#11151c", fg="#4da3ff")
        self.step_num.pack()
        # « Étape 2 sur 4 » se lit ; une barre se voit. Les deux, pour quelqu'un
        # qui veut savoir combien il reste avant d'avoir fini.
        self.step_bar = tk.Canvas(f, height=int(6 * self.scale), bg="#1a2029",
                                  highlightthickness=0, bd=0)
        self.step_bar.pack(fill="x", padx=24, pady=(8, 0))
        self.step_bar.bind("<Configure>", lambda _e: self.redraw_progress())
        self.step_text = tk.Label(f, text="", font=self.big, bg="#11151c", fg="#e9eef5",
                                  wraplength=int(380 * self.scale), justify="center")
        self.step_text.pack(pady=10, padx=16)
        self.step_img = tk.Label(f, bg="#11151c")
        self.step_img.pack(pady=6)
        self.step_check = tk.Label(f, text="", font=self.small, bg="#11151c", fg="#35c08a",
                                   wraplength=int(380 * self.scale), justify="center")
        self.step_check.pack(pady=4)

        row = tk.Frame(f, bg="#11151c")
        row.pack(fill="x", padx=24, pady=14)
        # Même corps de texte des deux côtés : sinon les deux boutons n'ont pas
        # la même hauteur et la rangée part de travers. La hiérarchie se joue
        # sur la couleur, pas sur la taille.
        tk.Button(row, text="Précédent", font=self.big, relief="flat", bg="#1a2029",
                  fg="#93a1b3", activebackground="#2b3440", cursor="hand2",
                  command=lambda: self.goto_step(self.step_i - 1)).pack(side="left", expand=True, fill="x", padx=(0, 4), ipady=8)
        self.btn_next = tk.Button(row, text="Suivant", font=self.big, relief="flat",
                                  bg="#4da3ff", fg="#04121f", activebackground="#7cbcff",
                                  cursor="hand2",
                                  command=lambda: self.goto_step(self.step_i + 1))
        self.btn_next.pack(side="left", expand=True, fill="x", padx=(4, 0), ipady=8)

        tk.Label(f, text="C'est vous qui faites la manipulation.\nL'ordinateur ne fait que vous montrer.",
                 font=self.small, bg="#11151c", fg="#7d8b9e",
                 justify="center").pack(side="bottom", pady=(0, 12))

    def show_list(self) -> None:
        for w in self.list_box.winfo_children():
            w.destroy()
        self.lessons = fetch_lessons()
        if not self.lessons:
            tk.Label(self.list_box, text="Aucune fiche pour l'instant.\nElles se créent après une demande d'aide.",
                     font=self.mid, bg="#11151c", fg="#7d8b9e", justify="center").pack(pady=24)
        for lesson in self.lessons:
            tk.Button(
                self.list_box, text=lesson.get("title", "Sans titre"), font=self.mid,
                relief="flat", bg="#1a2029", fg="#e9eef5", activebackground="#2b3440",
                anchor="w", padx=12, cursor="hand2", wraplength=int(360 * self.scale),
                justify="left",
                command=lambda L=lesson: self.open_lesson(L),
            ).pack(fill="x", pady=4, ipady=8)
        self.swap(self.frame_list)

    def build_choice(self) -> None:
        f = self.frame_choice
        self.choice_title = tk.Label(f, text="", font=self.big, bg="#11151c", fg="#e9eef5",
                                     wraplength=int(380 * self.scale), justify="center")
        self.choice_title.pack(pady=(28, 18), padx=16)

        self.btn_do_it = tk.Button(
            f, text="Faites-le pour moi", font=self.big, relief="flat",
            bg="#4da3ff", fg="#04121f", activebackground="#7cbcff",
            command=self.run_shortcut,
        )
        self.btn_do_it.pack(fill="x", padx=24, pady=(0, 6), ipady=10)
        self.choice_hint = tk.Label(f, text="", font=self.small, bg="#11151c",
                                    fg="#7d8b9e", wraplength=int(360 * self.scale),
                                    justify="center")
        self.choice_hint.pack(pady=(0, 18))

        tk.Button(f, text="Ou montrez-moi comment faire", font=self.mid, relief="flat",
                  bg="#1a2029", fg="#e9eef5", activebackground="#2b3440",
                  command=lambda: self.goto_step(0)).pack(fill="x", padx=24, ipady=8)

        self.choice_result = tk.Label(f, text="", font=self.mid, bg="#11151c",
                                      fg="#35c08a", wraplength=int(380 * self.scale),
                                      justify="center")
        self.choice_result.pack(pady=14, padx=16)

        tk.Button(f, text="Retour", font=self.mid, relief="flat", bg="#1a2029",
                  fg="#93a1b3", activebackground="#2b3440",
                  command=self.show_list).pack(fill="x", padx=24, pady=10, ipady=6)

    def run_shortcut(self) -> None:
        """Ouvre directement la destination enregistrée. Aucun modèle, aucun clic."""
        ok, detail = open_shortcut((self.lesson or {}).get("shortcut"))
        if ok:
            self.choice_result.config(text="C'est ouvert.", fg="#35c08a")
            print(f"[pont] raccourci ouvert : {detail}", flush=True)
        else:
            # Le raccourci a échoué : la fiche pas à pas reste le chemin sûr.
            self.choice_result.config(
                text=f"{detail}\nSuivez plutôt les étapes ci-dessous.", fg="#ffb020"
            )
            print(f"[pont] raccourci refuse : {detail}", flush=True)

    def open_lesson(self, lesson: dict) -> None:
        """Charge les captures une bonne fois, puis affiche la première étape.

        Elles ne changent jamais : les recharger et les redimensionner à chaque
        « Suivant » n'apporterait qu'une latence, sur une fenêtre destinée à
        quelqu'un qui lit lentement.
        """
        self.lesson = lesson
        self.load_images(lesson)

        shortcut = lesson.get("shortcut") or {}
        if shortcut.get("folder") in KNOWN_FOLDERS:
            where = FOLDER_LABELS[shortcut["folder"]]
            if shortcut.get("subfolder"):
                where += " > " + shortcut["subfolder"]
            self.choice_title.config(text=lesson.get("title", ""))
            self.choice_hint.config(text=f"Ouvre directement {where}")
            self.choice_result.config(text="")
            self.swap(self.frame_choice)
        else:
            self.goto_step(0)

    def load_images(self, lesson: dict) -> None:
        if lesson["id"] in self._images:
            return
        try:
            from PIL import Image, ImageTk
        except ImportError:
            self._images[lesson["id"]] = {}
            return

        width = int(340 * self.scale)
        cache: dict = {}
        for step in lesson.get("steps", []):
            name = step.get("image")
            if not name:
                continue
            raw = fetch_image(lesson["id"], name)
            if not raw:
                continue
            try:
                img = Image.open(io.BytesIO(raw))
                img = img.resize((width, int(img.height * width / img.width)), Image.LANCZOS)
                cache[name] = ImageTk.PhotoImage(img)
            except Exception as e:  # noqa: BLE001 — l'instruction seule reste lisible
                print(f"[pont] capture de fiche illisible : {e}", flush=True)
        self._images[lesson["id"]] = cache

    def goto_step(self, i: int) -> None:
        """Affiche une étape. N'exécute RIEN : le rejeu est pédagogique, pas automatique."""
        if self.lesson is None:
            return
        steps = self.lesson.get("steps", [])
        if i < 0:
            if (self.lesson.get("shortcut") or {}).get("folder") in KNOWN_FOLDERS:
                return self.open_lesson(self.lesson)
            return self.show_list()
        if i >= len(steps):
            return self.show_list()

        self.step_i = i
        step = steps[i]
        self.step_title.config(text=self.lesson.get("title", ""))
        self.step_num.config(text=f"Étape {i + 1} sur {len(steps)}")
        self.step_text.config(text=step.get("instruction", ""))
        check = step.get("checkpoint", "")
        self.step_check.config(text=("Vous devez voir : " + check) if check else "")
        self.btn_next.config(text="Terminé" if i == len(steps) - 1 else "Suivant")

        # Les captures sont déjà en mémoire : affichage immédiat, sans réseau.
        photo = self._images.get(self.lesson["id"], {}).get(step.get("image", ""))
        self.step_img.config(image=photo or "")

        self.swap(self.frame_step)
        # Après le swap seulement : avant, le canevas n'est pas affiché et
        # winfo_width() vaut 1, donc la barre se dessinait vide.
        self.draw_progress(i + 1, len(steps))

    def redraw_progress(self) -> None:
        if self.lesson is not None:
            self.draw_progress(self.step_i + 1, len(self.lesson.get("steps", [])))

    def draw_progress(self, done: int, total: int) -> None:
        self.step_bar.delete("all")
        self.step_bar.update_idletasks()
        width = max(self.step_bar.winfo_width(), 1)
        height = int(6 * self.scale)
        self.step_bar.create_rectangle(
            0, 0, int(width * done / max(total, 1)), height, fill="#4da3ff", width=0
        )

    # ---------------------------------------------------------- transitions

    def build_invite(self) -> None:
        """Le proche propose, la personne aidée décide. Jamais l'inverse."""
        f = self.frame_invite
        tk.Frame(f, bg="#11151c").pack(expand=True)
        tk.Label(f, text="Votre proche propose de vous aider",
                 font=self.big, bg="#11151c", fg="#e9eef5",
                 wraplength=int(380 * self.scale), justify="center").pack(pady=(0, 10), padx=16)
        self.invite_text = tk.Label(f, text="", font=self.mid, bg="#11151c", fg="#93a1b3",
                                    wraplength=int(360 * self.scale), justify="center")
        self.invite_text.pack(pady=(0, 6), padx=16)
        tk.Label(f, text="Si vous acceptez, il verra votre écran\njusqu'à ce que vous arrêtiez.",
                 font=self.small, bg="#11151c", fg="#7d8b9e", justify="center").pack(pady=(0, 22))

        tk.Button(f, text="Accepter", font=self.big, relief="flat",
                  bg="#4da3ff", fg="#04121f", activebackground="#7cbcff", cursor="hand2",
                  command=lambda: self.answer_invite(True)).pack(fill="x", padx=24, ipady=10)
        tk.Button(f, text="Non merci", font=self.mid, relief="flat",
                  bg="#1a2029", fg="#93a1b3", activebackground="#2b3440", cursor="hand2",
                  command=lambda: self.answer_invite(False)).pack(fill="x", padx=24, pady=10, ipady=8)
        tk.Frame(f, bg="#11151c").pack(expand=True)

    def answer_invite(self, accepted: bool) -> None:
        gate.reset()
        send_soon({"type": "invitation_response", "accepted": accepted})
        if accepted:
            self.doing.config(text=self.invite_text.cget("text"))
            self.banner.config(text="  ÉCRAN PARTAGÉ  ", bg="#ff5c5c")
            self.show_live()
        else:
            self.show_idle()

    def build_pair(self) -> None:
        """Le lien permanent à donner une fois à son proche.

        Il ne montre aucun écran : il permet seulement de proposer son aide.
        """
        f = self.frame_pair
        tk.Button(f, text="Retour", font=self.mid, relief="flat", bg="#1a2029",
                  fg="#93a1b3", activebackground="#2b3440", cursor="hand2",
                  command=self.show_idle).pack(side="bottom", fill="x",
                                               padx=24, pady=14, ipady=8)
        tk.Frame(f, bg="#11151c").pack(expand=True)
        tk.Label(f, text="Inviter un proche", font=self.big,
                 bg="#11151c", fg="#e9eef5").pack(pady=(0, 6))
        tk.Label(f, text="Montrez-lui ce code une fois.\nIl pourra ensuite vous proposer son aide,\nque vous resterez libre d'accepter ou non.",
                 font=self.mid, bg="#11151c", fg="#93a1b3", justify="center").pack(pady=(0, 14))
        self.pair_qr = tk.Label(f, bg="#11151c")
        self.pair_qr.pack()
        self.pair_url = tk.Label(f, text="", font=self.small, bg="#11151c",
                                 fg="#4da3ff", wraplength=int(370 * self.scale))
        self.pair_url.pack(pady=8)
        tk.Frame(f, bg="#11151c").pack(expand=True)

    def show_pair(self) -> None:
        if not self.pairing_url:
            return
        try:
            import qrcode
            from PIL import ImageTk

            img = qrcode.make(self.pairing_url, box_size=4, border=2).convert("RGB")
            side = int(170 * self.scale)
            self._pair_qr = ImageTk.PhotoImage(img.resize((side, side)))
            self.pair_qr.config(image=self._pair_qr)
        except Exception as e:  # noqa: BLE001 — le lien texte reste lisible
            print("[pont] QR indisponible : " + str(e), flush=True)
        self.pair_url.config(text=self.pairing_url)
        self.swap(self.frame_pair)

    def swap(self, frame: tk.Frame) -> None:
        for f in (self.frame_idle, self.frame_live, self.frame_list,
                  self.frame_step, self.frame_choice, self.frame_invite,
                  self.frame_pair):
            f.pack_forget()
        frame.pack(fill="both", expand=True)

    def show_idle(self) -> None:
        self.fill_quick()
        self.swap(self.frame_idle)

    def show_live(self) -> None:
        self.swap(self.frame_live)

    def ask_help(self) -> None:
        task = self.entry.get().strip()
        if not task or task == PLACEHOLDER:
            self.consent_error.config(
                text="Écrivez d'abord ce que vous cherchez, en une phrase."
            )
            self.entry.focus_set()
            return
        if not self.consent.get():
            self.consent_error.config(
                text="Cochez la case ci-dessus : sans votre accord, rien n'est partagé."
            )
            self.chk.config(fg="#ffb020")
            self.root.after(1200, lambda: self.chk.config(fg="#93a1b3"))
            return
        self.consent_error.config(text="")
        gate.reset()
        send_soon({"type": "help_request", "task": task})
        self.doing.config(text=f"« {task} »")
        self.helper_url.config(text="Création de la session…")
        self.banner.config(text="  ÉCRAN PARTAGÉ  ", bg="#ff5c5c")
        self.show_live()

    def stop(self) -> None:
        # D'abord le verrou local : plus aucune action ne passera, même si le
        # réseau est coupé ou le serveur injoignable.
        gate.raise_stop()
        send_soon({"type": "stop"})
        self.banner.config(text="  ARRÊTÉ  ", bg="#2b3440")
        self.qr_label.config(image="")
        self._qr_image = None
        self.doing.config(text="L'assistance est arrêtée. Votre écran n'est plus partagé.")
        self.helper_url.config(text="")
        self.root.after(2500, self.show_idle)

    def quit(self) -> None:
        gate.raise_stop()
        send_soon({"type": "stop"})
        self.root.after(150, self.root.destroy)

    def show_qr(self, url: str) -> None:
        """Le proche scanne, il ne tape rien."""
        try:
            import qrcode
            from PIL import ImageTk

            img = qrcode.make(url, box_size=4, border=2).convert("RGB")
            side = int(150 * self.scale)
            img = img.resize((side, side))
            self._qr_image = ImageTk.PhotoImage(img)
            self.qr_label.config(image=self._qr_image)
        except Exception as e:  # noqa: BLE001 — le lien texte reste affiché
            print(f"[pont] QR indisponible : {e}", flush=True)

    # ---------------------------------------------------------- messages réseau

    def track_self(self) -> None:
        """Publie la position de la fenêtre pour qu'elle soit masquée et protégée."""
        try:
            x, y = self.root.winfo_rootx(), self.root.winfo_rooty()
            w, h = self.root.winfo_width(), self.root.winfo_height()
            title = int(44 * self.scale)   # barre de titre, au-dessus de la zone client
            edge = int(10 * self.scale)
            self_window.set((x - edge, y - title, x + w + edge, y + h + edge))
        except tk.TclError:
            self_window.set(None)

    def pump(self) -> None:
        self.track_self()
        try:
            while True:
                kind, value = to_ui.get_nowait()
                if kind == "session":
                    self.show_qr(value)
                    self.helper_url.config(text=value)
                    print(f"\n>>> LIEN DU PROCHE : {value}\n", flush=True)
                elif kind == "action" and not gate.is_stopped():
                    self.doing.config(text=value)
                elif kind == "usage" and DEV_MODE:
                    u = value
                    pct = 100 * u["last_prompt"] / CONTEXT_LIMIT
                    cost = estimate_cost(u.get("prompt", 0), u.get("completion", 0))
                    self.usage_label.config(
                        text=(
                            f"{u['calls']} appels · {u['total']:,} tokens · "
                            f"contexte {u['last_prompt']:,}/{CONTEXT_LIMIT:,} ({pct:.0f} %) · "
                            f"~{cost * 100:.2f} ¢"
                        ).replace(",", " "),
                        fg="#ffb020" if pct > 75 else "#7d8b9e",
                    )
                elif kind == "pairing":
                    self.pairing_url = value
                    print("LIEN PERMANENT DU PROCHE : " + value, flush=True)
                    self.btn_invite.config(state="normal")

                elif kind == "invitation":
                    self.invite_text.config(text=f"« {value} »" if value else "")
                    self.swap(self.frame_invite)

                elif kind == "link":
                    online = value == "connecté"
                    couleur = "#35c08a" if online else "#ffb020"
                    self.link.config(
                        text="Connecté" if online else "Pas de connexion",
                        fg=couleur,
                    )
                    self.link_dot.itemconfigure(self.dot, fill=couleur)
                    if DEV_MODE and not online:
                        self.screen_label.config(text=value)
                elif kind == "screen":
                    if DEV_MODE:
                        self.screen_label.config(text=value)
        except queue.Empty:
            pass
        self.root.after(100, self.pump)


def main() -> None:
    args = sys.argv[1:]
    if args and args[0] == "--auto":
        # Essai sans interface : utile pour vérifier la chaîne complète en
        # pilotant le vrai écran, sans dépendre d'un clic humain.
        task = " ".join(args[1:]) or "Ouvre l'Explorateur de fichiers"
        print(f"[pont] mode essai — tâche : {task}", flush=True)
        asyncio.run(network(task))
        return

    start_network()
    root = tk.Tk()
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
