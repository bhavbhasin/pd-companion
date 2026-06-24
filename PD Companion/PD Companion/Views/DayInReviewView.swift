import SwiftUI
import SwiftData
import Charts
import HealthKit

struct DayInReviewView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var connectivity: PhoneConnectivityManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TremorReading.timestamp, order: .forward) private var allReadings: [TremorReading]
    @Query(sort: \FoodEvent.timestamp, order: .forward) private var allFoodEvents: [FoodEvent]
    // Default to today: the app is used through the day for logging (food, meds), so
    // the view should reflect "now" — seeing yesterday right after logging something
    // today reads as a bug. Today's data is partial (the chart fills as the day goes),
    // which is honest; the date chevrons still reach yesterday for a complete-day review.
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showingDatePicker = false
    @State private var showingLogSheet = false
    @State private var selectedEvent: DayEvent?
    @State private var showingBackup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlanceCard(
                        sleep: healthKit.daySleep,
                        tremorReadings: dayReadings,
                        hrv: healthKit.dayHRV
                    )
                    TremorTimelinePanel(
                        readings: dayReadings,
                        hasEverHadData: !allReadings.isEmpty,
                        events: allDayEvents,
                        dayStart: dayStart,
                        dayEnd: dayEnd,
                        onEventTap: { selectedEvent = $0 }
                    )
                    SleepStagesPanel(
                        sleep: healthKit.daySleep,
                        daylightMinutes: healthKit.dayDaylightMinutes
                    )
                    ObservationsPanel(
                        readings: dayReadings,
                        events: allDayEvents,
                        foodEvents: dayFoodEvents,
                        sleep: healthKit.daySleep,
                        hrvSamples: healthKit.dayHRVSamples,
                        daylightMinutes: healthKit.dayDaylightMinutes
                    )
                }
                .padding()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                dateHeader
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingLogSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Log entry")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingBackup = true
                    } label: {
                        Image(systemName: "externaldrive.badge.icloud")
                            .accessibilityLabel("Backup and export")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        InsightsView()
                    } label: {
                        Image(systemName: "lightbulb.max")
                            .accessibilityLabel("Insights")
                    }
                }
            }
            .sheet(isPresented: $showingLogSheet) {
                LogEntrySheet { loggedDate in
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
                await healthKit.fetchDayInReview(for: selectedDate)
            }
            .refreshable {
                connectivity.requestFreshTremorData()
                await healthKit.fetchDayInReview(for: selectedDate)
            }
        }
    }

    private var dayStart: Date { Calendar.current.startOfDay(for: selectedDate) }
    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
    }

    private var dayReadings: [TremorReading] {
        allReadings.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
    }

    private var dayFoodEvents: [FoodEvent] {
        allFoodEvents.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
    }

    private var allDayEvents: [DayEvent] {
        let food = dayFoodEvents.map {
            DayEvent.food(id: $0.id, time: $0.timestamp,
                          userDescription: $0.userDescription ?? "", attributes: $0.attributes)
        }
        return (healthKit.dayEvents + food).sorted { $0.time < $1.time }
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
        guard let latest = allReadings.last?.timestamp else {
            return "No tremor data yet"
        }
        let style: Date.FormatStyle = Calendar.current.isDateInToday(latest)
            ? .dateTime.hour().minute()
            : .dateTime.month().day().hour().minute()
        return "Updated \(latest.formatted(style))"
    }

    private var syncStatusColor: Color {
        guard let latest = allReadings.last?.timestamp else { return .secondary }
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

// MARK: - Glance card

private struct GlanceCard: View {
    let sleep: SleepBreakdown?
    let tremorReadings: [TremorReading]
    let hrv: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                stat(icon: "bed.double.fill", color: .indigo,
                     value: sleepValue, sub: "Total sleep")
                stat(icon: "waveform.path.ecg", color: tremorColor,
                     value: tremorValue, sub: tremorLabel)
            }
            HStack(spacing: 16) {
                stat(icon: "bolt.heart.fill", color: .purple,
                     value: hrvValue, sub: hrvLabel)
                stat(icon: "waveform.path", color: dyskinesiaColor,
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
        guard let v = avgTremor else { return "No Apple Watch data" }
        switch v {
        case ..<0.5: return "Tremor avg: None"
        case ..<1.5: return "Tremor avg: Slight"
        case ..<2.5: return "Tremor avg: Mild"
        case ..<3.5: return "Tremor avg: Moderate"
        default:     return "Tremor avg: Strong"
        }
    }

    private var tremorColor: Color {
        guard let v = avgTremor else { return .secondary }
        switch v {
        case ..<1: return .green
        case ..<2: return .yellow
        case ..<3: return .orange
        default:   return .red
        }
    }

    private var hrvValue: String {
        guard let hrv else { return "—" }
        return "\(Int(hrv)) ms"
    }

    // SDNN HRV is sampled by the Apple Watch (opportunistically during the day,
    // heavily during sleep). An empty tile means no watch reading for the day,
    // not a broken metric — say so explicitly.
    private var hrvLabel: String {
        hrv == nil ? "No Apple Watch data" : "HRV"
    }

    private var avgDyskinesia: Double? {
        guard !tremorReadings.isEmpty else { return nil }
        return tremorReadings.reduce(0.0) { $0 + $1.dyskinesiaScore } / Double(tremorReadings.count)
    }

    private var dyskinesiaValue: String {
        guard let v = avgDyskinesia else { return "—" }
        return String(format: "%.1f", v)
    }

    private var dyskinesiaLabel: String {
        guard let v = avgDyskinesia else { return "No Apple Watch data" }
        switch v {
        case ..<0.5: return "Dyskinesia: None"
        case ..<1.5: return "Dyskinesia: Slight"
        case ..<2.5: return "Dyskinesia: Mild"
        case ..<3.5: return "Dyskinesia: Moderate"
        default:     return "Dyskinesia: Strong"
        }
    }

    private var dyskinesiaColor: Color {
        guard let v = avgDyskinesia else { return .secondary }
        switch v {
        case ..<0.5: return .secondary
        case ..<1.5: return .yellow
        case ..<2.5: return .orange
        default:     return .pink
        }
    }
}

// MARK: - Tremor timeline

private struct TremorTimelinePanel: View {
    let readings: [TremorReading]
    let hasEverHadData: Bool
    let events: [DayEvent]
    let dayStart: Date
    let dayEnd: Date
    var onEventTap: (DayEvent) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tremor").font(.headline)
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
                    ForEach(chartBuckets, id: \.hour) { bucket in
                        AreaMark(
                            x: .value("Time", bucket.hour),
                            y: .value("Tremor", bucket.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.35), Color.blue.opacity(0.05)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }
                    ForEach(chartBuckets, id: \.hour) { bucket in
                        LineMark(
                            x: .value("Time", bucket.hour),
                            y: .value("Tremor", bucket.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYScale(domain: 0...4.6)
                .chartXScale(domain: dayStart...dayEnd)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 12 * 3600)
                .chartScrollPosition(initialX: dayStart)
                .chartYAxis {
                    AxisMarks(values: [0, 1, 2, 3, 4]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(yLabel(for: v)).font(.caption2)
                            }
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
        }
    }

    private func tapOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame {
                let plotFrame = geometry[anchor]
                VStack(spacing: 0) {
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
            return LegendEntry(icon: "figure.mind.and.body", label: "Meditation", palette: false, color: .cyan)
        case .workout(_, _, _, let type):
            return LegendEntry(icon: event.iconName, label: type.displayName, palette: false, color: .green)
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

    private struct HourBucket { let hour: Date; let value: Double }

    private struct LegendEntry: Identifiable {
        let icon: String
        let label: String
        let palette: Bool
        let color: Color
        var id: String { icon + "|" + label }
    }

    private var chartEvents: [DayEvent] { events }

    private var chartBuckets: [HourBucket] {
        hourlyBuckets
    }

    private var hourlyBuckets: [HourBucket] {
        guard !readings.isEmpty else { return [] }
        let cal = Calendar.current
        var sums: [Date: (sum: Double, count: Int)] = [:]
        for r in readings {
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.timestamp)
            var bucketComps = comps
            bucketComps.minute = (comps.minute ?? 0) >= 30 ? 30 : 0
            bucketComps.second = 0
            guard let bucket = cal.date(from: bucketComps) else { continue }
            let cur = sums[bucket] ?? (0, 0)
            sums[bucket] = (cur.sum + r.tremorScore, cur.count + 1)
        }
        var result = sums.map { HourBucket(hour: $0.key, value: $0.value.sum / Double($0.value.count)) }
            .sorted { $0.hour < $1.hour }
        // If the last bucket covers the day's final half-hour, anchor the curve
        // to dayEnd so it sits flush against the next-day boundary instead of
        // terminating ~15min early. Honest extension — same value, full coverage.
        if let last = result.last, last.hour >= dayEnd.addingTimeInterval(-30 * 60) {
            result.append(HourBucket(hour: dayEnd, value: last.value))
        }
        return result
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
    }
}

// MARK: - Sleep stages

private struct SleepStagesPanel: View {
    let sleep: SleepBreakdown?
    let daylightMinutes: Double?
    // Collapsed by default: total sleep already shows in the glance card, so the
    // hypnogram detail is opt-in. The interruptions badge stays visible collapsed —
    // it's the one sleep datum not surfaced elsewhere.
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
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
