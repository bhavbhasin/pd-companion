import SwiftUI
import Charts

// MARK: - Sleep trend drill-down (per-tile "trends" surface, #2)
//
// Tap the Sleep glance tile → this sheet. Three parts:
//   1. Last night — the Kampa sleep score (0–100, no verbal grade) broken into its three
//      components exactly like Apple's card, minus the "Low/High" verdict. Each component shows
//      its raw fact next to its points, so the number always shows its work.
//   2. Comparison — last night's score vs your 7-day / 30-day / all-time typical.
//   3. Trend — the nightly score over Week/Month/Year/All, scrubbable to read any night.
//
// The score's weights mirror Apple's (Duration 50 / Bedtime 30 / Interruptions 20); the point
// curves are ours (Apple doesn't publish them) — see `SleepScore`. Sleep clears the trend
// primitive's history bar the same way HRV does (Watch sleep spans months/years).
//
// The chart is a scrollable window over the whole record on the same two axes as HRV's —
// granularity picks the series, the range picks the window width. See that sheet's header.

struct SleepDetailSheet: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    /// The tapped tile's night. Its score comes from the loaded history, not a separate fetch.
    let dayDate: Date

    @State private var data: SleepTrendData?
        // Week, not month (Bhav, Jul 28 2026): a month is a review horizon, a week is what he can
    // still remember and act on. Applies to every detail sheet so they open consistently.
    @State private var range: HRVRange = .week
    @State private var loading = true
    /// The span the chart currently has on screen, reported back by it as you scroll. Drives the
    /// chart's header only — the card above stays pinned to the tapped night.
    @State private var visibleRange: ClosedRange<Date>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    lastNightSection
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        compareSection
                    }
                }
                .padding(.horizontal, 12)
                // Top only — a ScrollView already insets its content by the bottom safe area.
                .padding(.top, 12)
            }
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            // Shares the Review screen's cached load rather than re-running the 10-year query.
            await healthKit.loadSleepHistory()
            data = SleepTrendData.build(history: healthKit.sleepHistory, now: Date())
            loading = false
        }
    }

    // MARK: Section 1 — Last night

    private var isToday: Bool { Calendar.current.isDateInToday(dayDate) }

    /// The selected night's score, read from the history the trend is built on. It used to score
    /// `daySleep` (the day-window fetch) separately against a baseline that included this very
    /// night — two sources and a contaminated baseline, which is how the card and the scrubber
    /// showed different numbers for the same night. nil until the history load finishes.
    private var dayScore: SleepScore? { data?.score(on: dayDate) }

    private var lastNightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isToday ? "Last night" : dayDate.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.headline)

            if loading {
                // Section 1 now waits on the same history the trend uses — that shared load is
                // what guarantees the two agree.
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if let score = dayScore {
                // Same sizing as the other detail sheets' headline number: `.title` with the
                // glyph a step below it, so the four surfaces read as one family.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "bed.double.fill")
                        .font(.title2)
                        .foregroundStyle(Color.sleepAccent)
                    Text("\(score.total)")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Color.sleepAccent)
                    Text("/ 100").font(.title3).foregroundStyle(.secondary)
                }

                // Apple's card order: Duration, Bedtime, Interruptions.
                VStack(spacing: 0) {
                    componentRow(score.duration, name: "Duration")
                    Divider()
                    if let bedtime = score.bedtime {
                        componentRow(bedtime, name: "Bedtime")
                    } else {
                        bedtimePendingRow
                    }
                    Divider()
                    componentRow(score.interruptions, name: "Interruptions")
                }
            } else {
                Text(isToday ? "No sleep recorded last night." : "No sleep recorded that night.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func componentRow(_ c: SleepScore.Component, name: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.medium))
                Text(c.fact).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(c.points)/\(c.max)")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 10)
    }

    // Bedtime needs a personal baseline (~2 weeks). Until then it's honestly absent, not zeroed —
    // the score renormalizes over the two components we can measure (see `SleepScore`).
    private var bedtimePendingRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bedtime").font(.subheadline.weight(.medium))
                Text("Needs ~2 weeks of nights to learn your usual time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("—").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    // MARK: Section 2 — Comparison

    @ViewBuilder
    private var compareSection: some View {
        if let data {
            VStack(alignment: .leading, spacing: 14) {
                // Noun phrase, matching the other three detail sheets.
                Text("Comparison").font(.headline)

                HStack(spacing: 0) {
                    baselineStat("This night", dayScore.map { Double($0.total) }, accent: true)
                    baselineStat("7-day", data.avg7)
                    baselineStat("30-day", data.avg30)
                    baselineStat("All-time", data.avgAll)
                }

                if let c = data.comparison(dayScore: dayScore?.total) {
                    Text(c.text).font(.subheadline)
                        .foregroundStyle(c.isAboveUsual ? Color.green : Color.secondary)
                }

                Divider()

                Picker("Range", selection: $range) {
                    ForEach(HRVRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                trendChart(data)

                if let caption = data.trendCaption(for: range) {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func baselineStat(_ label: String, _ value: Double?, accent: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(accent ? Color.sleepAccent : Color.primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func trendChart(_ data: SleepTrendData) -> some View {
        // Series follows granularity, window follows the range — see the note on HRV's chart.
        let series = data.series(monthly: range.isMonthly)
        if series.count < 2 {
            Text("Not enough history yet for this range.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                TrendWindowHeader(
                    visibleRange: visibleRange,
                    points: series,
                    accent: .sleepAccent,
                    valueText: { "\(Int($0.rounded()))" },
                    label: range.isMonthly ? "monthly median" : "nightly score",
                    monthlyDates: range.isMonthly
                )
                ScrubbableTrendChart(
                    points: series,
                    // No axis-unit label. It shares the band above the plot with the scrub
                    // callout, and "Score" is long enough that a wide callout ("78 May 2024")
                    // truncated it to a floating "S". Nothing is lost: the header above states
                    // "nightly score" / "monthly median", and the axis runs 0-100 on a card
                    // titled Sleep. HRV keeps "ms" because two characters always survive.
                    accent: .indigo,
                    yAxisLabel: "",
                    valueText: { "\(Int($0.rounded()))" },
                    showPoints: range == .week,
                    monthlyDates: range.isMonthly,
                    visibleDomain: range.visibleDomain(
                        fullSpan: ScrubbableTrendChart.fullSpan(of: series)),
                    onVisibleRange: { visibleRange = $0 }
                )
            }
        }
    }
}

// MARK: - Computation
//
// Scores every night with one baseline bedtime (median over history — see `SleepScore` for why
// v1 uses a single baseline rather than a causal trailing window), then serves the same
// baselines/comparison/trend the HRV sheet does. Short ranges plot nightly scores; year/all plot
// the engine's monthly medians of the score (robust to night-to-night swing).

struct SleepTrendData {
    let baselineBedtime: Double?          // minutes since 6 PM, or nil (cold-start)
    let avg7: Double?
    let avg30: Double?
    let avgAll: Double?
    private let p10: Double?
    private let p90: Double?
    private let daily: [TrendPoint]        // one score per night, ascending
    private let trend: CorrelationEngine.TrendResult?
    private let scored: [(date: Date, score: SleepScore)]   // the same nights, full component breakdown

    static func build(history: [NightSleep], now: Date) -> SleepTrendData {
        let cal = Calendar.current

        // One scoring pass, shared with the glance tile (see `SleepScore.scoreHistory`): a night
        // is judged only by the nights before it, so the trend line matches what the score would
        // have read on that morning, and no surface can disagree with another about a night.
        let scored = SleepScore.scoreHistory(history)
        let daily: [TrendPoint] = scored.map { TrendPoint(date: $0.date, value: Double($0.score.total)) }

        // Display baseline: the nights before the most recent one, on the same causal rule.
        let baseline = SleepScore.baselineBedtimeMinutes(history.dropLast())

        func mean(sinceDaysAgo days: Int) -> Double? {
            guard let cutoff = cal.date(byAdding: .day, value: -days, to: now) else { return nil }
            let vals = daily.filter { $0.date >= cutoff }.map(\.value)
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }

        let allVals = daily.map(\.value)
        let avgAll = allVals.isEmpty ? nil : allVals.reduce(0, +) / Double(allVals.count)

        // Usual range = 10th/90th percentiles of the last 30 nightly scores (assumption-free,
        // same choice as HRV). Needs ≥8 recent nights to be meaningful.
        let cutoff30 = cal.date(byAdding: .day, value: -30, to: now)
        var recent = daily.filter { p in cutoff30.map { p.date >= $0 } ?? false }.map(\.value)
        recent.sort()
        let p10 = recent.count >= 8 ? Self.percentile(recent, 0.10) : nil
        let p90 = recent.count >= 8 ? Self.percentile(recent, 0.90) : nil

        let dated = daily.map { (date: $0.date, value: $0.value) }
        let trend = CorrelationEngine.longTermTrend(samples: dated, clip: (lo: 0, hi: 100))

        return SleepTrendData(baselineBedtime: baseline, avg7: mean(sinceDaysAgo: 7),
                              avg30: mean(sinceDaysAgo: 30), avgAll: avgAll,
                              p10: p10, p90: p90, daily: daily, trend: trend,
                              scored: scored)
    }

    /// The score for one night, as the trend line has it. Section 1 and the scrubber therefore
    /// read the same number for the same night by construction.
    func score(on date: Date) -> SleepScore? {
        let cal = Calendar.current
        return scored.first { cal.isDate($0.date, inSameDayAs: date) }?.score
    }

    private static func percentile(_ sorted: [Double], _ q: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        if sorted.count == 1 { return sorted[0] }
        let pos = q * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }

    struct SleepComparison { let text: String; let isAboveUsual: Bool }

    /// Compare to the usual range. Color is ASYMMETRIC by design: a better-than-usual night is
    /// highlighted (green), but a low night stays neutral — for a PD user a bad night is often
    /// the disease, not a habit, so we reward good sleep without stamping bad sleep in alarm color.
    func comparison(dayScore: Int?) -> SleepComparison? {
        guard let day = dayScore.map(Double.init), let lo = p10, let hi = p90 else { return nil }
        if day >= hi { return SleepComparison(text: "Higher than your usual lately.", isAboveUsual: true) }
        if day <= lo { return SleepComparison(text: "Lower than your usual lately.", isAboveUsual: false) }
        return SleepComparison(text: "About typical for you lately.", isAboveUsual: false)
    }

    /// The chart series at one granularity — the WHOLE record either way. Short windows read the
    /// nightly scores; year/all read the engine's monthly medians. Nothing is trimmed to a
    /// recency cutoff: the range picks the width of the chart's window and you scroll for the rest.
    func series(monthly: Bool) -> [TrendPoint] {
        monthly
            ? (trend?.months ?? []).map { TrendPoint(date: $0.month, value: $0.median) }
            : daily
    }

    /// Descriptive drift of the score — only when statistically real, and "All" ONLY: the slope
    /// is fitted to the whole record, so on the Year tab it described a line off screen. See the
    /// note on `HRVTrendData.trendCaption`.
    func trendCaption(for range: HRVRange) -> String? {
        guard range == .all, let t = trend, t.pValue < 0.05 else { return nil }
        let years = max(1, Int(t.spanYears.rounded()))
        let pct = Int(abs(t.pctChange).rounded())
        if t.slopePerYear < 0 { return "Trending down about \(pct)% over the last \(years) year\(years == 1 ? "" : "s")." }
        if t.slopePerYear > 0 { return "Trending up about \(pct)% over the last \(years) year\(years == 1 ? "" : "s")." }
        return "Stable over the last \(years) year\(years == 1 ? "" : "s")."
    }
}
