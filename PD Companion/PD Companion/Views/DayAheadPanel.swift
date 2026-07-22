import SwiftUI
import Charts

// "Today's forecast": runs the validated wearing-off / dose-response curve forward from
// today's logged doses (CorrelationEngine.dayForecast) and shows the day's ON/OFF cycle
// as a thin band. Rendered as a Swift Charts panel that shares the tremor chart's x-domain,
// 12h visible window, scroll position, and left gutter — so it sits directly under the
// tremor line and reads straight down (dose/workout markers on the chart above align to
// the band below). The elapsed part is MEASURED tremor (solid); the rest is PROJECTED
// (faded). Doses are the only projected event — a future validated lever (e.g. boxing)
// bends the same single band via WindowAdjustment; it never gets its own card or timeline.
// A ZERO-DOSE day renders the flat personal band instead (forecast.band != nil): elapsed
// day classified against the user's own typical range, remainder flat — different labels
// (never ON/OFF), same bar. See docs/design/forecast-composition-model.md, Phase 0.
//
// SAFETY: forecast/observation only — never a dosing instruction.
struct DayAheadPanel: View {
    let forecast: CorrelationEngine.DayForecast
    let dayStart: Date
    let dayEnd: Date
    @Binding var scrollX: Date
    // Shared crosshair time (same binding the tremor/glucose panels use) so the vertical
    // read-line sweeps straight down through the forecast band too. We draw only the LINE
    // here — no callout: the band is categorical (ON/OFF) and already color-coded, so a
    // text box would just restate the color. Quantitative readout stays on the panels that
    // have a number to report.
    @Binding var selectedTime: Date?
    @AppStorage("dayReview.expanded.forecast") private var expanded = true

    // ON = medication working (blue, calm). OFF = wearing-off (muted red — NOT orange,
    // which is dyskinesia on the chart above). Unknown = no watch data (gray). Labels
    // carry the meaning; color is a second cue, never the only one.
    // Zero-dose vocabulary reuses the same hues (typical = calm blue, above = muted red)
    // with different LABELS — ON/OFF is medication language and never appears there.
    private static let offColor = Color(red: 0.82, green: 0.28, blue: 0.30)
    private func color(_ phase: CorrelationEngine.DayForecast.Phase) -> Color {
        switch phase {
        case .on, .typical:  return Insight.brandBlue
        case .off, .above:   return Self.offColor
        case .unknown:       return .gray
        }
    }

    // An OBSERVED OFF is shaded by how severe the measured tremor actually was, so the band
    // agrees with the tremor line above instead of painting every wearing-off window the same
    // alarm-red (offThreshold sits at "Slight" on a 0–4 scale — a Mild OFF shouldn't look like
    // a Strong one). ON and projected stay flat: projected has no measurement to defer to.
    // Zero-dose `.above` shades the same way, from ITS classification line (the band's q75).
    private func fillOpacity(_ seg: CorrelationEngine.DayForecast.Segment) -> Double {
        guard seg.observed else { return 0.32 }                    // projected: faded, flat
        guard seg.phase == .off || seg.phase == .above,
              let t = seg.meanTremor else { return 0.9 }           // ON/typical / no reading
        let lo = seg.phase == .above
            ? (forecast.band?.q75 ?? CorrelationEngine.offThreshold)
            : CorrelationEngine.offThreshold
        let hi = 3.5                                               // … Strong
        let s = min(max((t - lo) / (hi - lo), 0), 1)
        return 0.45 + 0.45 * s
    }

    private var phaseAtNow: CorrelationEngine.DayForecast.Phase? {
        // Prefer the responsive live-edge read for the *current* state — the 30-min-binned segments
        // lag ~30min at the edge. Fall back to the segment containing `now` when there's too little
        // recent tremor to call it. See docs/design/tremor-averaging.md, Symptom 2.
        if let live = forecast.nowState { return live }
        return forecast.segments.first { forecast.now >= $0.start && forecast.now < $0.end }?.phase
    }

    // Rounded to the nearest 15 min: a personal dose-response estimate doesn't support
    // minute precision — "around 4:02 PM" overclaims; "around 4:00 PM" matches "around".
    private func time(_ date: Date) -> String {
        let secs = (date.timeIntervalSinceReferenceDate / 900).rounded() * 900
        return Date(timeIntervalSinceReferenceDate: secs)
            .formatted(date: .omitted, time: .shortened)
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

    // Severity name for a 0–4 tremor level (full words — the chart's axis abbreviates
    // "Mod" for space; a sentence shouldn't).
    private func levelName(_ t: Double) -> String {
        switch Int(t.rounded()) {
        case 0: return "None"
        case 1: return "Slight"
        case 2: return "Mild"
        case 3: return "Moderate"
        default: return "Strong"
        }
    }

    // Plain-language, present-tense, threshold-free — and forward-leaning: it leads with
    // the next transition (the forecast's whole point), not the current sliver. So a dose
    // that hasn't kicked in yet reads as "ON coming," not "you're OFF." Never a dosing
    // instruction — the onset time is the user's own latency, stated as expectation.
    private var headline: String {
        // Zero-dose day: the flat personal band, stated as expectation. Descriptive only —
        // no ON/OFF, no transition times (there are none to project), and deliberately NOT
        // conditioned on how today has gone so far (persistence validated NO-GO).
        if let band = forecast.band {
            let mid = levelName(band.median)
            let lo = levelName(band.q25), hi = levelName(band.q75)
            let range = lo == hi ? "usually staying around \(lo)"
                                 : "usually between \(lo) and \(hi)"
            return "No doses logged today — expect around your typical level: \(mid), \(range)."
        }
        switch phaseAtNow {
        case .on:
            // Inside the wear-off uncertainty band already (now past its lower bound) — the
            // "steady" claim is stale; acknowledge the transition instead of contradicting the band.
            if let range = forecast.nextOffRange, forecast.now >= range.lowerBound {
                return "You may be starting to wear off now."
            }
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
                // Band + headline as one tight pair (2pt) — the headline reads as the band's
                // caption. The 10pt outer spacing still separates this pair from the legend.
                VStack(alignment: .leading, spacing: 2) {
                    band

                    Text(headline)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                }

                legend

                Text("A pattern from your own data — not medical advice.")
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
                .foregroundStyle(color(seg.phase).opacity(fillOpacity(seg)))
            }
            RuleMark(x: .value("Now", forecast.now))
                .foregroundStyle(Color.primary.opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                // The pulsing dot is an annotation ON the rule, so it lives in the chart's
                // data coordinates and scrolls locked to the line (a chartOverlay lives in
                // screen space and would drift apart on scroll).
                .annotation(position: .overlay, alignment: .center) { NowPulse() }
            // The shared crosshair line, continued through the band so the eye reads one
            // moment straight down across tremor → forecast → glucose. Line only, matching
            // the other panels' selected-rule style; the band carries no callout.
            if let t = selectedTime {
                RuleMark(x: .value("Selected", t))
                    .foregroundStyle(.gray.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: 0...1)
        .chartXScale(domain: dayStart...dayEnd)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: 12 * 3600)
        .chartScrollPosition(x: $scrollX)
        .chartXSelection(value: $selectedTime)
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
            // Hourly ticks + 3-hour gridlines, but NO hour LABELS: the value labels reserve
            // ~18pt below the band for a compact glance strip that doesn't need them (the
            // headline states the timing, the tremor chart above carries the hour scale).
            // Dropping them reclaims that strip so the headline sits snug under the band.
            AxisMarks(values: .stride(by: .hour, count: 1)) { _ in
                AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.gray.opacity(0.4))
            }
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
            }
        }
        // Round just the colored plot region (not the axis labels below): the band's four
        // outer corners soften while the internal ON/OFF phase boundaries stay crisp.
        .chartPlotStyle { plot in
            plot.clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(height: 44)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            if forecast.band != nil {
                // Zero-dose vocabulary: measured level vs the user's own typical band.
                swatch(color: Insight.brandBlue, label: "Typical or better")
                swatch(color: Self.offColor, label: "Above typical")
            } else {
                swatch(color: Insight.brandBlue, label: "ON")
                swatch(color: Self.offColor, label: "OFF")
            }
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
        Seg(start: t(8),    end: t(9.3),  phase: .off,     observed: true,  meanTremor: 3.1), // strong
        Seg(start: t(9.3),  end: t(12.4), phase: .on,      observed: true),
        Seg(start: t(12.4), end: t(13.3), phase: .off,     observed: true,  meanTremor: 1.4), // mild
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
                      scrollX: .constant(t(9)), selectedTime: .constant(nil))
            .padding()
    }
}
#endif
