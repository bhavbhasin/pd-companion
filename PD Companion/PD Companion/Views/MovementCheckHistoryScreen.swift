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
/// ⛔ Pause is not a second measurement: `MovementCheckMetrics` defines it as the mean gap
/// between consecutive taps, which is algebraically `(last - first) / (n - 1)` — the reciprocal
/// of the tap rate. Measured on the Aug 5 2026 export, every trial returns the same ~9 s when
/// you multiply pause by its gap count, at 19, 21, 31 and 37 taps alike. Charting it beside
/// taps would draw one signal twice, mirrored. It stays as a fact row, where a number the
/// reader can look up is useful and a trend line would be a duplicate.
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
        case taps, travel, pause
        var id: String { rawValue }
        var label: String {
            switch self {
            case .taps:   "Taps"
            case .travel: "Travel"
            case .pause:  "Pause"
            }
        }
        var unit: String {
            switch self {
            case .taps:   ""
            case .travel: "m"
            case .pause:  "ms"
            }
        }
        /// Names what one point IS, since the chart's own title is just the metric name.
        var headerLabel: String {
            switch self {
            case .taps:   "taps per trial"
            case .travel: "per trial"
            case .pause:  "per trial"
            }
        }
        /// `nil` when the trial can't answer — travel needs the capture geometry, and a trial
        /// recorded before that was stored has no scale to convert its points by.
        func value(for trial: MovementCheckTrial) -> Double? {
            let s = MovementCheckMetrics.summary(for: trial)
            switch self {
            case .taps:   return Double(s.tapCount)
            case .travel: return s.travelMeters
            case .pause:  return s.interTapDwellMean * 1000
            }
        }
        func valueText(_ value: Double) -> String {
            switch self {
            case .taps:   String(format: "%.0f", value)
            case .travel: String(format: "%.1f m", value)
            case .pause:  String(format: "%.0f ms", value)
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
            // Only once there is something to draw — travel needs the capture geometry, so a
            // record that predates it has taps to plot and no travel, and an empty panel with
            // a title would read as a bug rather than as history.
            if points(.travel).count >= 2 { chartSection(.travel) }

            // Pause is a FACT here and never a chart — it is the tap count inverted, and a
            // second line of the same signal is not evidence. See the type doc.
            if let latest = handTrials.last {
                Section("Also recorded, most recent trial") {
                    secondaryRow(.pause, latest: latest)
                }
            }

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
        .navigationTitle("Movement check history")
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
        }
    }

    private func secondaryRow(_ metric: Metric, latest: MovementCheckTrial) -> some View {
        let value = metric.value(for: latest)
        let history = handTrials.dropLast().compactMap { metric.value(for: $0) }
        let rangeText = MovementCheckMetrics.usualRange(history).map {
            "\(metric.valueText($0.lo)) - \(metric.valueText($0.hi))"
        }
        return HStack {
            Text(metric.label).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value.map { metric.valueText($0) } ?? "—").font(.body.weight(.medium))
                if let rangeText {
                    Text("your usual lately \(rangeText)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
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
