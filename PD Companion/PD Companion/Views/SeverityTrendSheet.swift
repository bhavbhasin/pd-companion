import SwiftUI
import SwiftData
import Charts

// MARK: - Tremor / Dyskinesia trend drill-down (per-tile "trends" surface, #2)
//
// Tap the Tremor or Dyskinesia glance tile → this sheet. One shared surface: both are the same
// 0-4 severity signal (lower = better), so they differ only in identity color, glyph, and title.
// Same three-section shape as HRVDetailSheet:
//   1. Today — the day's value + honest context. NOT a within-day curve (that's the Tremor panel
//      on the Review screen already); this sheet is the CROSS-DAY story.
//   2. Comparison — the day vs 7-day / 30-day / all-time baselines + a Week/Month/All chart.
// Section 3 (engine "pattern") is deferred — it arrives free from the registry.
//
// Ranges are Week/Month/All only (no Year): tremor/dyskinesia history is ~2.5 months, too short
// for the ≥6-month monthly-median trend HRV/Sleep use. When history passes ~6 months, Year can
// join (same call the HRV sheet makes).
//
// A range sets the chart's WINDOW WIDTH, not a cutoff date. The chart plots the whole record and
// you swipe back through it, as Health's do — "Week" is *a* week, not *the last* seven days. The
// history was always fully loaded (the loaders below fetch unbounded); the old `series(for:)`
// filtered all but the newest days away on the way to the chart. Because the cards above the
// chart stay pinned to the tapped day, the chart carries its own header naming the span on
// screen — otherwise it could quietly show June while the verdict above argued about today.

/// One (date, value) reading, already mapped onto the 0-4 severity axis. Sendable so the history
/// fetch can run off the main actor and hand results back.
struct DatedSample: Sendable { let date: Date; let value: Double }

struct SeverityTrendSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let glyph: String
    let accent: Color
    /// The tapped tile's day — section 1 mirrors exactly what the tile showed.
    let dayValue: Double?
    let dayCount: Int
    let dayDate: Date
    /// Fetches the metric's full history (off-main). Injected so tremor and dyskinesia can each
    /// map their own store type onto the shared severity axis.
    let load: () async -> [DatedSample]

    @State private var data: SeverityTrendData?
        // Week, not month (Bhav, Jul 28 2026): a month is a review horizon, a week is what he can
    // still remember and act on. Applies to every detail sheet so they open consistently.
    @State private var range: SeverityRange = .week
    @State private var loading = true
    /// The span the chart currently has on screen, reported back by it as you scroll. Drives the
    /// chart's header only — the cards above stay pinned to the tapped day.
    @State private var visibleRange: ClosedRange<Date>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    todaySection
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        // Composition before comparison: the headline number, then what it is
                        // made of, then how it sits against other days.
                        bandSection
                        compareSection
                    }
                }
                .padding(.horizontal, 12)
                // Top only. A ScrollView already insets its content by the bottom safe area
                // (~34pt for the home indicator), so a bottom pad here just stacked on top of
                // that — and it was enough to keep the sheet scrollable by itself.
                .padding(.top, 12)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            data = SeverityTrendData.build(samples: await load(), now: Date(), dayDate: dayDate)
            loading = false
        }
    }

    // MARK: Section 1 — Today

    private var isToday: Bool { Calendar.current.isDateInToday(dayDate) }
    private var dayLabel: String {
        isToday ? "today" : dayDate.formatted(.dateTime.month(.abbreviated).day())
    }
    private var noDataCaption: String {
        isToday ? "No readings today yet." : "No readings on \(dayLabel)."
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(isToday ? "Today" : dayDate.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.headline)
                Spacer()
                // Title left, qualifier right — the same shape as "Time at each level". Saying
                // the number is a mean and not a peak cost a full line under it, and this row
                // was empty. Suppressed when there is no number for it to qualify.
                if dayCount > 0 {
                    Text(isToday ? "average so far" : "daily average")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Same glyph as the glance tile so the sheet reads as "that tile, opened."
                // A step below the number, so the number still leads the row now that it is
                // smaller — at equal size the glyph competes with it.
                Image(systemName: glyph)
                    .font(.title2)
                    .foregroundStyle(accent)
                // `.title`, not `.largeTitle`: the number was set at display scale in a card that
                // holds nothing else, and the row's height is what pushes the chart off screen.
                Text(dayValue.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(accent)
                // Severity word sits where HRV's "ms" unit sits — the label the tile carried.
                if let v = dayValue {
                    Text(SeverityScale.name(v)).font(.title3).foregroundStyle(.secondary)
                }
            }
            // An empty record keeps its own line: that sentence is the card's content, not a
            // qualifier on a number that isn't there.
            if dayCount == 0 {
                Text(noDataCaption)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Section 2 — Time at each level
    //
    // What the Today average is MADE OF. A single mean hides whether a 1.1 day was steady all
    // day or calm with a rough hour in it, and that difference is the whole of how the day felt.
    // Facts, no verdict: five rows, fixed scale order, no threshold picked and nothing sorted.

    @ViewBuilder
    private var bandSection: some View {
        if let data, data.hasBandData {
            let total = max(1, data.bandMinutes.values.reduce(0, +))
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Time at each level").font(.headline)
                    Spacer()
                    // Both qualifiers ride here rather than as a footer line under the rows: the
                    // footer cost a full line plus its spacing, and this header row was half empty.
                    // "so far" is today-only — it says the day is still running, and on a past day
                    // the card above already names the date. "includes sleep" is the shortened
                    // footer; the reason it gave (tremor is near zero asleep) is dropped, which
                    // the None row's size makes evident once the reader knows sleep is in there.
                    Text(isToday ? "so far · includes sleep" : "includes sleep")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 6) {
                    ForEach(data.bandRows, id: \.band) { row in
                        bandRow(row.band, minutes: row.minutes, total: total)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func bandRow(_ band: SeverityBand, minutes: Int, total: Int) -> some View {
        HStack(spacing: 10) {
            // Labels wear text tokens, never the fill color — the bar beside them carries the
            // severity, so the row stays readable if color is lost.
            Text(band.name)
                .font(.subheadline)
                .foregroundStyle(minutes > 0 ? Color.primary : Color.secondary)
                .frame(width: 74, alignment: .leading)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent.opacity(band.fillOpacity))
                    .frame(width: max(minutes > 0 ? 3 : 0,
                                      geo.size.width * CGFloat(minutes) / CGFloat(total)))
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)

            Text(minutes > 0 ? Self.duration(minutes) : "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(minutes > 0 ? Color.primary : Color.secondary)
                .frame(width: 62, alignment: .trailing)
        }
    }

    /// Minutes as h/m, matching how the sleep card writes durations.
    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: Section 3 — Comparison

    @ViewBuilder
    private var compareSection: some View {
        if let data {
            VStack(alignment: .leading, spacing: 14) {
                // Noun phrase, like its siblings ("Today", "Time at each level") — the clause
                // "How it compares" was the odd one out, and the card explains itself.
                Text("Comparison").font(.headline)

                // Baselines row — "This day" in the metric's accent to anchor the eye on the
                // subject of the comparison; the reference windows stay neutral.
                HStack(spacing: 0) {
                    baselineStat("This day", dayValue, accent: true)
                    baselineStat("7-day", data.avg7)
                    baselineStat("30-day", data.avg30)
                    baselineStat("All-time", data.avgAll)
                }

                if let c = data.comparison(dayValue: dayValue) {
                    Label {
                        Text(c.text)
                    } icon: {
                        Image(systemName: c.valence.icon)
                    }
                    .font(.subheadline)
                    .foregroundStyle(c.valence.color)
                }

                Divider()

                Picker("Range", selection: $range) {
                    ForEach(SeverityRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                trendChart(data)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func baselineStat(_ label: String, _ value: Double?, accent isAccent: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value.map { String(format: "%.1f", $0) } ?? "—")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(isAccent ? accent : Color.primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func trendChart(_ data: SeverityTrendData) -> some View {
        if data.daily.count < 2 {
            Text("Not enough history yet.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                TrendWindowHeader(
                    visibleRange: visibleRange,
                    points: data.daily,
                    accent: accent,
                    valueText: { String(format: "%.1f", $0) },
                    label: "daily average"
                )
                ScrubbableTrendChart(
                    points: data.daily,
                    accent: accent,
                    yAxisLabel: "",
                    valueText: { String(format: "%.1f", $0) },
                    showPoints: range == .week,
                    visibleDomain: range.visibleDomain(
                        fullSpan: ScrubbableTrendChart.fullSpan(of: data.daily)),
                    onVisibleRange: { visibleRange = $0 }
                )
            }
        }
    }

}

// MARK: - Range

enum SeverityRange: String, CaseIterable, Identifiable {
    case week, month, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .week:  "Week"
        case .month: "Month"
        case .all:   "All"
        }
    }

    /// How much of the record is on screen at once. The chart always plots EVERY day and this
    /// picks the width of the window you look through, so "Week" now means *a* week — the one you
    /// have scrolled to — rather than *the last* seven days.
    ///
    /// "All" is the whole record by definition, so it takes `fullSpan` and simply has nothing left
    /// to scroll to. It is given a width rather than opting out of windowing, so every range keeps
    /// the chart on the same code path and switching tabs cannot reset it.
    func visibleDomain(fullSpan: TimeInterval) -> TimeInterval {
        switch self {
        case .week:  7 * 86_400
        case .month: 30 * 86_400
        case .all:   fullSpan
        }
    }
}

// MARK: - Severity scale (shared with the glance tiles' 0-4 naming)

enum SeverityScale {
    static func name(_ v: Double) -> String { SeverityBand.of(v).name }
}

/// The five named steps of the 0-4 severity axis. Declared HIGHEST first — that is both the
/// display order of the breakdown card and the order the scale reads on the chart's y-axis, so
/// there is no sort step anywhere and no way for the two to disagree.
///
/// This owns the cut points. `SeverityScale.name` reads them here rather than repeating the
/// literals, so the word under the Today number and the rows of the breakdown can never drift.
enum SeverityBand: String, CaseIterable, Identifiable {
    case strong, moderate, mild, slight, none

    var id: String { rawValue }

    /// Inclusive lower bound; each band runs up to the next one's bound.
    var lowerBound: Double {
        switch self {
        case .strong:   3.5
        case .moderate: 2.5
        case .mild:     1.5
        case .slight:   0.5
        case .none:     0
        }
    }

    var name: String {
        switch self {
        case .strong:   "Strong"
        case .moderate: "Moderate"
        case .mild:     "Mild"
        case .slight:   "Slight"
        case .none:     "None"
        }
    }

    static func of(_ v: Double) -> SeverityBand {
        // allCases is highest-first, so the first match is the right band.
        allCases.first { v >= $0.lowerBound } ?? .none
    }

    /// Sequential ramp: ONE hue (the metric's identity color), faint → full as severity rises.
    /// Not five categorical hues — these bands are ordered magnitude, and a rainbow would imply
    /// they are unrelated categories. Every row is directly labeled, so nothing rests on color.
    var fillOpacity: Double {
        switch self {
        case .strong:   1.0
        case .moderate: 0.8
        case .mild:     0.6
        case .slight:   0.4
        case .none:     0.22
        }
    }
}

// MARK: - Valence (inverted vs HRV: for tremor/dyskinesia, LOWER is better)

/// `text` carries the 10th–90th percentile band the verdict was reached against, parenthesised
/// inline — "typical" is otherwise a judgement the reader has no way to check.
struct SeverityComparison { let text: String; let valence: SeverityValence }

enum SeverityValence {
    case better, typical, worse
    // Green = good (lower severity), amber = above-usual (a soft caution, not alarm), neutral =
    // typical. Same valence language as HRV/Insights — but the DIRECTION flips: here higher = worse.
    var color: Color {
        switch self {
        case .better:  .green
        case .typical: Color(.secondaryLabel)
        case .worse:   .orange
        }
    }
    var icon: String {
        switch self {
        case .better:  "arrow.down.circle.fill"
        case .typical: "checkmark.circle.fill"
        case .worse:   "arrow.up.circle.fill"
        }
    }
}

// MARK: - Computation
//
// Descriptive stats over the fetched history. Daily chart = one mean per calendar day (mirrors
// the glance tile's daily average). Baselines = plain means of raw readings since the cutoff.
// No longTermTrend/monthly-median path — the history is too short for it (see the range note).

struct SeverityTrendData {
    let avg7: Double?
    let avg30: Double?
    let avgAll: Double?
    let p10: Double?                 // 10th pct of recent daily averages
    let p90: Double?                 // 90th pct of recent daily averages
    /// One mean per day, ascending — the WHOLE record. The chart plots all of it and scrolls;
    /// nothing filters it down to the range picker any more.
    let daily: [TrendPoint]
    /// Minutes at each band for the day on screen; a band absent from the map had none.
    let bandMinutes: [SeverityBand: Int]

    /// Every band, highest first, with its minutes — always all five, so a day with no Strong
    /// time reads "—" rather than dropping a row and reflowing the card.
    var bandRows: [(band: SeverityBand, minutes: Int)] {
        SeverityBand.allCases.map { ($0, bandMinutes[$0] ?? 0) }
    }

    var hasBandData: Bool { bandMinutes.values.contains { $0 > 0 } }

    static func build(samples: [DatedSample], now: Date, dayDate: Date) -> SeverityTrendData {
        let cal = Calendar.current

        // One mean per calendar day — the unit for the chart + baselines-of-record.
        let byDay = Dictionary(grouping: samples) { cal.startOfDay(for: $0.date) }
        var daily: [TrendPoint] = []
        for (day, s) in byDay {
            let m = s.map(\.value).reduce(0, +) / Double(s.count)
            daily.append(TrendPoint(date: day, value: m))
        }
        daily.sort { $0.date < $1.date }

        func mean(sinceDaysAgo days: Int) -> Double? {
            guard let cutoff = cal.date(byAdding: .day, value: -days, to: now) else { return nil }
            let vals = samples.filter { $0.date >= cutoff }.map(\.value)
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }

        let allVals = samples.map(\.value)
        let avgAll = allVals.isEmpty ? nil : allVals.reduce(0, +) / Double(allVals.count)

        // "Usual range" = 10th/90th PERCENTILES of the last-30-day DAILY averages (not mean±SD:
        // severity is right-skewed — mostly-calm days with occasional rough ones). The 10/90 cut
        // flags roughly the top/bottom tenth of recent days as notably high/low.
        let cutoff30 = cal.date(byAdding: .day, value: -30, to: now)
        var recentDaily: [Double] = []
        for p in daily where (cutoff30.map { p.date >= $0 } ?? false) {
            recentDaily.append(p.value)
        }
        recentDaily.sort()
        let p10 = recentDaily.count >= 8 ? Self.percentile(recentDaily, 0.10) : nil
        let p90 = recentDaily.count >= 8 ? Self.percentile(recentDaily, 0.90) : nil

        // Minutes per band for the day on screen. Readings land ~1/min (measured median gap
        // 1 min over the last 5 days), so a reading counts as a minute — stated in the caption
        // rather than implied. Sleep is INCLUDED: the record spans ~22.8 h/day and tremor is
        // near zero asleep, so "None" carries several hours of sleep. Deliberate (Bhav, Jul 30) —
        // the chart above makes the sleep stretch obvious, and censoring it would add a sleep
        // dependency to a card whose job is just to show what the average is made of.
        let dayStart = cal.startOfDay(for: dayDate)
        let todays = samples.filter { cal.isDate($0.date, inSameDayAs: dayStart) }
        var minutes: [SeverityBand: Int] = [:]
        for s in todays { minutes[SeverityBand.of(s.value), default: 0] += 1 }

        return SeverityTrendData(avg7: mean(sinceDaysAgo: 7), avg30: mean(sinceDaysAgo: 30),
                                 avgAll: avgAll, p10: p10, p90: p90, daily: daily,
                                 bandMinutes: minutes)
    }

    /// Linear-interpolated percentile over an already-sorted array.
    private static func percentile(_ sorted: [Double], _ q: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        if sorted.count == 1 { return sorted[0] }
        let pos = q * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }

    /// The day vs the 10th/90th percentiles of recent daily averages. Direction is INVERTED vs
    /// HRV: lower severity = good = green; higher = amber caution; between = typical.
    func comparison(dayValue: Double?) -> SeverityComparison? {
        guard let day = dayValue, let lo = p10, let hi = p90 else { return nil }
        let f: (Double) -> String = { String(format: "%.1f", $0) }

        // A verdict the displayed numbers cannot show is noise. When the day and both band edges
        // round to the same string at card precision there is no difference to report — which is
        // the case for a record that sits at zero. Measured on Bhav's dyskinesia (0.00 on 84 of 84
        // days) the card claimed "Lower than your usual - a steadier day", in green, against a
        // stated range of 0.0 - 0.0. Derived from the display format, so there's no magic constant
        // and no separate "is this metric interesting" gate to keep in sync.
        guard !(f(day) == f(lo) && f(lo) == f(hi)) else { return nil }

        // The band rides INSIDE the verdict sentence, not on a second line — the verdict and the
        // numbers behind it are one statement, and a caption under it crowded the section. Same
        // %.1f as the headline and the baselines row, so the reader is comparing like with like.
        let usual = "(\(f(lo)) - \(f(hi)))"

        // STRICT. Sitting exactly AT the 10th/90th percentile is the edge of usual, not evidence
        // of being outside it — and with a zero-width band `day <= lo` and `day >= hi` are both
        // true, so the first branch won by ordering alone.
        if day < lo {
            return SeverityComparison(text: "Lower than your usual lately \(usual) - a steadier day.",
                                      valence: .better)
        }
        if day > hi {
            return SeverityComparison(text: "Higher than your usual lately \(usual).",
                                      valence: .worse)
        }
        return SeverityComparison(text: "About typical for you lately \(usual).",
                                  valence: .typical)
    }

}

// MARK: - History loaders (map each store type onto the shared severity axis, off-main)

extension SeverityTrendSheet {
    /// Full tremor history as (day, tremorScore) samples. Runs on a detached context so the
    /// ~months-long fetch never blocks the sheet's open animation.
    static func tremorHistory() async -> [DatedSample] {
        await Task.detached {
            let ctx = ModelContext(AppContainer.shared)
            let rows = (try? ctx.fetch(FetchDescriptor<TremorReading>())) ?? []
            return rows.map { DatedSample(date: $0.timestamp, value: $0.tremorScore) }
        }.value
    }

    /// Full dyskinesia history, mapped through the SAME floor+rescale the chart/tile use so the
    /// trend agrees with the glance tile's daily average.
    static func dyskinesiaHistory() async -> [DatedSample] {
        await Task.detached {
            let ctx = ModelContext(AppContainer.shared)
            let rows = (try? ctx.fetch(FetchDescriptor<DyskinesiaReading>())) ?? []
            return rows.map { DatedSample(date: $0.startDate, value: DyskinesiaDisplay.intensity($0.percentLikely)) }
        }.value
    }
}
