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
echo
echo "Demander aussi au Neo la pente qu'il reçoit de MyWhoosh (page 71 FE-C, toutes les 5 s) ?"
echo "C'est une demande d'information, pas une consigne de résistance."
read -r -p "Réponds o (oui) ou n (non), puis Entrée : " ASK
case "$ASK" in
  [oOyY]*) .venv/bin/python3 neo_capture.py --fec-status ;;
  *)       .venv/bin/python3 neo_capture.py ;;
esac
open .
echo
echo "Tu peux fermer cette fenêtre."
