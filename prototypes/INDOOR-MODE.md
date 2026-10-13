# Mode de session « indoor » — décisions

Notes de conception, à reprendre dans le code de l'app. Validé par une séance MyWhoosh le 2026-10-12 : DS et
MyWhoosh ont enregistré la même puissance moyenne (211,6 W), la même NP (225,4 / 225,7 W), la même cadence et la
même FC, sans aucune perte de signal.

## Connexion

- DS se connecte **en premier**, en Bluetooth, au home-trainer et à la ceinture. Le Neo n'accepte qu'une connexion
  Bluetooth : celui qui arrive le premier la garde.
- L'app indoor (MyWhoosh, Zwift…) se connecte **en ANT+ FE-C**, qui pilote la résistance.
- DS **écoute seulement** : jamais d'écriture sur le point de contrôle FTMS (`2AD9`). Deux apps qui donnent des
  consignes au même home-trainer se battraient. Le pilotage par DS (rouler un parcours en Race Mode) est un mode à
  part, quand DS est seul connecté.
- À dire dans l'aide : « dans votre app indoor, connectez le home-trainer en ANT+ ». Cas non couvert : pas de
  clé ANT+ sur l'ordinateur, ou app indoor sur tablette en Bluetooth seulement.
- Compromis assumé : un home-trainer qui n'accepte **qu'une** connexion Bluetooth (le Tacx Neo de première
  génération, plus de dix ans) ne peut pas servir à la fois l'app indoor en Bluetooth et DS. Sans clé ANT+ côté app
  indoor, DS ne lira pas le home-trainer. Échappatoires, dans l'ordre :
  1. un capteur de puissance sur le vélo (pédales, manivelle) connecté à DS, le home-trainer restant à l'app indoor ;
  2. la ceinture cardio seule, si elle accepte deux connexions ;
  3. plus tard, l'import de la sortie après coup (FIT, Strava).
  L'aide doit le dire en une phrase plutôt que laisser l'utilisateur chercher pourquoi DS ne trouve pas le Neo.

## Enregistrement

- **Localisation désactivée automatiquement** quand le type de session « indoor » est choisi, et seulement pour ce
  type, conformément à la politique de confidentialité ; l'app le mentionne à l'utilisateur. Sans GPS, pas de
  distance ni de vitesse fantômes (0,73 km et 12 km/h de pointe relevés lors de l'essai, téléphone immobile).
- Pas de météo ni d'analyse du vent.
- FIT exporté en `sub_sport` `indoor_cycling` (ou `virtual_activity`).
- Auto-pause : jamais sur la vitesse GPS, et **pas non plus sur 0 W / 0 rpm**. En descente, le Neo entraîne
  lui-même son volant (roue libre simulée) : on peut ne pas pédaler pendant une longue descente sans être arrêté.
  Si la vitesse du Neo est disponible, pause quand elle tombe à 0 ; sinon, pas d'auto-pause en indoor.
- Départ : bouton Flic 2 pour commencer ; ensuite, démarrage automatique au-dessus d'un seuil de puissance.

## Vitesse et pente

- La vitesse n'est pas dans la mesure de puissance (`2A63`). À chercher dans FTMS `2AD2` ou FE-C page 16. Test le
  plus simple : l'app nRF Connect sur l'iPhone, à la place de DS, pendant une séance MyWhoosh en ANT+.
- En descente, le Neo continue de faire tourner son volant : sa vitesse suit la simulation même à 0 W. C'est une
  bonne nouvelle pour la distance, et l'estimation de pente doit accepter P = 0 avec v > 0 (force motrice nulle).
- La pente peut se recalculer à partir de la puissance et de la vitesse : testé sur le FIT MyWhoosh avec sa vitesse
  virtuelle, écart moyen de 0,1 à 0,4 point de pente, corrélation 0,99. Reste à vérifier avec la vitesse du Neo.

## Caractérisation

- Sous le titre principal, un sélecteur à trois positions : **Toutes · Extérieur · Indoor**, plutôt qu'un simple
  « inclure les sessions indoor ». Une position supplémentaire suffit pour comparer directement les deux.
- Par défaut : Toutes. Le choix est mémorisé.
- En comparaison, superposer les courbes (puissance-durée, CP, W′) extérieur et indoor.
- Afficher la source de puissance de chaque série : si l'indoor vient du home-trainer et l'extérieur d'un capteur
  sur le vélo, une partie de l'écart vient des capteurs, pas du cycliste.

## Affichage en séance (toutes sessions)

- Couleur du pourcentage de réserve (W′bal) : normal au-dessus de 50 %, **jaune** à 50 % et moins, **orange** à
  35 % et moins, **magenta** à 15 % et moins.
- Hystérésis de 2 points en remontant (on ne repasse de jaune à normal qu'à 52 %), pour éviter que la couleur
  clignote quand la réserve oscille autour d'un seuil.
- La couleur ne doit pas être le seul signal : changer aussi un second indice (graisse du chiffre, pastille ou
  jauge) pour rester lisible en cas de daltonisme et d'un coup d'œil en plein effort.
