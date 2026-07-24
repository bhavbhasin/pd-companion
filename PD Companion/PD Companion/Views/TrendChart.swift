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

    // Native tap/drag selection (same interaction as the Tremor chart). Snapped to a real night.
    @State private var selectedDate: Date? = nil
    /// Measured callout width, used only to clamp it inside the plot at the series' ends.
    @State private var calloutWidth: CGFloat = 0

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
    private var yLo: Double { min(points.map(\.value).min() ?? 0, 0) }
    private var yHi: Double { points.map(\.value).max() ?? 1 }
    private var ySpan: Double { max(yHi - yLo, 1) }
    private var yDomain: ClosedRange<Double> { yLo...(yHi + ySpan * 0.08) }

    /// Gap between the callout's bottom edge and the top of the plot (where the crosshair starts).
    private let calloutGap: CGFloat = 4

    var body: some View {
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
        .chartXSelection(value: $selectedDate)
        .chartOverlay { proxy in calloutLane(proxy) }
        // A range/data swap invalidates the scrubbed point.
        .onChange(of: points) { selectedDate = nil }
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
