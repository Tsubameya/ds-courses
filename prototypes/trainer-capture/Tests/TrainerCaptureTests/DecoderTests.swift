import XCTest
@testable import TrainerCapture

private func data(_ bytes: [UInt8]) -> Data { Data(bytes) }

final class DecoderTests: XCTestCase {
    func testCyclingPowerWithWheelAndCrank() throws {
        // Drapeaux 0x0030 : tours de roue et de pédalier ; 149 W.
        let m = try XCTUnwrap(CyclingPowerMeasurement(data([
            0x30, 0x00, 0x95, 0x00,
            0xE8, 0x03, 0x00, 0x00, 0x00, 0x08,
            0x0A, 0x00, 0x00, 0x04,
        ])))
        XCTAssertEqual(m.power, 149)
        XCTAssertEqual(m.wheel, .init(count: 1000, eventTime: 2048))
        XCTAssertEqual(m.crank, .init(count: 10, eventTime: 1024))
        XCTAssertNil(m.pedalBalance)
    }

    func testCyclingPowerTruncatedIsRejected() {
        XCTAssertNil(CyclingPowerMeasurement(data([0x20, 0x00, 0x95, 0x00, 0x0A])))
    }

    func testCadenceFromCrankRevolutionsAcrossRollover() throws {
        var rate = RevolutionRate(ticksPerSecond: 1024)
        let t0 = Date()
        XCTAssertNil(rate.add(revolutions: 65535, eventTime: 65000, revolutionBits: 16, at: t0))
        // Un tour en 1280/1024 s = 1,25 s → 48 tr/min, les deux compteurs repassant par zéro.
        let rpm = try XCTUnwrap(rate.add(revolutions: 0, eventTime: 744, revolutionBits: 16, at: t0 + 1.25))
        XCTAssertEqual(rpm, 48, accuracy: 0.001)
    }

    func testCadenceDropsToZeroWhenPedalsStop() {
        var rate = RevolutionRate(ticksPerSecond: 1024)
        let t0 = Date()
        _ = rate.add(revolutions: 10, eventTime: 1024, revolutionBits: 16, at: t0)
        _ = rate.add(revolutions: 11, eventTime: 2304, revolutionBits: 16, at: t0 + 1.25)
        XCTAssertEqual(rate.add(revolutions: 11, eventTime: 2304, revolutionBits: 16, at: t0 + 2), 48)
        XCTAssertEqual(rate.add(revolutions: 11, eventTime: 2304, revolutionBits: 16, at: t0 + 5), 0)
    }

    func testIndoorBikeData() throws {
        // Bit 0 à 0 : vitesse présente. Bits 2 et 6 : cadence et puissance.
        let d = try XCTUnwrap(IndoorBikeData(data([0x44, 0x00, 0xEA, 0x0B, 0xB4, 0x00, 0xC8, 0x00])))
        XCTAssertEqual(d.speed, 30.5)
        XCTAssertEqual(d.cadence, 90)
        XCTAssertEqual(d.power, 200)
        XCTAssertNil(d.heartRate)
    }

    func testIndoorBikeDataMoreDataFlagMeansNoSpeed() throws {
        let d = try XCTUnwrap(IndoorBikeData(data([0x01, 0x00])))
        XCTAssertNil(d.speed)
    }

    func testMachineStatusSimulationParameters() throws {
        XCTAssertEqual(MachineStatus(data([0x12, 0x00, 0x00, 0x26, 0x02, 0x28, 0x33])),
                       .simulationParametersChanged(windSpeed: 0, grade: 5.5, crr: 0.004, windResistance: 0.51))
        guard case .simulationParametersChanged(_, let grade, _, _)? = MachineStatus(data([0x12, 0x00, 0x00, 0xD4, 0xFE, 0x28, 0x33])) else {
            return XCTFail("pente négative non décodée")
        }
        XCTAssertEqual(grade, -3)
    }

    func testMachineStatusTargetPower() {
        XCTAssertEqual(MachineStatus(data([0x08, 0xFA, 0x00])), .targetPowerChanged(watts: 250))
    }

    func testHeartRate() throws {
        // Drapeaux 0x16 : valeur sur 1 octet, contact détecté et pris en charge, intervalles RR (ignorés).
        let hr = try XCTUnwrap(HeartRateMeasurement(data([0x16, 0x7C, 0x00, 0x04])))
        XCTAssertEqual(hr.bpm, 124)
        XCTAssertEqual(hr.skinContact, true)
    }

    func testFECGeneralPageInsideANTMessage() throws {
        let page = try XCTUnwrap(FECPage(data([0xA4, 0x09, 0x4E, 0x05, 0x10, 0x19, 0x40, 0x64, 0xB8, 0x0B, 0xFF, 0x24, 0x00])))
        guard case .general(let speed, let distance, _, let hr) = page else { return XCTFail("\(page)") }
        XCTAssertEqual(speed, 10.8, accuracy: 0.0001)
        XCTAssertEqual(distance, 100)
        XCTAssertNil(hr)
    }

    func testFECTrainerPage() {
        XCTAssertEqual(FECPage(data([0x19, 0x05, 0x5A, 0x10, 0x27, 0xC8, 0x31, 0x20])),
                       .trainer(cadence: 90, power: 456, accumulatedPower: 10000))
    }

    func testFECCommandStatusEchoesGrade() throws {
        let page = try XCTUnwrap(FECPage(data([0x47, 0x33, 0x07, 0x00, 0xFF, 0x46, 0x50, 0x50])))
        guard case .commandStatus(0x33, 7, 0, .trackResistance(let grade?, let crr?)?) = page else {
            return XCTFail("\(page)")
        }
        XCTAssertEqual(grade, 5.5, accuracy: 0.0001)
        XCTAssertEqual(crr, 0.004, accuracy: 1e-9)
    }

    func testFECCommandStatusRequestMessage() {
        XCTAssertEqual(Array(TacxFEC.requestCommandStatus()),
                       [0xA4, 0x09, 0x4F, 0x05, 0x46, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x47, 0x01, 0xE6])
    }

    func testCharacteristicLookup() {
        XCTAssertEqual(TrainerCharacteristic(uuid: "2a63"), .cyclingPowerMeasurement)
        XCTAssertEqual(TrainerCharacteristic(uuid: "00002AD2-0000-1000-8000-00805F9B34FB"), .indoorBikeData)
        XCTAssertEqual(TrainerCharacteristic(uuid: "6e40fec2-b5a3-f393-e0a9-e50e24dcca9e"), .tacxFECRead)
        XCTAssertNil(TrainerCharacteristic(uuid: "2AD9"))  // le point de contrôle FTMS n'est jamais écouté
    }
}

final class GradeEstimatorTests: XCTestCase {
    func testRecoversGradeAtSteadySpeed() throws {
        var estimator = GradeEstimator()
        let p = estimator.parameters
        let v = 30 / 3.6
        let grade = 0.05
        let power = (p.totalMass * 9.81 * (grade + p.crr) + 0.5 * p.airDensity * p.cda * v * v) * v

        let t0 = Date()
        var estimate: Double?
        for second in 0...10 {
            estimate = estimator.add(power: power, speedKmh: 30, at: t0 + Double(second))
        }
        XCTAssertEqual(try XCTUnwrap(estimate), 5, accuracy: 0.01)
    }

    func testNoEstimateWhenNearlyStopped() {
        var estimator = GradeEstimator()
        let t0 = Date()
        for second in 0...10 {
            XCTAssertNil(estimator.add(power: 50, speedKmh: 3, at: t0 + Double(second)))
        }
    }
}

final class CaptureSessionTests: XCTestCase {
    func testWritesOneLinePerNotificationAndTracksSources() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let t0 = Date()
        let session = try CaptureSession(directory: directory, start: t0)

        session.record(characteristic: "2AD2", value: data([0x44, 0x00, 0xEA, 0x0B, 0xB4, 0x00, 0xC8, 0x00]), at: t0)
        session.record(characteristic: "2ADA", value: data([0x12, 0x00, 0x00, 0x26, 0x02, 0x28, 0x33]), at: t0 + 0.5)
        session.record(characteristic: "2AD9", value: data([0x00]), at: t0 + 0.6)  // ignorée

        XCTAssertEqual(session.metrics.speedKmh, 30.5)
        XCTAssertEqual(session.metrics.speedSource, "FTMS")
        XCTAssertEqual(session.metrics.power, 200)
        XCTAssertEqual(session.metrics.trainerGrade, 5.5)
        XCTAssertEqual(session.metrics.mode, .simulation)

        let text = try String(contentsOf: session.finish(), encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("heure,t_s,"))
        XCTAssertTrue(lines[2].contains("12 00 00 26 02 28 33"))
    }

    func testStaleSourceFallsBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let t0 = Date()
        let session = try CaptureSession(directory: directory, start: t0)
        session.record(characteristic: "2AD2", value: data([0x44, 0x00, 0xEA, 0x0B, 0xB4, 0x00, 0xC8, 0x00]), at: t0)
        session.record(characteristic: TrainerCharacteristic.tacxFECRead.rawValue,
                       value: data([0x10, 0x19, 0x40, 0x64, 0xB8, 0x0B, 0xFF, 0x24]), at: t0 + 5)
        XCTAssertEqual(session.metrics.speedSource, "FE-C 16")
    }

    func testFECPollingIsOffByDefault() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = try CaptureSession(directory: directory)
        XCTAssertNil(session.pendingFECRequest())
        session.pollsFECCommandStatus = true
        let t0 = Date()
        XCTAssertNotNil(session.pendingFECRequest(at: t0))
        XCTAssertNil(session.pendingFECRequest(at: t0 + 1))
        XCTAssertNotNil(session.pendingFECRequest(at: t0 + 6))
    }
}
