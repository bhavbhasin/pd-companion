import Foundation
import SwiftData

enum CSVBackupExporter {
    // Async + non-MainActor so the SwiftData fetch and CSV serialization run on
    // the cooperative thread pool, not blocking the UI. Take a ModelContainer
    // and build a fresh ModelContext inside; the UI's main-actor context is
    // not safe to use off the main thread.
    static func exportAll(container: ModelContainer) async -> URL? {
        let context = ModelContext(container)
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("Backup-\(folderTimestamp())", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let tremors = try context.fetch(
                FetchDescriptor<TremorReading>(sortBy: [SortDescriptor(\.timestamp)])
            )
            let tremorRange = dateRange(tremors.map(\.timestamp))
            try writeCSV(
                header: ["timestamp", "tremorScore", "dyskinesiaScore"],
                rows: tremors.map { [
                    iso($0.timestamp),
                    String($0.tremorScore),
                    String($0.dyskinesiaScore)
                ] },
                to: folder.appendingPathComponent(filename("tremor_readings", range: tremorRange))
            )

            // Its own stream — NOT the `dyskinesiaScore` column written above, which is a legacy
            // merged field on TremorReading (see SymptomData). Exporting only tremor left the one
            // model whose duplicates aren't cleaned also without a backup or a restore path.
            let dyskinesias = try context.fetch(
                FetchDescriptor<DyskinesiaReading>(sortBy: [SortDescriptor(\.startDate)])
            )
            let dyskinesiaRange = dateRange(dyskinesias.map(\.startDate))
            try writeCSV(
                header: ["startDate", "endDate", "percentLikely"],
                rows: dyskinesias.map { [
                    iso($0.startDate),
                    iso($0.endDate),
                    String($0.percentLikely)
                ] },
                to: folder.appendingPathComponent(
                    filename("dyskinesia_readings", range: dyskinesiaRange)
                )
            )

            let foods = try context.fetch(
                FetchDescriptor<FoodEvent>(sortBy: [SortDescriptor(\.timestamp)])
            )
            let foodRange = dateRange(foods.map(\.timestamp))
            try writeCSV(
                header: ["id", "timestamp", "userDescription", "type", "attributes", "notes"],
                rows: foods.map { [
                    $0.id.uuidString,
                    iso($0.timestamp),
                    $0.userDescription ?? "",
                    $0.type.rawValue,
                    $0.attributes.map(\.rawValue).joined(separator: "|"),
                    $0.notes ?? ""
                ] },
                to: folder.appendingPathComponent(filename("food_events", range: foodRange))
            )

            // Therapy has no HealthKit type, so this CSV is the ONLY copy of it outside
            // CloudKit — the one stream with no second home to recover from.
            let therapies = try context.fetch(
                FetchDescriptor<TherapySession>(sortBy: [SortDescriptor(\.start)])
            )
            let therapyRange = dateRange(therapies.map(\.start))
            try writeCSV(
                header: ["id", "name", "start", "end", "durationMinutes", "notes"],
                rows: therapies.map { [
                    $0.id.uuidString,
                    // The RESOLVED name, not the relationship — a CSV has to stand alone, and a
                    // therapy ID would make the backup unreadable without the catalog beside it.
                    $0.displayName,
                    iso($0.start),
                    iso($0.end),
                    String(Int($0.duration / 60)),
                    $0.notes ?? ""
                ] },
                to: folder.appendingPathComponent(
                    filename("therapy_sessions", range: therapyRange)
                )
            )

            // Movement checks have no HealthKit type either, so — like Therapy — this CSV is
            // the only copy outside CloudKit. Taps serialize as one semicolon-joined field
            // (offset,x,y,target per tap) rather than a second file: the backup shouldn't be
            // lossier than the store it's backing up, and there is no natural per-tap row key
            // to join a separate taps table back to its trial.
            let movementChecks = try context.fetch(
                FetchDescriptor<MovementCheckTrial>(sortBy: [SortDescriptor(\.timestamp)])
            )
            let movementRange = dateRange(movementChecks.map(\.timestamp))
            try writeCSV(
                // ⚠️ The geometry columns are not optional detail — `taps` are points in the
                // capture surface's space, so without the layout that produced them an
                // exported trial can't be turned back into distances by anything outside the
                // app either. Export what makes the raw stream self-describing.
                header: ["timestamp", "hand", "tapCount", "totalTravelPt", "totalTravelMeters",
                         "offTargetMeanPt", "interTapDwellMeanSec",
                         "containerWidthPt", "containerHeightPt",
                         "targetWidthPt", "targetHeightPt", "targetGapPt", "taps"],
                rows: movementChecks.map { trial -> [String] in
                    let summary = MovementCheckMetrics.summary(for: trial)
                    let travelMeters: String = summary.travelMeters.map { String($0) } ?? ""
                    let offTarget: String = summary.offTargetMean.map { String($0) } ?? ""
                    let stream: String = trial.taps
                        .map { "\($0.offset),\($0.x),\($0.y),\($0.target)" }
                        .joined(separator: ";")
                    return [
                        iso(trial.timestamp),
                        trial.hand.rawValue,
                        String(summary.tapCount),
                        String(summary.totalTravel),
                        travelMeters,
                        offTarget,
                        String(summary.interTapDwellMean),
                        String(trial.containerWidthPt),
                        String(trial.containerHeightPt),
                        String(trial.targetWidthPt),
                        String(trial.targetHeightPt),
                        String(trial.targetGapPt),
                        stream
                    ]
                },
                to: folder.appendingPathComponent(
                    filename("movement_checks", range: movementRange)
                )
            )

            // Rotation. ⚠️ Exports the SINGLE-AXIS angular velocity series plus the axis it was
            // projected onto — without the axis the series is unreadable, the same lesson the
            // tapping geometry columns exist for. Turns/amplitude/peak/decrement are all
            // re-derivable from this outside the app.
            let rotations = try context.fetch(
                FetchDescriptor<RotationTrial>(sortBy: [SortDescriptor(\.timestamp)])
            )
            let rotationRange = dateRange(rotations.map(\.timestamp))
            try writeCSV(
                header: ["timestamp", "hand", "turns", "meanAmplitudeDegrees",
                         "peakVelocityDegPerSec", "dominantFrequencyHz", "sampleRateHz",
                         "axisX", "axisY", "axisZ", "angularVelocityRadPerSec"],
                rows: rotations.map { trial -> [String] in
                    let s = RotationMetrics.summary(for: trial)
                    let series: String = trial.angularVelocity.map { String($0) }
                        .joined(separator: ";")
                    return [
                        iso(trial.timestamp),
                        trial.hand.rawValue,
                        s.map { String($0.turns) } ?? "",
                        s.map { String($0.meanAmplitudeDegrees) } ?? "",
                        s.map { String($0.peakVelocityDegreesPerSecond) } ?? "",
                        s.map { String($0.dominantFrequency) } ?? "",
                        String(trial.sampleRate),
                        String(trial.axisX),
                        String(trial.axisY),
                        String(trial.axisZ),
                        series
                    ]
                },
                to: folder.appendingPathComponent(
                    filename("rotation_trials", range: rotationRange)
                )
            )

            print("CSV backup written to \(folder.path) — tremors=\(tremors.count) dyskinesias=\(dyskinesias.count) foods=\(foods.count) therapies=\(therapies.count) movementChecks=\(movementChecks.count) rotations=\(rotations.count)")
            return folder
        } catch {
            print("CSV export failed: \(error)")
            return nil
        }
    }

    private static func writeCSV(header: [String], rows: [[String]], to url: URL) throws {
        var content = header.map(escape).joined(separator: ",")
        for row in rows {
            content += "\n" + row.map(escape).joined(separator: ",")
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private nonisolated static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func formatOptional(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func folderTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dateRange(_ dates: [Date]) -> (first: Date, last: Date)? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return (first, last)
    }

    private static func filename(_ base: String, range: (first: Date, last: Date)?) -> String {
        guard let range else { return "\(base).csv" }
        let from = filenameDateFormatter.string(from: range.first)
        let to = filenameDateFormatter.string(from: range.last)
        return from == to ? "\(base)_\(from).csv" : "\(base)_\(from)_to_\(to).csv"
    }
}
