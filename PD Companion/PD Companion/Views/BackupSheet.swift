import SwiftUI
import SwiftData

/// Backup screen: shows the on-device record counts and date spans that should
/// match the iCloud (CloudKit) backup, and hosts the CSV export action.
///
/// The counts here are the one-glance verification: compare them against the
/// record counts in the CloudKit Console. No need to sort ascending/descending
/// in the console — the "From → To" line is the span, the number is the total.
struct BackupSheet: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TremorReading.timestamp, order: .forward) private var tremorReadings: [TremorReading]
    @Query(sort: \FoodEvent.timestamp, order: .forward) private var foodEvents: [FoodEvent]
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DataCountRow(
                        title: "Tremor readings",
                        systemImage: "waveform.path.ecg",
                        tint: .blue,
                        count: tremorReadings.count,
                        first: tremorReadings.first?.timestamp,
                        last: tremorReadings.last?.timestamp
                    )
                    DataCountRow(
                        title: "Food events",
                        systemImage: "fork.knife",
                        tint: .brown,
                        count: foodEvents.count,
                        first: foodEvents.first?.timestamp,
                        last: foodEvents.last?.timestamp
                    )
                } header: {
                    Text("Stored on this device")
                } footer: {
                    Text("These are the records SwiftData holds locally. They mirror to your private iCloud backup, so these counts and date ranges should match what you see in the CloudKit Console.")
                }

                Section {
                    Button {
                        runExport()
                    } label: {
                        HStack {
                            Label("Export CSV backup", systemImage: "square.and.arrow.up")
                            Spacer()
                            if isExporting {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(isExporting)
                } footer: {
                    Text("Exports tremor, food, and HealthKit samples as CSV files you can save or share.")
                }
            }
            .navigationTitle("Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func runExport() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            defer { Task { @MainActor in isExporting = false } }
            guard let folder = await CSVBackupExporter.exportAll(
                container: AppContainer.shared
            ) else { return }
            await healthKit.exportAllSamples(to: folder)
            let files = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            )) ?? []
            guard !files.isEmpty else {
                try? FileManager.default.removeItem(at: folder)
                return
            }
            await MainActor.run {
                ShareSheetPresenter.present(items: files) {
                    try? FileManager.default.removeItem(at: folder)
                }
            }
        }
    }
}

private struct DataCountRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let count: Int
    let first: Date?
    let last: Date?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(rangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)")
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(count) records, \(rangeText)")
    }

    private var rangeText: String {
        guard let first, let last else { return "No records yet" }
        let from = Self.dateFormatter.string(from: first)
        let to = Self.dateFormatter.string(from: last)
        return from == to ? from : "\(from) – \(to)"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
