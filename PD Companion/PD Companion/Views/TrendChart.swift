import SwiftUI
import Charts

// MARK: - Shared scrubbable trend chart
//
// One line chart, used by every per-tile trend surface (HRV, Sleep, …) so they all read and
// behave identically. Drag across it and a crosshair + floating label report the EXACT value
// and date under your finger — the same "read a point as a number" affordance as Apple Health's
// trend charts, instead of eyeballing the line. The readout always snaps to a real data point;
// it never shows an interpolated value.

/// One point on a trend line. A named type (not a tuple) keeps Swift's type-checker fast and
/// gives the chart a stable identity.
struct TrendPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct ScrubbableTrendChart: View {
    let points: [TrendPoint]
    /// The line + highlighted point use the metric's identity color; the crosshair stays neutral.
    let accent: Color
    let yAxisLabel: String
    /// Formats the value for the readout (e.g. "72 ms", "81").
    let valueText: (Double) -> String
    /// Week ranges dot each night; longer ranges draw a clean line.
    var showPoints: Bool = false
    /// Month-granularity series (year / all) label the readout by month, not day.
    var monthlyDates: Bool = false
    /// How much x-axis is on screen at once. Set it and the chart becomes a WINDOW onto the whole
    /// series that you swipe back through, the way Health's charts do — the caller keeps passing
    /// every point it has and the range picker chooses the window width, not a cutoff date.
    /// `nil` fits the entire series to the width and there is nothing to scroll.
    var visibleDomain: TimeInterval? = nil
    /// Fires with the window actually on screen, on appear and on every scroll. The caller uses it
    /// to title the chart with the span being looked at instead of "the last 7 days".
    var onVisibleRange: ((ClosedRange<Date>) -> Void)? = nil
    /// Pass a shared binding to lock two stacked charts to the SAME window, so a reader
    /// comparing them is always comparing the same dates. `nil` (every existing caller) keeps
    /// the chart's own private scroll position and behaves exactly as before.
    var scrollPosition: Binding<Date>? = nil

    // Native tap/drag selection (same interaction as the Tremor chart). Snapped to a real night.
    @State private var selectedDate: Date? = nil
    /// Measured callout width, used only to clamp it inside the plot at the series' ends.
    @State private var calloutWidth: CGFloat = 0
    /// Leading edge of the visible window. Owned here unless the caller passed its own
    /// `scrollPosition` to link several charts together; the span showing is reported back
    /// either way via `onVisibleRange`.
    @State private var internalScrollX: Date = .distantPast
    private var scrollXBinding: Binding<Date> { scrollPosition ?? $internalScrollX }
    private var scrollX: Date {
        get { scrollXBinding.wrappedValue }
        nonmutating set { scrollXBinding.wrappedValue = newValue }
    }

    private var selected: TrendPoint? {
        guard let d = selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d))
        }
    }

    // y-domain from 0 with a thin margin above the data — just enough that the peak doesn't touch
    // the frame. (It used to reserve 55% for an in-plot callout; the callout now sits above the
    // plot, so that headroom was dead space between the top gridline and the axis-unit label.)
    // An explicit domain + explicit axes keep the crosshair RuleMark inside the plot data area
    // instead of spilling into the x-axis label band.
    //
    // Taken over the WHOLE series, not the visible window — deliberately. A window-fitted axis
    // would rescale as you scroll, so a calm week and a rough week would draw the same-height
    // line and panning would compare nothing.
    private var yLo: Double { min(points.map(\.value).min() ?? 0, 0) }
    private var yHi: Double { points.map(\.value).max() ?? 1 }
    private var ySpan: Double { max(yHi - yLo, 1) }
    private var yDomain: ClosedRange<Double> { yLo...(yHi + ySpan * 0.08) }

    /// Gap between the callout's bottom edge and the top of the plot (where the crosshair starts).
    private let calloutGap: CGFloat = 4

    // MARK: Visible window

    private var firstDate: Date { points.first?.date ?? Date() }
    private var lastDate: Date { points.last?.date ?? Date() }

    private static let halfDay: TimeInterval = 43_200

    /// The window that shows an entire series: its span plus half a day of air at each end, so the
    /// first and last points are not drawn on the frame edge. Exposed because a caller whose "All"
    /// range means *everything* needs to ask for this width by name rather than restate the maths.
    static func fullSpan(of points: [TrendPoint]) -> TimeInterval {
        guard let first = points.first?.date, let last = points.last?.date else { return 86_400 }
        return max(last.timeIntervalSince(first), 86_400) + 2 * halfDay
    }

    private var window: TimeInterval { visibleDomain ?? Self.fullSpan(of: points) }

    /// Leading edge that puts the newest point at the right of the window, carrying the same half
    /// day of air. A 7-day window then holds exactly 7 daily points, not 8 with two on the edges.
    private var newestStart: Date { lastDate.addingTimeInterval(-window + Self.halfDay) }

    private func reportVisibleRange() {
        onVisibleRange?(scrollX...scrollX.addingTimeInterval(window))
    }

    private var plot: some View {
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value(yAxisLabel, p.value))
                    .foregroundStyle(accent)
                    .interpolationMethod(.monotone)
                if showPoints {
                    PointMark(x: .value("Date", p.date), y: .value(yAxisLabel, p.value))
                        .foregroundStyle(accent)
                }
            }
            if let sel = selected {
                RuleMark(x: .value("Date", sel.date))
                    .foregroundStyle(.gray.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Date", sel.date), y: .value(yAxisLabel, sel.value))
                    .foregroundStyle(accent)
                    .symbolSize(90)
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxisLabel(yAxisLabel)
        .chartYAxis { AxisMarks() }
        .chartXAxis { AxisMarks() }
        .frame(height: 200)
    }

    var body: some View {
        // The branch is a constant per call site — a caller either windows its chart or it doesn't
        // — so this never flips at runtime and the chart keeps its identity across range switches.
        // Callers that pass no `visibleDomain` get the exact modifier chain they had before.
        Group {
            if let domain = visibleDomain {
                // Scrolling and selection coexist the way they do in Health: a plain horizontal
                // drag pans, a long press starts the crosshair. Swift Charts arbitrates that once
                // both modifiers are present — no hand-written gesture to get the priority wrong.
                plot
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: domain)
                    .chartScrollPosition(x: scrollXBinding)
                    .chartXSelection(value: $selectedDate)
                    .chartOverlay { proxy in calloutLane(proxy) }
            } else {
                plot
                    .chartXSelection(value: $selectedDate)
                    .chartOverlay { proxy in calloutLane(proxy) }
            }
        }
        // Open on the newest window, and go back to it whenever the width or the data changes —
        // landing mid-record after switching Week → Month would lose the reader's place.
        .onAppear { scrollX = newestStart; reportVisibleRange() }
        .onChange(of: window) { scrollX = newestStart }
        // A range/data swap invalidates the scrubbed point.
        .onChange(of: points) { selectedDate = nil; scrollX = newestStart }
        .onChange(of: scrollX) { reportVisibleRange() }
    }

    // The callout lives ABOVE the plot, not inside it: a Charts `.annotation` can only hang in the
    // plot area, where it crowds the data line no matter how it's anchored. Here it sits in the
    // band the chart already reserves above the plot (the one holding the y-axis unit label),
    // bottom-aligned to the top of the crosshair and tracking its x — so it never overlaps the
    // series. Clamped to the plot's x-range, which also keeps it clear of the unit label.
    @ViewBuilder
    private func calloutLane(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            if let sel = selected, let anchor = proxy.plotFrame {
                let plot = geo[anchor]
                let center = plot.minX + (proxy.position(forX: sel.date) ?? 0)
                let x = min(max(center - calloutWidth / 2, plot.minX),
                            max(plot.maxX - calloutWidth, plot.minX))
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                    callout(sel)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { calloutWidth = $0 }
                        .offset(x: x)
                }
                .frame(width: geo.size.width,
                       height: max(plot.minY - calloutGap, 0),
                       alignment: .bottomLeading)
            }
        }
        // The overlay must never intercept the scrub gesture underneath it.
        .allowsHitTesting(false)
    }

    // Styled to match the app's shared `CrosshairCallout`: a solid `systemBackground` box (adapts
    // light/dark — a material annotation renders wrong) with a hairline border + soft shadow.
    private func callout(_ p: TrendPoint) -> some View {
        HStack(spacing: 6) {
            Text(valueText(p.value)).font(.subheadline.weight(.semibold)).foregroundStyle(accent)
            Text(dateLabel(p.date)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .fixedSize()
    }

    private func dateLabel(_ date: Date) -> String {
        monthlyDates
            ? date.formatted(.dateTime.month(.abbreviated).year())
            : date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Shared window header
//
// The header a scrollable chart needs. Everything above it on a detail sheet is pinned to the
// tapped day, so once the chart can be scrolled back to June the chart has to say so itself —
// the same job as the RANGE block over Health's charts: what is on screen, and when it was.

struct TrendWindowHeader: View {
    /// The span the chart reports through `onVisibleRange`; nil only for the frame before it fires.
    let visibleRange: ClosedRange<Date>?
    /// The whole series the chart is plotting. The header describes the part inside the window.
    let points: [TrendPoint]
    let accent: Color
    /// Formats one end of the value range as a bare number.
    let valueText: (Double) -> String
    /// The metric's unit, if it has one ("ms"). Rides with the numbers, in the accent.
    var unit: String? = nil
    /// What the numbers ARE — "daily average", "nightly score", "monthly median".
    let label: String
    /// Month-granularity windows name months, not days.
    var monthlyDates: Bool = false

    /// The points actually inside the window, ascending. EVERYTHING the header says is derived
    /// from these and not from the window's own edges — the window carries half a day of air at
    /// each end and, at month granularity, its edge can fall in a month that has no point at all.
    /// Reading the edges named a month the chart wasn't plotting.
    private var windowed: [TrendPoint] {
        guard let r = visibleRange else { return [] }
        return points.filter { r.contains($0.date) }
    }

    var body: some View {
        let shown = windowed
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(rangeText(shown))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(shown.isEmpty ? Color.secondary : accent)
                if !shown.isEmpty {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            }
            // Holds the line's height while empty, so scrolling off the record doesn't reflow
            // the card under the reader's finger.
            Text(shown.isEmpty ? " " : spanText(shown))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A window holding one point — or several that round alike — is a value, not a range.
    private func rangeText(_ shown: [TrendPoint]) -> String {
        let vals = shown.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return "—" }
        let loText = valueText(lo), hiText = valueText(hi)
        let body = loText == hiText ? loText : "\(loText) - \(hiText)"
        return unit.map { "\(body) \($0)" } ?? body
    }

    /// "Jun 27 - Jul 3, 2026", or "Aug 2025 - Jul 2026" at month granularity — the first and last
    /// points on screen. The year is carried once unless the span straddles two.
    private func spanText(_ shown: [TrendPoint]) -> String {
        guard let from = shown.first?.date, let to = shown.last?.date else { return " " }
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: from) == cal.component(.year, from: to)
        if monthlyDates {
            let start = sameYear
                ? from.formatted(.dateTime.month(.abbreviated))
                : from.formatted(.dateTime.month(.abbreviated).year())
            return "\(start) - \(to.formatted(.dateTime.month(.abbreviated).year()))"
        }
        let start = sameYear
            ? from.formatted(.dateTime.month(.abbreviated).day())
            : from.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) - \(to.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}
