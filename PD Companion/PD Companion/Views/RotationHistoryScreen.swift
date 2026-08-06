import SwiftUI
import SwiftData
import Charts

/// History + trend for rotation. Two panels on one shared x-axis — Turns and Amplitude — the
/// same shape as Tapping's, and for the same reason: they don't share a y-axis (turns ~20-40,
/// amplitude ~60-180°) and normalizing them onto one would produce an axis in no unit anybody
/// can name. Locked to the same window by `sharedScroll` so the reader always compares the
/// same dates.
struct RotationHistoryScreen: View {
    @Query(sort: \RotationTrial.timestamp) private var allTrials: [RotationTrial]

    @State private var hand: MovementCheckHand = .left
    @State private var range: Range = .week
    @State private var visibleRange: ClosedRange<Date>?
    @State private var sharedScroll: Date = .distantPast

    private enum Metric: String, CaseIterable, Identifiable {
        case turns, amplitude
        var id: String { rawValue }
        var label: String {
            switch self {
            case .turns:     "Turns"
            case .amplitude: "Amplitude"
            }
        }
        /// ⛔ Empty for both: `chartYAxisLabel` overflows a trailing y-axis and renders as a
        /// clipped stub, and the window header already prints the unit on every value. Same
        /// call as the tapping charts.
        var unit: String { "" }
        var headerLabel: String {
            switch self {
            case .turns:     "turns per trial"
            case .amplitude: "per flip"
            }
        }
        var definition: String? {
            switch self {
            case .turns:     nil
            case .amplitude: RotationCopy.amplitudeDefinition
            }
        }
        func value(for trial: RotationTrial) -> Double? {
            guard let s = RotationMetrics.summary(for: trial) else { return nil }
            switch self {
            case .turns:     return Double(s.turns)
            case .amplitude: return s.meanAmplitudeDegrees
            }
        }
        func valueText(_ value: Double) -> String {
            switch self {
            case .turns:     String(format: "%.0f", value)
            case .amplitude: String(format: "%.0f°", value)
            }
        }
    }

    private enum Range: String, CaseIterable, Identifiable {
        case week, month, year, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week:  "Week"
            case .month: "Month"
            case .year:  "Year"
            case .all:   "All"
            }
        }
        func visibleDomain(fullSpan: TimeInterval) -> TimeInterval {
            switch self {
            case .week:  7 * 86_400
            case .month: 30 * 86_400
            case .year:  365 * 86_400
            case .all:   fullSpan
            }
        }
    }

    private var handTrials: [RotationTrial] { allTrials.filter { $0.hand == hand } }

    private func points(_ metric: Metric) -> [TrendPoint] {
        handTrials.compactMap { trial in
            metric.value(for: trial).map { TrendPoint(date: trial.timestamp, value: $0) }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Hand", selection: $hand) {
                    ForEach(MovementCheckHand.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                if points(.turns).count >= 2 {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            chartSection(.turns)
            if points(.amplitude).count >= 2 { chartSection(.amplitude) }

            // ⭐ Session-level, showing BOTH hands on one row — not one row per hand. A row
            // reading "37 turns" under a Left/Right picker couldn't say which hand it meant,
            // and more importantly the between-hands gap is the signal this feature exists
            // for; putting the two numbers side by side means the reader never has to toggle
            // the picker and hold one in their head. The picker still filters the charts.
            Section("History") {
                if sessions.isEmpty {
                    Text("No trials yet.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(sessions, id: \.id) { session in
                        sessionRow(session)
                    }
                }
            }
        }
        .navigationTitle("Rotation history")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func chartSection(_ metric: Metric) -> some View {
        let pts = points(metric)
        Section {
            if pts.count < 2 {
                Text(pts.isEmpty
                     ? "No \(hand.displayName.lowercased())-hand trials yet."
                     : "1 \(hand.displayName.lowercased())-hand trial so far - a trend needs at least 2.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                TrendWindowHeader(
                    visibleRange: visibleRange,
                    points: pts,
                    accent: RotationStyle.tint,
                    valueText: { metric.valueText($0) },
                    unit: nil,
                    label: metric.headerLabel
                )
                ScrubbableTrendChart(
                    points: pts,
                    accent: RotationStyle.tint,
                    yAxisLabel: metric.unit,
                    valueText: { metric.valueText($0) },
                    showPoints: true,
                    visibleDomain: range.visibleDomain(
                        fullSpan: ScrubbableTrendChart.fullSpan(of: pts)),
                    onVisibleRange: { visibleRange = $0 },
                    scrollPosition: $sharedScroll
                )
            }
        } header: {
            Text(metric.label)
        } footer: {
            if let definition = metric.definition { Text(definition) }
        }
    }

    /// One completed sitting: the trials within 5 minutes of each other, the same grouping the
    /// timeline detail sheet uses so "a session" means one thing everywhere.
    private struct Session: Identifiable {
        let id: UUID
        let time: Date
        let left: RotationTrial?
        let right: RotationTrial?
    }

    private var sessions: [Session] {
        var out: [Session] = []
        var pending: [RotationTrial] = []

        func flush() {
            guard let first = pending.first else { return }
            out.append(Session(id: first.id, time: first.timestamp,
                               left: pending.first { $0.hand == .left },
                               right: pending.first { $0.hand == .right }))
            pending = []
        }
        for trial in allTrials {
            if let last = pending.last,
               trial.timestamp.timeIntervalSince(last.timestamp) > 5 * 60 { flush() }
            pending.append(trial)
        }
        flush()
        return out.reversed()
    }

    private func sessionRow(_ session: Session) -> some View {
        HStack {
            Text(session.time, format: .dateTime.month(.abbreviated).day().hour().minute())
                .foregroundStyle(.secondary)
            Spacer()
            handTurns("L", session.left)
            handTurns("R", session.right)
        }
        .font(.subheadline)
    }

    private func handTurns(_ label: String, _ trial: RotationTrial?) -> some View {
        let turns = trial.flatMap { RotationMetrics.summary(for: $0)?.turns }
        return HStack(spacing: 3) {
            Text(label).foregroundStyle(.tertiary)
            Text(turns.map(String.init) ?? "—")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .frame(minWidth: 46, alignment: .trailing)
    }
}
