import Foundation
import HealthKit
import UIKit
import UserNotifications

/// Une séance que l'app a vue arriver dans Santé sans que l'utilisateur l'ouvre.
struct Detection: Codable, Identifiable {
    let id: UUID
    let detectedAt: Date
    let source: String
    let bundleID: String
    let activity: String
    let start: Date
    let end: Date
    let appState: String

    /// Temps écoulé entre la fin de la séance et sa détection.
    var delay: TimeInterval { detectedAt.timeIntervalSince(end) }
}

actor DetectionLog {
    static let shared = DetectionLog()

    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("detections.json")

    func all() -> [Detection] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Detection].self, from: data)) ?? []
    }

    /// Ajoute les détections inconnues et renvoie celles qui sont nouvelles.
    func append(_ new: [Detection]) -> [Detection] {
        var list = all()
        let known = Set(list.map(\.id))
        let added = new.filter { !known.contains($0.id) }
        list.insert(contentsOf: added, at: 0)
        try? JSONEncoder().encode(list).write(to: url, options: .atomic)
        return added
    }
}

/// Écoute Santé : iOS réveille l'app quand une séance y est écrite, même app fermée.
final class WorkoutWatcher {
    static let shared = WorkoutWatcher()
    static let authorizedKey = "healthAuthorizationRequested"

    private let anchorKey = "workoutAnchor"
    private var started = false

    func start() {
        guard !started, UserDefaults.standard.bool(forKey: Self.authorizedKey) else { return }
        started = true

        let type = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
            guard let self, error == nil else {
                completion()
                return
            }
            Task {
                await self.collectNewWorkouts()
                // À appeler impérativement, sinon iOS espace puis coupe les réveils.
                completion()
            }
        }
        Health.store.execute(query)
        Health.store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, error in
            if let error {
                print("Livraison en arrière-plan refusée : \(error)")
            }
        }
    }

    func collectNewWorkouts() async {
        let anchor = loadAnchor()
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.workout()], anchor: anchor)
        guard let result = try? await descriptor.result(for: Health.store) else { return }
        saveAnchor(result.newAnchor)

        // Premier passage : on prend la référence sans signaler tout l'historique.
        guard anchor != nil, !result.addedSamples.isEmpty else { return }

        let now = Date()
        let state = await MainActor.run { UIApplication.shared.applicationState.label }
        let detections = result.addedSamples.map { workout in
            Detection(
                id: workout.uuid,
                detectedAt: now,
                source: workout.sourceRevision.source.name,
                bundleID: workout.sourceRevision.source.bundleIdentifier,
                activity: workout.workoutActivityType == .cycling
                    ? "vélo" : "autre activité (\(workout.workoutActivityType.rawValue))",
                start: workout.startDate,
                end: workout.endDate,
                appState: state)
        }
        let added = await DetectionLog.shared.append(detections)
        for detection in added {
            await notify(detection)
        }
    }

    private func notify(_ detection: Detection) async {
        let content = UNMutableNotificationContent()
        content.title = "Nouvelle séance : \(detection.source)"
        content.body = "\(detection.activity.capitalized), détectée \(Report.delay(detection.delay)) après la fin."
        let request = UNNotificationRequest(identifier: detection.id.uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: anchorKey)
        }
    }
}

extension UIApplication.State {
    var label: String {
        switch self {
        case .active: return "premier plan"
        case .inactive: return "inactive"
        case .background: return "arrière-plan"
        @unknown default: return "inconnu"
        }
    }
}
