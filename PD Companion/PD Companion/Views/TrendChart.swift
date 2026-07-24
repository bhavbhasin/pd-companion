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

    private var selected: TrendPoint? {
        guard let d = selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d))
        }
    }

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
                // Full-height crosshair with the callout box hung from the top of the plot —
                // the same floating-callout pattern as the Tremor chart and Apple's sleep trend.
                RuleMark(x: .value("Date", sel.date))
                    .foregroundStyle(.gray.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top, alignment: .center, spacing: 2,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
                    ) {
                        callout(sel)
                    }
                PointMark(x: .value("Date", sel.date), y: .value(yAxisLabel, sel.value))
                    .foregroundStyle(accent)
                    .symbolSize(90)
            }
        }
        .chartYAxisLabel(yAxisLabel)
        .frame(height: 200)
        .chartXSelection(value: $selectedDate)
        // A range/data swap invalidates the scrubbed point.
        .onChange(of: points) { selectedDate = nil }
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
