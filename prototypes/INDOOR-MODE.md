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

## Enregistrement

- **Localisation désactivée automatiquement** quand le type de session « indoor » est choisi, et seulement pour ce
  type, conformément à la politique de confidentialité ; l'app le mentionne à l'utilisateur. Sans GPS, pas de
  distance ni de vitesse fantômes (0,73 km et 12 km/h de pointe relevés lors de l'essai, téléphone immobile).
- Pas de météo ni d'analyse du vent.
- FIT exporté en `sub_sport` `indoor_cycling` (ou `virtual_activity`).
- Auto-pause fondée sur la puissance et la cadence (0 W et 0 rpm pendant plus de 5 s), jamais sur la vitesse GPS.
- Départ : bouton Flic 2 pour commencer ; ensuite, démarrage automatique au-dessus d'un seuil de puissance.

## Vitesse et pente

- La vitesse n'est pas dans la mesure de puissance (`2A63`). À chercher dans FTMS `2AD2` ou FE-C page 16 : c'est
  l'objet du module `trainer-capture`.
- La pente peut se recalculer à partir de la puissance et de la vitesse : testé sur le FIT MyWhoosh avec sa vitesse
  virtuelle, écart moyen de 0,1 à 0,4 point de pente, corrélation 0,99. Reste à vérifier avec la vitesse du Neo.

## Caractérisation

- Sous le titre principal, un sélecteur à trois positions : **Toutes · Extérieur · Indoor**, plutôt qu'un simple
  « inclure les sessions indoor ». Une position supplémentaire suffit pour comparer directement les deux.
- Par défaut : Toutes. Le choix est mémorisé.
- En comparaison, superposer les courbes (puissance-durée, CP, W′) extérieur et indoor.
- Afficher la source de puissance de chaque série : si l'indoor vient du home-trainer et l'extérieur d'un capteur
  sur le vélo, une partie de l'écart vient des capteurs, pas du cycliste.
