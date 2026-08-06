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

            Section("History") {
                if handTrials.isEmpty {
                    Text("No \(hand.displayName.lowercased())-hand trials yet.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(handTrials.reversed(), id: \.id) { trial in
                        historyRow(trial)
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

    private func historyRow(_ trial: RotationTrial) -> some View {
        let turns = RotationMetrics.summary(for: trial)?.turns
        return HStack {
            Text(trial.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                .foregroundStyle(.secondary)
            Spacer()
            Text(turns.map { "\($0) turns" } ?? "—")
                .font(.subheadline.weight(.medium))
        }
        .font(.subheadline)
    }
}
