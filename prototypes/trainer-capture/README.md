# TrainerCapture — décodeur et mode capture

Paquet Swift qui décode tout ce qu'un home-trainer et une ceinture publient en Bluetooth, et enregistre une séance
notification par notification. Objectif : savoir, sur une vraie sortie MyWhoosh, **d'où peuvent venir la vitesse et
la pente**, en écoutant seulement, pendant que l'app indoor pilote le home-trainer en ANT+ FE-C.

## Ce qui est écouté

| Caractéristique | Service | Ce qu'on en tire |
|---|---|---|
| `2A63` Cycling Power Measurement | `1818` | Puissance ; cadence par les tours de pédalier ; vitesse par les tours de roue, si publiés |
| `2AD2` FTMS Indoor Bike Data | `1826` | Vitesse, cadence, puissance, distance, si publiées |
| `2ADA` FTMS Fitness Machine Status | `1826` | **Pente** (code `0x12`), consigne ERG (code `0x08`), si le home-trainer les annonce |
| `2A37` Heart Rate Measurement | `180D` | FC, et si la ceinture touche la peau |
| `6E40FEC2-…` canal FE-C de Tacx | `6E40FEC1-…` | Page 16 (vitesse), page 25 (puissance, cadence), page 71 (dernière consigne reçue, **pente comprise**) |

Le point de contrôle FTMS (`2AD9`) n'est jamais utilisé : la capture n'envoie aucune consigne au home-trainer.

Une seule écriture existe, **désactivée par défaut** : demander la page 71 au canal FE-C de Tacx
(`pollsFECCommandStatus`). Ce n'est pas une consigne, c'est une demande d'information : le Neo répond en publiant la
dernière commande qu'il a reçue, donc la pente que MyWhoosh lui a envoyée en ANT+. À essayer lors d'une deuxième
séance, une fois la première capture faite sans rien écrire.

## Brancher sur la couche Bluetooth de l'app

La capture ne prend pas la main sur `CBPeripheral` : l'app garde son délégué, et lui transmet les notifications.

```swift
import CoreBluetooth
import TrainerCapture

let capture = try CaptureSession(directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])

// 1. À la découverte des services, s'abonner à tout ce que la capture sait lire.
let wanted = Set(TrainerCharacteristic.allCases.map { CBUUID(string: $0.rawValue) })
func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    for c in service.characteristics ?? [] where wanted.contains(c.uuid) {
        p.setNotifyValue(true, for: c)
    }
}

// 2. Transmettre chaque notification.
func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
    guard let value = c.value else { return }
    capture.record(characteristic: c.uuid.uuidString, value: value)
    // capture.metrics : puissance, cadence, vitesse (et sa source), FC, pente annoncée, pente estimée, mode.

    // 3. Facultatif, deuxième séance seulement : relayer la demande de page 71.
    if let request = capture.pendingFECRequest(),
       let fecWrite = p.services?.flatMap({ $0.characteristics ?? [] })
           .first(where: { $0.uuid == CBUUID(string: TacxFEC.writeCharacteristic) }) {
        p.writeValue(request, for: fecWrite, type: .withResponse)
    }
}

// 4. En fin de séance : le fichier à partager.
let url = capture.finish()
```

Pour la découverte des services, ajouter `1818`, `1826`, `180D` et `6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E` à la
liste passée à `discoverServices`. Si le canal FE-C n'apparaît pas, le Neo ne l'expose pas à ce firmware.

## Le fichier produit

`capture-<date>.csv`, une ligne par notification :

`heure, t_s, caracteristique, brut, decodage, puissance_w, cadence_rpm, vitesse_kmh, source_vitesse, fc_bpm,
pente_trainer_pct, source_pente, pente_estimee_pct, mode`

- **brut** : les octets reçus, en hexadécimal. On peut tout redécoder plus tard, même ce que le décodeur ignore.
- **source_vitesse** : `FTMS`, `FE-C 16` ou `CPS roue`, la plus prioritaire encore fraîche (moins de 3 s).
- **pente_trainer_pct** : la pente annoncée par le Neo, si elle apparaît quelque part (`FTMS 2ADA` ou `FE-C 71`).
- **pente_estimee_pct** : la pente recalculée avec la puissance et la vitesse, lissée sur 8 s (voir
  `GradeEstimator` ; masse 85 kg, CdA 0,30 m², Crr 0,004 par défaut, à ajuster). Vide en mode ERG.
- **mode** : `SIM`, `ERG` ou `?`, selon les consignes vues passer.

## Protocole

1. DS d'abord, connecté au Neo et à la ceinture en Bluetooth ; puis MyWhoosh en ANT+ FE-C.
2. Une sortie MyWhoosh d'une vingtaine de minutes avec de vraies montées et descentes, en mode simulation (pas ERG).
3. Partager le CSV, et le FIT MyWhoosh de la même sortie (il contient l'altitude) : on comparera la pente
   annoncée ou estimée au profil réel.

## Tests

`swift test` sur un Mac. Les vecteurs d'octets des tests suivent les normes Bluetooth (Cycling Power, FTMS,
Heart Rate) et ANT+ FE-C ; ils n'ont pas encore été comparés à de vraies trames du Neo : c'est l'objet de la capture.
