import SwiftUI
import SwiftData
import WatchConnectivity

/// Contact-support screen.
///
/// Deliberately NOT built on `MFMailComposeViewController`: that only works when Apple
/// Mail is configured, so it fails outright for anyone whose mail lives in the Gmail or
/// Outlook app. The self-contained path is primary here — the address and the diagnostics
/// are on screen, copyable, and shareable through any channel. Opening a mail app is one
/// optional route out, not the only one.
///
/// The diagnostics are shown in full before they go anywhere. In a health app the user
/// should be able to read exactly what they are about to send, and confirm for themselves
/// that it contains no health values.
struct SupportView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKit: HealthKitManager
    @StateObject private var cloudAccount = CloudAccountMonitor.shared
    @State private var didCopy = false
    @State private var stats: RecordStats?

    /// Count + span for one stream. Deliberately NOT `@Query`.
    ///
    /// ⛔ **Never hold a `@Query` over a reading stream to compute a count.** `SettingsSheet` did
    /// exactly that (added `eea4104`, Jul 30) and materialized every `TremorReading` and
    /// `DyskinesiaReading` — ~157k SwiftData objects on the reference record — to display four
    /// numbers on a screen one level deeper. Worse, a `@Query` re-runs whenever anything saves to
    /// the store, so once the therapy screens started writing, opening or leaving Settings paid
    /// that fetch again each time. A count is `fetchCount`, and a span is two `fetchLimit = 1`
    /// fetches: twelve cheap queries instead of a full hydration. Same pattern
    /// `DayInReviewView.hasEverHadData` already uses.
    struct RecordStats {
        var tremor: (count: Int, first: Date?, last: Date?) = (0, nil, nil)
        var dyskinesia: (count: Int, first: Date?, last: Date?) = (0, nil, nil)
        var food: (count: Int, first: Date?, last: Date?) = (0, nil, nil)
        var therapy: (count: Int, first: Date?, last: Date?) = (0, nil, nil)
        var movementCheck: (count: Int, first: Date?, last: Date?) = (0, nil, nil)
    }

    private var diagnostics: String {
        let s = stats ?? RecordStats()
        return SupportDiagnostics.text(
            healthAuthorized: healthKit.isAuthorized,
            iCloudStatus: cloudAccount.diagnosticDescription,
            tremorCount: s.tremor.count,
            tremorFirst: s.tremor.first,
            tremorLast: s.tremor.last,
            dyskinesiaCount: s.dyskinesia.count,
            dyskinesiaFirst: s.dyskinesia.first,
            dyskinesiaLast: s.dyskinesia.last,
            foodCount: s.food.count,
            foodFirst: s.food.first,
            foodLast: s.food.last,
            therapyCount: s.therapy.count,
            therapyFirst: s.therapy.first,
            therapyLast: s.therapy.last,
            movementCheckCount: s.movementCheck.count,
            movementCheckFirst: s.movementCheck.first,
            movementCheckLast: s.movementCheck.last
        )
    }

    /// Cheapest possible span: the earliest and latest row, one each, never the rows between.
    private func span<T: PersistentModel>(
        _ type: T.Type, key: KeyPath<T, Date>, sortBy: KeyPath<T, Date> & Sendable
    ) -> (count: Int, first: Date?, last: Date?) {
        let count = (try? modelContext.fetchCount(FetchDescriptor<T>())) ?? 0
        guard count > 0 else { return (0, nil, nil) }
        var ascending = FetchDescriptor<T>(sortBy: [SortDescriptor(sortBy, order: .forward)])
        ascending.fetchLimit = 1
        var descending = FetchDescriptor<T>(sortBy: [SortDescriptor(sortBy, order: .reverse)])
        descending.fetchLimit = 1
        let first = (try? modelContext.fetch(ascending))?.first?[keyPath: key]
        let last = (try? modelContext.fetch(descending))?.first?[keyPath: key]
        return (count, first, last)
    }

    private func loadStats() {
        var s = RecordStats()
        s.tremor = span(TremorReading.self, key: \.timestamp, sortBy: \.timestamp)
        s.dyskinesia = span(DyskinesiaReading.self, key: \.startDate, sortBy: \.startDate)
        s.food = span(FoodEvent.self, key: \.timestamp, sortBy: \.timestamp)
        s.therapy = span(TherapySession.self, key: \.start, sortBy: \.start)
        s.movementCheck = span(MovementCheckTrial.self, key: \.timestamp, sortBy: \.timestamp)
        stats = s
    }

    var body: some View {
        List {
            Section {
                Text(SupportDiagnostics.supportEmail)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Insight.brandBlue)
                    .textSelection(.enabled)
                    .accessibilityLabel("Support email address, \(SupportDiagnostics.supportEmail)")
            } header: {
                Text("Email us")
            } footer: {
                Text("Tell us what happened in your own words. The details below say which version you're on and how much data you have - nothing about your health.")
            }

            Section {
                Button {
                    UIPasteboard.general.string = diagnostics
                    withAnimation { didCopy = true }
                } label: {
                    Label(didCopy ? "Copied" : "Copy details", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }

                Button {
                    ShareSheetPresenter.present(items: [diagnostics])
                } label: {
                    Label("Share details", systemImage: "square.and.arrow.up")
                }

                if let mailURL = SupportDiagnostics.mailURL(body: diagnostics) {
                    Link(destination: mailURL) {
                        Label("Open in email app", systemImage: "envelope")
                    }
                }
            }

            Section {
                Text(diagnostics)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            } header: {
                Text("Details")
            }
        }
        .navigationTitle("Contact support")
        .navigationBarTitleDisplayMode(.inline)
        // Counted when this screen opens — the only place the numbers are read — instead of
        // being held live by the screen above it.
        .task { loadStats() }
    }
}

/// Builds the support diagnostics block.
///
/// ⛔ Counts and status only — never a health value. A support message should never carry
/// a tremor reading, a dose, or a symptom. Sizes and spans are enough to reproduce almost
/// any bug worth reporting, and they cost the user nothing to disclose.
enum SupportDiagnostics {
    /// Single point of truth for the address. A Namecheap forwarder points this at the
    /// real inbox, so routing can change without shipping an app update.
    static let supportEmail = "support@kampa.health"

    static var versionAndBuild: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static func text(
        healthAuthorized: Bool,
        /// Passed in rather than fetched here: `accountStatus()` is async and `text()` is a
        /// pure string builder the view reads synchronously — same shape as the counts.
        iCloudStatus: String,
        tremorCount: Int,
        tremorFirst: Date?,
        tremorLast: Date?,
        dyskinesiaCount: Int,
        dyskinesiaFirst: Date?,
        dyskinesiaLast: Date?,
        foodCount: Int,
        foodFirst: Date?,
        foodLast: Date?,
        therapyCount: Int,
        therapyFirst: Date?,
        therapyLast: Date?,
        movementCheckCount: Int,
        movementCheckFirst: Date?,
        movementCheckLast: Date?
    ) -> String {
        var lines = [
            "Kampa \(versionAndBuild)",
            "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion), \(deviceModel)",
            "Apple Watch paired: \(isWatchPaired)",
            "Health access: \(healthAuthorized ? "granted" : "not granted")",
            // The third of the three things that silently break a user's record — and the
            // one with no recovery, since CloudKit is the only restore path.
            "iCloud: \(iCloudStatus)",
            "Tremor readings: \(tremorCount)\(span(tremorFirst, tremorLast))",
            // Its own line, not folded into tremor: the two are independent one-minute series
            // and a sync or dedup fault can move one without the other — which is invisible if
            // only tremor is reported.
            "Dyskinesia readings: \(dyskinesiaCount)\(span(dyskinesiaFirst, dyskinesiaLast))",
            "Food events: \(foodCount)\(span(foodFirst, foodLast))",
            // Its own line for the same reason dyskinesia has one: therapy is the only stream
            // with no HealthKit copy, so if it goes missing this count is the only evidence.
            "Therapy sessions: \(therapyCount)\(span(therapyFirst, therapyLast))",
            // Its own line for the same reason therapy has one: no HealthKit copy, so this
            // count is the only evidence if the stream goes missing.
            "Movement checks: \(movementCheckCount)\(span(movementCheckFirst, movementCheckLast))"
        ]
        lines.append("Sent \(Self.timestampFormatter.string(from: Date()))")
        return lines.joined(separator: "\n")
    }

    /// `mailto:` rather than `MFMailComposeViewController` — this opens whatever the user
    /// set as their default mail app, so it works for Gmail and Outlook users too.
    static func mailURL(body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Kampa support"),
            URLQueryItem(name: "body", value: "\n\n\(body)")
        ]
        return components.url
    }

    private static func span(_ first: Date?, _ last: Date?) -> String {
        guard let first, let last else { return "" }
        let from = dayFormatter.string(from: first)
        let to = dayFormatter.string(from: last)
        return from == to ? " (\(from))" : " (\(from) to \(to))"
    }

    /// The hardware identifier, e.g. `iPhone17,1`. `UIDevice.model` only ever says
    /// "iPhone", which is useless for reproducing a device-specific bug.
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static var isWatchPaired: String {
        guard WCSession.isSupported() else { return "not supported" }
        return WCSession.default.isPaired ? "yes" : "no"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm zzz"
        return formatter
    }()
}
