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

            print("CSV backup written to \(folder.path) — tremors=\(tremors.count) foods=\(foods.count)")
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
