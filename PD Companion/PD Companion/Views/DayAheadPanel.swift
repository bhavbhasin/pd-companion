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

    // EXACTLY THREE hues, one meaning each — direction, never vocabulary:
    //   blue  = calm      (ON inside a dose envelope; usual-or-better outside one)
    //   red   = elevated  (OFF inside; worse-than-usual outside) — muted, NOT orange, which
    //                      is dyskinesia on the chart above
    //   gray  = no reading
    // Which QUESTION was asked is carried by the label and the headline, never by a hue.
    //
    // `.below` deliberately shares plain blue (Jul 24 2026). It briefly had its own deeper
    // shade, on the theory that it was a materially stronger state than ON — below q25 vs
    // below the 1.0 OFF line. Measured on Bhav's own 78 days that premise is false: his q25
    // is 1.08, essentially the same line as offThreshold, so "better than usual" really is
    // "ON without the pill" (his original framing) and a second blue bought nothing but a
    // question from a first-time reader. The state survives in the headline, which is where
    // its value actually is.
    private static let offColor = Color(red: 0.82, green: 0.28, blue: 0.30)
    private func color(_ phase: CorrelationEngine.DayForecast.Phase) -> Color {
        switch phase {
        case .on, .typical, .below:  return Insight.brandBlue
        case .off, .above:           return Self.offColor
        case .unknown:               return .gray
        }
    }

    // Flat fills. Severity shading on an observed OFF was removed (Jul 24 2026): the tremor
    // chart sits directly above this bar and already reports severity precisely, so the shade
    // duplicated it while quietly making "darker" mean two things — magnitude in red, category
    // in blue. Shade now means exactly one thing (the `.below` category); opacity means exactly
    // one thing (projected vs measured).
    private func fillOpacity(_ seg: CorrelationEngine.DayForecast.Segment) -> Double {
        seg.observed ? 0.9 : 0.32
    }

    private var phaseAtNow: CorrelationEngine.DayForecast.Phase? {
        // The current-state read is simply the segment containing `now` — the honest 30-min
        // measured reconstruction. The old responsive live-edge override was removed (Jul 24 2026):
        // on thin/irregular data it painted a false ON at the edge. See docs/design/tremor-averaging.md.
        forecast.segments.first { forecast.now >= $0.start && forecast.now < $0.end }?.phase
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
    // A day can now carry BOTH vocabularies (dosed morning, cleared evening), so which
    // sentence to write is decided by the phase at `now`, not by the day.
    private var isDoseVocabularyNow: Bool {
        phaseAtNow == .on || phaseAtNow == .off
    }

    // End of the last stretch a dose could explain — the "your dose is past its window"
    // anchor. Read off the timeline itself so the sentence and the bar can't disagree.
    private var doseVocabularyEnd: Date? {
        forecast.segments.last { $0.phase == .on || $0.phase == .off }?.end
    }

    /// The band's spread in severity words. The 5-name scale is coarse: median + both
    /// quartiles can round to the same word, which made the range read as one-sided
    /// ("Mild, between Slight and Mild"). State a range ONLY across names that differ FROM
    /// the median, so the copy never contradicts itself or over-claims precision.
    /// "generally", not "usually" — "your usual level: Mild, usually Slight to Mild" says
    /// usual twice in one breath now that "usual" is the panel's anchor word.
    private func spreadText(_ band: CorrelationEngine.SubstrateBand) -> String {
        let mid = levelName(band.median)
        let lo = levelName(band.q25)
        let hi = levelName(band.q75)
        if lo == mid && hi == mid { return "generally staying around \(mid)" }
        if lo == mid { return "generally \(mid) to \(hi)" }
        if hi == mid { return "generally \(lo) to \(mid)" }
        return "generally between \(lo) and \(hi)"
    }

    /// SUBSTRATE headline: a zero-dose day, OR a dosed day whose drug has cleared. The
    /// opening clause states WHY substrate vocabulary applies — the old copy said "No doses
    /// logged today" unconditionally, a lie on a day like Jul 24 (one 5:23 AM dose).
    private func substrateHeadline(_ band: CorrelationEngine.SubstrateBand) -> String {
        let mid = levelName(band.median)
        let cleared = (doseVocabularyEnd.map { $0 <= forecast.now }) ?? false
        let lead = cleared ? "Your last dose is past its expected window" : "No doses logged today"
        // Where today sits relative to the band is a MEASUREMENT, so it leads when decisive
        // in either direction — and a below-band stretch is the one the weaning story turns
        // on, so it never gets buried behind the generic expectation.
        switch phaseAtNow {
        case .below:
            return "\(lead) - and you're running better than usual right now (your usual is \(mid))."
        case .above:
            return "\(lead) - you're running worse than usual right now (your usual is \(mid))."
        default:
            return "\(lead) - expect around your usual level: \(mid), \(spreadText(band))."
        }
    }

    private var headline: String {
        // Substrate vocabulary wins whenever `now` isn't inside a dose's influence envelope.
        // Descriptive only: no ON/OFF, no transition times, and deliberately NOT conditioned
        // on how today has gone so far (persistence validated NO-GO).
        if let band = forecast.band, !isDoseVocabularyNow {
            return substrateHeadline(band)
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

    // Derived from the phases the day ACTUALLY contains, not from a day-level mode flag —
    // a mixed day (dosed morning, cleared evening) legitimately carries both vocabularies.
    // Blue and red each cover two phases, so when both vocabularies are present the swatch
    // slashes them rather than showing two identical-looking colour chips.
    private var present: Set<CorrelationEngine.DayForecast.Phase> {
        Set(forecast.segments.map(\.phase))
    }

    /// Joined label for one colour that covers several phases ("ON / usual").
    private func sharedLabel(_ pairs: [(CorrelationEngine.DayForecast.Phase, String)]) -> String {
        let shown = present
        var parts: [String] = []
        for (phase, name) in pairs where shown.contains(phase) { parts.append(name) }
        return parts.joined(separator: " / ")
    }

    // "usual", never "typical": one anchor word across every label, so a reader is never left
    // wondering whether usual and typical mean two different things. And the substrate labels
    // state DIRECTION ("better than usual" / "worse than usual") rather than position ("below"
    // / "above") — on a symptom scale lower is better, so "below" reads as a deficit to anyone
    // not already thinking in tremor units. (Bhav, Jul 24.)
    private var legend: some View {
        let shown = present
        // `.below` shares plain blue, so it folds into that swatch's wording ("usual or
        // better") rather than claiming a second, identical-looking chip.
        var calmParts: [String] = []
        if shown.contains(.on) { calmParts.append("ON") }
        if shown.contains(.typical) || shown.contains(.below) {
            calmParts.append(shown.contains(.below) ? "usual or better" : "usual")
        }
        let calm = calmParts.joined(separator: " / ")
        let hot = sharedLabel([(.off, "OFF"), (.above, "worse than usual")])
        return HStack(spacing: 14) {
            if !calm.isEmpty { swatch(color: Insight.brandBlue, label: calm) }
            if !hot.isEmpty { swatch(color: Self.offColor, label: hot) }
            if shown.contains(.unknown) { swatch(color: .gray, label: "No watch data") }
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
#Preview("Zero-dose day — flat personal band") {
    let day = Calendar.current.startOfDay(for: .now)
    func t(_ h: Double) -> Date { day.addingTimeInterval(h * 3600) }
    let now = t(14.5)
    typealias Seg = CorrelationEngine.DayForecast.Segment
    // Elapsed day classified against the band's q75: a typical morning, one stretch that
    // ran above the band (shaded by severity), a not-worn gap — then the flat projection.
    let segments: [Seg] = [
        Seg(start: t(7),    end: t(10),   phase: .typical, observed: true),
        Seg(start: t(10),   end: t(11.5), phase: .above,   observed: true, meanTremor: 2.7),
        Seg(start: t(11.5), end: t(12.5), phase: .unknown, observed: true),
        Seg(start: t(12.5), end: now,     phase: .typical, observed: true),
        Seg(start: now,     end: t(24),   phase: .typical, observed: false),
    ]
    let forecast = CorrelationEngine.DayForecast(
        segments: segments, now: now,
        nextOffStart: nil, nextOffRange: nil,       // no dose vocabulary on a zero-dose day
        confidence: .moderate,
        band: .init(median: 1.8, q25: 1.4, q75: 2.2, nDays: 22))
    return ScrollView {
        DayAheadPanel(forecast: forecast, dayStart: day, dayEnd: t(24),
                      scrollX: .constant(t(9)), selectedTime: .constant(nil))
            .padding()
    }
}

#Preview("Mixed day — one early dose, then substrate") {
    // The Jul 24 2026 shape (Phase 0.5): asleep through the only dose's window, awake into a
    // measured OFF at the envelope's end, then substrate vocabulary for the rest of the day —
    // including one dose-free stretch that ran BELOW the band (the weaning signal).
    let day = Calendar.current.startOfDay(for: .now)
    func t(_ h: Double) -> Date { day.addingTimeInterval(h * 3600) }
    let now = t(18.5)
    typealias Seg = CorrelationEngine.DayForecast.Segment
    let segments: [Seg] = [
        Seg(start: t(0),    end: t(5.4),  phase: .typical, observed: true),   // awake + asleep, calm
        Seg(start: t(5.4),  end: t(8.75), phase: .on,      observed: true),   // inside the 5:23 AM envelope
        Seg(start: t(8.75), end: t(9.0),  phase: .off,     observed: true, meanTremor: 2.0), // woke up wearing off
        Seg(start: t(9.0),  end: t(9.5),  phase: .unknown, observed: true),   // watch gap
        Seg(start: t(9.5),  end: t(14),   phase: .above,   observed: true, meanTremor: 1.8),
        Seg(start: t(14),   end: t(16),   phase: .below,   observed: true, meanTremor: 0.4), // unmedicated calm
        Seg(start: t(16),   end: now,     phase: .above,   observed: true, meanTremor: 1.7),
        Seg(start: now,     end: t(24),   phase: .typical, observed: false),
    ]
    let forecast = CorrelationEngine.DayForecast(
        segments: segments, now: now,
        nextOffStart: nil, nextOffRange: nil,
        confidence: .moderate,
        band: .init(median: 1.05, q25: 0.5, q75: 1.6, nDays: 68))
    return ScrollView {
        DayAheadPanel(forecast: forecast, dayStart: day, dayEnd: t(24),
                      scrollX: .constant(t(6)), selectedTime: .constant(nil))
            .padding()
    }
}

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
