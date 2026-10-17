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
- À faire plus tard : une table de compatibilité des home-trainers, d'après leurs fiches techniques et des essais
  (nombre de connexions Bluetooth simultanées, FTMS, FE-C sur Bluetooth, vitesse publiée, ANT+ FE-C). L'avertissement
  peut alors devenir précis : affiché seulement pour les modèles concernés, au moment où DS ne parvient pas à s'y
  connecter pendant une séance indoor.

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

Mesuré le 2026-10-16 (Tacx Neo 10423, MyWhoosh « Montréal » en ANT+ FE-C, 26 min, 245 m D+), en écoutant le Neo en
Bluetooth depuis le Mac (`trainer-capture/sniff`).

- **Ce Neo n'expose pas FTMS** (`1826`). Il publie : Cycling Power (`2A63`, et `2A64` vecteur de pédalage), CSC
  (`2A5B`, tours de roue virtuels) et le canal FE-C de Tacx (`6E40FEC1…`, pages 16, 25, 71…).
- **Puissance** : identique à MyWhoosh (écart moyen 4 W par seconde).
- **Vitesse** : disponible (FE-C page 16, ou CSC avec ~2,39 m par tour), mais c'est **la vitesse propre du Neo**, pas la
  vitesse virtuelle de MyWhoosh : 27,5 km/h de moyenne contre 31,2, corrélation 0,91, et nettement plus basse en roue
  libre dans les descentes. La distance qu'on en tirerait serait ~12 % plus courte que celle de MyWhoosh.
- **Pente** : le Neo ne connaît que **la consigne** que MyWhoosh lui envoie, pas la pente de la route. Lue en page 71
  (en la demandant, page 70, sur `6E40FEC3`) : corrélation 0,98 avec le profil, mais **0,55 × la pente réelle en
  montée** — exactement le réglage « difficulté » de MyWhoosh, vérifié à 55 % et **plafonnée à −2 % en descente**. Elle dit ce que les jambes ont
  senti, pas ce que la route faisait. Connaissant le réglage, on retrouverait la pente réelle des montées
  (consigne ÷ 0,55, à 0,25 point près) ; pas celle des descentes, écrêtées.
- La pente et l'altitude réelles n'existent que dans MyWhoosh : on ne les aura qu'avec son FIT, après coup.
- Lire la page 71 impose d'**écrire** une demande au Neo : ce n'est pas une consigne de résistance, mais cela déroge
  au principe « DS écoute seulement ». À décider avant de l'utiliser dans l'app.

**Conséquence pour la v1** : puissance, cadence, FC et durée en direct (validés deux fois) ; la vitesse du Neo peut
servir à l'auto-pause (vitesse nulle) mais ne doit pas être présentée comme la vitesse ou la distance de la sortie ;
pas de pente affichée. La distance, la vitesse et le dénivelé « officiels » viendront plus tard de l'import du FIT de
l'app indoor.

## Validation de la v1 (2026-10-17)

Codée par la session principale de DS dans le labo `_ui-lab/indoor-v1` (famille de séances Practice · Competition ·
Indoor), build 2026101602 installé sur l'iPhone. Séance de 296 s marquée « indoor », comparée au FIT MyWhoosh
(« Toulouse Plains », 284 secondes communes après un décalage d'horloge de +32 s) :

| | DS | MyWhoosh |
|---|---|---|
| Puissance moyenne | 208,2 W | 210,4 W (écart moyen 10,9 W par seconde) |
| Cadence moyenne | 76,4 rpm | 76,5 rpm |
| FC moyenne | 140,4 bpm | 140,3 bpm |

Aucune position ni vent enregistrés, pas d'auto-pause.

- **Décision de Guillaume (17/10)** : pas de vitesse affichée en indoor pour l'instant. La vitesse du Neo n'est pas
  celle des apps gamifiées (MyWhoosh, Zwift) ; elle conviendrait plus tard pour TrainerRoad et les logiciels non
  gamifiés.
- Reste au labo : le réglage Auto-pause doit afficher « Off » tant qu'un type Indoor est choisi ; ne plus écrire
  `altRaw` ni `baro` dans les échantillons indoor.

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
