import Foundation

/// Mise en forme, à l'écran et dans le rapport texte à renvoyer après les essais.
enum Report {
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
    }

    static func delay(_ seconds: TimeInterval) -> String {
        if seconds < 0 { return "avant la fin" }
        if seconds < 90 { return "\(Int(seconds)) s" }
        if seconds < 5400 { return "\(Int(seconds / 60)) min" }
        return "\(number(seconds / 3600)) h"
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year().hour().minute())
    }

    static func yesNo(_ value: Bool?) -> String {
        switch value {
        case true?: return "oui"
        case false?: return "non"
        case nil: return "non renseigné"
        }
    }

    /// Une ligne par série : « W ✓ · FC ✓ · Cad – … ».
    static func seriesLine(_ report: WorkoutReport) -> String {
        report.series.map { "\($0.short) \($0.hasData ? "✓" : "–")" }.joined(separator: " · ")
    }

    static func text(workouts: [WorkoutReport], detections: [Detection]) -> String {
        var lines = ["Sonde Santé — rapport du \(date(.now))", ""]

        lines.append("== Sorties vélo (\(workouts.count)) ==")
        for w in workouts {
            lines.append("")
            lines.append("• \(w.sourceName) [\(w.bundleID)] v\(w.appVersion ?? "?") — \(date(w.start))")
            lines.append("  durée \(duration(w.duration)), intérieur : \(yesNo(w.indoor)), "
                         + "distance \(w.distanceMeters.map { "\(number($0 / 1000)) km" } ?? "–"), "
                         + "énergie \(w.energyKcal.map { "\(number($0)) kcal" } ?? "–")")
            lines.append("  appareil : \(w.deviceName ?? "–"), produit : \(w.productType ?? "–"), "
                         + "tracé GPS : \(yesNo(w.hasRoute)), activités : \(w.activityCount), événements : \(w.eventCount)")
            lines.append("  résumés : \(w.statistics.isEmpty ? "aucun" : w.statistics.joined(separator: ", "))")
            for s in w.series {
                let sources = s.inWindow.map { "\($0.source) ×\($0.count) (\($0.summary))" }.joined(separator: " ; ")
                lines.append("  \(s.label) : \(s.associated) rattachés ; pendant la séance : \(sources.isEmpty ? "rien" : sources)")
            }
            if !w.overlaps.isEmpty {
                lines.append("  ⚠︎ chevauche : \(w.overlaps.joined(separator: ", "))")
            }
            if !w.metadata.isEmpty {
                lines.append("  métadonnées : " + w.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
            }
        }

        lines.append("")
        lines.append("== Détections automatiques (\(detections.count)) ==")
        for d in detections {
            lines.append("• \(d.source) [\(d.bundleID)] \(d.activity) terminée le \(date(d.end)), "
                         + "détectée \(delay(d.delay)) après, app \(d.appState)")
        }
        return lines.joined(separator: "\n")
    }
}
