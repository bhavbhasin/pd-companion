import SwiftUI
import SwiftData
import Charts
import HealthKit

struct DayInReviewView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var connectivity: PhoneConnectivityManager
    @Query(sort: \TremorReading.timestamp, order: .forward) private var allReadings: [TremorReading]
    @State private var selectedDate: Date = Calendar.current.startOfDay(
        for: Date().addingTimeInterval(-86400)
    )
    @State private var showingWatchStatus = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateHeader
                    GlanceCard(
                        sleep: healthKit.daySleep,
                        events: healthKit.dayEvents,
                        tremorReadings: dayReadings,
                        hrv: healthKit.dayHRV,
                        daylightMinutes: healthKit.dayDaylightMinutes
                    )
                    TremorTimelinePanel(
                        readings: dayReadings,
                        events: healthKit.dayEvents,
                        dayStart: dayStart,
                        dayEnd: dayEnd
                    )
                    SleepStagesPanel(
                        sleep: healthKit.daySleep
                    )
                    ObservationsPlaceholder()
                }
                .padding()
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingWatchStatus = true
                    } label: {
                        Image(systemName: watchStatus.icon)
                            .foregroundStyle(watchStatus.color)
                            .accessibilityLabel(watchStatus.label)
                    }
                }
            }
            .alert("Watch Status", isPresented: $showingWatchStatus) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(watchStatus.label)
            }
            .task(id: selectedDate) {
                await healthKit.fetchDayInReview(for: selectedDate)
            }
            .refreshable {
                await healthKit.fetchDayInReview(for: selectedDate)
            }
        }
    }

    private var watchStatus: (icon: String, color: Color, label: String) {
        if !connectivity.isWatchPaired {
            return ("applewatch.slash", .secondary, "No Apple Watch paired")
        }
        if !connectivity.isWatchAppInstalled {
            return ("applewatch.slash", .secondary, "Watch app not installed")
        }
        if connectivity.isWatchReachable {
            return ("applewatch.radiowaves.left.and.right", .green, "Watch app active")
        }
        return ("applewatch", .secondary, "Watch paired (app inactive)")
    }

    private var dayStart: Date { Calendar.current.startOfDay(for: selectedDate) }
    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
    }

    private var dayReadings: [TremorReading] {
        allReadings.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
    }

    private var dateHeader: some View {
        HStack {
            Button {
                shiftDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(headerTitle)
                    .font(.headline)
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                shiftDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(isAtToday)
            .opacity(isAtToday ? 0.3 : 1)
        }
    }

    private var headerTitle: String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        if cal.isDate(selectedDate, inSameDayAs: today) { return "Today" }
        if cal.isDate(selectedDate, inSameDayAs: yesterday) { return "Yesterday" }
        return selectedDate.formatted(.relative(presentation: .named))
    }

    private var isAtToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: Date())
    }

    private func shiftDay(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if next > today { return }
        selectedDate = Calendar.current.startOfDay(for: next)
    }
}

private struct GlanceCard: View {
    let sleep: SleepBreakdown?
    let events: [DayEvent]
    let tremorReadings: [TremorReading]
    let hrv: Double?
    let daylightMinutes: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                stat(
                    icon: "bed.double.fill", color: .indigo,
                    value: sleepValue, sub: "Total sleep"
                )
                stat(
                    icon: "waveform.path.ecg", color: tremorColor,
                    value: tremorValue, sub: tremorLabel
                )
            }
            HStack(spacing: 16) {
                stat(
                    icon: "pill.fill", color: .red, secondaryColor: .yellow,
                    value: "\(medicationCount)", sub: medicationLabel
                )
                stat(
                    icon: workoutIcon, color: .green,
                    value: workoutValue, sub: workoutSub
                )
            }
            HStack(spacing: 16) {
                stat(
                    icon: "bolt.heart.fill", color: .purple,
                    value: hrvValue, sub: "HRV"
                )
                stat(
                    icon: "sun.max.fill", color: .orange,
                    value: daylightValue, sub: "In daylight"
                )
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var hrvValue: String {
        guard let hrv else { return "—" }
        return "\(Int(hrv)) ms"
    }

    private var daylightValue: String {
        guard let mins = daylightMinutes, mins > 0 else { return "—" }
        if mins < 60 { return "\(Int(mins))m" }
        let h = Int(mins / 60)
        let m = Int(mins) % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func stat(
        icon: String, color: Color, secondaryColor: Color? = nil,
        value: String, sub: String
    ) -> some View {
        HStack(spacing: 10) {
            Group {
                if let secondaryColor {
                    Image(systemName: icon)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(color, secondaryColor)
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
            }
            .font(.title3)
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline)
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        guard let v = avgTremor else { return "No tremor data" }
        switch v {
        case ..<0.5: return "Tremor avg: None"
        case ..<1.5: return "Tremor avg: Slight"
        case ..<2.5: return "Tremor avg: Mild"
        case ..<3.5: return "Tremor avg: Moderate"
        default: return "Tremor avg: Strong"
        }
    }

    private var tremorColor: Color {
        guard let v = avgTremor else { return .secondary }
        switch v {
        case ..<1: return .green
        case ..<2: return .yellow
        case ..<3: return .orange
        default: return .red
        }
    }

    private var medicationCount: Int {
        events.filter { if case .medication = $0 { return true } else { return false } }.count
    }

    private var medicationLabel: String {
        let names: [String] = events.compactMap { event in
            if case .medication(_, _, let name) = event { return name }
            return nil
        }
        let unique = Set(names.filter { !$0.isEmpty })
        if unique.count == 1, let only = unique.first {
            return medicationCount == 1 ? "\(only) dose" : "\(only) doses"
        }
        return medicationCount == 1 ? "Dose" : "Doses"
    }

    private var workouts: [(label: String, duration: TimeInterval, type: HKWorkoutActivityType)] {
        events.compactMap { event in
            if case .workout(_, _, let dur, let type) = event {
                return (type.displayName, dur, type)
            }
            return nil
        }
    }

    private var workoutValue: String {
        let ws = workouts
        if ws.isEmpty { return "—" }
        if ws.count == 1 { return formatDuration(ws[0].duration) }
        let total = ws.reduce(0.0) { $0 + $1.duration }
        return "\(ws.count) · \(formatDuration(total))"
    }

    private var workoutSub: String {
        let ws = workouts
        if ws.isEmpty { return "No workouts" }
        if ws.count == 1 { return ws[0].label }
        let names = ws.map { $0.label }
        return names.joined(separator: ", ")
    }

    private var workoutIcon: String {
        let ws = workouts
        guard let first = ws.first else { return "figure.run" }
        switch first.type {
        case .taiChi, .yoga, .pilates, .mindAndBody, .flexibility:
            return "figure.mind.and.body"
        case .pickleball, .tennis, .tableTennis: return "figure.tennis"
        case .running: return "figure.run"
        case .walking, .hiking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        default: return "figure.run"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMin = Int(seconds / 60)
        let h = totalMin / 60
        let m = totalMin % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

private struct TremorTimelinePanel: View {
    let readings: [TremorReading]
    let events: [DayEvent]
    let dayStart: Date
    let dayEnd: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tremor")
                .font(.headline)
            if hourlyBuckets.isEmpty {
                emptyState("No tremor data captured for this day.")
            } else {
                Chart {
                    ForEach(events) { event in
                        RuleMark(x: .value("Event time", event.time))
                            .foregroundStyle(.gray.opacity(0.25))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    ForEach(events) { event in
                        PointMark(
                            x: .value("Event time", event.time),
                            y: .value("Event lane", 4.3)
                        )
                        .symbol {
                            eventIcon(for: event)
                        }
                    }
                    ForEach(hourlyBuckets, id: \.hour) { bucket in
                        LineMark(
                            x: .value("Time", bucket.hour),
                            y: .value("Tremor", bucket.value)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
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
                                Text(label(for: v)).font(.caption2)
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
                .frame(height: 200)

                if !events.isEmpty {
                    HStack(spacing: 12) {
                        legendItem(systemImage: "pill.fill", palette: (.red, .yellow), label: "Medication")
                        legendItem(systemImage: "figure.run", solid: .green, label: "Workout")
                        legendItem(systemImage: "brain.head.profile", solid: .cyan, label: "Mindfulness")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                .font(.system(size: 13))
        case .workout:
            Image(systemName: event.iconName)
                .foregroundStyle(.green)
                .font(.system(size: 13))
        case .mindfulness:
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.cyan)
                .font(.system(size: 13))
        }
    }

    @ViewBuilder
    private func legendItem(systemImage: String, palette: (Color, Color)? = nil, solid: Color? = nil, label: String) -> some View {
        HStack(spacing: 4) {
            Group {
                if let palette {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(palette.0, palette.1)
                } else if let solid {
                    Image(systemName: systemImage)
                        .foregroundStyle(solid)
                }
            }
            .font(.system(size: 10))
            Text(label)
        }
    }

    private struct HourBucket {
        let hour: Date
        let value: Double
    }

    private var hourlyBuckets: [HourBucket] {
        guard !readings.isEmpty else { return [] }
        let cal = Calendar.current
        var sums: [Date: (sum: Double, count: Int)] = [:]
        for r in readings {
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: r.timestamp)
            guard let bucket = cal.date(from: comps) else { continue }
            let cur = sums[bucket] ?? (0, 0)
            sums[bucket] = (cur.sum + r.tremorScore, cur.count + 1)
        }
        return sums.map { HourBucket(hour: $0.key, value: $0.value.sum / Double($0.value.count)) }
            .sorted { $0.hour < $1.hour }
    }

    private func label(for level: Int) -> String {
        switch level {
        case 0: return "None"
        case 1: return "Slight"
        case 2: return "Mild"
        case 3: return "Mod"
        case 4: return "Strong"
        default: return ""
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(height: 120)
            .frame(maxWidth: .infinity)
    }
}

private struct SleepStagesPanel: View {
    let sleep: SleepBreakdown?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sleep")
                    .font(.headline)
                Spacer()
                if let s = sleep, s.interruptions > 0 {
                    Label("\(s.interruptions) interruption\(s.interruptions == 1 ? "" : "s")",
                          systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
            }

            if let s = sleep, s.hasData, !s.stages.isEmpty {
                Chart {
                    ForEach(s.stages) { seg in
                        BarMark(
                            xStart: .value("Start", seg.start),
                            xEnd: .value("End", seg.end),
                            y: .value("Stage", seg.stage.displayName)
                        )
                        .foregroundStyle(color(for: seg.stage))
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake: return .orange
        case .rem: return .cyan
        case .core: return .blue
        case .deep: return .indigo
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
        let hours = Int(h)
        let minutes = Int((h - Double(hours)) * 60)
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

private struct ObservationsPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text("Observations")
                    .font(.headline)
            }
            Text("Computed correlations between tremor and sleep, medication, and activity will appear here once enough data has been collected to identify reliable patterns.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
