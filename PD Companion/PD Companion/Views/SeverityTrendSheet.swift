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
//   2. How it compares — the day vs 7-day / 30-day / all-time baselines + a Week/Month/All chart.
// Section 3 (engine "pattern") is deferred — it arrives free from the registry.
//
// Ranges are Week/Month/All only (no Year): tremor/dyskinesia history is ~2.5 months, too short
// for the ≥6-month monthly-median trend HRV/Sleep use. "All" = every daily average so far. When
// history passes ~6 months, Year can join (same call the HRV sheet makes).

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    todaySection
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        compareSection
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
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
            data = SeverityTrendData.build(samples: await load(), now: Date())
            loading = false
        }
    }

    // MARK: Section 1 — Today

    private var isToday: Bool { Calendar.current.isDateInToday(dayDate) }
    private var dayLabel: String {
        isToday ? "today" : dayDate.formatted(.dateTime.month(.abbreviated).day())
    }
    private var todayCaption: String {
        if dayCount == 0 {
            return isToday ? "No readings today yet." : "No readings on \(dayLabel)."
        }
        return isToday ? "Average for the day so far." : "Average for the day."
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isToday ? "Today" : dayDate.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Same glyph as the glance tile so the sheet reads as "that tile, opened."
                Image(systemName: glyph)
                    .font(.title)
                    .foregroundStyle(accent)
                Text(dayValue.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(accent)
                // Severity word sits where HRV's "ms" unit sits — the label the tile carried.
                if let v = dayValue {
                    Text(SeverityScale.name(v)).font(.title3).foregroundStyle(.secondary)
                }
            }
            Text(todayCaption)
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Section 2 — How it compares

    @ViewBuilder
    private var compareSection: some View {
        if let data {
            VStack(alignment: .leading, spacing: 14) {
                Text("How it compares").font(.headline)

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
        let series = data.series(for: range)
        if series.count < 2 {
            Text("Not enough history yet for this range.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        } else {
            ScrubbableTrendChart(
                points: series,
                accent: accent,
                yAxisLabel: "",
                valueText: { String(format: "%.1f", $0) },
                showPoints: range == .week
            )
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
}

// MARK: - Severity scale (shared with the glance tiles' 0-4 naming)

enum SeverityScale {
    static func name(_ v: Double) -> String {
        switch v {
        case ..<0.5: "None"
        case ..<1.5: "Slight"
        case ..<2.5: "Mild"
        case ..<3.5: "Moderate"
        default:     "Strong"
        }
    }
}

// MARK: - Valence (inverted vs HRV: for tremor/dyskinesia, LOWER is better)

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
    private let daily: [TrendPoint]  // one mean per day, ascending

    static func build(samples: [DatedSample], now: Date) -> SeverityTrendData {
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

        return SeverityTrendData(avg7: mean(sinceDaysAgo: 7), avg30: mean(sinceDaysAgo: 30),
                                 avgAll: avgAll, p10: p10, p90: p90, daily: daily)
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
        if day <= lo { return SeverityComparison(text: "Lower than your usual lately - a steadier day.", valence: .better) }
        if day >= hi { return SeverityComparison(text: "Higher than your usual lately.", valence: .worse) }
        return SeverityComparison(text: "About typical for you lately.", valence: .typical)
    }

    /// The chart series for a range. Short windows filter the daily averages; "All" is every day.
    func series(for range: SeverityRange) -> [TrendPoint] {
        let cal = Calendar.current
        switch range {
        case .week:
            guard let c = cal.date(byAdding: .day, value: -7, to: Date()) else { return daily }
            return daily.filter { $0.date >= c }
        case .month:
            guard let c = cal.date(byAdding: .day, value: -30, to: Date()) else { return daily }
            return daily.filter { $0.date >= c }
        case .all:
            return daily
        }
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
