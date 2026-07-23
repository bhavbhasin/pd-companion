import SwiftUI
import Charts

// MARK: - HRV trend drill-down (first per-tile "trends" surface, #2)
//
// Tap the HRV glance tile → this sheet. Two sections only (v1):
//   1. Today — the day's value + honest context. NOT a within-day curve: the Watch samples
//      HRV only ~9×/day, so there's no honest intra-day "shape" to draw (same lesson as gait).
//   2. How it compares — the day vs your 7-day / 30-day / all-time baselines, plus a
//      Week/Month/Year/All trend chart. This is HRV's real story: a slow multi-month drift.
// Section 3 (engine "pattern") is intentionally deferred — it arrives free from the registry.
//
// HRV clears the ≥6-month bar the trend primitive needs (Watch history spans years), which
// is why it — not tremor (~2.5 mo) — is the first metric to get a trend surface.

struct HRVDetailSheet: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    /// The tapped tile's day — section 1 mirrors exactly what the tile showed.
    let dayValue: Double?
    let dayCount: Int
    let dayDate: Date

    @State private var data: HRVTrendData?
    @State private var range: HRVRange = .month
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    todaySection
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        compareSection
                    }
                }
                .padding()
            }
            .navigationTitle("HRV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            let history = await healthKit.fetchHRVHistory()
            data = HRVTrendData.build(history: history, now: Date())
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
                // Same glyph as the glance tile (`bolt.heart.fill`) so the sheet reads as
                // "the HRV tile, opened."
                Image(systemName: "bolt.heart.fill")
                    .font(.title)
                    .foregroundStyle(Color.hrvAccent)
                Text(dayValue.map { "\(Int($0))" } ?? "—")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.hrvAccent)
                Text("ms").font(.title3).foregroundStyle(.secondary)
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

                // Baselines row — "This day" in HRV's accent to anchor the eye on the subject
                // of the comparison; the reference windows stay neutral.
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

                // Trend chart
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
            Text(value.map { "\(Int($0))" } ?? "—")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(accent ? Color.hrvAccent : Color.primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func trendChart(_ data: HRVTrendData) -> some View {
        let series = data.series(for: range)
        if series.count < 2 {
            Text("Not enough history yet for this range.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        } else {
            Chart(series, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("HRV", point.value))
                    .foregroundStyle(.purple)
                    .interpolationMethod(.monotone)
                if range == .week {
                    PointMark(x: .value("Date", point.date), y: .value("HRV", point.value))
                        .foregroundStyle(.purple)
                }
            }
            .chartYAxisLabel("ms")
            .frame(height: 180)
        }
    }
}

// MARK: - Range

enum HRVRange: String, CaseIterable, Identifiable {
    case week, month, year, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .week:  "Week"
        case .month: "Month"
        case .year:  "Year"
        case .all:   "All"
        }
    }
}

// HRV's identity accent (matches the glance tile's `bolt.heart.fill` and the trend line).
extension Color { static let hrvAccent = Color.purple }

struct HRVComparison { let text: String; let valence: HRVValence }

enum HRVValence {
    case higher, typical, lower
    // Green = good (higher HRV), amber = below-usual (a soft caution, not alarm), neutral =
    // typical. Same valence language as the Insights cards' green "Strong/Result".
    var color: Color {
        switch self {
        case .higher:  .green
        case .typical: Color(.secondaryLabel)
        case .lower:   .orange
        }
    }
    var icon: String {
        switch self {
        case .higher:  "arrow.up.circle.fill"
        case .typical: "checkmark.circle.fill"
        case .lower:   "arrow.down.circle.fill"
        }
    }
}

// MARK: - Computation
//
// Descriptive stats over the fetched HRV history. The multi-month/year trend reuses the
// engine's `longTermTrend` primitive (monthly medians → OLS slope + t-test) — the same math
// behind the gait card. Short windows (7/30-day) are plain means of daily averages.
// A named point type (not a tuple) keeps Swift's type-checker fast and gives the chart a
// stable id.

struct HRVPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct HRVTrendData {
    let avg7: Double?
    let avg30: Double?
    let avgAll: Double?
    let p10: Double?                                    // 10th pct of recent daily averages
    let p90: Double?                                    // 90th pct of recent daily averages
    private let daily: [HRVPoint]                       // one mean per day, ascending
    private let trend: CorrelationEngine.TrendResult?  // monthly medians + slope (year/all)

    static func build(history: [HRVSample], now: Date) -> HRVTrendData {
        let cal = Calendar.current

        // One mean per calendar day (the unit for the short-window charts + baselines).
        let byDay = Dictionary(grouping: history) { cal.startOfDay(for: $0.timestamp) }
        var daily: [HRVPoint] = []
        for (day, samples) in byDay {
            let m = samples.map(\.value).reduce(0, +) / Double(samples.count)
            daily.append(HRVPoint(date: day, value: m))
        }
        daily.sort { $0.date < $1.date }

        func mean(sinceDaysAgo days: Int) -> Double? {
            guard let cutoff = cal.date(byAdding: .day, value: -days, to: now) else { return nil }
            let vals = history.filter { $0.timestamp >= cutoff }.map(\.value)
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }

        let allVals = history.map(\.value)
        let avgAll = allVals.isEmpty ? nil : allVals.reduce(0, +) / Double(allVals.count)

        // "Usual range" from the last-30-day DAILY averages as PERCENTILES (10th/90th), not
        // mean±SD: HRV daily values are right-skewed, so percentiles are assumption-free and
        // robust. The 10/90 cut flags roughly the top/bottom tenth of recent days as notably
        // high/low — a chosen sensitivity, not a distributional assumption.
        let cutoff30 = cal.date(byAdding: .day, value: -30, to: now)
        var recentDaily: [Double] = []
        for p in daily where (cutoff30.map { p.date >= $0 } ?? false) {
            recentDaily.append(p.value)
        }
        recentDaily.sort()
        let p10 = recentDaily.count >= 8 ? Self.percentile(recentDaily, 0.10) : nil
        let p90 = recentDaily.count >= 8 ? Self.percentile(recentDaily, 0.90) : nil

        // ms is physiological; the wide clip only drops clear artifacts and the monthly
        // MEDIAN makes the trend insensitive to it anyway.
        let dated = history.map { (date: $0.timestamp, value: $0.value) }
        let trend = CorrelationEngine.longTermTrend(samples: dated, clip: (lo: 5, hi: 300))

        return HRVTrendData(avg7: mean(sinceDaysAgo: 7), avg30: mean(sinceDaysAgo: 30),
                            avgAll: avgAll, p10: p10, p90: p90, daily: daily, trend: trend)
    }

    /// Linear-interpolated percentile over an already-sorted array.
    private static func percentile(_ sorted: [Double], _ q: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        if sorted.count == 1 { return sorted[0] }
        let pos = q * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }

    /// The day vs the 10th/90th percentiles of recent daily averages. Returns text + a
    /// valence so the view can color it (higher HRV = good = green; lower = amber; typical
    /// = neutral) — the same "green means good" language the Insights cards use.
    func comparison(dayValue: Double?) -> HRVComparison? {
        guard let day = dayValue, let lo = p10, let hi = p90 else { return nil }
        if day >= hi { return HRVComparison(text: "Higher than your usual - a good sign for HRV.", valence: .higher) }
        if day <= lo { return HRVComparison(text: "Lower than your usual lately.", valence: .lower) }
        return HRVComparison(text: "About typical for you lately.", valence: .typical)
    }

    /// The chart series for a range: short windows use daily averages; year/all use the
    /// engine's monthly medians (robust to the day-to-day HRV noise).
    func series(for range: HRVRange) -> [HRVPoint] {
        let cal = Calendar.current
        switch range {
        case .week:
            guard let c = cal.date(byAdding: .day, value: -7, to: Date()) else { return daily }
            return daily.filter { $0.date >= c }
        case .month:
            guard let c = cal.date(byAdding: .day, value: -30, to: Date()) else { return daily }
            return daily.filter { $0.date >= c }
        case .year:
            let months = (trend?.months ?? []).map { HRVPoint(date: $0.month, value: $0.median) }
            return Array(months.suffix(12))
        case .all:
            return (trend?.months ?? []).map { HRVPoint(date: $0.month, value: $0.median) }
        }
    }

    /// Descriptive magnitude of the long-term drift — shown only under year/all, only when
    /// the slope is statistically real. Purely factual; no clinical verdict (that's section 3).
    func trendCaption(for range: HRVRange) -> String? {
        guard range == .year || range == .all, let t = trend, t.pValue < 0.05 else { return nil }
        let years = max(1, Int(t.spanYears.rounded()))
        let pct = Int(abs(t.pctChange).rounded())
        if t.slopePerYear < 0 { return "Trending down about \(pct)% over the last \(years) year\(years == 1 ? "" : "s")." }
        if t.slopePerYear > 0 { return "Trending up about \(pct)% over the last \(years) year\(years == 1 ? "" : "s")." }
        return "Stable over the last \(years) year\(years == 1 ? "" : "s")."
    }
}
