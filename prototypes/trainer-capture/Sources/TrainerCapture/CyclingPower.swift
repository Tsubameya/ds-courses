import Foundation

/// Cycling Power Measurement (0x2A63).
public struct CyclingPowerMeasurement: Equatable {
    public var power: Int
    /// Part de la jambe de référence, en %.
    public var pedalBalance: Double?
    /// Couple cumulé, en N·m.
    public var accumulatedTorque: Double?
    /// Tours de roue cumulés ; heure du dernier tour en 1/2048 s.
    public var wheel: Revolutions?
    /// Tours de pédalier cumulés ; heure du dernier tour en 1/1024 s.
    public var crank: Revolutions?
    /// Énergie cumulée, en kJ.
    public var accumulatedEnergy: Int?

    public struct Revolutions: Equatable {
        public var count: UInt32
        public var eventTime: UInt16
    }

    public init?(_ data: Data) {
        var r = ByteReader(data)
        guard let flags = r.uint16(), let power = r.int16() else { return nil }
        self.power = Int(power)
        func has(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }

        if has(0) {
            guard let v = r.uint8() else { return nil }
            pedalBalance = Double(v) / 2
        }
        if has(2) {
            guard let v = r.uint16() else { return nil }
            accumulatedTorque = Double(v) / 32
        }
        if has(4) {
            guard let revs = r.uint32(), let time = r.uint16() else { return nil }
            wheel = Revolutions(count: revs, eventTime: time)
        }
        if has(5) {
            guard let revs = r.uint16(), let time = r.uint16() else { return nil }
            crank = Revolutions(count: UInt32(revs), eventTime: time)
        }
        // Champs qui ne servent pas ici mais qu'il faut sauter pour atteindre l'énergie.
        if has(6) { guard r.skip(4) else { return nil } }   // forces extrêmes
        if has(7) { guard r.skip(4) else { return nil } }   // couples extrêmes
        if has(8) { guard r.skip(3) else { return nil } }   // angles extrêmes
        if has(9) { guard r.skip(2) else { return nil } }   // point mort haut
        if has(10) { guard r.skip(2) else { return nil } }  // point mort bas
        if has(11) {
            guard let v = r.uint16() else { return nil }
            accumulatedEnergy = Int(v)
        }
    }
}

/// Cadence ou vitesse de roue à partir de compteurs cumulés : (tours, heure du dernier tour).
/// Les deux compteurs reviennent à zéro régulièrement ; les différences se font modulo 2¹⁶ (ou 2³²).
public struct RevolutionRate {
    /// Nombre de graduations par seconde de l'heure d'événement : 1024 (pédalier) ou 2048 (roue).
    let ticksPerSecond: Double
    /// Au-delà de ce délai sans nouveau tour, on considère que ça ne tourne plus.
    let staleAfter: TimeInterval

    private var last: (revolutions: UInt32, eventTime: UInt16)?
    private var lastChange: Date?
    private(set) var revolutionsPerMinute: Double?

    public init(ticksPerSecond: Double, staleAfter: TimeInterval = 3) {
        self.ticksPerSecond = ticksPerSecond
        self.staleAfter = staleAfter
    }

    /// `revolutionBits` : 16 pour le pédalier, 32 pour la roue.
    public mutating func add(revolutions: UInt32, eventTime: UInt16, revolutionBits: Int, at date: Date) -> Double? {
        defer { last = (revolutions, eventTime) }
        guard let previous = last else {
            lastChange = date
            return nil
        }
        let revMask: UInt64 = revolutionBits >= 32 ? 0xFFFF_FFFF : (1 << UInt64(revolutionBits)) - 1
        let deltaRevs = (UInt64(revolutions) &- UInt64(previous.revolutions)) & revMask
        let deltaTicks = eventTime &- previous.eventTime
        if deltaRevs == 0 || deltaTicks == 0 {
            if let changed = lastChange, date.timeIntervalSince(changed) > staleAfter {
                revolutionsPerMinute = 0
            }
            return revolutionsPerMinute
        }
        lastChange = date
        revolutionsPerMinute = Double(deltaRevs) / (Double(deltaTicks) / ticksPerSecond) * 60
        return revolutionsPerMinute
    }
}
