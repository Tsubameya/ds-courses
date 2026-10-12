# Sonde Santé — prototype iOS

Une app jetable qui répond à une seule question : **les sorties vélo indoor (Zwift, MyWhoosh, Rouvy, TrainerRoad…)
arrivent-elles dans Apple Santé, assez vite et assez complètes, pour que Directeur Sportif les récupère sans
serveur ?**

Elle ne fait rien d'autre que lire et rapporter. Elle n'écrit rien dans Santé.

## Ce qu'elle mesure

Pour chaque sortie vélo des 90 derniers jours (les 30 plus récentes) :

- **l'app qui l'a écrite** (nom, identifiant, version), l'appareil, et si la séance est marquée « en intérieur » ;
- **les données présentes** : puissance, fréquence cardiaque, cadence, vitesse, distance, énergie. Pour chacune, le
  nombre d'échantillons rattachés à la séance, et ce qui a été enregistré pendant la séance, app par app, avec
  moyenne et maximum ;
- les résumés enregistrés au niveau de la séance, le tracé GPS, les métadonnées brutes ;
- **les doublons** : séances d'apps différentes qui se chevauchent (Zwift et Strava qui écrivent la même sortie).

Et en continu, **les détections automatiques** : dès que l'accès est autorisé, l'app demande à iOS de la réveiller
quand une séance est écrite dans Santé. Chaque réveil est noté avec le délai entre la fin de la séance et sa
détection, et l'état de l'app à ce moment (arrière-plan ou non). Une notification s'affiche à chaque détection.

Le bouton de partage exporte tout en texte : c'est ce rapport qu'il faut renvoyer.

## Lancer l'app

Il faut un Mac avec Xcode 15 ou plus récent, et un iPhone sous iOS 17 ou plus (Santé n'existe pas dans le
simulateur avec de vraies données).

Avec [XcodeGen](https://github.com/yonaskolb/XcodeGen) :

```sh
brew install xcodegen
cd prototypes/healthkit-probe
xcodegen
open HealthProbe.xcodeproj
```

Sans XcodeGen : créer dans Xcode une app iOS SwiftUI nommée `HealthProbe`, remplacer ses fichiers Swift par ceux de
`Sources/`, puis dans *Signing & Capabilities* ajouter **HealthKit** en cochant **Background Delivery**. Dans
*Info*, ajouter `NSHealthShareUsageDescription` (Privacy — Health Share Usage Description).

Dans les deux cas, choisir son équipe dans *Signing & Capabilities*, puis lancer sur l'iPhone. Un compte
développeur payant peut être nécessaire pour la capacité HealthKit.

## Protocole d'essai

1. Lancer l'app, toucher **Autoriser l'accès à Santé**, tout accepter, autoriser les notifications.
2. Toucher **Analyser** une première fois : on voit ce que Santé contient déjà.
3. Revenir à l'écran d'accueil sans forcer l'app à quitter : iOS peut ne plus réveiller une app balayée hors du
   sélecteur d'apps. Un essai après l'avoir balayée dira si c'est le cas ici.
4. Faire une sortie dans chaque configuration ci-dessous, puis attendre sans ouvrir la sonde. Noter si une
   notification arrive, et quand.
5. Ouvrir la sonde, toucher **Analyser**, puis **Exporter le rapport**.

| Configuration | Ce qu'on vérifie |
|---|---|
| Zwift sur iPhone/iPad | Zwift écrit-il dans Santé, avec la puissance ? |
| Zwift sur PC, Mac ou Apple TV + Companion | Companion écrit-il quelque chose ? |
| MyWhoosh, Rouvy, TrainerRoad (chacun) | Même question, app par app |
| N'importe laquelle sur PC → Strava, avec l'option Santé de Strava activée | Strava réécrit-il dans Santé une sortie qu'il n'a pas enregistrée ? Avec quelles données ? |
| Deux chemins actifs à la fois (l'app et Strava) | Doublons, et lequel est le plus complet |

Les réglages à noter pour chaque essai : l'option Santé dans l'app d'entraînement, et dans Strava
(*Réglages › Applications, services et appareils › Santé*).

## Ce qu'il faut savoir en lisant les résultats

- iOS ne dit jamais à une app que la lecture lui a été refusée : un type refusé donne simplement « rien ». En cas
  de doute, vérifier *Réglages › Santé › Accès aux données et appareils › Sonde Santé*.
- Les données de Santé sont chiffrées tant que le téléphone est verrouillé : une détection peut n'arriver qu'au
  déverrouillage suivant. C'est précisément ce que le délai mesure.
- « Rattachés » compte les échantillons que l'app d'origine a liés à la séance ; « pendant la séance » compte tout
  ce qui a été enregistré dans l'intervalle, y compris par une montre portée en même temps.

Ce prototype n'a pas sa place dans ce dépôt de données à terme : il devra rejoindre le code de l'app.
