"""Harnais de visée Holo — tout en local, sans backend ni WebSocket.

Ce n'est pas le produit : c'est l'outil qui sert à vérifier que le modèle voit
juste sur une machine donnée. Il a servi à trouver le mauvais écran et la
température trop haute ; gardez-le pour calibrer avant une démo.

    python holo_agent.py --check                 un aller-retour, sans toucher la souris
    python holo_agent.py --check "Clique sur X"   idem, sur une cible précise
    python holo_agent.py "Ouvre l'Explorateur"    boucle complète, l'agent agit
"""

from __future__ import annotations

import json
import sys
import time
from datetime import datetime
from pathlib import Path

import pyautogui

from bridge.screen import Screen, execute_action
from carepilot_tools import (
    MIN_SECONDS_PER_STEP,
    MODEL,
    SYSTEM_PROMPT,
    TEMPERATURE,
    TOOLS,
    make_client,
    observation,
    to_assistant_message,
    trim_to_last_n_images,
)

BASE_DIR = Path(__file__).parent
STOP_FILE = BASE_DIR / "STOP"
TRACE_FILE = BASE_DIR / "trace.jsonl"
MAX_STEPS = 25

client = make_client()


def stop_requested() -> bool:
    return STOP_FILE.exists()


def log_trace(record: dict) -> None:
    with TRACE_FILE.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------- boucle


def run(task: str, max_steps: int = MAX_STEPS) -> str:
    screen = Screen()
    for w in screen.warnings:
        print("ATTENTION :", w)

    session_id = datetime.now().strftime("%Y%m%d-%H%M%S")
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": task},
    ]
    print(f"[{session_id}] écran {screen.width}x{screen.height} — tâche : {task}")

    for step in range(1, max_steps + 1):
        if stop_requested():
            return "Arrêté par la personne aidée."

        t0 = time.time()
        frame_id = f"{session_id}-step{step:02d}"
        b64 = screen.grab(frame_id, save=True)
        messages.append(observation(b64))
        trim_to_last_n_images(messages)

        resp = client.chat.completions.create(
            model=MODEL,
            messages=messages,
            tools=TOOLS,
            tool_choice="required",
            temperature=TEMPERATURE,
        )
        msg = resp.choices[0].message
        messages.append(to_assistant_message(msg))

        if not msg.tool_calls:
            print(f"  step {step}: aucune action proposée, nouvelle observation")
            continue

        for call in msg.tool_calls:
            name = call.function.name
            args = json.loads(call.function.arguments or "{}")
            print(f"  step {step}: {name} {args}")
            base = {"session": session_id, "step": step, "frame": frame_id,
                    "tool": name, "args": args}

            if name == "answer":
                log_trace(base)
                return args["content"]

            if name == "ask_helper":
                log_trace(base)
                print(f"\n>>> QUESTION AU PROCHE : {args['question']}")
                if args.get("options"):
                    print("    options :", " / ".join(args["options"]))
                reply = input("    réponse du proche (vide = arrêter) > ").strip()
                if not reply:
                    return "Session suspendue en attente du proche."
                result = f"Réponse du proche : {reply}"
            else:
                try:
                    result = execute_action(screen, name, args, stop_requested)
                except PermissionError as e:
                    return str(e)

            log_trace({**base, "result": result})
            messages.append({"role": "tool", "tool_call_id": call.id, "content": result})

        elapsed = time.time() - t0
        if elapsed < MIN_SECONDS_PER_STEP:
            time.sleep(MIN_SECONDS_PER_STEP - elapsed)

    return "Budget d'étapes épuisé."


# ---------------------------------------------------------------- sonde


def check(task: str = "Ouvre l'Explorateur de fichiers") -> None:
    """Un seul aller-retour vers Holo, sans jamais toucher la souris."""
    screen = Screen()
    for w in screen.warnings:
        print("ATTENTION :", w)
    print(f"écran détecté : {screen.width}x{screen.height} "
          f"(origine {screen.origin_x},{screen.origin_y})")

    b64 = screen.grab("check", save=True)
    t0 = time.time()
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": task},
            observation(b64),
        ],
        tools=TOOLS,
        tool_choice="required",
        temperature=TEMPERATURE,
    )
    msg = resp.choices[0].message
    print(f"réponse de {MODEL} en {time.time() - t0:.1f} s")

    if not msg.tool_calls:
        print("ÉCHEC : aucune action proposée. Contenu brut :", msg.content)
        sys.exit(2)

    for call in msg.tool_calls:
        args = json.loads(call.function.arguments or "{}")
        print(f"  action proposée : {call.function.name} {args}")
        if "x" in args and "y" in args:
            px, py = screen.to_pixels(args["x"], args["y"])
            print(f"  -> clic qui serait exécuté en ({px}, {py}) px — NON exécuté")

    print("\nOK : la chaîne capture -> Holo -> action fonctionne.")


def main() -> None:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)

    if args[0] == "--check":
        check(" ".join(args[1:]) or "Ouvre l'Explorateur de fichiers")
        return

    STOP_FILE.unlink(missing_ok=True)
    try:
        print("\nRÉSULTAT :", run(" ".join(args)))
    except pyautogui.FailSafeException:
        print("\nArrêt d'urgence (failsafe souris).")


if __name__ == "__main__":
    main()
