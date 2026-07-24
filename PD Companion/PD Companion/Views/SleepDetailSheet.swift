import SwiftUI
import Charts

// MARK: - Sleep trend drill-down (per-tile "trends" surface, #2)
//
// Tap the Sleep glance tile → this sheet. Three parts:
//   1. Last night — the Kampa sleep score (0–100, no verbal grade) broken into its three
//      components exactly like Apple's card, minus the "Low/High" verdict. Each component shows
//      its raw fact next to its points, so the number always shows its work.
//   2. How it compares — last night's score vs your 7-day / 30-day / all-time typical.
//   3. Trend — the nightly score over Week/Month/Year/All, scrubbable to read any night.
//
// The score's weights mirror Apple's (Duration 50 / Bedtime 30 / Interruptions 20); the point
// curves are ours (Apple doesn't publish them) — see `SleepScore`. Sleep clears the trend
// primitive's history bar the same way HRV does (Watch sleep spans months/years).

struct SleepDetailSheet: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    /// The tapped tile's night — section 1 mirrors what the tile showed.
    let daySleep: SleepBreakdown?
    let dayDate: Date

    @State private var data: SleepTrendData?
    @State private var range: HRVRange = .month
    @State private var loading = true

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
                .padding(.vertical, 12)
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
            let history = await healthKit.fetchSleepHistory()
            data = SleepTrendData.build(history: history, now: Date())
            loading = false
        }
    }

    // MARK: Section 1 — Last night

    private var isToday: Bool { Calendar.current.isDateInToday(dayDate) }

    /// The selected night as a `NightSleep`, scored with the history baseline once loaded.
    private var dayScore: SleepScore? {
        guard let s = daySleep, s.hasData else { return nil }
        let night = NightSleep(date: Calendar.current.startOfDay(for: dayDate),
                               asleepHours: s.totalAsleepHours,
                               wakeUps: s.interruptions,
                               awakeMinutes: s.awakeMinutes,
                               bedtime: s.bedtime)
        return SleepScore.score(night, baselineBedtimeMinutes: data?.baselineBedtime)
    }

    private var lastNightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isToday ? "Last night" : dayDate.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.headline)

            if let score = dayScore {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "bed.double.fill")
                        .font(.title)
                        .foregroundStyle(Color.sleepAccent)
                    Text("\(score.total)")
                        .font(.largeTitle.weight(.semibold))
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

    // MARK: Section 2 — How it compares

    @ViewBuilder
    private var compareSection: some View {
        if let data {
            VStack(alignment: .leading, spacing: 14) {
                Text("How it compares").font(.headline)

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
        let series = data.series(for: range)
        if series.count < 2 {
            Text("Not enough history yet for this range.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        } else {
            ScrubbableTrendChart(
                points: series,
                accent: .indigo,
                yAxisLabel: "Score",
                valueText: { "\(Int($0.rounded()))" },
                showPoints: range == .week,
                monthlyDates: range == .year || range == .all
            )
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

    static func build(history: [NightSleep], now: Date) -> SleepTrendData {
        let cal = Calendar.current
        // Display baseline = the trailing-13-night average bedtime (Apple's window), used to score
        // the currently-shown night in the sheet.
        let baseline = SleepScore.baselineBedtimeMinutes(history)

        // Each historical night is scored against ITS OWN trailing-13 baseline (causal — a night
        // is judged only by the nights before it), so the trend line matches what the score would
        // have read on that morning.
        let daily: [TrendPoint] = history.enumerated().map { i, night in
            let prior = history[..<i]
                .compactMap { $0.bedtime.map(SleepScore.minutesSince6PM) }
                .suffix(SleepScore.baselineNights)
            let nightBaseline: Double? = prior.count >= SleepScore.baselineNights
                ? prior.reduce(0, +) / Double(prior.count) : nil
            let s = SleepScore.score(night, baselineBedtimeMinutes: nightBaseline)
            return TrendPoint(date: night.date, value: Double(s.total))
        }

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
                              p10: p10, p90: p90, daily: daily, trend: trend)
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

    func series(for range: HRVRange) -> [TrendPoint] {
        let cal = Calendar.current
        switch range {
        case .week:
            guard let c = cal.date(byAdding: .day, value: -7, to: Date()) else { return daily }
            return daily.filter { $0.date >= c }
        case .month:
            guard let c = cal.date(byAdding: .day, value: -30, to: Date()) else { return daily }
            return daily.filter { $0.date >= c }
        case .year:
            let months = (trend?.months ?? []).map { TrendPoint(date: $0.month, value: $0.median) }
            return Array(months.suffix(12))
        case .all:
            return (trend?.months ?? []).map { TrendPoint(date: $0.month, value: $0.median) }
        }
    }

    /// Descriptive drift of the score — shown only under year/all, only when statistically real.
    func trendCaption(for range: HRVRange) -> String? {
        guard range == .year || range == .all, let t = trend, t.pValue < 0.05 else { return nil }
        let years = max(1, Int(t.spanYears.rounded()))
        let pct = Int(abs(t.pctChange).rounded())
        if t.slopePerYear < 0 { return "Trending down about \(pct)% over the last \(years) year\(years == 1 ? "" : "s")." }
        if t.slopePerYear > 0 { return "Trending up about \(pct)% over the last \(years) year\(years == 1 ? "" : "s")." }
        return "Stable over the last \(years) year\(years == 1 ? "" : "s")."
    }
}
