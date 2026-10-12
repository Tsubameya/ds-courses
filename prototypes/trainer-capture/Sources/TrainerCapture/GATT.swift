import Foundation

/// Les caractéristiques que la capture écoute. Toutes en notification seule :
/// le mode capture n'écrit jamais sur un point de contrôle.
public enum TrainerCharacteristic: String, CaseIterable {
    /// Cycling Power Measurement (service 0x1818).
    case cyclingPowerMeasurement = "2A63"
    /// FTMS Indoor Bike Data (service 0x1826).
    case indoorBikeData = "2AD2"
    /// FTMS Fitness Machine Status (service 0x1826) : changements de consigne, dont la pente.
    case fitnessMachineStatus = "2ADA"
    /// Heart Rate Measurement (service 0x180D).
    case heartRateMeasurement = "2A37"
    /// Canal FE-C de Tacx sur Bluetooth, sens home-trainer → téléphone.
    case tacxFECRead = "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"

    public var service: String {
        switch self {
        case .cyclingPowerMeasurement: return "1818"
        case .indoorBikeData, .fitnessMachineStatus: return "1826"
        case .heartRateMeasurement: return "180D"
        case .tacxFECRead: return TacxFEC.service
        }
    }

    /// Reconnaît une caractéristique à partir de `CBUUID.uuidString`, qu'il soit court (« 2A63 »)
    /// ou complet (« 00002A63-0000-1000-8000-00805F9B34FB »).
    public init?(uuid: String) {
        let upper = uuid.uppercased()
        let baseSuffix = "-0000-1000-8000-00805F9B34FB"
        let short = upper.count == 36 && upper.hasPrefix("0000") && upper.hasSuffix(baseSuffix)
            ? String(upper.dropFirst(4).prefix(4))
            : upper
        self.init(rawValue: short)
    }
}

public enum TacxFEC {
    public static let service = "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E"
    /// Sens téléphone → home-trainer. Le mode capture ne l'utilise que pour `TacxFEC.requestCommandStatus()`.
    public static let writeCharacteristic = "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"
}
