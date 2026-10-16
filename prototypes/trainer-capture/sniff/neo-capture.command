#!/bin/bash
# Lance la capture dans le Terminal. Double-cliquable dans le Finder, et ouvert par l'app Neo Capture.
# ★ Ouvert COMME UN DOCUMENT par le Terminal (open -a Terminal, ou double-clic), pas exécuté par un
#   ordre AppleScript « do script » : dans ce second cas, macOS imputait la demande Bluetooth au
#   lanceur et la refusait, alors que le Terminal était autorisé.
cd "$(dirname "$0")" || exit 1
clear
if ! .venv/bin/python3 -c 'import bleak' 2>/dev/null; then
  echo "Installation de bleak (une minute)…"
  rm -rf .venv && python3 -m venv .venv \
    && .venv/bin/python3 -m pip install --upgrade pip \
    && .venv/bin/python3 -m pip install bleak \
    && .venv/bin/python3 -c 'import bleak' && echo "Installation réussie." \
    || { echo "Échec de l'installation : copie ce qui précède à Claude."; exit 1; }
fi
.venv/bin/python3 neo_capture.py
open .
echo
echo "Tu peux fermer cette fenêtre."
