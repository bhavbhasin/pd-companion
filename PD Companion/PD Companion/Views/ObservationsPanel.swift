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

struct ObservationEngine {

    static func generate(
        readings: [TremorReading],
        events: [DayEvent],
        foodEvents: [FoodEvent],
        sleep: SleepBreakdown?,
        hrv: Double?
    ) -> [DayObservation] {
        guard !readings.isEmpty else { return [] }

        var result: [DayObservation] = []
        result += doseWindowObservations(readings: readings, events: events)
        result += workoutWindowObservations(readings: readings, events: events)
        result += tremorTrajectoryObservation(readings: readings)
        result += caffeineObservations(readings: readings, foodEvents: foodEvents)
        result += sugarObservations(readings: readings, foodEvents: foodEvents)
        result += proteinDoseProximityObservations(events: events, foodEvents: foodEvents)
        result += fatDoseProximityObservations(events: events, foodEvents: foodEvents)
        result += sleepObservations(sleep: sleep)
        return result
    }

    // MARK: Post-dose tremor effect

    private static func doseWindowObservations(
        readings: [TremorReading], events: [DayEvent]
    ) -> [DayObservation] {
        let doses: [(time: Date, name: String?)] = events.compactMap {
            if case .medication(_, let time, let name) = $0 { return (time, name) }
            return nil
        }

        return doses.compactMap { dose in
            let pre = windowAvg(readings,
                                from: dose.time.addingTimeInterval(-1800),
                                to: dose.time)
            let post = windowAvg(readings,
                                 from: dose.time.addingTimeInterval(1800),
                                 to: dose.time.addingTimeInterval(5400))
            guard let pre, let post, pre > 0.1 else { return nil }

            let delta = (pre - post) / pre * 100
            let timeStr = dose.time.formatted(.dateTime.hour().minute())
            let name = (dose.name ?? "dose").capitalized

            if delta >= 15 {
                return DayObservation(
                    icon: "pill.fill",
                    iconColor: .green,
                    headline: "\(name) at \(timeStr) — tremor down \(Int(delta))%",
                    detail: "Avg \(fmt(pre)) before → \(fmt(post)) in the 30–90 min window after.",
                    sentiment: .positive
                )
            } else if delta <= -15 {
                return DayObservation(
                    icon: "pill.fill",
                    iconColor: .orange,
                    headline: "Tremor rose after \(name.lowercased()) at \(timeStr)",
                    detail: "Avg \(fmt(pre)) before → \(fmt(post)) after. May indicate wearing-off timing.",
                    sentiment: .negative
                )
            }
            return nil
        }
    }

    // MARK: Post-workout effect

    private static func workoutWindowObservations(
        readings: [TremorReading], events: [DayEvent]
    ) -> [DayObservation] {
        let workouts: [(start: Date, end: Date, type: HKWorkoutActivityType)] = events.compactMap {
            if case .workout(_, let start, let dur, let type) = $0 {
                return (start, start.addingTimeInterval(dur), type)
            }
            return nil
        }

        return workouts.compactMap { workout in
            let pre = windowAvg(readings,
                                from: workout.start.addingTimeInterval(-1800),
                                to: workout.start)
            let post = windowAvg(readings,
                                 from: workout.end.addingTimeInterval(1800),
                                 to: workout.end.addingTimeInterval(5400))
            guard let pre, let post, pre > 0.1 else { return nil }

            let delta = (pre - post) / pre * 100
            let name = workout.type.displayName

            if delta >= 15 {
                return DayObservation(
                    icon: "figure.run",
                    iconColor: .green,
                    headline: "\(name) reduced tremor \(Int(delta))%",
                    detail: "Avg \(fmt(pre)) before → \(fmt(post)) in the hour after the session.",
                    sentiment: .positive
                )
            } else if delta <= -15 {
                return DayObservation(
                    icon: "figure.run",
                    iconColor: .orange,
                    headline: "Tremor elevated after \(name)",
                    detail: "Avg \(fmt(pre)) before → \(fmt(post)) after. May resolve over the next few hours.",
                    sentiment: .neutral
                )
            }
            return nil
        }
    }

    // MARK: Tremor trajectory (morning / afternoon / evening)

    private static func tremorTrajectoryObservation(readings: [TremorReading]) -> [DayObservation] {
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
        )]
    }

    // MARK: Attribute helpers — delegate to FoodAttribute.detect for entries saved before wiring

    private static func attributes(for event: FoodEvent) -> [FoodAttribute] {
        if !event.attributes.isEmpty { return event.attributes }
        return FoodAttribute.detect(in: event.userDescription ?? "")
    }

    private static func hasCaffeine(_ event: FoodEvent) -> Bool {
        attributes(for: event).contains(.caffeine)
    }

    private static func hasProtein(_ event: FoodEvent) -> Bool {
        attributes(for: event).contains(.protein)
    }

    private static func hasSugar(_ event: FoodEvent) -> Bool {
        attributes(for: event).contains(.sugar)
    }

    private static func hasFat(_ event: FoodEvent) -> Bool {
        attributes(for: event).contains(.fat)
    }

    // MARK: Caffeine effect

    private static func caffeineObservations(
        readings: [TremorReading], foodEvents: [FoodEvent]
    ) -> [DayObservation] {
        return foodEvents.filter { hasCaffeine($0) }.compactMap { event in
            let pre = windowAvg(readings,
                                from: event.timestamp.addingTimeInterval(-900),
                                to: event.timestamp)
            let post = windowAvg(readings,
                                 from: event.timestamp.addingTimeInterval(1800),
                                 to: event.timestamp.addingTimeInterval(3600))
            guard let pre, let post, pre > 0.1 else { return nil }

            let delta = (post - pre) / pre * 100
            let timeStr = event.timestamp.formatted(.dateTime.hour().minute())

            guard delta >= 20 else { return nil }
            return DayObservation(
                icon: "cup.and.saucer.fill",
                iconColor: .orange,
                headline: "Tremor rose after caffeine at \(timeStr) (+\(Int(delta))%)",
                detail: "Avg \(fmt(pre)) before → \(fmt(post)) in the 30–60 min window after.",
                sentiment: .negative
            )
        }
    }

    // MARK: Sugar effect

    private static func sugarObservations(
        readings: [TremorReading], foodEvents: [FoodEvent]
    ) -> [DayObservation] {
        return foodEvents.filter { hasSugar($0) }.compactMap { event in
            let pre = windowAvg(readings,
                                from: event.timestamp.addingTimeInterval(-900),
                                to: event.timestamp)
            let post = windowAvg(readings,
                                 from: event.timestamp.addingTimeInterval(1800),
                                 to: event.timestamp.addingTimeInterval(3600))
            guard let pre, let post, pre > 0.1 else { return nil }

            let delta = (post - pre) / pre * 100
            let timeStr = event.timestamp.formatted(.dateTime.hour().minute())

            guard delta >= 20 else { return nil }
            return DayObservation(
                icon: "fork.knife",
                iconColor: .orange,
                headline: "Tremor rose after high-sugar entry at \(timeStr) (+\(Int(delta))%)",
                detail: "Glycemic spike → postprandial hypotension is common in PD and can elevate tremor. Avg \(fmt(pre)) before → \(fmt(post)) in the 30–60 min window after.",
                sentiment: .negative
            )
        }
    }

    // MARK: Protein-dose proximity

    private static func proteinDoseProximityObservations(
        events: [DayEvent], foodEvents: [FoodEvent]
    ) -> [DayObservation] {
        let doseTimes: [Date] = events.compactMap {
            if case .medication(_, let time, _) = $0 { return time }
            return nil
        }

        return foodEvents
            .filter { hasProtein($0) }
            .compactMap { meal in
                guard doseTimes.contains(where: {
                    abs($0.timeIntervalSince(meal.timestamp)) < 3600
                }) else { return nil }

                let timeStr = meal.timestamp.formatted(.dateTime.hour().minute())
                return DayObservation(
                    icon: "fork.knife",
                    iconColor: .orange,
                    headline: "Protein meal at \(timeStr) close to a dose",
                    detail: "Dietary protein competes with levodopa for absorption — check whether tremor was affected in the following hour.",
                    sentiment: .neutral
                )
            }
    }

    // MARK: Fat-dose proximity

    private static func fatDoseProximityObservations(
        events: [DayEvent], foodEvents: [FoodEvent]
    ) -> [DayObservation] {
        let doseTimes: [Date] = events.compactMap {
            if case .medication(_, let time, _) = $0 { return time }
            return nil
        }

        return foodEvents
            .filter { hasFat($0) }
            .compactMap { meal in
                guard doseTimes.contains(where: {
                    abs($0.timeIntervalSince(meal.timestamp)) < 5400
                }) else { return nil }

                let timeStr = meal.timestamp.formatted(.dateTime.hour().minute())
                return DayObservation(
                    icon: "fork.knife",
                    iconColor: .orange,
                    headline: "High-fat meal at \(timeStr) close to a dose",
                    detail: "Fat slows gastric emptying and can delay your Sinemet onset by 20–40 minutes — your effective window may start later than usual.",
                    sentiment: .neutral
                )
            }
    }

    // MARK: Sleep context

    private static func sleepObservations(sleep: SleepBreakdown?) -> [DayObservation] {
        guard let sleep, sleep.hasData else { return [] }

        if sleep.totalAsleepHours < 6.0 {
            return [DayObservation(
                icon: "bed.double.fill",
                iconColor: .orange,
                headline: "Short sleep night (\(formatHours(sleep.totalAsleepHours)))",
                detail: "Poor sleep is associated with higher tremor severity the following day.",
                sentiment: .negative
            )]
        }

        if sleep.deepHours < 0.5 {
            return [DayObservation(
                icon: "bed.double.fill",
                iconColor: .orange,
                headline: "Low deep sleep (\(formatHours(sleep.deepHours)))",
                detail: "Deep sleep supports motor recovery — this may have affected today's tremor baseline.",
                sentiment: .negative
            )]
        }

        return []
    }

    // MARK: Helpers

    private static func windowAvg(
        _ readings: [TremorReading], from start: Date, to end: Date, minCount: Int = 2
    ) -> Double? {
        let window = readings.filter { $0.timestamp >= start && $0.timestamp < end }
        guard window.count >= minCount else { return nil }
        return window.map(\.tremorScore).reduce(0, +) / Double(window.count)
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
    let hrv: Double?

    private var observations: [DayObservation] {
        ObservationEngine.generate(
            readings: readings, events: events,
            foodEvents: foodEvents, sleep: sleep, hrv: hrv
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text("Observations")
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
