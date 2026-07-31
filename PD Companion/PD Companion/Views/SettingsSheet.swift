import SwiftUI
import SwiftData

/// The app's Settings screen: what Kampa has stored, where it came from, how to get
/// it out, how to get help, and the legal footing.
///
/// The record counts are the one-glance verification against iCloud: compare them
/// against the record counts in the CloudKit Console. No need to sort ascending or
/// descending there — the "From → To" line is the span, the number is the total.
struct SettingsSheet: View {
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
                    NavigationLink {
                        HealthSourcesView()
                    } label: {
                        Label("Data sources", systemImage: "laptopcomputer.and.iphone")
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Choose which devices are yours. Data from anyone else won't be used.")
                }

                // MARK: - Medications (not built yet)
                //
                // The per-drug card exclusion toggle belongs here, between Your data and
                // Backup. Design: docs/design/medication-cards.md. The trigger is a user
                // who confirms doses on a schedule they already keep — the dose fetch gates
                // on `logStatus == .taken`, so 5-8 confirmed medications become 5-8 cards
                // in a single day. Slot a `Section { … } header: { Text("Medications") }`
                // in here; nothing else on this screen needs to move.

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
                } header: {
                    Text("Backup & export")
                } footer: {
                    Text("Your data is saved on this iPhone and mirrored to your private iCloud backup automatically. Exporting saves a copy of your tremor, food, and Health data as CSV files you can keep or share.")
                }

                Section {
                    Link(destination: URL(string: "https://kampa.health/faq.html#getting-started")!) {
                        Label("Getting started", systemImage: "book")
                    }
                    Link(destination: URL(string: "https://kampa.health/faq.html")!) {
                        Label("FAQ", systemImage: "questionmark.circle")
                    }
                    NavigationLink {
                        SupportView(
                            tremorCount: tremorReadings.count,
                            tremorFirst: tremorReadings.first?.timestamp,
                            tremorLast: tremorReadings.last?.timestamp,
                            foodCount: foodEvents.count,
                            foodFirst: foodEvents.first?.timestamp,
                            foodLast: foodEvents.last?.timestamp
                        )
                    } label: {
                        Label("Contact support", systemImage: "envelope")
                    }
                } header: {
                    Text("Help & support")
                }

                Section {
                    Link(destination: URL(string: "https://kampa.health/privacy.html")!) {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://kampa.health/terms.html")!) {
                        Label("Terms of use", systemImage: "doc.text")
                    }
                    LabeledContent("Version", value: SupportDiagnostics.versionAndBuild)
                } header: {
                    Text("About")
                } footer: {
                    Text("Kampa is a wellness tool, not a medical device. It doesn't diagnose or treat any condition, and it never tells you to change your medication. Talk to your neurologist about your care.")
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

    /// Start of Kampa's own record — the earliest thing the app itself logged.
    ///
    /// Health samples from before this have nothing in Kampa to be correlated against,
    /// so the high-volume HealthKit streams are clipped to it. `nil` (no Kampa data yet)
    /// falls back to full history, preserving the previous behaviour for a case where
    /// there is nothing to export against anyway.
    private var kampaRecordStart: Date? {
        [tremorReadings.first?.timestamp, foodEvents.first?.timestamp].compactMap { $0 }.min()
    }

    private func runExport() {
        guard !isExporting else { return }
        isExporting = true
        let recordStart = kampaRecordStart
        Task {
            defer { Task { @MainActor in isExporting = false } }
            guard let folder = await CSVBackupExporter.exportAll(
                container: AppContainer.shared
            ) else { return }
            await healthKit.exportAllSamples(to: folder, kampaRecordStart: recordStart)
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
