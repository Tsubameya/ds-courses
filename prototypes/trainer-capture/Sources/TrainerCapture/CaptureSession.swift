import Foundation

/// Une notification décodée.
public enum DecodedValue: Equatable {
    case cyclingPower(CyclingPowerMeasurement)
    case indoorBikeData(IndoorBikeData)
    case machineStatus(MachineStatus)
    case heartRate(HeartRateMeasurement)
    case fec(FECPage)

    public static func decode(_ characteristic: TrainerCharacteristic, _ value: Data) -> DecodedValue? {
        switch characteristic {
        case .cyclingPowerMeasurement: return CyclingPowerMeasurement(value).map(DecodedValue.cyclingPower)
        case .indoorBikeData: return IndoorBikeData(value).map(DecodedValue.indoorBikeData)
        case .fitnessMachineStatus: return MachineStatus(value).map(DecodedValue.machineStatus)
        case .heartRateMeasurement: return HeartRateMeasurement(value).map(DecodedValue.heartRate)
        case .tacxFECRead: return FECPage(value).map(DecodedValue.fec)
        }
    }
}

/// L'état courant, toutes sources confondues, avec l'origine de chaque valeur.
public struct LiveMetrics: Equatable {
    public enum Mode: String { case unknown = "?", simulation = "SIM", erg = "ERG" }

    public var power: Int?
    public var cadence: Double?
    public var speedKmh: Double?
    public var speedSource: String?
    public var heartRate: Int?
    /// Pente annoncée par le home-trainer (FTMS 0x2ADA ou FE-C page 71), en %.
    public var trainerGrade: Double?
    public var trainerGradeSource: String?
    /// Pente recalculée à partir de la puissance et de la vitesse, en %.
    public var estimatedGrade: Double?
    public var mode: Mode = .unknown
}

/// Mode capture : à brancher sur la couche Bluetooth existante de l'app.
///
/// L'app s'abonne aux caractéristiques de `TrainerCharacteristic.allCases` qu'elle trouve, et transmet
/// chaque notification à `record(characteristic:value:)` depuis `peripheral(_:didUpdateValueFor:error:)`.
/// Chaque notification devient une ligne d'un fichier CSV : l'heure, l'octet brut, le décodage,
/// et l'état courant. Rien n'est écrit vers le home-trainer, sauf si l'app relaie
/// `pendingFECRequest(at:)`, désactivé par défaut.
public final class CaptureSession {
    public let fileURL: URL
    public private(set) var metrics = LiveMetrics()

    /// Demander la page 71 au canal FE-C de Tacx, pour y lire la pente envoyée en ANT+. Désactivé par défaut.
    public var pollsFECCommandStatus = false
    public var fecPollInterval: TimeInterval = 5
    /// Circonférence de roue pour la vitesse tirée des tours de roue (0x2A63), en m.
    public var wheelCircumference = 2.105
    public var gradeEstimator = GradeEstimator()

    private let handle: FileHandle
    private let start: Date
    private let lock = NSLock()
    private var crankRate = RevolutionRate(ticksPerSecond: 1024)
    private var wheelRate = RevolutionRate(ticksPerSecond: 2048)
    private var lastFECRequest: Date?

    /// Valeurs par source : la plus prioritaire encore fraîche l'emporte.
    private struct Reading { var value: Double; var at: Date }
    private var speeds: [String: Reading] = [:]
    private var cadences: [String: Reading] = [:]
    private var powers: [String: Reading] = [:]
    private static let speedOrder = ["FTMS", "FE-C 16", "CPS roue"]
    private static let cadenceOrder = ["FTMS", "FE-C 25", "CPS pédalier"]
    private static let powerOrder = ["CPS", "FTMS", "FE-C 25"]
    private static let freshness: TimeInterval = 3

    private static let header = "heure,t_s,caracteristique,brut,decodage,puissance_w,cadence_rpm,vitesse_kmh,"
        + "source_vitesse,fc_bpm,pente_trainer_pct,source_pente,pente_estimee_pct,mode\n"

    public init(directory: URL, start: Date = Date()) throws {
        let stamp = ISO8601DateFormatter().string(from: start).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("capture-\(stamp).csv")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(Self.header.utf8).write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        fileURL = url
        self.handle = handle
        self.start = start
    }

    deinit {
        try? handle.close()
    }

    /// À appeler pour chaque notification reçue. Sans effet pour une caractéristique inconnue.
    @discardableResult
    public func record(characteristic uuid: String, value: Data, at date: Date = Date()) -> DecodedValue? {
        guard let characteristic = TrainerCharacteristic(uuid: uuid) else { return nil }
        lock.lock()
        defer { lock.unlock() }

        let decoded = DecodedValue.decode(characteristic, value)
        if let decoded { apply(decoded, at: date) }
        resolve(at: date)
        write(characteristic, value, decoded, at: date)
        return decoded
    }

    /// Le message à écrire sur `TacxFEC.writeCharacteristic`, quand il est temps de redemander la page 71.
    public func pendingFECRequest(at date: Date = Date()) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard pollsFECCommandStatus else { return nil }
        if let last = lastFECRequest, date.timeIntervalSince(last) < fecPollInterval { return nil }
        lastFECRequest = date
        return TacxFEC.requestCommandStatus()
    }

    public func finish() -> URL {
        lock.lock()
        defer { lock.unlock() }
        try? handle.synchronize()
        return fileURL
    }

    // MARK: - État

    private func apply(_ value: DecodedValue, at date: Date) {
        switch value {
        case .cyclingPower(let m):
            powers["CPS"] = Reading(value: Double(m.power), at: date)
            if let crank = m.crank,
               let rpm = crankRate.add(revolutions: crank.count, eventTime: crank.eventTime, revolutionBits: 16, at: date) {
                cadences["CPS pédalier"] = Reading(value: rpm, at: date)
            }
            if let wheel = m.wheel,
               let rpm = wheelRate.add(revolutions: wheel.count, eventTime: wheel.eventTime, revolutionBits: 32, at: date) {
                speeds["CPS roue"] = Reading(value: rpm * wheelCircumference * 60 / 1000, at: date)
            }
        case .indoorBikeData(let d):
            if let v = d.speed { speeds["FTMS"] = Reading(value: v, at: date) }
            if let v = d.cadence { cadences["FTMS"] = Reading(value: v, at: date) }
            if let v = d.power { powers["FTMS"] = Reading(value: Double(v), at: date) }
            if let v = d.heartRate, v > 0 { metrics.heartRate = v }
        case .machineStatus(let status):
            switch status {
            case .simulationParametersChanged(_, let grade, _, _):
                metrics.trainerGrade = grade
                metrics.trainerGradeSource = "FTMS 2ADA"
                metrics.mode = .simulation
            case .targetPowerChanged:
                metrics.mode = .erg
            default:
                break
            }
        case .heartRate(let hr):
            metrics.heartRate = hr.bpm
        case .fec(let page):
            applyFEC(page, at: date)
        }
    }

    private func applyFEC(_ page: FECPage, at date: Date) {
        switch page {
        case .general(let speed, _, _, let hr):
            speeds["FE-C 16"] = Reading(value: speed, at: date)
            if let hr { metrics.heartRate = hr }
        case .trainer(let cadence, let power, _):
            if let cadence { cadences["FE-C 25"] = Reading(value: Double(cadence), at: date) }
            if let power { powers["FE-C 25"] = Reading(value: Double(power), at: date) }
        case .commandStatus(_, _, _, let command?):
            switch command {
            case .trackResistance(let grade?, _):
                metrics.trainerGrade = grade
                metrics.trainerGradeSource = "FE-C 71"
                metrics.mode = .simulation
            case .targetPower:
                metrics.mode = .erg
            default:
                break
            }
        default:
            break
        }
    }

    private func resolve(at date: Date) {
        let speed = pick(speeds, Self.speedOrder, at: date)
        metrics.speedKmh = speed?.value
        metrics.speedSource = speed?.source
        metrics.cadence = pick(cadences, Self.cadenceOrder, at: date)?.value
        metrics.power = pick(powers, Self.powerOrder, at: date).map { Int($0.value) }
        if metrics.mode != .erg, let power = metrics.power, let speed = metrics.speedKmh {
            metrics.estimatedGrade = gradeEstimator.add(power: Double(power), speedKmh: speed, at: date)
        } else {
            metrics.estimatedGrade = nil
        }
    }

    private func pick(_ readings: [String: Reading], _ order: [String], at date: Date) -> (value: Double, source: String)? {
        for source in order {
            if let r = readings[source], date.timeIntervalSince(r.at) <= Self.freshness {
                return (r.value, source)
            }
        }
        return nil
    }

    // MARK: - Fichier

    private func write(_ characteristic: TrainerCharacteristic, _ value: Data, _ decoded: DecodedValue?, at date: Date) {
        let m = metrics
        let fields: [String] = [
            ISO8601DateFormatter.capture.string(from: date),
            String(format: "%.3f", date.timeIntervalSince(start)),
            characteristic.rawValue,
            value.hex,
            decoded.map { String(describing: $0) } ?? "non décodé",
            m.power.map(String.init) ?? "",
            m.cadence.map { String(format: "%.1f", $0) } ?? "",
            m.speedKmh.map { String(format: "%.2f", $0) } ?? "",
            m.speedSource ?? "",
            m.heartRate.map(String.init) ?? "",
            m.trainerGrade.map { String(format: "%.2f", $0) } ?? "",
            m.trainerGradeSource ?? "",
            m.estimatedGrade.map { String(format: "%.1f", $0) } ?? "",
            m.mode.rawValue,
        ]
        let line = fields.map(Self.csvField).joined(separator: ",") + "\n"
        handle.write(Data(line.utf8))
    }

    private static func csvField(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension ISO8601DateFormatter {
    static let capture: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
