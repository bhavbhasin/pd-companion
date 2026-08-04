import SwiftUI
import SwiftData

/// The app's Settings screen: where data comes from, how to get it out, how to get
/// help, and the legal footing.
///
/// ⛔ Deliberately does NOT show tremor/food record counts. Those were developer
/// instrumentation — a one-glance check against the CloudKit Console — and they were
/// the largest, boldest thing on a screen where they meant nothing to a user. The same
/// counts, with spans, now live in Contact support → details, which is the context that
/// actually needs them. `@Query` is kept here only to feed that block.
struct SettingsSheet: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @StateObject private var cloudAccount = CloudAccountMonitor.shared
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TremorReading.timestamp, order: .forward) private var tremorReadings: [TremorReading]
    @Query(sort: \DyskinesiaReading.startDate, order: .forward) private var dyskinesiaReadings: [DyskinesiaReading]
    @Query(sort: \FoodEvent.timestamp, order: .forward) private var foodEvents: [FoodEvent]
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        HealthSourcesView()
                    } label: {
                        Label("Data sources", systemImage: "laptopcomputer.and.iphone")
                    }
                    Button {
                        runExport()
                    } label: {
                        HStack {
                            Label("Export CSV backup", systemImage: "square.and.arrow.up")
                                .foregroundStyle(.primary)
                            Spacer()
                            if isExporting {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(isExporting)
                } header: {
                    Text("Your data")
                } footer: {
                    // Was a flat assertion that backup was happening, with nothing checking it.
                    // This is the standing surface: the banner on Day in Review is dismissible,
                    // this line keeps telling the truth for as long as it stays true.
                    Text(cloudAccount.settingsFooterText)
                }

                // MARK: - Medications (not built yet)
                //
                // The per-drug card exclusion toggle belongs here, after Your data.
                // Design: docs/design/medication-cards.md. The trigger is a user who
                // confirms doses on a schedule they already keep — the dose fetch gates
                // on `logStatus == .taken`, so 5-8 confirmed medications become 5-8 cards
                // in a single day. Slot a `Section { … } header: { Text("Medications") }`
                // in here; nothing else on this screen needs to move.

                Section {
                    // Points at the dedicated setup page, not the FAQ's thinner section:
                    // /start carries every step in first-run order with a short video each,
                    // and its anchors are what in-app "Show me how" links will target.
                    externalLink("Getting started", systemImage: "book",
                                 url: "https://kampa.health/start.html")
                    externalLink("FAQ", systemImage: "questionmark.circle",
                                 url: "https://kampa.health/faq.html")
                    NavigationLink {
                        SupportView(
                            tremorCount: tremorReadings.count,
                            tremorFirst: tremorReadings.first?.timestamp,
                            tremorLast: tremorReadings.last?.timestamp,
                            dyskinesiaCount: dyskinesiaReadings.count,
                            dyskinesiaFirst: dyskinesiaReadings.first?.startDate,
                            dyskinesiaLast: dyskinesiaReadings.last?.startDate,
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
                    externalLink("Privacy policy", systemImage: "hand.raised",
                                 url: "https://kampa.health/privacy.html")
                    externalLink("Terms of use", systemImage: "doc.text",
                                 url: "https://kampa.health/terms.html")
                    LabeledContent("Version", value: SupportDiagnostics.versionAndBuild)
                } header: {
                    Text("About")
                } footer: {
                    Text("Kampa is a wellness tool, not a medical device. It doesn't diagnose or treat any condition and never advises on medication. Talk to your neurologist about your care.")
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

    /// A row that opens a web page, styled to match the in-app rows around it.
    ///
    /// A bare `Link` renders its whole label in the accent colour, so a list mixing links
    /// with `NavigationLink`s reads as a wall of blue interrupted by ordinary rows. This
    /// keeps the icon tinted and the title in primary text — the same shape as every other
    /// row — and adds a small arrow so it is still clear the tap leaves the app.
    private func externalLink(_ title: String, systemImage: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Label {
                    Text(title).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: systemImage)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityHint("Opens in your browser")
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
                        Text("Turn off anything that isn't yours - its data won't be used anywhere in Kampa. New devices are added automatically.")
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
