# neo_capture.py — capture Bluetooth du home-trainer depuis le Mac

Enregistre, pendant une séance MyWhoosh en ANT+, tout ce que le home-trainer publie en Bluetooth. Ne donne aucune
consigne au home-trainer.

## Une seule fois : l'installation

Dans le Terminal, depuis le dossier `ds-courses` :

```sh
git pull
cd prototypes/trainer-capture/sniff
python3 -m venv .venv
source .venv/bin/activate
pip install bleak
```

## À chaque séance

1. **DS déconnecté du Neo** (fermer l'app, ou « Disconnect » dans Sensors) : le Neo n'accepte qu'une connexion
   Bluetooth.
2. Dans le Terminal, depuis ce dossier `sniff` :
   ```sh
   source .venv/bin/activate
   python3 neo_capture.py
   ```
   La première fois, autoriser le Terminal à utiliser le Bluetooth.
3. Attendre « Connecté » et la liste des services, puis lancer MyWhoosh, home-trainer en **ANT+**.
4. Rouler en **mode simulation** (pas ERG), sur un parcours avec des montées et des descentes. Le Mac reste près du
   Neo et ne se met pas en veille.
5. **Ctrl+C** à la fin. Le fichier `capture-<date>.csv` est dans ce dossier.

À envoyer : ce CSV et le FIT MyWhoosh de la même sortie.

## Si ça coince

- « Aucun appareil Neo trouvé » : pédaler un tour pour réveiller le Neo, vérifier que DS n'y est pas connecté, ou
  `python3 neo_capture.py --list` pour voir les noms à portée.
- Autre home-trainer : `python3 neo_capture.py --name KICKR` (une partie de son nom Bluetooth).
- « Connexion perdue » : le programme se reconnecte tout seul.
