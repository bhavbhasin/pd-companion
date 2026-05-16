import HealthKit
import Foundation
import Combine

@MainActor
class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var todaySnapshot: HealthSample?
    @Published var lastMedicationDoseDate: Date?
    @Published var lastMedicationName: String?
    @Published var todayWorkouts: [HKWorkout] = []
    @Published var error: String?

    @Published var dayInReviewDate: Date = Calendar.current.startOfDay(
        for: Date().addingTimeInterval(-86400)
    )
    @Published var daySleep: SleepBreakdown?
    @Published var dayEvents: [DayEvent] = []
    @Published var dayHRV: Double?
    @Published var dayDaylightMinutes: Double?

    private let writeTypes: Set<HKSampleType> = [
        HKObjectType.categoryType(forIdentifier: .mindfulSession)!
    ]

    private let readTypes: Set<HKObjectType> = {
        let types: [HKObjectType] = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .timeInDaylight)!,
            HKObjectType.workoutType(),
        ]
        return Set(types)
    }()

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            error = "HealthKit is not available on this device."
            return
        }

        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
        } catch {
            self.error = "HealthKit authorization failed: \(error.localizedDescription)"
        }

        await requestMedicationAuthorization()
    }

    private func requestMedicationAuthorization() async {
        await withCheckedContinuation { continuation in
            store.requestPerObjectReadAuthorization(
                for: HKObjectType.userAnnotatedMedicationType(),
                predicate: nil
            ) { _, _ in
                continuation.resume()
            }
        }
    }

    func fetchTodaySnapshot() async {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        async let sleep = fetchSleepHours(from: startOfDay, to: now)
        async let hrv = fetchLatestQuantity(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli))
        async let rhr = fetchLatestQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let exercise = fetchCumulativeQuantity(.appleExerciseTime, from: startOfDay, to: now, unit: .minute())
        async let steps = fetchCumulativeQuantity(.stepCount, from: startOfDay, to: now, unit: .count())
        async let mindfulness = fetchMindfulnessMinutes(from: startOfDay, to: now)

        var snapshot = HealthSample(date: startOfDay)
        snapshot.sleepHours = await sleep
        snapshot.hrvAverage = await hrv
        snapshot.restingHeartRate = await rhr
        snapshot.exerciseMinutes = await exercise
        snapshot.stepCount = await steps
        snapshot.mindfulnessMinutes = await mindfulness

        todaySnapshot = snapshot

        await fetchLatestMedicationDose()
        await fetchTodayWorkouts(from: startOfDay, to: now)
    }

    private func fetchTodayWorkouts(from start: Date, to end: Date) async {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate, ascending: false
        )

        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                Task { @MainActor in
                    self.todayWorkouts = (samples as? [HKWorkout]) ?? []
                    continuation.resume()
                }
            }
            store.execute(query)
        }
    }

    private func fetchLatestMedicationDose() async {
        let medications = await fetchUserMedications()
        var medMap: [HKHealthConceptIdentifier: HKUserAnnotatedMedication] = [:]
        for med in medications {
            medMap[med.medication.identifier] = med
        }

        let doseType = HKObjectType.medicationDoseEventType()
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate, ascending: false
        )

        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: doseType,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                Task { @MainActor in
                    let doses = (samples as? [HKMedicationDoseEvent]) ?? []
                    if let dose = doses.first(where: { $0.logStatus == .taken }) {
                        self.lastMedicationDoseDate = dose.startDate
                        if let med = medMap[dose.medicationConceptIdentifier] {
                            self.lastMedicationName = med.nickname ?? med.medication.displayText
                        }
                    }
                    continuation.resume()
                }
            }
            store.execute(query)
        }
    }

    private func fetchUserMedications() async -> [HKUserAnnotatedMedication] {
        await withCheckedContinuation { continuation in
            var collected: [HKUserAnnotatedMedication] = []
            let query = HKUserAnnotatedMedicationQuery(
                predicate: nil,
                limit: HKObjectQueryNoLimit
            ) { _, medication, isFinished, _ in
                if let medication {
                    collected.append(medication)
                }
                if isFinished {
                    continuation.resume(returning: collected)
                }
            }
            store.execute(query)
        }
    }

    private func fetchSleepHours(from start: Date, to end: Date) async -> Double? {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let asleepSamples = samples.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                    || $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                    || $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                }
                let totalSeconds = asleepSamples.reduce(0.0) {
                    $0 + $1.endDate.timeIntervalSince($1.startDate)
                }
                continuation.resume(returning: totalSeconds / 3600.0)
            }
            store.execute(query)
        }
    }

    private func fetchLatestQuantity(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit
    ) async -> Double? {
        let quantityType = HKQuantityType.quantityType(forIdentifier: identifier)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType, predicate: nil, limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func fetchCumulativeQuantity(
        _ identifier: HKQuantityTypeIdentifier, from start: Date, to end: Date, unit: HKUnit
    ) async -> Double? {
        let quantityType = HKQuantityType.quantityType(forIdentifier: identifier)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType, quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    func fetchDayInReview(for date: Date) async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)

        async let sleep = fetchSleepBreakdown(forDayStartingAt: startOfDay)
        async let workouts = fetchWorkoutsInRange(from: startOfDay, to: endOfDay)
        async let doses = fetchMedicationDosesInRange(from: startOfDay, to: endOfDay)
        async let mindful = fetchMindfulnessSessionsInRange(from: startOfDay, to: endOfDay)
        async let hrv = fetchAverageHRVInRange(from: startOfDay, to: endOfDay)
        async let daylight = fetchTimeInDaylightInRange(from: startOfDay, to: endOfDay)

        let resolvedSleep = await sleep
        let resolvedWorkouts = await workouts
        let resolvedDoses = await doses
        let resolvedMindful = await mindful
        let resolvedHRV = await hrv
        let resolvedDaylight = await daylight

        var events: [DayEvent] = []
        for dose in resolvedDoses {
            events.append(.medication(id: UUID(), time: dose.time, name: dose.name))
        }
        for workout in resolvedWorkouts {
            events.append(.workout(
                id: UUID(),
                start: workout.startDate,
                duration: workout.duration,
                type: workout.workoutActivityType
            ))
        }
        for session in resolvedMindful {
            events.append(.mindfulness(
                id: UUID(), start: session.start, duration: session.duration
            ))
        }
        events.sort { $0.time < $1.time }

        dayInReviewDate = startOfDay
        daySleep = resolvedSleep
        dayEvents = events
        dayHRV = resolvedHRV
        dayDaylightMinutes = resolvedDaylight
    }

    private func fetchAverageHRVInRange(from start: Date, to end: Date) async -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                let value = statistics?.averageQuantity()?.doubleValue(
                    for: HKUnit.secondUnit(with: .milli)
                )
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchTimeInDaylightInRange(from start: Date, to end: Date) async -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .timeInDaylight)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: .minute())
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchSleepBreakdown(forDayStartingAt startOfDay: Date) async -> SleepBreakdown {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let windowStart = startOfDay.addingTimeInterval(-6 * 3600)
        let windowEnd = startOfDay.addingTimeInterval(14 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: .empty)
                    return
                }
                let relevant = samples.filter {
                    $0.endDate >= startOfDay && $0.endDate < windowEnd
                }

                let chosen = Self.dedupeSleepBySource(relevant)

                var deep = 0.0, rem = 0.0, core = 0.0, awake = 0.0
                var asleepStarts: [Date] = []
                var asleepEnds: [Date] = []
                var awakeSamples: [HKCategorySample] = []
                var segments: [SleepStageSegment] = []
                for sample in chosen {
                    let dur = sample.endDate.timeIntervalSince(sample.startDate)
                    let stage: SleepStage?
                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        deep += dur
                        asleepStarts.append(sample.startDate)
                        asleepEnds.append(sample.endDate)
                        stage = .deep
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        rem += dur
                        asleepStarts.append(sample.startDate)
                        asleepEnds.append(sample.endDate)
                        stage = .rem
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                         HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        core += dur
                        asleepStarts.append(sample.startDate)
                        asleepEnds.append(sample.endDate)
                        stage = .core
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        awake += dur
                        awakeSamples.append(sample)
                        stage = .awake
                    default:
                        stage = nil
                    }
                    if let stage {
                        segments.append(SleepStageSegment(
                            stage: stage, start: sample.startDate, end: sample.endDate
                        ))
                    }
                }
                let bedtime = asleepStarts.min()
                let wakeTime = asleepEnds.max()
                let interruptions: Int
                if let bedtime, let wakeTime {
                    interruptions = awakeSamples.filter {
                        $0.startDate > bedtime && $0.endDate < wakeTime
                    }.count
                } else {
                    interruptions = 0
                }
                let breakdown = SleepBreakdown(
                    totalAsleepHours: (deep + rem + core) / 3600.0,
                    deepHours: deep / 3600.0,
                    remHours: rem / 3600.0,
                    coreHours: core / 3600.0,
                    awakeMinutes: awake / 60.0,
                    interruptions: interruptions,
                    bedtime: bedtime,
                    wakeTime: wakeTime,
                    stages: segments.sorted { $0.start < $1.start }
                )
                continuation.resume(returning: breakdown)
            }
            store.execute(query)
        }
    }

    private nonisolated static func dedupeSleepBySource(_ samples: [HKCategorySample]) -> [HKCategorySample] {
        guard !samples.isEmpty else { return [] }
        let appleSamples = samples.filter {
            $0.sourceRevision.source.bundleIdentifier.hasPrefix("com.apple.")
        }
        if !appleSamples.isEmpty { return appleSamples }
        let bySource = Dictionary(grouping: samples) { $0.sourceRevision.source.bundleIdentifier }
        let dominant = bySource.max { lhs, rhs in
            asleepDuration(in: lhs.value) < asleepDuration(in: rhs.value)
        }
        return dominant?.value ?? samples
    }

    private nonisolated static func asleepDuration(in samples: [HKCategorySample]) -> TimeInterval {
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        return samples.reduce(0.0) { acc, s in
            asleepValues.contains(s.value) ? acc + s.endDate.timeIntervalSince(s.startDate) : acc
        }
    }

    private func fetchWorkoutsInRange(from start: Date, to end: Date) async -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    private func fetchMedicationDosesInRange(
        from start: Date, to end: Date
    ) async -> [(time: Date, name: String?)] {
        let medications = await fetchUserMedications()
        var medMap: [HKHealthConceptIdentifier: HKUserAnnotatedMedication] = [:]
        for med in medications {
            medMap[med.medication.identifier] = med
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.medicationDoseEventType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let doses = samples as? [HKMedicationDoseEvent] else {
                    continuation.resume(returning: [])
                    return
                }
                let takenOnly = doses.filter { $0.logStatus == .taken }
                let mapped: [(time: Date, name: String?)] = takenOnly.map { dose in
                    let name: String?
                    if let med = medMap[dose.medicationConceptIdentifier] {
                        name = med.nickname ?? med.medication.displayText
                    } else {
                        name = nil
                    }
                    return (dose.startDate, name)
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    private func fetchMindfulnessSessionsInRange(
        from start: Date, to end: Date
    ) async -> [(start: Date, duration: TimeInterval)] {
        let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindfulType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let mapped = samples.map { sample in
                    (sample.startDate, sample.endDate.timeIntervalSince(sample.startDate))
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    func writeMindfulSession(start: Date, duration: TimeInterval) async throws {
        let type = HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        let sample = HKCategorySample(type: type, value: 0, start: start, end: start.addingTimeInterval(duration))
        try await store.save(sample)
    }

    func deleteMindfulSession(start: Date, duration: TimeInterval) async throws {
        let type = HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        let end = start.addingTimeInterval(duration)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: []
        )
        let samples = try await descriptor.result(for: store)
        for sample in samples {
            try await store.delete(sample)
        }
    }

    private func fetchMindfulnessMinutes(from start: Date, to end: Date) async -> Double? {
        let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindfulType, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let totalSeconds = samples.reduce(0.0) {
                    $0 + $1.endDate.timeIntervalSince($1.startDate)
                }
                continuation.resume(returning: totalSeconds / 60.0)
            }
            store.execute(query)
        }
    }
}
