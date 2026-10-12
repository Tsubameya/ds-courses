import Foundation

/// FTMS Indoor Bike Data (0x2AD2). Seuls les champs annoncés par les drapeaux sont présents.
public struct IndoorBikeData: Equatable {
    /// km/h. Attention : présent quand le bit 0 (« More Data ») vaut 0.
    public var speed: Double?
    public var averageSpeed: Double?
    /// tr/min.
    public var cadence: Double?
    public var averageCadence: Double?
    /// m.
    public var totalDistance: Int?
    public var resistanceLevel: Int?
    /// W.
    public var power: Int?
    public var averagePower: Int?
    /// kcal.
    public var totalEnergy: Int?
    public var heartRate: Int?
    /// s.
    public var elapsedTime: Int?
    public var remainingTime: Int?

    public init?(_ data: Data) {
        var r = ByteReader(data)
        guard let flags = r.uint16() else { return nil }
        func has(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }

        if !has(0) {
            guard let v = r.uint16() else { return nil }
            speed = Double(v) / 100
        }
        if has(1) {
            guard let v = r.uint16() else { return nil }
            averageSpeed = Double(v) / 100
        }
        if has(2) {
            guard let v = r.uint16() else { return nil }
            cadence = Double(v) / 2
        }
        if has(3) {
            guard let v = r.uint16() else { return nil }
            averageCadence = Double(v) / 2
        }
        if has(4) {
            guard let v = r.uint24() else { return nil }
            totalDistance = Int(v)
        }
        if has(5) {
            guard let v = r.int16() else { return nil }
            resistanceLevel = Int(v)
        }
        if has(6) {
            guard let v = r.int16() else { return nil }
            power = Int(v)
        }
        if has(7) {
            guard let v = r.int16() else { return nil }
            averagePower = Int(v)
        }
        if has(8) {
            // Énergie totale (UInt16), par heure (UInt16), par minute (UInt8).
            guard let total = r.uint16(), r.skip(3) else { return nil }
            totalEnergy = total == 0xFFFF ? nil : Int(total)
        }
        if has(9) {
            guard let v = r.uint8() else { return nil }
            heartRate = Int(v)
        }
        if has(10) { guard r.skip(1) else { return nil } }  // équivalent métabolique
        if has(11) {
            guard let v = r.uint16() else { return nil }
            elapsedTime = Int(v)
        }
        if has(12) {
            guard let v = r.uint16() else { return nil }
            remainingTime = Int(v)
        }
    }
}

/// FTMS Fitness Machine Status (0x2ADA) : ce que le home-trainer annonce quand sa consigne change.
public enum MachineStatus: Equatable {
    case reset
    case stoppedOrPaused(byUser: UInt8)
    case startedOrResumed
    case targetResistanceChanged(level: Double)
    /// Mode ERG : consigne en watts.
    case targetPowerChanged(watts: Int)
    /// Mode simulation : c'est ici qu'apparaît la pente, si le home-trainer la publie.
    case simulationParametersChanged(windSpeed: Double, grade: Double, crr: Double, windResistance: Double)
    case wheelCircumferenceChanged(millimeters: Double)
    case controlPermissionLost
    case other(opCode: UInt8, parameters: Data)

    public init?(_ data: Data) {
        var r = ByteReader(data)
        guard let op = r.uint8() else { return nil }
        switch op {
        case 0x01:
            self = .reset
        case 0x02:
            self = .stoppedOrPaused(byUser: r.uint8() ?? 0)
        case 0x04:
            self = .startedOrResumed
        case 0x07:
            guard let v = r.uint8() else { return nil }
            self = .targetResistanceChanged(level: Double(v) / 10)
        case 0x08:
            guard let v = r.int16() else { return nil }
            self = .targetPowerChanged(watts: Int(v))
        case 0x12:
            guard let wind = r.int16(), let grade = r.int16(), let crr = r.uint8(), let cw = r.uint8() else { return nil }
            self = .simulationParametersChanged(
                windSpeed: Double(wind) / 1000,     // m/s
                grade: Double(grade) / 100,         // %
                crr: Double(crr) / 10_000,
                windResistance: Double(cw) / 100)   // kg/m
        case 0x13:
            guard let v = r.uint16() else { return nil }
            self = .wheelCircumferenceChanged(millimeters: Double(v) / 10)
        case 0xFF:
            self = .controlPermissionLost
        default:
            self = .other(opCode: op, parameters: data.dropFirst())
        }
    }
}

/// Heart Rate Measurement (0x2A37).
public struct HeartRateMeasurement: Equatable {
    public var bpm: Int
    /// nil si la ceinture ne publie pas l'état du contact avec la peau.
    public var skinContact: Bool?

    public init?(_ data: Data) {
        var r = ByteReader(data)
        guard let flags = r.uint8() else { return nil }
        if flags & 0x01 != 0 {
            guard let v = r.uint16() else { return nil }
            bpm = Int(v)
        } else {
            guard let v = r.uint8() else { return nil }
            bpm = Int(v)
        }
        skinContact = flags & 0x04 != 0 ? flags & 0x02 != 0 : nil
    }
}
