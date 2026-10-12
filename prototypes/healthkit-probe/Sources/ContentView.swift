import HealthKit
import SwiftUI
import UserNotifications

@MainActor
final class ProbeModel: ObservableObject {
    @Published var workouts: [WorkoutReport] = []
    @Published var detections: [Detection] = []
    @Published var status = ""
    @Published var isRunning = false

    func authorize() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "Santé n'est pas disponible sur cet appareil."
            return
        }
        do {
            try await Health.requestAuthorization()
            UserDefaults.standard.set(true, forKey: WorkoutWatcher.authorizedKey)
            WorkoutWatcher.shared.start()
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            // iOS ne dit jamais si la lecture a été refusée : un refus donne simplement des résultats vides.
            status = "Accès demandé. Si rien n'apparaît, vérifier Réglages › Santé › Accès aux données › Sonde Santé."
        } catch {
            status = "Erreur : \(error.localizedDescription)"
        }
    }

    func analyze() async {
        isRunning = true
        defer { isRunning = false }
        do {
            let list = try await Health.recentCyclingWorkouts()
            var reports: [WorkoutReport] = []
            for (index, workout) in list.enumerated() {
                status = "Analyse \(index + 1)/\(list.count)…"
                reports.append(await Health.analyze(workout))
            }
            workouts = Health.markOverlaps(reports)
            status = reports.isEmpty
                ? "Aucune sortie vélo trouvée sur 90 jours."
                : "\(reports.count) sorties analysées."
        } catch {
            status = "Erreur : \(error.localizedDescription)"
        }
        await reloadDetections()
    }

    func reloadDetections() async {
        detections = await DetectionLog.shared.all()
    }
}

struct ContentView: View {
    @StateObject private var model = ProbeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Autoriser l'accès à Santé") {
                        Task { await model.authorize() }
                    }
                    Button("Analyser les sorties vélo (90 jours)") {
                        Task { await model.analyze() }
                    }
                    .disabled(model.isRunning)
                    if !model.status.isEmpty {
                        Text(model.status).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Sorties vélo") {
                    ForEach(model.workouts) { report in
                        NavigationLink {
                            WorkoutDetailView(report: report)
                        } label: {
                            WorkoutRow(report: report)
                        }
                    }
                }

                Section("Détections automatiques") {
                    if model.detections.isEmpty {
                        Text("Aucune pour l'instant. Termine une sortie, puis ne touche plus à l'app.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.detections) { detection in
                        DetectionRow(detection: detection)
                    }
                }
            }
            .navigationTitle("Sonde Santé")
            .toolbar {
                ShareLink(item: Report.text(workouts: model.workouts, detections: model.detections)) {
                    Label("Exporter le rapport", systemImage: "square.and.arrow.up")
                }
            }
            .task { await model.reloadDetections() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.reloadDetections() }
                }
            }
        }
    }
}

struct WorkoutRow: View {
    let report: WorkoutReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(report.sourceName).font(.headline)
                Spacer()
                Text(Report.date(report.start)).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(Report.duration(report.duration)) · intérieur : \(Report.yesNo(report.indoor))")
                .font(.subheadline)
            Text(Report.seriesLine(report)).font(.caption.monospaced())
            if !report.overlaps.isEmpty {
                Text("⚠︎ Chevauche : \(report.overlaps.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

struct DetectionRow: View {
    let detection: Detection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(detection.source) — \(detection.activity)").font(.headline)
            Text("Terminée le \(Report.date(detection.end))").font(.subheadline)
            Text("Détectée \(Report.delay(detection.delay)) après la fin, app \(detection.appState)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WorkoutDetailView: View {
    let report: WorkoutReport

    var body: some View {
        List {
            Section("Origine") {
                row("App", report.sourceName)
                row("Identifiant", report.bundleID)
                row("Version", report.appVersion ?? "–")
                row("Appareil", report.deviceName ?? "–")
                row("Produit", report.productType ?? "–")
            }
            Section("Séance") {
                row("Début", Report.date(report.start))
                row("Durée", Report.duration(report.duration))
                row("Intérieur", Report.yesNo(report.indoor))
                row("Distance", report.distanceMeters.map { "\(Report.number($0 / 1000)) km" } ?? "–")
                row("Énergie", report.energyKcal.map { "\(Report.number($0)) kcal" } ?? "–")
                row("Tracé GPS", Report.yesNo(report.hasRoute))
                row("Activités / événements", "\(report.activityCount) / \(report.eventCount)")
                row("Résumés", report.statistics.isEmpty ? "aucun" : report.statistics.joined(separator: ", "))
            }
            Section("Séries de données") {
                ForEach(report.series) { series in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(series.label).font(.headline)
                        Text("\(series.associated) échantillons rattachés à la séance").font(.caption)
                        if series.inWindow.isEmpty {
                            Text("Rien pendant la séance").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(series.inWindow, id: \.self) { source in
                            Text("\(source.source) : \(source.count) — \(source.summary)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !report.metadata.isEmpty {
                Section("Métadonnées") {
                    ForEach(report.metadata, id: \.self) { entry in
                        row(entry.key, entry.value)
                    }
                }
            }
        }
        .navigationTitle(report.sourceName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).textSelection(.enabled)
        }
    }
}
