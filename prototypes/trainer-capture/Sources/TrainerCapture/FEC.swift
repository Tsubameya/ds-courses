import Foundation

/// Une page ANT+ FE-C de 8 octets, telle que le canal FE-C de Tacx la fait passer en Bluetooth.
public enum FECPage: Equatable {
    /// Page 16 : données générales.
    case general(speed: Double, distanceRollover: Int, elapsedQuarterSeconds: Int, heartRate: Int?)
    /// Page 25 : données propres au home-trainer.
    case trainer(cadence: Int?, power: Int?, accumulatedPower: Int)
    /// Pages 48 à 51 : consignes. Un home-trainer ne les émet pas ; on les retrouve dans la page 71.
    case basicResistance(percent: Double)
    case targetPower(watts: Double)
    case windResistance(coefficient: Double?, windSpeed: Int?, draftingFactor: Double?)
    case trackResistance(grade: Double?, crr: Double?)
    /// Page 71 : état de la dernière commande reçue par le home-trainer, d'où qu'elle vienne.
    /// `status` : 0 réussie, 1 échouée, 2 non prise en charge, 3 rejetée, 4 en cours, 255 aucune encore.
    indirect case commandStatus(lastCommand: UInt8, sequence: UInt8, status: UInt8, command: FECPage?)
    case other(page: UInt8, bytes: Data)

    /// Accepte un message ANT complet (A4 · longueur · identifiant · canal · 8 octets · somme de contrôle)
    /// ou les 8 octets de la page seuls.
    public init?(_ data: Data) {
        let bytes = Array(data)
        if bytes.count == 8 {
            self.init(page: bytes)
        } else if bytes.count >= 12, bytes[0] == 0xA4, [0x4E, 0x4F].contains(bytes[2]) {
            self.init(page: Array(bytes[4..<12]))
        } else {
            return nil
        }
    }

    init?(page b: [UInt8]) {
        guard b.count == 8 else { return nil }
        switch b[0] {
        case 0x10:
            self = .general(
                speed: Double(UInt16(b[4]) | UInt16(b[5]) << 8) / 1000 * 3.6,   // 0,001 m/s → km/h
                distanceRollover: Int(b[3]),
                elapsedQuarterSeconds: Int(b[2]),
                heartRate: b[6] == 0xFF ? nil : Int(b[6]))
        case 0x19:
            let power = Int(b[5]) | Int(b[6] & 0x0F) << 8
            self = .trainer(
                cadence: b[2] == 0xFF ? nil : Int(b[2]),
                power: power == 0xFFF ? nil : power,
                accumulatedPower: Int(b[3]) | Int(b[4]) << 8)
        case 0x47:
            // Les octets 4 à 7 reprennent les données de la commande, à replacer en fin de page.
            let echoed: FECPage?
            switch b[1] {
            case 0x30, 0x31, 0x32, 0x33:
                echoed = FECPage(page: [b[1], 0xFF, 0xFF, 0xFF, b[4], b[5], b[6], b[7]])
            default:
                echoed = nil
            }
            self = .commandStatus(lastCommand: b[1], sequence: b[2], status: b[3], command: echoed)
        case 0x30:
            self = .basicResistance(percent: Double(b[7]) / 2)
        case 0x31:
            self = .targetPower(watts: Double(UInt16(b[6]) | UInt16(b[7]) << 8) / 4)
        case 0x32:
            self = .windResistance(
                coefficient: b[5] == 0xFF ? nil : Double(b[5]) / 100,
                windSpeed: b[6] == 0xFF ? nil : Int(b[6]) - 127,   // km/h
                draftingFactor: b[7] == 0xFF ? nil : Double(b[7]) / 100)
        case 0x33:
            let raw = UInt16(b[5]) | UInt16(b[6]) << 8
            self = .trackResistance(
                grade: raw == 0xFFFF ? nil : Double(raw) / 100 - 200,     // %
                crr: b[7] == 0xFF ? nil : Double(b[7]) * 5e-5)
        default:
            self = .other(page: b[0], bytes: Data(b))
        }
    }
}

extension TacxFEC {
    /// Message ANT « demande de la page 71 », à écrire sur `writeCharacteristic`.
    ///
    /// Ce n'est pas une consigne de résistance : le home-trainer répond seulement en publiant
    /// la page 71, qui contient la dernière commande reçue (la pente envoyée par MyWhoosh en ANT+).
    /// C'est malgré tout une écriture : à réserver aux essais, une demande toutes les quelques secondes.
    public static func requestCommandStatus(channel: UInt8 = 5) -> Data {
        // Page 70 : numéro de série de l'émetteur (2 octets, inutilisés), descripteurs (2), réponse
        // demandée (une transmission), page demandée, type de commande (demande de page).
        let page: [UInt8] = [0x46, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x47, 0x01]
        var message: [UInt8] = [0xA4, 0x09, 0x4F, channel] + page
        message.append(message.reduce(0, ^))
        return Data(message)
    }
}
