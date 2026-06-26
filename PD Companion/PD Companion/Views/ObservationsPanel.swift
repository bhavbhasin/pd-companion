import SwiftUI
import HealthKit

// MARK: - DayObservation model

struct DayObservation: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let headline: String
    let detail: String?
    let sentiment: Sentiment
    // Representative time, used to order the panel chronologically
    // (night → daytime events → end-of-day summaries). Defaults late so
    // anything unanchored sinks to the bottom rather than jumping to the top.
    var sortDate: Date = .distantFuture

    /// Returns a copy anchored to `date` for chronological ordering.
    func at(_ date: Date) -> DayObservation {
        var copy = self
        copy.sortDate = date
        return copy
    }

    enum Sentiment {
        case positive, negative, neutral, informational

        var accent: Color {
            switch self {
            case .positive:      return .green
            case .negative:      return .orange
            case .neutral:       return .secondary
            case .informational: return .blue
            }
        }
    }
}

// MARK: - Engine
//
// Design note: this is a single-day, rule-based engine. With one day of data it
// can describe *what co-occurred*, but it cannot prove *what caused what* — a single
// pill-then-walk or a missed-dose-then-coffee can't be statistically untangled from
// one instance. So the language here is deliberately temporal/contextual, not causal,
// and it guards against the two most common misattributions (overlapping dose+activity,
// and food "effects" that are really pre-dose wearing-off). Real attribution is the
// job of the cross-day correlation engine; this panel only surfaces hypotheses.

struct ObservationEngine {

    static func generate(
        readings: [TremorReading],
        events: [DayEvent],
        foodEvents: [FoodEvent],
        sleep: SleepBreakdown?,
        hrvSamples: [HRVSample],
        daylightMinutes: Double?
    ) -> [DayObservation] {
        guard !readings.isEmpty else { return [] }

        let doseTimes: [Date] = events.compactMap {
            if case .medication(_, let time, _) = $0 { return time }
            return nil
        }

        let dayStart = Calendar.current.startOfDay(for: readings.map(\.timestamp).min() ?? Date())
        let dayEnd = dayStart.addingTimeInterval(86400)

        var result: [DayObservation] = []
        result += medicationAndExerciseObservations(readings: readings, events: events)
        result += dyskinesiaDoseObservations(readings: readings, events: events)
        result += tremorTrajectoryObservation(readings: readings, anchor: dayEnd)
        result += foodEvents.filter { hasCaffeine($0) }.compactMap {
            foodRiseObservation(event: $0, readings: readings, doseTimes: doseTimes,
                                factorLabel: "caffeine", icon: "cup.and.saucer.fill",
                                mechanismNote: "")
        }
        result += foodEvents.filter { hasSugar($0) }.compactMap {
            foodRiseObservation(event: $0, readings: readings, doseTimes: doseTimes,
                                factorLabel: "sugar", icon: "fork.knife",
                                mechanismNote: "Glycemic swings can affect tremor in PD. ")
        }
        result += hrvTremorObservation(readings: readings, hrvSamples: hrvSamples, anchor: dayEnd)
        result += sleepObservations(sleep: sleep, daylightMinutes: daylightMinutes, anchor: dayStart)

        // Chronological: night (sleep/daylight) → daytime events → end-of-day summaries.
        return result.sorted { $0.sortDate < $1.sortDate }
    }

    // MARK: Medication + exercise (with confounder guard)
    //
    // If a dose and a workout share a response window we can't credit either one,
    // so we emit a single combined note instead of two competing claims. Only the
    // doses/workouts that *don't* overlap get a standalone observation.

    private static func medicationAndExerciseObservations(
        readings: [TremorReading], events: [DayEvent]
    ) -> [DayObservation] {
        let doses: [(time: Date, name: String)] = events.compactMap {
            if case .medication(_, let time, let name) = $0 { return (time, name ?? "dose") }
            return nil
        }
        let workouts: [(start: Date, end: Date, name: String)] = events.compactMap {
            if case .workout(_, let start, let dur, let type) = $0 {
                return (start, start.addingTimeInterval(dur), type.displayName)
            }
            return nil
        }

        var out: [DayObservation] = []
        var confoundedDoses = Set<Int>()
        var confoundedWorkouts = Set<Int>()

        // Combined notes: a dose landing from 30 min before the workout starts to
        // 90 min after it ends shares the tremor response window with the activity.
        for (wi, w) in workouts.enumerated() {
            guard let di = doses.firstIndex(where: { dose in
                dose.time >= w.start.addingTimeInterval(-1800) &&
                dose.time <= w.end.addingTimeInterval(5400)
            }) else { continue }

            confoundedWorkouts.insert(wi)
            confoundedDoses.insert(di)

            let anchor = min(w.start, doses[di].time)
            let pre = windowAvg(readings, from: anchor.addingTimeInterval(-1800), to: anchor)
            let post = windowAvg(readings,
                                 from: w.end.addingTimeInterval(1800),
                                 to: w.end.addingTimeInterval(5400))
            guard let pre, let post, pre > 0.1 else { continue }

            let pct = (pre - post) / pre * 100
            // Same magnitude floor as the standalone branches: ignore noise-floor swings
            // where neither side reaches Slight (1.0) or the absolute change is < 0.5.
            guard abs(pct) >= 15, max(pre, post) >= 1.0, abs(pre - post) >= 0.5 else { continue }
            let dir = pct > 0 ? "lower" : "higher"
            out.append(DayObservation(
                icon: "pill.fill",
                iconColor: .secondary,
                headline: "\(doses[di].name.capitalized) and \(w.name.lowercased()) overlapped — tremor \(dir) afterward",
                detail: "Avg \(fmt(pre)) before → \(fmt(post)) after. The dose and the activity were too close together to credit either one — watch days you do just one.",
                sentiment: .neutral
            ).at(anchor))
        }

        // Standalone workouts
        for (wi, w) in workouts.enumerated() where !confoundedWorkouts.contains(wi) {
            let pre = windowAvg(readings, from: w.start.addingTimeInterval(-1800), to: w.start)
            let post = windowAvg(readings,
                                 from: w.end.addingTimeInterval(1800),
                                 to: w.end.addingTimeInterval(5400))
            guard let pre, let post, pre > 0.1 else { continue }
            let pct = (pre - post) / pre * 100
            if pct >= 15, pre >= 1.0, pre - post >= 0.5 {
                out.append(DayObservation(
                    icon: "figure.run", iconColor: .green,
                    headline: "Tremor fell \(Int(pct))% after \(w.name.lowercased())",
                    detail: "Avg \(fmt(pre)) before → \(fmt(post)) in the hour after the session. One day isn't proof — watch whether it holds.",
                    sentiment: .positive
                ).at(w.start))
            } else if pct <= -15, post >= 1.0, post - pre >= 0.5 {
                out.append(DayObservation(
                    icon: "figure.run", iconColor: .orange,
                    headline: "Tremor rose after \(w.name.lowercased())",
                    detail: "Avg \(fmt(pre)) before → \(fmt(post)) after. May settle over the next few hours.",
                    sentiment: .neutral
                ).at(w.start))
            }
        }

        // Standalone doses
        for (di, dose) in doses.enumerated() where !confoundedDoses.contains(di) {
            let pre = windowAvg(readings, from: dose.time.addingTimeInterval(-1800), to: dose.time)
            let post = windowAvg(readings,
                                 from: dose.time.addingTimeInterval(1800),
                                 to: dose.time.addingTimeInterval(5400))
            guard let pre, let post, pre > 0.1 else { continue }
            let pct = (pre - post) / pre * 100
            let timeStr = dose.time.formatted(.dateTime.hour().minute())
            let name = dose.name.capitalized
            // Magnitude floor: only call a change real when the *meaningful* side reaches
            // at least Slight (1.0) AND the absolute swing is >= 0.5. Without this, a
            // noise-floor wiggle (e.g. 0.1 -> 0.4, both well below Slight) trips a false
            // "wearing-off" because the tiny pre denominator inflates the percentage.
            // Mirrors the peak-dose dyskinesia branch's post>=0.5 / post-pre>=0.5 gate.
            if pct >= 15, pre >= 1.0, pre - post >= 0.5 {
                out.append(DayObservation(
                    icon: "pill.fill", iconColor: .green,
                    headline: "Tremor fell \(Int(pct))% after \(name) at \(timeStr)",
                    detail: "Avg \(fmt(pre)) before → \(fmt(post)) in the 30–90 min window after.",
                    sentiment: .positive
                ).at(dose.time))
            } else if pct <= -15, post >= 1.0, post - pre >= 0.5 {
                out.append(DayObservation(
                    icon: "pill.fill", iconColor: .orange,
                    headline: "Tremor rose after \(name) at \(timeStr)",
                    detail: "Avg \(fmt(pre)) before → \(fmt(post)) after — may indicate wearing-off before the next dose.",
                    sentiment: .neutral
                ).at(dose.time))
            }
        }

        return out
    }

    // MARK: Peak-dose dyskinesia
    //
    // Inverted from tremor: dyskinesia (levodopa-induced involuntary movement)
    // tends to *rise* near peak dose, 30–120 min after taking it. Gated on an
    // absolute floor so near-zero readings don't fire noise.

    private static func dyskinesiaDoseObservations(
        readings: [TremorReading], events: [DayEvent]
    ) -> [DayObservation] {
        let doses: [(time: Date, name: String)] = events.compactMap {
            if case .medication(_, let time, let name) = $0 { return (time, name ?? "dose") }
            return nil
        }
        return doses.compactMap { dose in
            let pre = windowAvg(readings,
                                from: dose.time.addingTimeInterval(-1800),
                                to: dose.time, metric: \.dyskinesiaScore)
            let post = windowAvg(readings,
                                 from: dose.time.addingTimeInterval(1800),
                                 to: dose.time.addingTimeInterval(7200), metric: \.dyskinesiaScore)
            guard let pre, let post, post >= 0.5, post - pre >= 0.5 else { return nil }
            let timeStr = dose.time.formatted(.dateTime.hour().minute())
            return DayObservation(
                icon: "waveform.path", iconColor: .pink,
                headline: "Dyskinesia rose after \(dose.name.capitalized) at \(timeStr)",
                detail: "Avg \(fmt(pre)) before → \(fmt(post)) in the 30–120 min window after. Involuntary movement that peaks after a dose is typical peak-dose dyskinesia — note whether it eases as the dose wears off.",
                sentiment: .neutral
            ).at(dose.time)
        }
    }

    // MARK: Tremor trajectory (morning / afternoon / evening)

    private static func tremorTrajectoryObservation(readings: [TremorReading], anchor: Date) -> [DayObservation] {
        let cal = Calendar.current

        func avg(hour range: Range<Int>) -> Double? {
            let subset = readings.filter { range.contains(cal.component(.hour, from: $0.timestamp)) }
            guard subset.count >= 3 else { return nil }
            return subset.map(\.tremorScore).reduce(0, +) / Double(subset.count)
        }

        let rawPeriods: [(String, Double?)] = [
            ("morning", avg(hour: 6..<12)),
            ("afternoon", avg(hour: 12..<18)),
            ("evening", avg(hour: 18..<23))
        ]
        let periods: [(name: String, avg: Double)] = rawPeriods.compactMap { pair in
            guard let a = pair.1 else { return nil }
            return (pair.0, a)
        }

        guard periods.count >= 2,
              let best = periods.min(by: { $0.avg < $1.avg }),
              let worst = periods.max(by: { $0.avg < $1.avg }),
              worst.avg - best.avg >= 0.3 else { return [] }

        return [DayObservation(
            icon: "chart.bar.fill",
            iconColor: .blue,
            headline: "Tremor was lowest in the \(best.name)",
            detail: "\(best.name.capitalized): \(fmt(best.avg)) avg · \(worst.name.capitalized): \(fmt(worst.avg)) avg",
            sentiment: .informational
        ).at(anchor)]
    }

    // MARK: Attribute helpers — delegate to FoodAttribute.detect for entries saved before wiring

    private static func attributes(for event: FoodEvent) -> [FoodAttribute] {
        if !event.attributes.isEmpty { return event.attributes }
        return FoodAttribute.detect(in: event.userDescription ?? "")
    }

    private static func hasCaffeine(_ event: FoodEvent) -> Bool { attributes(for: event).contains(.caffeine) }
    private static func hasSugar(_ event: FoodEvent) -> Bool { attributes(for: event).contains(.sugar) }

    // MARK: Food → tremor rise (caffeine / sugar), with pre-dose wearing-off guard

    private static func foodRiseObservation(
        event: FoodEvent, readings: [TremorReading], doseTimes: [Date],
        factorLabel: String, icon: String, mechanismNote: String
    ) -> DayObservation? {
        let pre = windowAvg(readings,
                            from: event.timestamp.addingTimeInterval(-900),
                            to: event.timestamp)
        let post = windowAvg(readings,
                             from: event.timestamp.addingTimeInterval(1800),
                             to: event.timestamp.addingTimeInterval(3600))
        guard let pre, let post, pre > 0.1 else { return nil }

        let delta = (post - pre) / pre * 100
        // Magnitude floor (same as the dose/workout branches): the rise must reach at
        // least Slight (1.0) and move >= 0.5 absolute, so a noise-floor wiggle
        // (e.g. 0.1 -> 0.3) can't trip a false "caffeine/sugar raised tremor" via the
        // tiny pre denominator.
        guard delta >= 20, post >= 1.0, post - pre >= 0.5 else { return nil }
        let timeStr = event.timestamp.formatted(.dateTime.hour().minute())

        // Confounder: tremor naturally climbs before the first dose of the day.
        // If no dose preceded this entry, a rise is more likely wearing-off than the food.
        let dosedBefore = doseTimes.contains { $0 <= event.timestamp }
        guard dosedBefore else {
            return DayObservation(
                icon: "clock.arrow.circlepath", iconColor: .secondary,
                headline: "Tremor rose around \(timeStr), after \(factorLabel)",
                detail: "You hadn't taken a dose yet, so this likely reflects morning wearing-off rather than the \(factorLabel). Avg \(fmt(pre)) → \(fmt(post)).",
                sentiment: .neutral
            ).at(event.timestamp)
        }

        // This card only renders when a dose already preceded the food (the no-prior-dose
        // case returns the morning-wearing-off card above), so a wearing-off rise is always
        // a live alternative explanation. Pose it as a question and de-attribute in the
        // subline rather than implying the food caused the rise — real attribution is the
        // cross-day engine's job (its dose-confound guard drops dose-shadowed food events).
        return DayObservation(
            icon: icon, iconColor: .orange,
            headline: "Tremor rose at \(timeStr) (+\(Int(delta))%) — \(factorLabel) or wearing-off?",
            detail: "\(mechanismNote)Avg \(fmt(pre)) → \(fmt(post)) in the 30–60 min window after. Insights tells them apart.",
            sentiment: .neutral
        ).at(event.timestamp)
    }

    // MARK: HRV ↔ tremor (within-day association)
    //
    // A single day-average HRV can't be related to tremor. Instead we pair each
    // tremor reading with the nearest HRV sample, split the day into lower- vs
    // higher-HRV stretches, and only surface a hedged note when there's enough
    // data and a real gap. This stays silent on quiet/low-data days rather than
    // inventing a pattern. The cross-day engine does the real verdict.

    private static func hrvTremorObservation(
        readings: [TremorReading], hrvSamples: [HRVSample], anchor: Date
    ) -> [DayObservation] {
        guard hrvSamples.count >= 4, readings.count >= 8 else { return [] }

        let paired: [(tremor: Double, hrv: Double)] = readings.compactMap { r in
            guard let nearest = hrvSamples.min(by: {
                abs($0.timestamp.timeIntervalSince(r.timestamp)) <
                abs($1.timestamp.timeIntervalSince(r.timestamp))
            }), abs(nearest.timestamp.timeIntervalSince(r.timestamp)) <= 900 else { return nil }
            return (r.tremorScore, nearest.value)
        }
        guard paired.count >= 8 else { return [] }

        let sortedHRV = paired.map(\.hrv).sorted()
        let medianHRV = sortedHRV[sortedHRV.count / 2]
        let low = paired.filter { $0.hrv < medianHRV }
        let high = paired.filter { $0.hrv >= medianHRV }
        guard low.count >= 3, high.count >= 3 else { return [] }

        let lowT = low.map(\.tremor).reduce(0, +) / Double(low.count)
        let highT = high.map(\.tremor).reduce(0, +) / Double(high.count)
        guard highT > 0.1 else { return [] }

        let pct = (lowT - highT) / highT * 100
        guard pct >= 20 else { return [] }

        return [DayObservation(
            icon: "bolt.heart.fill", iconColor: .purple,
            headline: "Tremor ran higher when HRV was lower today",
            detail: "Avg \(fmt(lowT)) on lower-HRV stretches vs \(fmt(highT)) on higher — worth confirming across more days.",
            sentiment: .informational
        ).at(anchor)]
    }

    // MARK: Sleep + daylight (circadian) context

    private static func sleepObservations(
        sleep: SleepBreakdown?, daylightMinutes: Double?, anchor: Date
    ) -> [DayObservation] {
        var out: [DayObservation] = []

        if let sleep, sleep.hasData {
            if sleep.totalAsleepHours < 6.0 {
                out.append(DayObservation(
                    icon: "bed.double.fill", iconColor: .orange,
                    headline: "Short sleep night (\(formatHours(sleep.totalAsleepHours)))",
                    detail: "Poor sleep is associated with higher tremor severity the following day.",
                    sentiment: .negative
                ).at(anchor))
            } else if sleep.deepHours < 0.5 {
                out.append(DayObservation(
                    icon: "bed.double.fill", iconColor: .orange,
                    headline: "Low deep sleep (\(formatHours(sleep.deepHours)))",
                    detail: "Deep sleep supports motor recovery — this may have affected today's tremor baseline.",
                    sentiment: .negative
                ).at(anchor))
            }
        }

        if let mins = daylightMinutes, mins < 20 {
            out.append(DayObservation(
                icon: "sun.max.fill", iconColor: .orange,
                headline: "Little time in daylight (\(Int(mins))m)",
                detail: "Light exposure anchors your circadian rhythm and supports sleep quality, which in turn influence next-day motor symptoms.",
                sentiment: .neutral
            ).at(anchor.addingTimeInterval(1)))
        }

        return out
    }

    // MARK: Helpers

    private static func windowAvg(
        _ readings: [TremorReading], from start: Date, to end: Date,
        minCount: Int = 2, metric: KeyPath<TremorReading, Double> = \.tremorScore
    ) -> Double? {
        let window = readings.filter { $0.timestamp >= start && $0.timestamp < end }
        guard window.count >= minCount else { return nil }
        return window.map { $0[keyPath: metric] }.reduce(0, +) / Double(window.count)
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func formatHours(_ h: Double) -> String {
        let hours = Int(h)
        let minutes = Int((h - Double(hours)) * 60)
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

// MARK: - Views

struct ObservationsPanel: View {
    let readings: [TremorReading]
    let events: [DayEvent]
    let foodEvents: [FoodEvent]
    let sleep: SleepBreakdown?
    let hrvSamples: [HRVSample]
    let daylightMinutes: Double?

    private var observations: [DayObservation] {
        ObservationEngine.generate(
            readings: readings, events: events,
            foodEvents: foodEvents, sleep: sleep,
            hrvSamples: hrvSamples, daylightMinutes: daylightMinutes
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text("Daily Observations")
                    .font(.headline)
            }

            if observations.isEmpty {
                Text(readings.isEmpty
                     ? "No tremor data for this day — observations appear once readings are captured."
                     : "No clear patterns detected today. Log events (medication, food, workouts) to surface correlations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(observations) { obs in
                        ObservationCard(observation: obs)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ObservationCard: View {
    let observation: DayObservation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: observation.icon)
                .foregroundStyle(observation.iconColor)
                .font(.system(size: 15))
                .frame(width: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(observation.headline)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let detail = observation.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(observation.sentiment.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(observation.sentiment.accent.opacity(0.2), lineWidth: 1)
        )
    }
}
