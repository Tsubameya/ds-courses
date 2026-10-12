import Foundation
import HealthKit

/// Ce que Santé contient pour une sortie vélo, tel que l'app d'origine l'a écrit.
struct WorkoutReport: Identifiable {
    let id: UUID
    let sourceName: String
    let bundleID: String
    let appVersion: String?
    let productType: String?
    let deviceName: String?
    let start: Date
    let end: Date
    let duration: TimeInterval
    let indoor: Bool?
    let distanceMeters: Double?
    let energyKcal: Double?
    /// Types résumés au niveau de la séance (HKWorkout.allStatistics).
    let statistics: [String]
    let metadata: [MetadataEntry]
    let activityCount: Int
    let eventCount: Int
    let hasRoute: Bool
    let series: [SeriesReport]
    /// Autres séances (d'autres apps) qui se chevauchent avec celle-ci : doublons probables.
    var overlaps: [String] = []
}

struct MetadataEntry: Hashable {
    let key: String
    let value: String
}

struct SeriesReport: Identifiable {
    let id: String
    let label: String
    let short: String
    /// Échantillons rattachés à la séance par l'app qui l'a écrite.
    let associated: Int
    /// Échantillons enregistrés pendant la séance, regroupés par app, rattachés ou non.
    let inWindow: [SourceCount]

    var hasData: Bool { associated > 0 || !inWindow.isEmpty }
}

struct SourceCount: Hashable {
    let source: String
    let count: Int
    let summary: String
}

enum Health {
    static let store = HKHealthStore()

    struct Series {
        let identifier: HKQuantityTypeIdentifier
        let label: String
        let short: String
        let unit: HKUnit
        let unitLabel: String

        var type: HKQuantityType { HKQuantityType(identifier) }
    }

    static let series: [Series] = [
        Series(identifier: .cyclingPower, label: "Puissance", short: "W",
               unit: .watt(), unitLabel: "W"),
        Series(identifier: .heartRate, label: "Fréquence cardiaque", short: "FC",
               unit: .count().unitDivided(by: .minute()), unitLabel: "bpm"),
        Series(identifier: .cyclingCadence, label: "Cadence", short: "Cad",
               unit: .count().unitDivided(by: .minute()), unitLabel: "rpm"),
        Series(identifier: .cyclingSpeed, label: "Vitesse", short: "Vit",
               unit: .meterUnit(with: .kilo).unitDivided(by: .hour()), unitLabel: "km/h"),
        Series(identifier: .distanceCycling, label: "Distance", short: "Dist",
               unit: .meterUnit(with: .kilo), unitLabel: "km"),
        Series(identifier: .activeEnergyBurned, label: "Énergie active", short: "kcal",
               unit: .kilocalorie(), unitLabel: "kcal"),
    ]

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.cyclingFunctionalThresholdPower),
        ]
        for s in series { types.insert(s.type) }
        return types
    }

    static func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    static func recentCyclingWorkouts(days: Int = 90, limit: Int = 30) async throws -> [HKWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let since = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(since)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: nil)
        let all = try await descriptor.result(for: store)
        return Array(all.filter { $0.workoutActivityType == .cycling }.prefix(limit))
    }

    static func analyze(_ workout: HKWorkout) async -> WorkoutReport {
        let fromWorkout = HKQuery.predicateForObjects(from: workout)
        let during = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])

        var seriesReports: [SeriesReport] = []
        for s in series {
            let associated = (try? await samples(s.type, fromWorkout)) ?? []
            let window = (try? await samples(s.type, during)) ?? []
            let bySource = Dictionary(grouping: window) { $0.sourceRevision.source.name }
                .map { name, samples in
                    SourceCount(source: name, count: samples.count, summary: summarize(samples, s))
                }
                .sorted { $0.count > $1.count }
            seriesReports.append(SeriesReport(id: s.identifier.rawValue, label: s.label, short: s.short,
                                              associated: associated.count, inWindow: bySource))
        }

        let routes = (try? await HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: fromWorkout)],
            sortDescriptors: [],
            limit: 1).result(for: store)) ?? []

        let revision = workout.sourceRevision
        return WorkoutReport(
            id: workout.uuid,
            sourceName: revision.source.name,
            bundleID: revision.source.bundleIdentifier,
            appVersion: revision.version,
            productType: revision.productType,
            deviceName: workout.device?.name,
            start: workout.startDate,
            end: workout.endDate,
            duration: workout.duration,
            indoor: workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool,
            distanceMeters: workout.statistics(for: HKQuantityType(.distanceCycling))?
                .sumQuantity()?.doubleValue(for: .meter()),
            energyKcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie()),
            statistics: workout.allStatistics.keys.map { label(for: $0) }.sorted(),
            metadata: (workout.metadata ?? [:])
                .map { MetadataEntry(key: $0.key, value: String(describing: $0.value)) }
                .sorted { $0.key < $1.key },
            activityCount: workout.workoutActivities.count,
            eventCount: workout.workoutEvents?.count ?? 0,
            hasRoute: !routes.isEmpty,
            series: seriesReports)
    }

    /// Signale les séances qui se chevauchent : la même sortie écrite par deux apps (Zwift et Strava…).
    static func markOverlaps(_ reports: [WorkoutReport]) -> [WorkoutReport] {
        var marked = reports
        for i in marked.indices {
            marked[i].overlaps = reports.enumerated().compactMap { j, other in
                guard j != i, other.start < reports[i].end, reports[i].start < other.end else { return nil }
                return other.sourceName
            }
        }
        return marked
    }

    private static func samples(_ type: HKQuantityType, _ predicate: NSPredicate) async throws -> [HKQuantitySample] {
        try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [],
            limit: nil).result(for: store)
    }

    private static func summarize(_ samples: [HKQuantitySample], _ s: Series) -> String {
        let values = samples.map { $0.quantity.doubleValue(for: s.unit) }
        guard let max = values.max() else { return "" }
        let total = values.reduce(0, +)
        if s.type.aggregationStyle == .cumulative {
            return "total \(Report.number(total)) \(s.unitLabel)"
        }
        return "moy. \(Report.number(total / Double(values.count))) · max \(Report.number(max)) \(s.unitLabel)"
    }

    private static func label(for type: HKQuantityType) -> String {
        series.first { $0.type == type }?.label ?? type.identifier
    }
}
