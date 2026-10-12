import Foundation

/// Estime la pente simulée à partir de la puissance et de la vitesse du home-trainer.
///
/// En mode simulation, le home-trainer freine selon le modèle
/// F = m·g·(pente + Crr) + ½·ρ·CdA·v² + m·a, et la puissance vaut F·v.
/// On inverse ce modèle : pente ≈ (P/v − ½·ρ·CdA·v² − m·a) / (m·g) − Crr.
/// Le résultat n'est juste que si les paramètres ressemblent à ceux de l'app indoor,
/// et il n'a aucun sens en mode ERG.
public struct GradeEstimator {
    public struct Parameters {
        /// Cycliste + vélo, kg.
        public var totalMass: Double = 85
        /// m².
        public var cda: Double = 0.30
        public var crr: Double = 0.004
        /// kg/m³.
        public var airDensity: Double = 1.2

        public init() {}
    }

    public var parameters: Parameters
    /// Lissage : la pente est calculée sur cette fenêtre glissante.
    public var window: TimeInterval

    private var samples: [(date: Date, power: Double, speed: Double)] = []

    public init(parameters: Parameters = Parameters(), window: TimeInterval = 8) {
        self.parameters = parameters
        self.window = window
    }

    /// Renvoie la pente en %, ou nil tant que la fenêtre est trop courte ou que la roue tourne trop lentement.
    public mutating func add(power: Double, speedKmh: Double, at date: Date) -> Double? {
        samples.append((date, power, speedKmh / 3.6))
        samples.removeAll { date.timeIntervalSince($0.date) > window }
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= window / 2 else { return nil }

        let meanPower = samples.map(\.power).reduce(0, +) / Double(samples.count)
        let meanSpeed = samples.map(\.speed).reduce(0, +) / Double(samples.count)
        guard meanSpeed > 1.5 else { return nil }

        let p = parameters
        let g = 9.81
        let acceleration = (last.speed - first.speed) / span
        let force = meanPower / meanSpeed
        let aero = 0.5 * p.airDensity * p.cda * meanSpeed * meanSpeed
        let slope = (force - aero - p.totalMass * acceleration) / (p.totalMass * g) - p.crr
        return min(max(slope * 100, -25), 25)
    }
}
