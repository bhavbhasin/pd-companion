import SwiftUI
import Charts

// "Today's forecast": runs the validated wearing-off / dose-response curve forward from
// today's logged doses (CorrelationEngine.dayForecast) and shows the day's ON/OFF cycle
// as a thin band. Rendered as a Swift Charts panel that shares the tremor chart's x-domain,
// 12h visible window, scroll position, and left gutter — so it sits directly under the
// tremor line and reads straight down (dose/workout markers on the chart above align to
// the band below). The elapsed part is MEASURED tremor (solid); the rest is PROJECTED
// (faded). Doses are the only input — a future validated lever (e.g. boxing) bends the
// same single band via WindowAdjustment; it never gets its own card or timeline.
//
// SAFETY: forecast/observation only — never a dosing instruction.
struct DayAheadPanel: View {
    let forecast: CorrelationEngine.DayForecast
    let dayStart: Date
    let dayEnd: Date
    @Binding var scrollX: Date
    @AppStorage("dayReview.expanded.forecast") private var expanded = true

    // ON = medication working (blue, calm). OFF = wearing-off (muted red — NOT orange,
    // which is dyskinesia on the chart above). Unknown = no watch data (gray). Labels
    // carry the meaning; color is a second cue, never the only one.
    private static let offColor = Color(red: 0.82, green: 0.28, blue: 0.30)
    private func color(_ phase: CorrelationEngine.DayForecast.Phase) -> Color {
        switch phase {
        case .on:      return Insight.brandBlue
        case .off:     return Self.offColor
        case .unknown: return .gray
        }
    }

    private var phaseAtNow: CorrelationEngine.DayForecast.Phase? {
        forecast.segments.first { forecast.now >= $0.start && forecast.now < $0.end }?.phase
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private var whenText: String {
        if let range = forecast.nextOffRange {
            return "\(time(range.lowerBound)) – \(time(range.upperBound))"
        }
        if let off = forecast.nextOffStart { return "around \(time(off))" }
        return ""
    }

    // The next projected ON onset after now (only exists in the just-dosed, pre-onset
    // gap — a logged dose whose ON hasn't started yet; future/unlogged doses can't appear).
    private var nextOnStart: Date? {
        forecast.segments.first { $0.start > forecast.now && !$0.observed && $0.phase == .on }?.start
    }

    // Plain-language, present-tense, threshold-free — and forward-leaning: it leads with
    // the next transition (the forecast's whole point), not the current sliver. So a dose
    // that hasn't kicked in yet reads as "ON coming," not "you're OFF." Never a dosing
    // instruction — the onset time is the user's own latency, stated as expectation.
    private var headline: String {
        switch phaseAtNow {
        case .on:
            if let off = forecast.nextOffStart, off > forecast.now {
                return "You're likely ON (steady) right now — wearing off expected \(whenText)."
            }
            return "You're likely ON (steady) right now."
        case .off:
            if let on = nextOnStart {
                return "Your last dose should bring you ON (steady) around \(time(on))."
            }
            return "You may be in an OFF (wearing-off) window right now."
        default:
            if let on = nextOnStart {
                return "Your last dose should bring you ON (steady) around \(time(on))."
            }
            if let off = forecast.nextOffStart, off > forecast.now {
                return "An OFF (wearing-off) window is expected \(whenText)."
            }
            return "Not enough recent watch data to call your state right now."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max")
                        .foregroundStyle(Insight.brandBlue)
                    Text("Today's forecast")
                        .font(.headline)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                band

                Text(headline)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)

                legend

                Text("A pattern from your own data — not medical advice. Share it with your neurologist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's forecast. \(headline)")
    }

    // Shares the tremor chart's domain / 12h window / scroll / gutter so it aligns.
    private var band: some View {
        Chart {
            ForEach(Array(forecast.segments.enumerated()), id: \.offset) { _, seg in
                RectangleMark(
                    xStart: .value("Start", seg.start),
                    xEnd: .value("End", seg.end),
                    yStart: .value("lo", 0),
                    yEnd: .value("hi", 1)
                )
                .foregroundStyle(color(seg.phase).opacity(seg.observed ? 0.9 : 0.32))
            }
            RuleMark(x: .value("Now", forecast.now))
                .foregroundStyle(Color.primary.opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                // The pulsing dot is an annotation ON the rule, so it lives in the chart's
                // data coordinates and scrolls locked to the line (a chartOverlay lives in
                // screen space and would drift apart on scroll).
                .annotation(position: .overlay, alignment: .center) { NowPulse() }
        }
        .chartYScale(domain: 0...1)
        .chartXScale(domain: dayStart...dayEnd)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: 12 * 3600)
        .chartScrollPosition(x: $scrollX)
        .chartYAxis {
            // Empty label reserving the SAME gutter (same side + width) as the tremor/glucose
            // panels — they use the default (trailing) Y-axis, so the plot's left edge is the
            // container edge and all three timelines line up. Forcing .leading here shifted the
            // plot right by the gutter width and threw off both alignment and the "now" overlay.
            AxisMarks(values: [0]) { _ in
                AxisValueLabel {
                    Text(" ").frame(width: DayReviewLayout.yAxisWidth, alignment: .leading)
                }
            }
        }
        .chartXAxis {
            // Same hourly ticks + 3-hour labels/gridlines as the tremor & glucose panels,
            // so the three stacked timelines read as one.
            AxisMarks(values: .stride(by: .hour, count: 1)) { _ in
                AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.gray.opacity(0.4))
            }
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: 60)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            swatch(color: Insight.brandBlue, label: "ON")
            swatch(color: Self.offColor, label: "OFF")
            swatch(color: .gray, label: "No watch data")
        }
    }

    private func swatch(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// Live "now" cursor: a solid dot with an expanding, fading ring (radar ping) — signals
// "current time" without a text label taking horizontal space.
private struct NowPulse: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.6), lineWidth: 1.5)
                .frame(width: 7, height: 7)
                .scaleEffect(animate ? 2.6 : 1)
                .opacity(animate ? 0 : 0.7)
            Circle()
                .fill(Color.primary)
                .frame(width: 7, height: 7)
        }
        .animation(.easeOut(duration: 1.3).repeatForever(autoreverses: false), value: animate)
        .onAppear { animate = true }
    }
}

#if DEBUG
#Preview("Today's forecast — mid-afternoon") {
    let day = Calendar.current.startOfDay(for: .now)
    func t(_ h: Double) -> Date { day.addingTimeInterval(h * 3600) }
    let now = t(14.5)
    typealias Seg = CorrelationEngine.DayForecast.Segment
    let segments: [Seg] = [
        Seg(start: t(8),    end: t(9.3),  phase: .off,     observed: true),
        Seg(start: t(9.3),  end: t(12.4), phase: .on,      observed: true),
        Seg(start: t(12.4), end: t(13.3), phase: .off,     observed: true),
        Seg(start: t(13.3), end: now,     phase: .on,      observed: true),
        Seg(start: now,     end: t(16.5), phase: .on,      observed: false),
        Seg(start: t(16.5), end: t(24),   phase: .off,     observed: false),
    ]
    let forecast = CorrelationEngine.DayForecast(
        segments: segments, now: now,
        nextOffStart: t(16.5),
        nextOffRange: t(16.5).addingTimeInterval(-25 * 60)...t(16.5).addingTimeInterval(25 * 60),
        confidence: .moderate)
    return ScrollView {
        DayAheadPanel(forecast: forecast, dayStart: day, dayEnd: t(24),
                      scrollX: .constant(t(9)))
            .padding()
    }
}
#endif
