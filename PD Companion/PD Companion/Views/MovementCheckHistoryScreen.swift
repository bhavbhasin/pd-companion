import SwiftUI
import SwiftData
import Charts

/// History + trend for movement checks. ⛔ Not a glance tile, not a Day-in-Review panel — a
/// movement check is sparser than gait, which was already parked for a daily panel for lacking
/// an honest daily shape. Reachable only from the result screen and from `+`. See
/// docs/design/movement-checks.md.
///
/// ⭐ **Two panels, one shared x-axis — taps and travel. Pause is NOT plotted.**
///
/// ⛔ **Pause is not displayed anywhere any more, and should not come back.**
/// `MovementCheckMetrics` defines it as the mean gap between consecutive taps, which is
/// algebraically `(last - first) / (n - 1)` — the reciprocal of the tap rate. Measured on the
/// Aug 5 2026 export, every trial returns the same ~9 s when you multiply pause by its gap
/// count, at 19, 21, 31 and 37 taps alike. It restates the tap count in a different unit,
/// whether as a chart or as a row. It is still computed and still exported.
///
/// Its fact row went to **Spread** — mean distance from a tap to the middle of its box — which
/// is the one recorded quantity free to vary when the tap count doesn't. ⛔ Not called
/// "accuracy": that reads as a grade, and this feature never issues one.
///
/// The two charts that remain don't share a y-axis (taps ~15-40, travel ~1-3 m) and are NOT
/// normalized onto one — a normalized axis reads in no unit anybody can name. They're stacked
/// small multiples instead, locked to the same window by `sharedScroll` so scrolling one
/// scrolls the other and the reader is always comparing the same dates.
struct MovementCheckHistoryScreen: View {
    @Query(sort: \MovementCheckTrial.timestamp) private var allTrials: [MovementCheckTrial]

    @State private var hand: MovementCheckHand = .left
    @State private var range: Range = .week
    @State private var visibleRange: ClosedRange<Date>?
    /// Shared by both charts so they can never show different spans.
    @State private var sharedScroll: Date = .distantPast

    private enum Metric: String, CaseIterable, Identifiable {
        case taps, spread
        var id: String { rawValue }
        var label: String {
            switch self {
            case .taps:   "Taps"
            case .spread: "Spread"
            }
        }
        var unit: String {
            switch self {
            case .taps:   ""
            case .spread: "mm"
            }
        }
        /// Names what one point IS, since the chart's own title is just the metric name.
        var headerLabel: String {
            switch self {
            case .taps:   "taps per trial"
            case .spread: "per trial"
            }
        }
        /// Printed under the panel, matching the matrix word for word.
        var definition: String? {
            switch self {
            case .taps:   nil
            case .spread: MovementCheckCopy.spreadDefinition
            }
        }
        /// `nil` when the trial can't answer — travel needs the capture geometry, and a trial
        /// recorded before that was stored has no scale to convert its points by.
        func value(for trial: MovementCheckTrial) -> Double? {
            let s = MovementCheckMetrics.summary(for: trial)
            switch self {
            case .taps:   return Double(s.tapCount)
            case .spread: return s.offTargetMM
            }
        }
        func valueText(_ value: Double) -> String {
            switch self {
            case .taps:   String(format: "%.0f", value)
            case .spread: String(format: "%.0f mm", value)
            }
        }
    }

    /// Window width only — the chart always plots the whole filtered series and this picks
    /// how much of it is on screen at once, same convention as `HRVRange`.
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

    private var handTrials: [MovementCheckTrial] {
        allTrials.filter { $0.hand == hand }
    }

    private func points(_ metric: Metric) -> [TrendPoint] {
        handTrials.compactMap { trial in
            metric.value(for: trial).map { TrendPoint(date: trial.timestamp, value: $0) }
        }
    }

    private var tapPoints: [TrendPoint] { points(.taps) }

    var body: some View {
        List {
            Section {
                Picker("Hand", selection: $hand) {
                    ForEach(MovementCheckHand.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                if tapPoints.count >= 2 {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            chartSection(.taps)
            // Only once there is something to draw — spread needs the capture geometry, so a
            // record that predates it has taps to plot and no spread, and an empty panel with
            // a title would read as a bug rather than as history.
            if points(.spread).count >= 2 { chartSection(.spread) }

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
        .navigationTitle("Tapping history")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One metric's panel: the window header and the chart, locked to the shared scroll
    /// position so every panel on this screen shows the same dates.
    @ViewBuilder
    private func chartSection(_ metric: Metric) -> some View {
        let pts = points(metric)
        Section {
            if pts.count < 2 {
                // Names the actual count, not just "not enough" — a chart genuinely cannot
                // draw a line from one point (or zero), and saying so plainly is the
                // difference between "expected, keep going" and "is this broken."
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
                    accent: MovementCheckStyle.tint,
                    valueText: { metric.valueText($0) },
                    unit: nil,
                    label: metric.headerLabel
                )

                ScrubbableTrendChart(
                    points: pts,
                    accent: MovementCheckStyle.tint,
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
            // Same sentence the matrix prints, from the same constant — a word explained on
            // one screen and cryptic on another is the drift this shares copy to avoid.
            if let definition = metric.definition { Text(definition) }
        }
    }

    private func historyRow(_ trial: MovementCheckTrial) -> some View {
        let s = MovementCheckMetrics.summary(for: trial)
        let rate = MovementCheckStyle.trialDuration > 0 ? Double(s.tapCount) / MovementCheckStyle.trialDuration : 0
        return HStack {
            Text(trial.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f taps/sec", rate))
                .font(.subheadline.weight(.medium))
        }
        .font(.subheadline)
    }
}
