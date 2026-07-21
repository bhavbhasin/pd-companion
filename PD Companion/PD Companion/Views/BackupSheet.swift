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
                    Text("Saved on this iPhone and mirrored to your private iCloud backup.")
                }

                Section {
                    NavigationLink {
                        HealthSourcesView()
                    } label: {
                        Label("Data sources", systemImage: "laptopcomputer.and.iphone")
                    }
                } footer: {
                    Text("Choose which devices are yours. Data from anyone else won't be used.")
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
                    Text("Save your tremor, food, and Health data as CSV files.")
                }
            }
            .navigationTitle("Settings")
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

/// App-wide "which devices are yours?" review. Multi-select by exclusion: every source
/// is "mine" (on) by default; the user switches off any that aren't theirs (a family
/// member's watch, an old restored device that synced in). Exclusions persist per-user
/// and apply to EVERY metric Kampa reads — not just gait. New sources are included
/// automatically. This is the only honest way to validate ownership; HealthKit gives no
/// "this is the account owner" flag.
struct HealthSourcesView: View {
    @EnvironmentObject private var healthKit: HealthKitManager
    @State private var sources: [HealthSourceInfo] = []
    @State private var excluded: Set<String> = HealthSourcePrefs.excluded
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                // Centered on the grouped background — consistent with the rest of the app's
                // loading states, not a lone white cell that reads like an empty text field.
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large).tint(Insight.brandBlue)
                    Text("Finding your devices…").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else if sources.isEmpty {
                VStack(spacing: 8) {
                    Text("No devices found").font(.headline)
                    Text("Nothing has written to Apple Health yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    Section {
                        ForEach(sources) { s in
                            Toggle(isOn: binding(for: s)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name)
                                    if let st = s.stats {
                                        Text("\(st.count.formatted()) entries · \(span(st))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(Insight.brandBlue)
                        }
                    } header: {
                        Text("Your devices")
                    } footer: {
                        Text("Turn off anything that isn't yours — its data won't be used anywhere in Kampa. New devices are added automatically.")
                    }
                }
            }
        }
        .navigationTitle("Data sources")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            // Phase 1: names appear instantly (HKSourceQuery, no sample scan).
            sources = await healthKit.fetchAllHealthSources()
            loaded = true
            // Phase 2: entry counts + date spans fill in from the heavier tally.
            let stats = await healthKit.sourceStats()
            sources = sources.map {
                var s = $0
                s.stats = stats[HealthSourcePrefs.canonical(s.name)]
                return s
            }
        }
    }

    /// On = "mine" (included). Writes straight through to the shared store so the change
    /// takes effect app-wide the next time any metric is read — no explicit save step.
    private func binding(for s: HealthSourceInfo) -> Binding<Bool> {
        let key = HealthSourcePrefs.canonical(s.name)
        return Binding(
            get: { !excluded.contains(key) },
            set: { isMine in
                if isMine { excluded.remove(key) }
                else { excluded.insert(key) }
                HealthSourcePrefs.excluded = excluded
            }
        )
    }

    private func span(_ st: HealthSourceInfo.Stats) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return "\(f.string(from: st.firstDate))–\(f.string(from: st.lastDate))"
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
