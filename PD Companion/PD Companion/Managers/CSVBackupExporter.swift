import Foundation
import SwiftData

@MainActor
enum CSVBackupExporter {
    static func exportAll(context: ModelContext) -> URL? {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("Backup-\(folderTimestamp())", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let tremors = try context.fetch(
                FetchDescriptor<TremorReading>(sortBy: [SortDescriptor(\.timestamp)])
            )
            try writeCSV(
                header: ["timestamp", "tremorScore", "dyskinesiaScore"],
                rows: tremors.map { [
                    iso($0.timestamp),
                    String($0.tremorScore),
                    String($0.dyskinesiaScore)
                ] },
                to: folder.appendingPathComponent("tremor_readings.csv")
            )

            let foods = try context.fetch(
                FetchDescriptor<FoodEvent>(sortBy: [SortDescriptor(\.timestamp)])
            )
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
                to: folder.appendingPathComponent("food_events.csv")
            )

            let snapshots = try context.fetch(
                FetchDescriptor<HealthSnapshot>(sortBy: [SortDescriptor(\.date)])
            )
            try writeCSV(
                header: [
                    "date", "sleepHours", "hrvAverage", "restingHeartRate",
                    "exerciseMinutes", "mindfulnessMinutes", "stepCount"
                ],
                rows: snapshots.map { [
                    iso($0.date),
                    formatOptional($0.sleepHours),
                    formatOptional($0.hrvAverage),
                    formatOptional($0.restingHeartRate),
                    formatOptional($0.exerciseMinutes),
                    formatOptional($0.mindfulnessMinutes),
                    formatOptional($0.stepCount)
                ] },
                to: folder.appendingPathComponent("health_snapshots.csv")
            )

            print("CSV backup written to \(folder.path) — tremors=\(tremors.count) foods=\(foods.count) snapshots=\(snapshots.count)")
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

    private static func escape(_ field: String) -> String {
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
}
