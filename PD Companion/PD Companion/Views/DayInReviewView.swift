import SwiftUI
import SwiftData
import Charts
import HealthKit

struct DayInReviewView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var connectivity: PhoneConnectivityManager
    @Environment(\.modelContext) private var modelContext
    // Newest reading timestamp for the header sync-status label. Fetched with a
    // fetchLimit = 1 descriptor (refreshLatestReadingDate) and refreshed reactively
    // via DayReviewContent's onDataChanged — loading every TremorReading into an
    // @Query just to read .last is the perf trap this screen used to hit.
    @State private var latestReadingDate: Date?
    // Default to today: the app is used through the day for logging (food, meds), so
    // the view should reflect "now" — seeing yesterday right after logging something
    // today reads as a bug. Today's data is partial (the chart fills as the day goes),
    // which is honest; the date chevrons still reach yesterday for a complete-day review.
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showingDatePicker = false
    @State private var showingLogSheet = false
    @State private var selectedEvent: DayEvent?
    @State private var showingBackup = false

    // One size/weight for all three top-bar icons (plus, gear, lightbulb) so they render
    // at matched height — the default toolbar font let the heavier `lightbulb.max` glyph
    // sit taller than the outline pair, most visible in landscape.
    private static let toolbarIconFont = Font.system(size: 18, weight: .regular)

    var body: some View {
        NavigationStack {
            DayReviewContent(
                selectedDate: selectedDate,
                onEventTap: { selectedEvent = $0 },
                onDataChanged: refreshLatestReadingDate
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                dateHeader
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Both in one ToolbarItem (not two): separate ToolbarItems get pushed apart
                // with a wide default gap — an HStack keeps the pair tight.
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 18) {
                        Button {
                            showingLogSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(Self.toolbarIconFont)
                                .accessibilityLabel("Log entry")
                        }
                        Button {
                            showingBackup = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(Self.toolbarIconFont)
                                .accessibilityLabel("Settings")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        InsightsView()
                    } label: {
                        Image(systemName: "lightbulb.max")
                            .font(Self.toolbarIconFont)
                            .accessibilityLabel("Insights")
                    }
                }
            }
            .sheet(isPresented: $showingLogSheet) {
                LogEntrySheet(defaultDate: selectedDate) { loggedDate in
                    selectedDate = Calendar.current.startOfDay(for: loggedDate)
                }
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailSheet(event: event)
            }
            .sheet(isPresented: $showingBackup) {
                BackupSheet()
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    DatePicker(
                        "Select a date",
                        selection: $selectedDate,
                        in: ...Calendar.current.startOfDay(for: Date()),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Jump to date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Today") {
                                selectedDate = Calendar.current.startOfDay(for: Date())
                                showingDatePicker = false
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingDatePicker = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .task(id: selectedDate) {
                refreshLatestReadingDate()
                await healthKit.fetchDayInReview(for: selectedDate)
            }
            .refreshable {
                connectivity.requestFreshTremorData()
                await healthKit.fetchDayInReview(for: selectedDate)
                refreshLatestReadingDate()
            }
        }
    }

    // Reads only the single most-recent reading (fetchLimit = 1) for the header's
    // "Updated …" label — no full-table hydration. Called on day change, pull-to-refresh,
    // and reactively from DayReviewContent whenever the day's readings change.
    private func refreshLatestReadingDate() {
        var descriptor = FetchDescriptor<TremorReading>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        latestReadingDate = (try? modelContext.fetch(descriptor))?.first?.timestamp
    }

    private var dateHeader: some View {
        HStack {
            Button { shiftDay(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.title3).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                showingDatePicker = true
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(syncStatusText)
                        .font(.caption2).foregroundStyle(syncStatusColor)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Selected day: \(selectedDate.formatted(.dateTime.weekday(.wide).month().day())). Tap to pick a date.")

            Spacer()

            Button { shiftDay(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.title3).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(isAtToday)
            .opacity(isAtToday ? 0.3 : 1)
        }
    }

    private var isAtToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: Date())
    }

    private var syncStatusText: String {
        guard let latest = latestReadingDate else {
            return "No tremor data yet"
        }
        let style: Date.FormatStyle = Calendar.current.isDateInToday(latest)
            ? .dateTime.hour().minute()
            : .dateTime.month().day().hour().minute()
        return "Updated \(latest.formatted(style))"
    }

    private var syncStatusColor: Color {
        guard let latest = latestReadingDate else { return .secondary }
        let age = Date().timeIntervalSince(latest)
        switch age {
        case ..<(6 * 3600):      return .secondary
        case ..<(24 * 3600):     return .orange
        default:                 return .red
        }
    }

    private func shiftDay(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if next > today { return }
        selectedDate = Calendar.current.startOfDay(for: next)
    }
}

// MARK: - Day-scoped content

/// Owns the day-scoped SwiftData queries. The predicate is built in init from the
/// selected day's bounds, so SwiftData only hydrates that day's rows instead of the
/// whole table. SwiftUI re-creates this view (and re-runs the query) whenever the
/// parent passes a new selectedDate — the canonical dynamic-@Query pattern.
/// Shared layout constants for the stacked Review panels. The y-axis gutter width is
/// pinned equal across Tremor and Glucose so their plot rectangles match and the shared
/// x-domain lines up pixel-for-pixel — the vertical read across panels depends on it.
enum DayReviewLayout {
    static let yAxisWidth: CGFloat = 46   // fits the widest tremor label ("Strong")
}

private struct DayReviewContent: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var connectivity: PhoneConnectivityManager
    @Environment(\.modelContext) private var modelContext

    private let dayStart: Date
    private let dayEnd: Date
    private let onEventTap: (DayEvent) -> Void
    private let onDataChanged: () -> Void

    // Shared horizontal-scroll position for the stacked Tremor + Glucose charts, so they
    // pan together and a spike lines up with the meal/dose that caused it. Both charts bind
    // to this; a no-glucose day simply has one fewer consumer (nothing breaks).
    @State private var chartScrollX: Date

    // Shared crosshair time: tapping either chart sets this, and BOTH panels draw a rule +
    // value readout at that instant — the vertical read as a number, not just by eye.
    // Anchored to a time (scrolls with the data); tap the pill's × or change day to clear.
    @State private var selectedTime: Date?

    // Tier-1 "rest of your day" forecast (today only). Computed off-main from full
    // history + today's doses; nil = not estimable (cold start) or not today → panel
    // hidden. Recomputed when the day, its doses, or its readings change (see task id).
    @State private var forecast: CorrelationEngine.DayForecast?

    @Query private var dayReadings: [TremorReading]
    @Query private var dayDyskinesia: [DyskinesiaReading]
    @Query private var dayFoodEvents: [FoodEvent]

    init(selectedDate: Date,
         onEventTap: @escaping (DayEvent) -> Void,
         onDataChanged: @escaping () -> Void) {
        let start = Calendar.current.startOfDay(for: selectedDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86400)
        self.dayStart = start
        self.dayEnd = end
        self.onEventTap = onEventTap
        self.onDataChanged = onDataChanged
        _chartScrollX = State(initialValue: start)
        _dayReadings = Query(
            filter: #Predicate<TremorReading> { $0.timestamp >= start && $0.timestamp < end },
            sort: \TremorReading.timestamp, order: .forward
        )
        _dayDyskinesia = Query(
            filter: #Predicate<DyskinesiaReading> { $0.startDate >= start && $0.startDate < end },
            sort: \DyskinesiaReading.startDate, order: .forward
        )
        _dayFoodEvents = Query(
            filter: #Predicate<FoodEvent> { $0.timestamp >= start && $0.timestamp < end },
            sort: \FoodEvent.timestamp, order: .forward
        )
    }

    // Cheap COUNT(*) — does the user have any tremor reading ever? — without hydrating rows.
    private var hasEverHadData: Bool {
        ((try? modelContext.fetchCount(FetchDescriptor<TremorReading>())) ?? 0) > 0
    }

    private var allDayEvents: [DayEvent] {
        let food = dayFoodEvents.map {
            DayEvent.food(id: $0.id, time: $0.timestamp,
                          userDescription: $0.userDescription ?? "", attributes: $0.attributes)
        }
        return (healthKit.dayEvents + food).sorted { $0.time < $1.time }
    }

    // Shown when watch data has gone stale (paired watch, has synced before, silent >8h). One
    // human-doable step only — never reboot/force-quit. See docs/design/watch-sync-payload-options.md.
    private var staleWatchBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "applewatch.slash")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Watch data is behind")
                    .font(.subheadline.weight(.semibold))
                Text("Open Kampa on your Watch to sync your latest data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Re-fire the forecast task on day change and whenever today's events (doses) or
    // readings move — so a freshly logged dose or a just-synced reading updates it live.
    private var forecastKey: String {
        "\(dayStart.timeIntervalSince1970)|\(healthKit.dayEvents.count)|\(dayReadings.count)"
    }

    /// Compute the Tier-1 forecast for today only. Snapshots full history + today's data
    /// into Sendable values on the main actor (a one-shot fetch — not a live full-table
    /// @Query, which this screen deliberately avoids), then runs the engine off-main.
    private func recomputeForecast() async {
        guard Calendar.current.isDate(dayStart, inSameDayAs: Date()) else {
            forecast = nil
            return
        }
        let allDoses = await healthKit.fetchMedicationDoses()
        let ds = dayStart, de = dayEnd
        // No early-out on a zero-dose day: the engine returns the flat-band forecast for it
        // (Phase 0, forecast-composition-model.md) — medication is an event, not a user trait.
        let todays = allDoses.filter { $0.timestamp >= ds && $0.timestamp < de }
        let history = ((try? modelContext.fetch(FetchDescriptor<TremorReading>())) ?? [])
            .map { TremorPoint(timestamp: $0.timestamp, tremorScore: $0.tremorScore) }
        let todaysReadings = dayReadings.map {
            TremorPoint(timestamp: $0.timestamp, tremorScore: $0.tremorScore)
        }
        let now = Date()
        // The forecast projects from the same KM duration the wearing-off card reads, so it
        // needs the same sleep-censoring: a duration inflated by unobservable sleep would
        // project ON windows that run too long. Same reason the censor lives in the primitive
        // rather than on one card.
        // min/max, not first/last: `history` comes from an unsorted fetch, so first/last
        // would silently truncate the sleep window to an arbitrary sub-range.
        let sleep: [SleepInterval]
        if let lo = history.map(\.timestamp).min(), let hi = history.map(\.timestamp).max() {
            sleep = await healthKit.fetchSleepIntervals(from: lo, to: hi)
        } else {
            sleep = []
        }
        forecast = await Task.detached(priority: .userInitiated) {
            CorrelationEngine.dayForecast(
                history: history, allDoses: allDoses,
                todaysDoses: todays, todaysReadings: todaysReadings,
                dayStart: ds, dayEnd: de, now: now, sleep: sleep)
        }.value
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if connectivity.syncIsStale {
                    staleWatchBanner
                }
                GlanceCard(
                    sleep: healthKit.daySleep,
                    tremorReadings: dayReadings,
                    dyskinesiaReadings: dayDyskinesia,
                    hrv: healthKit.dayHRV
                )
                TremorTimelinePanel(
                    readings: dayReadings,
                    dyskinesia: dayDyskinesia,
                    hasEverHadData: hasEverHadData,
                    events: allDayEvents,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    scrollX: $chartScrollX,
                    selectedTime: $selectedTime,
                    onEventTap: onEventTap
                )
                // Directly under the tremor line + sharing its 12h scroll, so the forecast
                // band reads straight down from the chart (dose/workout markers align).
                // Today only; hidden when neither the wearing-off model (dosed day) nor
                // the flat personal band (zero-dose day) is estimable yet.
                if let forecast {
                    DayAheadPanel(forecast: forecast, dayStart: dayStart, dayEnd: dayEnd,
                                  scrollX: $chartScrollX, selectedTime: $selectedTime)
                }
                // Day-gated: only for a CGM (Lingo) user, and only when this day has a
                // curve (else a quiet note). Sits directly under Tremor with a matched
                // x-domain and shared scroll so meals/doses read straight down across panels.
                if !healthKit.dayGlucose.isEmpty {
                    GlucosePanel(
                        samples: healthKit.dayGlucose,
                        events: allDayEvents,
                        dayStart: dayStart,
                        dayEnd: dayEnd,
                        scrollX: $chartScrollX,
                        selectedTime: $selectedTime
                    )
                } else if healthKit.hasEverHadGlucose {
                    GlucosePanel.gapNote
                }
                SleepStagesPanel(
                    sleep: healthKit.daySleep,
                    daylightMinutes: healthKit.dayDaylightMinutes
                )
                ObservationsPanel(
                    readings: dayReadings,
                    dyskinesia: dayDyskinesia,
                    events: allDayEvents,
                    foodEvents: dayFoodEvents,
                    sleep: healthKit.daySleep,
                    hrvSamples: healthKit.dayHRVSamples,
                    daylightMinutes: healthKit.dayDaylightMinutes
                )
            }
            // Tighter side gutters + inter-card spacing to reclaim real estate as more
            // panels appear (was default 16 all round + 16 spacing).
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        // Recompute the forecast on day change, and when today's doses or readings move.
        .task(id: forecastKey) { await recomputeForecast() }
        // Option B: when a sync lands a new reading for the visible day, nudge the parent
        // to re-read the latest-reading timestamp so the header label stays live.
        .onChange(of: dayReadings.last?.timestamp) { _, _ in onDataChanged() }
        // Reset the shared scroll to the start of a newly selected day. @State survives
        // the dynamic-@Query re-init, so without this a day change would keep the prior
        // day's scroll offset (and could land outside the new day's domain).
        .onChange(of: dayStart) { _, newStart in
            chartScrollX = newStart
            selectedTime = nil
        }
    }
}

// MARK: - Dyskinesia display mapping

/// Display-time mapping from Apple's raw per-minute dyskinesia *likelihood*
/// (`DyskinesiaReading.percentLikely`, 0…1) onto the shared 0–4 chart axis.
/// Lives here (not on the model) deliberately — `DyskinesiaReading` stores the raw
/// signal; thresholding is a display concern (see the model's doc comment).
///
/// ⚠️ The legacy `TremorReading.dyskinesiaScore` (= `percentLikely / 25`) is NOT used
/// here — that bug crushes the value ~100× so it reads ~0 for everyone. The chart and
/// glance card both read this stream instead.
enum DyskinesiaDisplay {
    /// Minutes whose `percentLikely` is below this are treated as artifact (→ 0).
    /// CMDyskineticSymptomResult has no abstain state, so ordinary voluntary movement
    /// leaks a false "likely" baseline (Apple Movement-Disorder addendum §5.4). A floor
    /// suppresses that noise — without it we'd re-create the StrivePD false-positive that
    /// testers without dyskinesia complained about.
    ///
    /// ⚠️ PROVISIONAL. Bhav's dyskinesia is ~0, so this can't be tuned on his data — it
    /// needs a wrist that actually has dyskinesia (his dad / a dyskinetic tester). This is
    /// the single knob. See BACKLOG "Fix dyskinesia scale + noise floor".
    static let noiseFloor = 0.5

    /// Floor, then rescale the surviving range so `noiseFloor → 0` and `1.0 → 4`.
    /// NOTE: this is a *likelihood* drawn on a severity axis, not a calibrated amplitude
    /// like `tremorScore` — the two waveforms answer "how likely" vs "how strong".
    static func intensity(_ percentLikely: Double) -> Double {
        guard percentLikely > noiseFloor else { return 0 }
        return (percentLikely - noiseFloor) / (1 - noiseFloor) * 4
    }

    /// Mean display-intensity over a day's readings, or nil if there are none.
    static func dayAverage(_ readings: [DyskinesiaReading]) -> Double? {
        guard !readings.isEmpty else { return nil }
        let sum = readings.reduce(0.0) { $0 + intensity($1.percentLikely) }
        return sum / Double(readings.count)
    }
}

// MARK: - Glance card

private struct GlanceCard: View {
    let sleep: SleepBreakdown?
    let tremorReadings: [TremorReading]
    let dyskinesiaReadings: [DyskinesiaReading]
    let hrv: Double?

    // Constant identity colors (blue = tremor, orange = dyskinesia) match the chart's two
    // waveforms exactly — this card doubles as the chart's implicit legend. Height/number
    // encode severity; color only says *which signal*. (The old value-varying severity
    // gradient was a redundant 3rd encoding that over-signalled a noisy daily average.)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                stat(icon: "bed.double.fill", color: .indigo,
                     value: sleepValue, sub: "Total sleep")
                stat(icon: "waveform.path.ecg", color: .blue,
                     value: tremorValue, sub: tremorLabel)
            }
            HStack(spacing: 16) {
                stat(icon: "bolt.heart.fill", color: .purple,
                     value: hrvValue, sub: hrvLabel)
                stat(icon: "waveform.path", color: .dyskinesia,
                     value: dyskinesiaValue, sub: dyskinesiaLabel)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func stat(icon: String, color: Color, value: String, sub: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline)
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var sleepValue: String {
        guard let s = sleep, s.hasData else { return "—" }
        let h = Int(s.totalAsleepHours)
        let m = Int((s.totalAsleepHours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    private var avgTremor: Double? {
        guard !tremorReadings.isEmpty else { return nil }
        return tremorReadings.reduce(0.0) { $0 + $1.tremorScore } / Double(tremorReadings.count)
    }

    private var tremorValue: String {
        guard let v = avgTremor else { return "—" }
        return String(format: "%.1f", v)
    }

    private var tremorLabel: String {
        guard let v = avgTremor else { return "Tremor" }
        switch v {
        case ..<0.5: return "Tremor avg: None"
        case ..<1.5: return "Tremor avg: Slight"
        case ..<2.5: return "Tremor avg: Mild"
        case ..<3.5: return "Tremor avg: Moderate"
        default:     return "Tremor avg: Strong"
        }
    }

    private var hrvValue: String {
        guard let hrv else { return "—" }
        return "\(Int(hrv)) ms"
    }

    // SDNN HRV is sampled by the Apple Watch (opportunistically during the day,
    // heavily during sleep). An empty tile shows "—" over the "HRV" label; the
    // "open your Watch to sync" explanation lives in the Tremor card below, so
    // the tile keeps its metric name rather than restating the empty reason.
    private var hrvLabel: String { "HRV" }

    // Reads the raw DyskinesiaReading stream through the display mapping (floor + rescale),
    // NOT the crushed legacy TremorReading.dyskinesiaScore. Stays in lock-step with the
    // chart's dyskinesia waveform, which uses the same mapping.
    private var avgDyskinesia: Double? {
        DyskinesiaDisplay.dayAverage(dyskinesiaReadings)
    }

    private var dyskinesiaValue: String {
        guard let v = avgDyskinesia else { return "—" }
        return String(format: "%.1f", v)
    }

    private var dyskinesiaLabel: String {
        guard let v = avgDyskinesia else { return "Dyskinesia" }
        switch v {
        case ..<0.5: return "Dyskinesia: None"
        case ..<1.5: return "Dyskinesia: Slight"
        case ..<2.5: return "Dyskinesia: Mild"
        case ..<3.5: return "Dyskinesia: Moderate"
        default:     return "Dyskinesia: Strong"
        }
    }
}

// MARK: - Tremor timeline

private struct TremorTimelinePanel: View {
    let readings: [TremorReading]
    let dyskinesia: [DyskinesiaReading]
    let hasEverHadData: Bool
    let events: [DayEvent]
    let dayStart: Date
    let dayEnd: Date
    @Binding var scrollX: Date
    @Binding var selectedTime: Date?
    var onEventTap: (DayEvent) -> Void = { _ in }

    // First time we render an empty tremor state, so the copy can escalate from "warming up"
    // to a real "check your Watch setup" prompt once it's clearly overdue (Jon sat ~a month
    // on the reassuring version).
    @AppStorage("tremor.firstEmptyEpoch") private var firstEmptyEpoch: Double = 0
    private var daysSinceFirstEmpty: Double {
        guard firstEmptyEpoch > 0 else { return 0 }
        return Date().timeIntervalSince(Date(timeIntervalSince1970: firstEmptyEpoch)) / 86_400
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(.blue)
                Text("Tremor").font(.headline)
            }
            if hourlyBuckets.isEmpty {
                emptyStateView
            } else {
                Chart {
                    ForEach(chartEvents) { event in
                        RuleMark(x: .value("Event time", event.time))
                            .foregroundStyle(.gray.opacity(0.25))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    ForEach(chartEvents) { event in
                        PointMark(
                            x: .value("Event time", event.time),
                            y: .value("Event lane", 4.3)
                        )
                        .symbol { eventIcon(for: event) }
                    }
                    // One series per contiguous run of buckets → both the fill and the line
                    // break where the Watch reported no data for a true gap (see `tremorSegments`),
                    // instead of interpolating a straight span across it. A lone bucket flanked by
                    // gaps can't draw as a 1-point line, so render it as a dot (like the glucose panel).
                    ForEach(tremorSegments, id: \.id) { segment in
                        if segment.points.count == 1, let p = segment.points.first {
                            PointMark(
                                x: .value("Time", p.plotX),
                                y: .value("Tremor", p.value)
                            )
                            .foregroundStyle(Color.blue)
                            .symbolSize(28)
                        } else {
                            ForEach(segment.points, id: \.hour) { bucket in
                                AreaMark(
                                    x: .value("Time", bucket.plotX),
                                    y: .value("Tremor", bucket.value),
                                    series: .value("Segment", "tremor-area-\(segment.id)")
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.35), Color.blue.opacity(0.05)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                            }
                            ForEach(segment.points, id: \.hour) { bucket in
                                LineMark(
                                    x: .value("Time", bucket.plotX),
                                    y: .value("Tremor", bucket.value),
                                    series: .value("Segment", "tremor-line-\(segment.id)")
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(Color.blue)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                    }
                    // Dyskinesia overlay — same 0–4 axis (NOT a 2nd axis, which would
                    // manufacture a correlation). Pink, and an *unshaded* line (not a 2nd
                    // area fill) — two overlapping fills read as mud; the primary signal
                    // (tremor) keeps its fill, the overlay is a clean line on top. The
                    // explicit `series:` is load-bearing: without it Charts merges these
                    // points into the tremor line (one color + a spurious connecting line).
                    // Draws nothing when the day has no dyskinesia (honest empty — Bhav ~0).
                    // Broken at true gaps on the same >60min rule as tremor (dyskinesiaSegments):
                    // a not-worn stretch shows no dyskinesia line either — consistent across signals,
                    // and correct for a user who *does* have dyskinesia to report. Per-segment series
                    // names stay distinct from the tremor line's so Charts never merges the two.
                    ForEach(dyskinesiaSegments, id: \.id) { segment in
                        if segment.points.count == 1, let p = segment.points.first {
                            PointMark(
                                x: .value("Time", p.plotX),
                                y: .value("Dyskinesia", p.value)
                            )
                            .foregroundStyle(Color.dyskinesia)
                            .symbolSize(28)
                        } else {
                            ForEach(segment.points, id: \.hour) { bucket in
                                LineMark(
                                    x: .value("Time", bucket.plotX),
                                    y: .value("Dyskinesia", bucket.value),
                                    series: .value("Signal", "dyskinesia-\(segment.id)")
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(Color.dyskinesia)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                    }
                    if let t = selectedTime {
                        RuleMark(x: .value("Selected", t))
                            .foregroundStyle(.gray.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        // Hang the callout from just under the event-glyph lane (glyphs sit at
                        // y≈4.3) into the plot's empty top — clears the glyphs and never clips
                        // at the card top. Invisible anchor point (symbolSize 0).
                        PointMark(x: .value("Selected", t), y: .value("Callout lane", 4.05))
                            .symbolSize(0)
                            .annotation(position: .bottom, alignment: .center, spacing: 2,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))) {
                                // Suppressed past `now`: today's future has no measured tremor
                                // or glucose, so the box would be all "—". The rule line stays.
                                if showsCallout(at: t) {
                                    CrosshairCallout(time: t, rows: [
                                        .init(value: tremorReadout(at: t), label: "Tremor", color: .blue),
                                        .init(value: dyskinesiaReadout(at: t), label: "Dyskinesia", color: .dyskinesia)
                                    ])
                                }
                            }
                    }
                }
                .chartYScale(domain: 0...4.6)
                .chartXScale(domain: dayStart...dayEnd)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 12 * 3600)
                .chartScrollPosition(x: $scrollX)
                .chartXSelection(value: $selectedTime)
                .chartYAxis {
                    AxisMarks(values: [0, 1, 2, 3, 4]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            // Fixed-width gutter (shared with the glucose panel) so the two
                            // stacked charts have identical plot widths and align vertically.
                            Text(value.as(Int.self).map { yLabel(for: $0) } ?? "")
                                .font(.caption2)
                                .frame(width: DayReviewLayout.yAxisWidth, alignment: .leading)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 1)) { _ in
                        AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.gray.opacity(0.4))
                    }
                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartOverlay { proxy in
                    tapOverlay(proxy: proxy)
                }
                .frame(height: 200)

                if !chartEvents.isEmpty {
                    legendRow
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func eventIcon(for event: DayEvent) -> some View {
        switch event {
        case .medication:
            Image(systemName: "pill.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red, .yellow)
                .font(.system(size: 16))
        case .workout:
            Image(systemName: event.iconName)
                .foregroundStyle(.green)
                .font(.system(size: 16))
        case .mindfulness:
            Image(systemName: "figure.mind.and.body")
                .foregroundStyle(.cyan)
                .font(.system(size: 16))
        case .food:
            Image(systemName: "fork.knife")
                .foregroundStyle(Color.brown)
                .font(.system(size: 16))
        case .giSymptom:
            // One restrained purple glyph for the whole GI cluster (see GISymptom.tint).
            Image(systemName: GISymptom.timelineSymbol)
                .foregroundStyle(GISymptom.tint)
                .font(.system(size: 16))
        }
    }

    private func tapOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame {
                let plotFrame = geometry[anchor]
                VStack(spacing: 0) {
                    // Top strip = event lane: a tap here opens the nearest meal/dose detail.
                    // The plot body below stays non-interactive so the chart's own scroll
                    // and `.chartXSelection` (crosshair) work — an opaque overlay here would
                    // swallow the scroll drag.
                    Color.clear
                        .frame(height: 36)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            SpatialTapGesture().onEnded { value in
                                handleTap(at: value.location.x, proxy: proxy)
                            }
                        )
                    Color.clear
                        .frame(maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
                .frame(width: plotFrame.width)
                .offset(x: plotFrame.minX, y: plotFrame.minY)
            }
        }
    }

    private func handleTap(at x: CGFloat, proxy: ChartProxy) {
        guard let tappedDate: Date = proxy.value(atX: x, as: Date.self) else { return }
        let nearest = chartEvents.min { a, b in
            abs(a.time.timeIntervalSince(tappedDate)) < abs(b.time.timeIntervalSince(tappedDate))
        }
        guard let nearest, abs(nearest.time.timeIntervalSince(tappedDate)) < 3600 else { return }
        onEventTap(nearest)
    }

    /// Tremor score at the crosshair time — the bucket for the slot the crosshair sits in, on the
    /// 0–4 severity scale to one decimal, or "—" when that slot is empty (not worn) or off the day.
    private func tremorReadout(at time: Date) -> String {
        guard let b = bucketForSlot(hourlyBuckets, containing: time) else { return "—" }
        return String(format: "%.1f", b.value)
    }

    /// Whether the crosshair callout should render at `time`. On today, only over measured
    /// time (≤ now): past `now` every panel is blank, so the box would be all "—". On a past
    /// day there is no future portion, so it shows throughout. See the forecast band, which
    /// carries the shared line into the projected region but never a callout.
    private func showsCallout(at time: Date) -> Bool {
        guard Calendar.current.isDateInToday(dayStart) else { return true }
        return time <= Date()
    }

    /// Dyskinesia intensity at the crosshair time (same 0–4 display mapping as the waveform), to one
    /// decimal. A worn-but-calm slot reads 0.0 (honest — Bhav is ~0); an *empty* slot reads "—"
    /// (not worn ⇒ unknown, not a measured zero — matches the broken curve).
    private func dyskinesiaReadout(at time: Date) -> String {
        guard let b = bucketForSlot(dyskinesiaBuckets, containing: time) else { return "—" }
        return String(format: "%.1f", b.value)
    }

    /// The bucket whose 30-min slot contains `time`, or nil if that slot is empty (not worn). Slot-
    /// containment — not nearest-within-N — so the readout can't snap across a gap to a slot up to
    /// N minutes away and report a value for a stretch the Watch never measured.
    private func bucketForSlot(_ buckets: [HourBucket], containing time: Date) -> HourBucket? {
        buckets.first { b in
            time >= b.hour && time < b.hour.addingTimeInterval(Self.bucketSeconds)
        }
    }

    @ViewBuilder
    private var legendRow: some View {
        FlowLayout(spacing: 14, lineSpacing: 6) {
            ForEach(legendEntries) { entry in
                legendItem(entry: entry)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// One chip per distinct glyph drawn on the chart today, in order of first
    /// appearance. Workouts and mindfulness dedupe by activity type (two boxing
    /// sessions -> a single "Boxing" chip); medication and food collapse to one
    /// category chip regardless of dose name or meal description.
    private var legendEntries: [LegendEntry] {
        var seen = Set<String>()
        var result: [LegendEntry] = []
        for event in chartEvents {
            let entry = legendEntry(for: event)
            if seen.insert(entry.id).inserted {
                result.append(entry)
            }
        }
        return result
    }

    private func legendEntry(for event: DayEvent) -> LegendEntry {
        switch event {
        case .medication:
            return LegendEntry(icon: "pill.fill", label: "Medication", palette: true, color: .red)
        case .food:
            return LegendEntry(icon: "fork.knife", label: "Food", palette: false, color: .brown)
        case .mindfulness:
            return LegendEntry(icon: "figure.mind.and.body", label: "Mindfulness", palette: false, color: .cyan)
        case .workout(_, _, _, let type):
            return LegendEntry(icon: event.iconName, label: type.displayName, palette: false, color: .green)
        case .giSymptom:
            return LegendEntry(icon: GISymptom.timelineSymbol, label: "Symptom", palette: false, color: GISymptom.tint)
        }
    }

    @ViewBuilder
    private func legendItem(entry: LegendEntry) -> some View {
        HStack(spacing: 4) {
            Group {
                if entry.palette {
                    Image(systemName: entry.icon)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.red, .yellow)
                } else {
                    Image(systemName: entry.icon).foregroundStyle(entry.color)
                }
            }
            .font(.system(size: 12))
            Text(entry.label)
        }
    }

    // `hour` = slot START (drives containment, gap-break, sort — unchanged). `plotX` = where the
    // point is drawn on the x-axis (slot CENTER), so the curve sits over the half-hour it summarizes
    // instead of skewing ~15min early. `value` = the slot's robust PEAK (P90), not its mean.
    private struct HourBucket { let hour: Date; let plotX: Date; let value: Double }

    private struct LegendEntry: Identifiable {
        let icon: String
        let label: String
        let palette: Bool
        let color: Color
        var id: String { icon + "|" + label }
    }

    private var chartEvents: [DayEvent] { events }

    // Break the curve across an empty 30-min slot — that *is* a true data gap. Apple's Movement
    // Disorder API emits ~1 sample/min while the Watch is worn, and a slot needs only ONE sample
    // to be "present", so an empty slot means "not worn" (charger / off wrist), never "calm" or
    // sampling jitter. No separate not-worn threshold is needed: the 30-min bucketing already IS
    // the noise filter (jitter can't empty a slot), so the bucket width does the job a threshold
    // otherwise would. Consequence worth knowing: a removal shorter than a slot that leaves a
    // sliver of data in every slot it touches (e.g. off 4:05–4:45 → 4:00 keeps 4:00–4:05, 4:30
    // keeps 4:45–5:00) empties no slot and won't break — fine for charging (≥60 min always fully
    // empties ≥1 slot). This rule can never false-break a worn line (worn ⇒ every slot present).
    // Chart buckets are 10 min (was 30): tremor moves faster than a half-hour, so a 30-min slot
    // smears a rising edge — a late peak gets back-dated onto the slot's start. See design note.
    private static let bucketSeconds: TimeInterval = 10 * 60
    // Break the line across any gap wider than one slot (a not-worn stretch); 1.5× the slot size
    // tolerates exact spacing without false-breaking a worn line, incl. the dayEnd anchor at +10 min.
    private static let gapBreak: TimeInterval = 15 * 60

    // Split 30-min buckets into contiguous runs, cutting wherever consecutive present buckets are
    // more than one slot apart — i.e. ≥1 empty slot sits between them. Each run becomes its own
    // chart series so catmullRom (and any fill) never bridges a slot the Watch didn't report.
    // Shared by both signals so tremor and dyskinesia break on the *same* empty slots — a not-worn
    // stretch shows neither line.
    private func segments(_ buckets: [HourBucket]) -> [(id: Int, points: [HourBucket])] {
        guard !buckets.isEmpty else { return [] }
        var runs: [[HourBucket]] = [[buckets[0]]]
        for b in buckets.dropFirst() {
            if let last = runs[runs.count - 1].last,
               b.hour.timeIntervalSince(last.hour) > Self.gapBreak {
                runs.append([b])
            } else {
                runs[runs.count - 1].append(b)
            }
        }
        return runs.enumerated().map { (id: $0.offset, points: $0.element) }
    }

    private var tremorSegments: [(id: Int, points: [HourBucket])] { segments(hourlyBuckets) }
    private var dyskinesiaSegments: [(id: Int, points: [HourBucket])] { segments(dyskinesiaBuckets) }

    private var hourlyBuckets: [HourBucket] {
        guard !readings.isEmpty else { return [] }
        let cal = Calendar.current
        var slots: [Date: [Double]] = [:]
        for r in readings {
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.timestamp)
            var bucketComps = comps
            bucketComps.minute = ((comps.minute ?? 0) / 10) * 10
            bucketComps.second = 0
            guard let bucket = cal.date(from: bucketComps) else { continue }
            slots[bucket, default: []].append(r.tremorScore)
        }
        // Value = MEAN of the 10-min slot. At this granularity the short window itself localizes the
        // peak (no long-window smearing), and the mean keeps brief-but-real tremor breakthroughs
        // visible instead of discarding them the way a median would — Bhav's call: show spikes, don't
        // hide them. Trade-off accepted: a lone motion-artifact minute nudges a slot up ~0.3. Plotted
        // at slot CENTER. See docs/design/tremor-averaging.md.
        var result = slots.map {
            HourBucket(hour: $0.key,
                       plotX: $0.key.addingTimeInterval(Self.bucketSeconds / 2),
                       value: $0.value.reduce(0, +) / Double($0.value.count))
        }
        .sorted { $0.hour < $1.hour }
        // If the last bucket covers the day's final slot, anchor the curve to dayEnd so it sits
        // flush against the next-day boundary instead of terminating ~5min early. Honest extension.
        if let last = result.last, last.hour >= dayEnd.addingTimeInterval(-Self.bucketSeconds) {
            result.append(HourBucket(hour: dayEnd, plotX: dayEnd, value: last.value))
        }
        return result
    }

    // Same 30-min bucketing as tremor, but each minute's raw `percentLikely` passes
    // through the display mapping (floor + rescale to 0–4) before averaging. Skips the
    // tremor curve's dayEnd-anchor tail — that's a cosmetic edge for the primary signal.
    private var dyskinesiaBuckets: [HourBucket] {
        guard !dyskinesia.isEmpty else { return [] }
        let cal = Calendar.current
        var slots: [Date: [Double]] = [:]
        for r in dyskinesia {
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.startDate)
            var bucketComps = comps
            bucketComps.minute = ((comps.minute ?? 0) / 10) * 10
            bucketComps.second = 0
            guard let bucket = cal.date(from: bucketComps) else { continue }
            slots[bucket, default: []].append(DyskinesiaDisplay.intensity(r.percentLikely))
        }
        // Mean + slot-center + 10-min, matching tremor — both lines share the 0–4 axis and must use
        // the same statistic, or they silently mean different things. See design note.
        return slots.map {
            HourBucket(hour: $0.key,
                       plotX: $0.key.addingTimeInterval(Self.bucketSeconds / 2),
                       value: $0.value.reduce(0, +) / Double($0.value.count))
        }
        .sorted { $0.hour < $1.hour }
    }

    private func yLabel(for level: Int) -> String {
        switch level {
        case 0: return "None"
        case 1: return "Slight"
        case 2: return "Mild"
        case 3: return "Mod"
        case 4: return "Strong"
        default: return ""
        }
    }

    // The sync hint (and its Watch glyph) only makes sense when today's data exists on the
    // Watch but hasn't reached the phone yet — never for a warming-up new user or an old day.
    private var isSyncHint: Bool {
        hasEverHadData && Calendar.current.isDateInToday(dayStart)
    }

    // Empty-state copy depends on *why* there's no data.
    private var emptyMessage: String {
        if !hasEverHadData {
            // Overdue: stop reassuring and point at the usual culprits (Watch app not
            // installed, or Motion & Fitness off).
            if daysSinceFirstEmpty >= 2 {
                return "Still no tremor data. Check that Kampa is installed on your Apple Watch, and that Motion & Fitness is enabled in Settings → Privacy & Security → Motion & Fitness."
            }
            return "Kampa is warming up. Tremor tracking begins after about a day of Watch wear."
        }
        if isSyncHint {
            return "No tremor data yet today.\nOpen Kampa on your Apple Watch for about 30 seconds, with your iPhone nearby, to sync."
        }
        return "No tremor data captured for this day."
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            if isSyncHint {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 28))
                    .foregroundStyle(Insight.brandBlue)
            }
            Text(emptyMessage)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 120).frame(maxWidth: .infinity)
        .onAppear {
            // Stamp the first time we ever show an empty state, so the copy can escalate
            // after a couple of days. Only while truly dataless — clears once data arrives.
            if !hasEverHadData, firstEmptyEpoch == 0 {
                firstEmptyEpoch = Date().timeIntervalSince1970
            } else if hasEverHadData, firstEmptyEpoch != 0 {
                firstEmptyEpoch = 0
            }
        }
    }
}

// MARK: - Glucose (CGM)

/// Continuous-glucose panel — sits directly under Tremor with a matched x-domain so a
/// meal or dose reads straight down across both charts. Display-only (step 1 of the CGM
/// slice): the curve, the 70–180 mg/dL target band shaded, and the same event RuleMarks
/// as the tremor panel. The vertical read across panels IS the gastric-emptying →
/// absorption chain. Collapsible; default expanded (observing it by eye is the whole point
/// right now). Scroll is matched-but-independent (Option A) — the two panels align at the
/// initial position; locking their scroll together is a later iteration.
private struct GlucosePanel: View {
    let samples: [GlucoseSample]
    let events: [DayEvent]
    let dayStart: Date
    let dayEnd: Date
    @Binding var scrollX: Date
    @Binding var selectedTime: Date?
    @AppStorage("dayReview.expanded.glucose") private var expanded = true

    // Break the line across sensor gaps > 15 min so we never draw a straight segment over
    // missing data (warmup / between-sensor / dropout). Each contiguous run becomes its own
    // series, which stops Charts from connecting the ends across the gap.
    private var segments: [(id: Int, points: [GlucoseSample])] {
        guard !samples.isEmpty else { return [] }
        var runs: [[GlucoseSample]] = [[samples[0]]]
        for s in samples.dropFirst() {
            if let last = runs[runs.count - 1].last,
               s.date.timeIntervalSince(last.date) > 15 * 60 {
                runs.append([s])
            } else {
                runs[runs.count - 1].append(s)
            }
        }
        return runs.enumerated().map { (id: $0.offset, points: $0.element) }
    }

    // The distinct HealthKit source(s) feeding today's glucose — shown in the caption so the
    // user knows where it came from (a CGM brand, or their own manual/finger-prick entries).
    private var sourceText: String {
        let names = Set(samples.map(\.source)).sorted()
        guard !names.isEmpty else { return "" }
        return names.count == 1 ? "source: \(names[0])" : "sources: \(names.joined(separator: ", "))"
    }

    // Day's mean glucose — a stable one-number summary for the header (more meaningful for
    // a whole-day review than the last reading before a sensor gap).
    private var dayAverage: Int? {
        guard !samples.isEmpty else { return nil }
        return Int((samples.map(\.value).reduce(0, +) / Double(samples.count)).rounded())
    }

    // Fixed 40–180 frame (broad enough to show a sub-70 low and a post-meal spike without
    // rescaling day-to-day), expanding only if a reading actually falls outside it.
    private var yDomain: ClosedRange<Double> {
        let values = samples.map(\.value)
        let lo = min(40, (values.min() ?? 40) - 5)
        let hi = max(180, (values.max() ?? 180) + 5)
        return lo...hi
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Title + chevron toggle collapse. Kept as its own button so the crosshair
                // pill's × (outside it) doesn't also fire the collapse.
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "drop.fill").foregroundStyle(.pink)
                        Text("Glucose").font(.headline).foregroundStyle(.primary)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if let avg = dayAverage {
                    Text("\(avg) mg/dL avg")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if expanded {
                Chart {
                    // Target-range band (70–140 mg/dL — the non-diabetic metabolic-health
                    // target, matching Lingo's own reference lines) shaded behind the curve.
                    RectangleMark(
                        xStart: .value("Start", dayStart),
                        xEnd: .value("End", dayEnd),
                        yStart: .value("Low", 70),
                        yEnd: .value("High", 140)
                    )
                    .foregroundStyle(Color.green.opacity(0.08))

                    // Same event lines as the tremor panel above (dashed) so a meal/dose
                    // reads straight down across both charts.
                    ForEach(events) { event in
                        RuleMark(x: .value("Event time", event.time))
                            .foregroundStyle(.gray.opacity(0.25))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }

                    // One series per contiguous segment → no line drawn across gaps. An
                    // isolated reading (finger-prick / lone manual entry) is its own 1-point
                    // segment, which a line can't render — draw those as dots so they show.
                    ForEach(segments, id: \.id) { segment in
                        if segment.points.count == 1, let p = segment.points.first {
                            PointMark(
                                x: .value("Time", p.date),
                                y: .value("Glucose", p.value)
                            )
                            .foregroundStyle(Color.pink)
                            .symbolSize(28)
                        } else {
                            ForEach(segment.points, id: \.date) { p in
                                LineMark(
                                    x: .value("Time", p.date),
                                    y: .value("Glucose", p.value),
                                    series: .value("Segment", segment.id)
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(Color.pink)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                    }

                    if let t = selectedTime {
                        RuleMark(x: .value("Selected", t))
                            .foregroundStyle(.gray.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .annotation(position: .top, alignment: .center, spacing: 4,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))) {
                                // Suppressed past `now` (see tremor panel): no measured glucose
                                // in today's future. The rule line stays; only the box hides.
                                if showsCallout(at: t) {
                                    CrosshairCallout(time: t, rows: [
                                        .init(value: glucoseReadout(at: t), label: "", color: .pink)
                                    ])
                                }
                            }
                    }
                }
                .chartYScale(domain: yDomain)
                .chartXScale(domain: dayStart...dayEnd)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 12 * 3600)
                .chartScrollPosition(x: $scrollX)
                .chartXSelection(value: $selectedTime)
                .chartYAxis {
                    AxisMarks(values: [70, 100, 140]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            // Fixed-width gutter (== the tremor panel's) so both plot
                            // rectangles are the same width → the shared x-domain maps to
                            // the same pixels and a meal reads straight down across panels.
                            Text(value.as(Int.self).map { "\($0)" } ?? "")
                                .font(.caption2)
                                .frame(width: DayReviewLayout.yAxisWidth, alignment: .leading)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .frame(height: 160)

                Text("mg/dL · target band 70–140 · \(sourceText)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Glucose at the crosshair time — nearest sample within 10 min, else "—" (a gap the
    /// broken line already shows). Read-only lookup, no interpolation across a gap.
    private func glucoseReadout(at time: Date) -> String {
        guard let s = samples.min(by: {
            abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time))
        }), abs(s.date.timeIntervalSince(time)) < 10 * 60 else { return "— mg/dL" }
        return "\(Int(s.value.rounded())) mg/dL"
    }

    /// Matches the tremor panel: suppress the callout past `now` on today (no measured glucose
    /// in the future), show throughout on past days. The rule line is unaffected.
    private func showsCallout(at time: Date) -> Bool {
        guard Calendar.current.isDateInToday(dayStart) else { return true }
        return time <= Date()
    }

    /// Shown on a CGM user's *gap* day (sensor warmup / between sensors / dropout) so the
    /// panel's absence isn't misread as "glucose is fine" — a known-CGM user expects it here.
    static var gapNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "drop")
                .foregroundStyle(.pink.opacity(0.6)).font(.caption)
            Text("No glucose data for this day.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Crosshair readout

/// Floating callout anchored above the crosshair line (StrivePD-style): the selected time
/// and one bold colored value per signal with its label. Shown while pressing-and-holding a
/// chart; releasing dismisses it. Shared by Tremor (two rows) and Glucose (one row).
///
/// Background is an explicit `systemBackground` (NOT `.regularMaterial`, which rendered dark
/// and unreadable over the light-mode chart) so text stays high-contrast in both modes.
private struct CrosshairCallout: View {
    struct Row: Identifiable {
        let value: String
        let label: String
        let color: Color
        var id: String { label }
    }
    let time: Date
    let rows: [Row]

    var body: some View {
        // Single row (time + values) keeps the callout short, so when it overflows upward
        // past the plot it lands just above the event glyphs without clipping at the card top.
        HStack(spacing: 8) {
            Text(time.formatted(.dateTime.hour().minute()))
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(rows) { row in
                HStack(spacing: 4) {
                    Text(row.value).font(.subheadline.weight(.semibold))
                        .foregroundStyle(row.color)
                    if !row.label.isEmpty {
                        Text(row.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .fixedSize()
    }
}

// MARK: - Sleep stages

private struct SleepStagesPanel: View {
    let sleep: SleepBreakdown?
    let daylightMinutes: Double?
    // Collapsed by default: total sleep already shows in the glance card, so the
    // hypnogram detail is opt-in. The interruptions badge stays visible collapsed —
    // it's the one sleep datum not surfaced elsewhere.
    @AppStorage("dayReview.expanded.sleep") private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "bed.double.fill").foregroundStyle(.indigo)
                    Text("Sleep").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    if let s = sleep, s.interruptions > 0 {
                        Label("\(s.interruptions) interruption\(s.interruptions == 1 ? "" : "s")",
                              systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange).labelStyle(.titleAndIcon)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
            if let s = sleep, s.hasData, !s.stages.isEmpty {
                Chart {
                    ForEach(s.stages) { seg in
                        BarMark(
                            xStart: .value("Start", seg.start),
                            xEnd: .value("End", seg.end),
                            y: .value("Stage", seg.stage.displayName)
                        )
                        .foregroundStyle(stageColor(seg.stage))
                        .cornerRadius(2)
                    }
                }
                .chartYScale(domain: SleepStage.allCases.map { $0.displayName })
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name).font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 130)

                HStack(spacing: 16) {
                    sleepStat("Bedtime", s.bedtime?.formatted(.dateTime.hour().minute()) ?? "—")
                    sleepStat("Wake", s.wakeTime?.formatted(.dateTime.hour().minute()) ?? "—")
                    sleepStat("Total", formatHours(s.totalAsleepHours))
                    sleepStat("Deep", formatHours(s.deepHours))
                    sleepStat("REM", formatHours(s.remHours))
                }
                .font(.caption)
            } else {
                Text("No sleep recorded for this night.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }

            if let mins = daylightMinutes, mins > 0 {
                Divider().padding(.vertical, 2)
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(.orange).font(.caption)
                    Text("\(daylightText(mins)) in daylight")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            }   // end if expanded
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func daylightText(_ mins: Double) -> String {
        if mins < 60 { return "\(Int(mins))m" }
        let h = Int(mins / 60); let m = Int(mins) % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func stageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return .orange
        case .rem:   return .cyan
        case .core:  return .blue
        case .deep:  return .indigo
        }
    }

    private func sleepStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
        }
    }

    private func formatHours(_ h: Double) -> String {
        if h <= 0 { return "—" }
        let hours = Int(h); let minutes = Int((h - Double(hours)) * 60)
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

// MARK: - Flow layout

/// Left-to-right layout that wraps to the next line when it runs out of width,
/// so the legend grows gracefully on a busy day instead of clipping.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 14
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxLineWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxLineWidth = max(maxLineWidth, x - spacing)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : maxLineWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                      anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#if DEBUG
// Synthetic data only — exercises the dyskinesia overlay's rendering, which can't be
// seen on Bhav's own data (~0 dyskinesia). Tremor sawtooths DOWN after each dose;
// dyskinesia likelihood peaks mid-ON — the inverse "seesaw" the overlay exists to show.
// The dyskinesia `percentLikely` deliberately straddles DyskinesiaDisplay.noiseFloor so
// the floor (peaks clear it, background doesn't) is visible too.
#Preview("Tremor + dyskinesia seesaw") {
    let cal = Calendar.current
    let dayStart = cal.startOfDay(for: Date())
    let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
    func at(_ h: Int, _ m: Int) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: dayStart) ?? dayStart
    }
    let doses = [at(8, 0), at(12, 0)]
    // Smooth bell centered `center` min after a dose — keeps catmullRom from overshooting
    // the way it does on hard steps (which is what made the preview look chaotic).
    func bell(_ x: Double, center: Double, width: Double) -> Double {
        exp(-pow((x - center) / width, 2))
    }

    var tremor: [TremorReading] = []
    var dysk: [DyskinesiaReading] = []
    var t = at(6, 0)
    let endSampling = at(16, 0)
    while t < endSampling {
        // Minutes since the most recent prior dose (large before any dose).
        let sinceDose = doses.filter { $0 <= t }.map { t.timeIntervalSince($0) / 60 }.min() ?? 600
        // Tremor: ~2.8 OFF, dips toward ~0.4 at peak ON (~90 min post-dose).
        let tremorScore = max(0.3, 2.8 - 2.4 * bell(sinceDose, center: 90, width: 60))
        tremor.append(TremorReading(timestamp: t, tremorScore: tremorScore, dyskinesiaScore: 0))
        // Dyskinesia likelihood: a smooth bump at peak-dose ON (~100 min), opposite the
        // tremor trough. Baseline 0.2 stays *below* the noise floor (→ 0); the peak (~0.9)
        // clears it — so the floor is visible in the render too.
        let likely = 0.20 + 0.70 * bell(sinceDose, center: 100, width: 45)
        dysk.append(DyskinesiaReading(startDate: t, endDate: t.addingTimeInterval(60), percentLikely: likely))
        t = t.addingTimeInterval(10 * 60)
    }
    let events: [DayEvent] = doses.map { .medication(id: UUID(), time: $0, name: "Sinemet") }

    return ScrollView {
        TremorTimelinePanel(
            readings: tremor,
            dyskinesia: dysk,
            hasEverHadData: true,
            events: events,
            dayStart: dayStart,
            dayEnd: dayEnd,
            scrollX: .constant(dayStart),
            selectedTime: .constant(nil)
        )
        .padding()
    }
}
#endif
