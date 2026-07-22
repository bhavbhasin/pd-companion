import HealthKit
import Foundation
import Combine

/// Per-user HealthKit source exclusions (device/app names the user marked "not mine"),
/// stored locally. Default empty → every source counts, correct for the common
/// single-owner case. New sources are included automatically; only exclusions persist.
///
/// Applies APP-WIDE: a foreign device that synced into the Health store (a family
/// member's watch, an old restored device) is dropped from every metric Kampa reads,
/// not just gait. Names are matched as lowercased substrings, the rule the gait path
/// has always used.
enum HealthSourcePrefs {
    private static let key = "excludedHealthSources"
    private static let legacyGaitKey = "excludedGaitSources"

    static var excluded: Set<String> {
        get {
            let defaults = UserDefaults.standard
            if let stored = defaults.stringArray(forKey: key) { return Set(stored) }
            // One-time migration: carry over the old gait-only exclusions so an existing
            // user's "not mine" choices keep applying (now everywhere). Canonicalize on the
            // way in and persist under the new key so we never fall through to the legacy
            // key again.
            if let legacy = defaults.stringArray(forKey: legacyGaitKey) {
                let migrated = legacy.map(canonical)
                defaults.set(migrated, forKey: key)
                return Set(migrated)
            }
            return []
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: key) }
    }

    /// Canonical form for matching and dedup: lowercased, with every run of whitespace
    /// (including the non-breaking space U+00A0 that HealthKit sprinkles into device
    /// names) folded to a single regular space, and trimmed. Without this, one physical
    /// device — e.g. "BB ⌚️ 11" stored once with a normal space and once with U+00A0 —
    /// splits into two list rows and dodges exclusion (a substring with a plain space
    /// never matches the non-breaking-space variant).
    static func canonical(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    /// True if `sourceName` is excluded. Both sides are canonicalized, then matched by
    /// containment (excluded entries are full canonical names, so this is effectively
    /// exact match while tolerating any legacy partial entry). Empty set ⇒ false.
    static func isExcluded(_ sourceName: String, in excluded: Set<String>) -> Bool {
        guard !excluded.isEmpty else { return false }
        let name = canonical(sourceName)
        return excluded.contains { name.contains($0) }
    }
}

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
    @Published var dayHRVSamples: [HRVSample] = []
    @Published var dayDaylightMinutes: Double?
    @Published var dayGlucose: [GlucoseSample] = []
    /// Sticky once any viewed day has Lingo glucose — lets a CGM user's *gap* day show a
    /// quiet "no glucose" note instead of hiding the panel, while a never-CGM user never
    /// sees it. Set in `fetchDayInReview`; step-1 approximation (see the glucose fetch note).
    @Published var hasEverHadGlucose = false

    private let writeTypes: Set<HKSampleType> = {
        var types: Set<HKSampleType> = [
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            // Required so the phone can call HKHealthStore.startWatchApp(with:) to wake
            // the Watch app for a tremor sync. We never build or save an HKWorkout —
            // the session is only used for its background-runtime privilege.
            HKObjectType.workoutType()
        ]
        // GI symptoms are logged from Kampa (+ sheet / mic / Siri) as HKCategorySamples.
        types.formUnion(GISymptom.sampleTypes)
        return types
    }()

    private let readTypes: Set<HKObjectType> = {
        var types: [HKObjectType] = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .timeInDaylight)!,
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .walkingSpeed)!,
            HKObjectType.quantityType(forIdentifier: .walkingAsymmetryPercentage)!,
            HKObjectType.quantityType(forIdentifier: .walkingDoubleSupportPercentage)!,
            HKObjectType.quantityType(forIdentifier: .walkingStepLength)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .bloodGlucose)!,
        ]
        // GI symptom categories, read back for the timeline + engine.
        return Set(types).union(GISymptom.sampleTypes)
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

    func exportAllSamples(to folder: URL) async {
        await HealthKitExporter.exportAll(to: folder, store: store)
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

    /// Keep only samples whose source the user hasn't excluded (a foreign device synced
    /// into their Health store). `nonisolated static` so it runs inside a HealthKit query's
    /// completion handler, on whatever thread that fires. Empty set ⇒ input unchanged.
    nonisolated static func includedSources<S: HKSample>(
        _ samples: [S], excluded: Set<String>
    ) -> [S] {
        guard !excluded.isEmpty else { return samples }
        return samples.filter { !HealthSourcePrefs.isExcluded($0.sourceRevision.source.name, in: excluded) }
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
                let workouts = Self.includedSources((samples as? [HKWorkout]) ?? [],
                                                    excluded: HealthSourcePrefs.excluded)
                Task { @MainActor in
                    self.todayWorkouts = workouts
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

    /// Sleep as INTERVALS, not a total. The engine has to know WHEN the patient was asleep
    /// — to subtract it from a dose gap, and to censor a dose's observation at sleep onset —
    /// and a scalar of hours can answer neither question. (`fetchSleepHours` below stays as
    /// the Review panel's nightly total; this is a separate read for the engine.)
    ///
    /// `asleepUnspecified` IS included: coarse sources (AutoSleep, manual entries) write only
    /// that, and dropping it would silently score those spans as waking OFF. `inBed` is NOT:
    /// it covers lying down awake, which is real OFF the patient lived through — verified on
    /// Bhav's 3pm nap, where he lay down ~3:00 but Apple detected sleep only from 4:08, and
    /// that first hour carried genuine tremor. An `awake` interruption inside a night is
    /// likewise absent from the result, so it correctly counts as waking time.
    func fetchSleepIntervals(from start: Date, to end: Date) async -> [SleepInterval] {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let raw = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let samples = Self.includedSources(raw, excluded: HealthSourcePrefs.excluded)
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                ]
                let intervals = samples
                    .filter { asleepValues.contains($0.value) }
                    .map { SleepInterval(start: $0.startDate, end: $0.endDate) }
                continuation.resume(returning: CorrelationEngine.mergeSleep(intervals))
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
                guard let raw = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let samples = Self.includedSources(raw, excluded: HealthSourcePrefs.excluded)
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
        async let hrvSamples = fetchHRVSamplesInRange(from: startOfDay, to: endOfDay)
        async let daylight = fetchTimeInDaylightInRange(from: startOfDay, to: endOfDay)
        async let glucose = fetchGlucoseSeries(from: startOfDay, to: endOfDay)
        async let gi = fetchGISymptomsInRange(from: startOfDay, to: endOfDay)

        let resolvedSleep = await sleep
        let resolvedWorkouts = await workouts
        let resolvedDoses = await doses
        let resolvedMindful = await mindful
        let resolvedHRV = await hrv
        let resolvedHRVSamples = await hrvSamples
        let resolvedDaylight = await daylight
        let resolvedGlucose = await glucose
        let resolvedGI = await gi

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
                id: session.uuid, start: session.start, duration: session.duration,
                isEditable: session.isEditable, source: session.source
            ))
        }
        for gi in resolvedGI {
            events.append(.giSymptom(
                id: gi.uuid, time: gi.time, symptom: gi.symptom,
                severity: gi.severity, isEditable: gi.isEditable
            ))
        }
        events.sort { $0.time < $1.time }

        dayInReviewDate = startOfDay
        daySleep = resolvedSleep
        dayEvents = events
        dayHRV = resolvedHRV
        dayHRVSamples = resolvedHRVSamples
        dayDaylightMinutes = resolvedDaylight
        dayGlucose = resolvedGlucose
        if !resolvedGlucose.isEmpty { hasEverHadGlucose = true }
    }

    /// Blood-glucose samples for the day — brand-agnostic. Reads ALL `bloodGlucose` so any
    /// CGM (Lingo/Stelo/Libre…) or a finger-prick/manual entry in Apple Health shows up; the
    /// panel draws dense CGM data as a line and isolated readings as dots. Read-only: no
    /// SwiftData/CloudKit ingestion — glucose lives in HealthKit and we render it by eye.
    ///
    /// Light dedup on exact timestamp collapses the case where one sensor is mirrored by two
    /// apps (e.g. Libre + a middleware) into one point; distinct real readings never share an
    /// exact `startDate`, so genuine data is untouched. Step 1 of the CGM slice; no engine yet.
    func fetchGlucoseSeries(from start: Date, to end: Date) async -> [GlucoseSample] {
        let type = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
        let unit = HKUnit(from: "mg/dL")
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let raw = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let samples = Self.includedSources(raw, excluded: HealthSourcePrefs.excluded)
                var seen = Set<Date>()
                var out: [GlucoseSample] = []
                for s in samples where seen.insert(s.startDate).inserted {
                    out.append(GlucoseSample(
                        date: s.startDate,
                        value: s.quantity.doubleValue(for: unit),
                        source: s.sourceRevision.source.name
                    ))
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
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

    /// Timestamped HRV (SDNN) samples for the day, sorted ascending.
    /// The day-average alone can't be related to tremor within a single day;
    /// the per-sample series lets the engine do a within-day association.
    private func fetchHRVSamplesInRange(from start: Date, to end: Date) async -> [HRVSample] {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: sort
            ) { _, samples, _ in
                let included = Self.includedSources(samples as? [HKQuantitySample] ?? [],
                                                    excluded: HealthSourcePrefs.excluded)
                let result = included.map {
                    HRVSample(
                        timestamp: $0.startDate,
                        value: $0.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                    )
                }
                continuation.resume(returning: result)
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
        // 6 PM (prev day) → 6 PM (this day): a 24h window that tiles cleanly with
        // adjacent days (no gap, no overlap) using Apple's ~6 PM sleep-day boundary. This
        // captures the overnight AND any daytime naps on the day, so the total sums all of
        // the day's sleep — matching Apple Health's daily "Time Asleep" — rather than
        // clipping the afternoon at 2 PM.
        let windowStart = startOfDay.addingTimeInterval(-6 * 3600)
        let windowEnd = startOfDay.addingTimeInterval(18 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                guard let raw = samples as? [HKCategorySample] else {
                    continuation.resume(returning: .empty)
                    return
                }
                let samples = Self.includedSources(raw, excluded: HealthSourcePrefs.excluded)
                // Keep the whole nocturnal window. The fetch predicate already
                // bounds the lower end at windowStart (~6 PM the prior evening),
                // so requiring endDate >= startOfDay (midnight) was wrong: it
                // discarded every sleep segment that ended before midnight,
                // dropping the pre-midnight portion of the night for anyone who
                // falls asleep before 12 AM (e.g. a 10 PM bedtime lost ~2h).
                let relevant = samples.filter {
                    $0.endDate > windowStart && $0.endDate < windowEnd
                }

                // Gap-fill across sources: a "staging" source (one that emits Deep/REM —
                // e.g. Apple Watch) is authoritative wherever it tracked; coarser sources
                // (e.g. AutoSleep, which only writes "asleep unspecified") fill ONLY the
                // spans the stager left blank. This recovers sleep the Watch missed (a
                // late-detected onset) without letting a coarse all-night block steamroll
                // the Watch's real awake/interruption detail.
                let primarySources = Set(
                    relevant.filter {
                        $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                        $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    }.map { $0.sourceRevision.source.bundleIdentifier }
                )

                // Flatten to one stage-per-moment timeline (also dedupes a single source
                // that overlaps itself across syncs), with staging sources winning per-moment.
                let segments = Self.flattenSleepStages(relevant, primarySources: primarySources)

                var deep = 0.0, rem = 0.0, core = 0.0, awake = 0.0
                for seg in segments {
                    let dur = seg.end.timeIntervalSince(seg.start)
                    switch seg.stage {
                    case .deep:  deep += dur
                    case .rem:   rem += dur
                    case .core:  core += dur
                    case .awake: awake += dur
                    }
                }

                let asleepSegments = segments.filter { $0.stage != .awake }
                let bedtime = asleepSegments.first?.start
                let wakeTime = asleepSegments.last?.end
                let interruptions: Int
                if let bedtime, let wakeTime {
                    interruptions = segments.filter {
                        $0.stage == .awake && $0.start > bedtime && $0.end < wakeTime
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
                    stages: segments
                )
                continuation.resume(returning: breakdown)
            }
            store.execute(query)
        }
    }

    /// Collapses overlapping sleep samples into one non-overlapping timeline so each
    /// moment is counted exactly once, merging multiple sources with **gap-fill**.
    ///
    /// Two layers of priority pick the winner at each instant:
    ///  1. **Source tier** — a sample from a `primarySources` source (a stager: emits
    ///     Deep/REM, e.g. Apple Watch) outranks any coarse-source sample, so the stager
    ///     is authoritative wherever it tracked and coarse sources (e.g. AutoSleep's
    ///     all-night "asleep unspecified" block) only fill the spans it left blank. This
    ///     recovers a late-detected onset without erasing the stager's awake/interruption
    ///     detail.
    ///  2. **Stage** — within a tier the deepest stage wins, and any asleep stage outranks
    ///     awake so a stray awake layer never carves a hole in real sleep.
    ///
    /// Also dedupes a single source that overlaps itself across syncs (one tester's Oura
    /// layered a night ~2x → a naive sum reported 10h16m for a 7h38m night). A no-op on
    /// clean, single-source data (union == sum). `primarySources` empty → all samples are
    /// the same tier (plain union), the right fallback when no stager is present.
    private nonisolated static func flattenSleepStages(
        _ samples: [HKCategorySample], primarySources: Set<String>
    ) -> [SleepStageSegment] {
        let staged: [(start: Date, end: Date, stage: SleepStage, tier: Int)] = samples.compactMap {
            guard let stage = sleepStage(for: $0.value), $0.endDate > $0.startDate else { return nil }
            let tier = primarySources.contains($0.sourceRevision.source.bundleIdentifier) ? 1 : 0
            return ($0.startDate, $0.endDate, stage, tier)
        }
        guard !staged.isEmpty else { return [] }

        let bounds = Set(staged.flatMap { [$0.start, $0.end] }).sorted()
        var segments: [SleepStageSegment] = []
        for i in 0..<(bounds.count - 1) {
            let a = bounds[i], b = bounds[i + 1]
            let mid = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
            // Tier first (a stager wins wherever it tracked → coarse sources only gap-fill),
            // then stage priority within the winning tier.
            let winner = staged
                .filter { $0.start <= mid && mid < $0.end }
                .max { ($0.tier, stagePriority($0.stage)) < ($1.tier, stagePriority($1.stage)) }
            guard let winner else { continue }
            if let last = segments.last, last.stage == winner.stage, last.end == a {
                segments[segments.count - 1] = SleepStageSegment(stage: winner.stage, start: last.start, end: b)
            } else {
                segments.append(SleepStageSegment(stage: winner.stage, start: a, end: b))
            }
        }
        return segments
    }

    private nonisolated static func sleepStage(for value: Int) -> SleepStage? {
        switch value {
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:  return .rem
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
             HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .core
        case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
        default: return nil
        }
    }

    /// Higher wins when stages overlap. Any asleep stage outranks awake so a stray
    /// awake layer never carves a hole in real sleep.
    private nonisolated static func stagePriority(_ stage: SleepStage) -> Int {
        switch stage {
        case .deep:  return 4
        case .rem:   return 3
        case .core:  return 2
        case .awake: return 0
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
                continuation.resume(returning: Self.includedSources(
                    (samples as? [HKWorkout]) ?? [], excluded: HealthSourcePrefs.excluded))
            }
            store.execute(query)
        }
    }

    /// The workout *adapter*: all workouts over the last `days` days, mapped to the
    /// engine's `WorkoutEvent` shape (HealthKit's activity type carried as a raw
    /// value, so the engine stays HealthKit-free). This is the single per-stream
    /// burden that gets workouts into the engine — every activity type (Tai Chi,
    /// boxing, pickleball, tango…) arrives through here, tagged, needing no new code.
    func fetchWorkoutEvents(days: Int = 120) async -> [WorkoutEvent] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end)
            ?? end.addingTimeInterval(-Double(days) * 86400)
        let workouts = await fetchWorkoutsInRange(from: start, to: end)
        return workouts.map {
            WorkoutEvent(start: $0.startDate,
                         duration: $0.duration,
                         activityRawValue: $0.workoutActivityType.rawValue)
        }
    }

    /// All "taken" medication/supplement doses over the last `days` days, mapped to the
    /// engine's `Dose` type — keyed by name, with NO substance allowlist. The old
    /// `sinemet/mucuna` hard-coding is gone: the engine now stratifies by formulation and
    /// lets the estimability gate decide which substances show a real levodopa pulse
    /// (`CorrelationEngine.estimableFormulations`), so every logged substance is modeled and
    /// inert ones self-exclude. A dose whose medication isn't set up in Apple Health (nil
    /// name) is kept under `"Unspecified"` rather than discarded.
    func fetchMedicationDoses(days: Int = 120) async -> [Dose] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end)
            ?? end.addingTimeInterval(-Double(days) * 86400)
        let raw = await fetchMedicationDosesInRange(from: start, to: end)
        return raw.map { Dose(timestamp: $0.time, name: $0.name ?? "Unspecified") }
    }

    /// Fetch the four mobility-metric series across (effectively) the user's full
    /// history, for the gait-progression analysis. `excludedSources` is a set of
    /// lowercased substrings matched against each sample's source name — used to drop
    /// foreign data (e.g. a family member's device that synced into this HealthKit
    /// store), which otherwise pollutes the multi-year trend. See the gait build note.
    func fetchGaitSeries(
        excludedSources: Set<String> = []
    ) async -> [GaitMetric: [GaitSample]] {
        let now = Date()
        let signature = GaitCache.signature(excludedSources)
        // Cache read/write off the main actor (small JSON, but no reason to block UI).
        let cached = await Task.detached { GaitCache.load() }.value
        // Reuse the cache only if it was built under the SAME source-exclusion set AND was
        // fully rebuilt recently. The age check forces a periodic cold sweep, which is what
        // lets DELETIONS in HealthKit eventually drop out (the merge is append-only and can't
        // un-know a sample) and bounds unbounded growth past the 12-year window.
        let usable: GaitCache.Payload?
        if let cached, cached.excludedSignature == signature,
           now.timeIntervalSince(cached.fullBuiltAt) <= GaitCache.maxAge {
            usable = cached
        } else {
            usable = nil
        }
        let fullBuiltAt = usable?.fullBuiltAt ?? now   // reset when we do a full rebuild

        let fullStart = Calendar.current.date(byAdding: .year, value: -12, to: now) ?? .distantPast

        var out: [GaitMetric: [GaitSample]] = [:]
        var metricsPayload: [String: GaitCache.MetricCache] = [:]
        for metric in GaitMetric.allCases {
            let prior = usable?.metrics[metric.rawValue]
            // Incremental: query only (last fetch, now]; full 12-year sweep on a cold/expired cache.
            let start = prior?.watermark ?? fullStart
            let fresh = await fetchGaitMetric(metric, start: start, end: now, excluded: excludedSources)
            let merged = (prior?.samples ?? []) + fresh   // strictStartDate → windows disjoint, no dedup
            out[metric] = merged
            metricsPayload[metric.rawValue] = GaitCache.MetricCache(watermark: now, samples: merged)
        }
        let payload = GaitCache.Payload(
            excludedSignature: signature, fullBuiltAt: fullBuiltAt, metrics: metricsPayload)
        await Task.detached { GaitCache.save(payload) }.value
        return out
    }

    private func fetchGaitMetric(
        _ metric: GaitMetric, start: Date, end: Date, excluded: Set<String>
    ) async -> [GaitSample] {
        // `.strictStartDate`: match by START date only, so a sample lands in exactly one
        // delta window. Without it HealthKit matches by OVERLAP, and an interval sample
        // straddling a fetch instant would be returned in two consecutive windows and cached
        // twice (a silent duplicate that skews the monthly median).
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let (type, unit) = Self.gaitHKType(metric)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let mapped: [GaitSample] = samples.compactMap { s in
                    let name = s.sourceRevision.source.name.lowercased()
                    if excluded.contains(where: { name.contains($0) }) { return nil }
                    return GaitSample(date: s.startDate, value: s.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    /// HealthKit type + unit for each gait metric. Percentage metrics use `.percent()`
    /// (values come back as 0–1 fractions, matching the engine's clip ranges).
    private static func gaitHKType(_ m: GaitMetric) -> (HKQuantityType, HKUnit) {
        switch m {
        case .walkingSpeed:
            return (HKObjectType.quantityType(forIdentifier: .walkingSpeed)!,
                    HKUnit.meter().unitDivided(by: .second()))
        case .stepLength:
            return (HKObjectType.quantityType(forIdentifier: .walkingStepLength)!, .meter())
        case .doubleSupport:
            return (HKObjectType.quantityType(forIdentifier: .walkingDoubleSupportPercentage)!, .percent())
        case .asymmetry:
            return (HKObjectType.quantityType(forIdentifier: .walkingAsymmetryPercentage)!, .percent())
        }
    }

    /// The HealthKit sample types Kampa enumerates for the "which devices are yours?"
    /// review — every metric it reads, minus the high-volume continuous streams (heart
    /// rate, steps) that would make the stats tally crawl. A foreign device shows up in
    /// one of these anyway (a synced watch writes sleep / workouts / gait).
    private static var sourceReviewTypes: [HKSampleType] {
        var types: [HKSampleType] = GaitMetric.allCases.map { gaitHKType($0).0 }
        types.append(HKObjectType.workoutType())
        types.append(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        types.append(HKObjectType.categoryType(forIdentifier: .mindfulSession)!)
        types.append(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!)
        types.append(HKObjectType.quantityType(forIdentifier: .bloodGlucose)!)
        return types
    }

    /// Distinct devices/apps that have written to any metric Kampa reads — powers the
    /// app-wide review. Phase 1: names only, via `HKSourceQuery`, which reads HealthKit's
    /// source index WITHOUT pulling a sample — so the list is instant. Counts and date
    /// spans arrive separately from `sourceStats()`. Deduped by canonical name (folds
    /// whitespace variants); Kampa's own bundle is dropped (you can't opt out of your own
    /// in-app logs).
    func fetchAllHealthSources() async -> [HealthSourceInfo] {
        let localBundleID = Bundle.main.bundleIdentifier
        var byKey: [String: String] = [:]   // canonical name → clean display name
        for type in Self.sourceReviewTypes {
            for src in await sources(for: type) {
                if src.bundleIdentifier == localBundleID { continue }
                let key = HealthSourcePrefs.canonical(src.name)
                if byKey[key] == nil {
                    byKey[key] = src.name.replacingOccurrences(of: "\u{00a0}", with: " ")
                }
            }
        }
        return byKey.values
            .map { HealthSourceInfo(name: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Phase 2: entry count + date span per source, keyed by canonical name. This IS the
    /// expensive pass (it scans samples), so it runs after the names are already on screen
    /// and the view merges the result in. Kampa's own bundle is skipped, matching the list.
    func sourceStats() async -> [String: HealthSourceInfo.Stats] {
        let start = Calendar.current.date(byAdding: .year, value: -12, to: Date()) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let localBundleID = Bundle.main.bundleIdentifier
        var tally: [String: (count: Int, first: Date, last: Date)] = [:]
        for type in Self.sourceReviewTypes {
            for s in await anySamples(type: type, predicate: predicate) {
                if s.sourceRevision.source.bundleIdentifier == localBundleID { continue }
                let key = HealthSourcePrefs.canonical(s.sourceRevision.source.name)
                if let e = tally[key] {
                    tally[key] = (e.count + 1, min(e.first, s.startDate), max(e.last, s.startDate))
                } else {
                    tally[key] = (1, s.startDate, s.startDate)
                }
            }
        }
        return tally.mapValues {
            HealthSourceInfo.Stats(count: $0.count, firstDate: $0.first, lastDate: $0.last)
        }
    }

    /// The sources (apps/devices) that have written samples of `type`. `HKSourceQuery`
    /// answers from HealthKit's index without fetching samples — cheap and fast.
    private func sources(for type: HKSampleType) async -> [HKSource] {
        await withCheckedContinuation { c in
            let q = HKSourceQuery(sampleType: type, samplePredicate: nil) { _, sources, _ in
                c.resume(returning: Array(sources ?? []))
            }
            store.execute(q)
        }
    }

    /// Generic sample fetch for the stats tally — works for quantity, category, and
    /// workout types (all `HKSample`), so one loop can count across metrics.
    private func anySamples(type: HKSampleType, predicate: NSPredicate) async -> [HKSample] {
        await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                c.resume(returning: s ?? [])
            }
            store.execute(q)
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
    ) async -> [(uuid: UUID, start: Date, duration: TimeInterval, isEditable: Bool, source: String)] {
        let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let localBundleID = Bundle.main.bundleIdentifier
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindfulType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let raw = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let samples = Self.includedSources(raw, excluded: HealthSourcePrefs.excluded)
                let mapped = samples.map { sample in
                    // Carry the sample's UUID so deletes can target it exactly; editable
                    // only if Kampa saved it (HealthKit forbids deleting other sources').
                    (sample.uuid,
                     sample.startDate,
                     sample.endDate.timeIntervalSince(sample.startDate),
                     sample.sourceRevision.source.bundleIdentifier == localBundleID,
                     sample.sourceRevision.source.name)
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    func writeMindfulSession(start: Date, duration: TimeInterval) async throws {
        let type = HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        let sample = HKCategorySample(type: type, value: 0,
                                      start: start, end: start.addingTimeInterval(duration))
        try await store.save(sample)
    }

    // MARK: - GI symptoms

    /// Write one GI symptom as a point-in-time `HKCategorySample` (start == end). Twin of
    /// `writeMindfulSession`; the same close-loop pattern (Apple Health is system-of-record).
    func writeGISymptom(_ symptom: GISymptom, severity: GISeverity, at date: Date) async throws {
        let sample = HKCategorySample(type: symptom.categoryType,
                                      value: severity.hkSeverity.rawValue,
                                      start: date, end: date)
        try await store.save(sample)
    }

    func deleteGISymptom(_ symptom: GISymptom, uuid: UUID) async throws {
        let predicate = HKQuery.predicateForObjects(with: [uuid])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: symptom.categoryType, predicate: predicate)],
            sortDescriptors: []
        )
        for sample in try await descriptor.result(for: store) {
            try await store.delete(sample)
        }
    }

    /// All logged GI symptoms in range, one HKSampleQuery per category (events are sparse,
    /// so 6 small queries is fine). `notPresent` samples are dropped — a confirmed-absent
    /// marker is not a timeline event.
    private func fetchGISymptomsInRange(from start: Date, to end: Date)
        async -> [(uuid: UUID, time: Date, symptom: GISymptom, severity: GISeverity, isEditable: Bool)] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let localBundleID = Bundle.main.bundleIdentifier
        var out: [(uuid: UUID, time: Date, symptom: GISymptom, severity: GISeverity, isEditable: Bool)] = []
        for symptom in GISymptom.allCases {
            let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: symptom.categoryType, predicate: predicate,
                    limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
                ) { _, samples, _ in
                    continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
                }
                store.execute(query)
            }
            for sample in samples {
                guard let severity = GISeverity(hkValue: sample.value) else { continue }
                out.append((sample.uuid, sample.startDate, symptom, severity,
                            sample.sourceRevision.source.bundleIdentifier == localBundleID))
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    func deleteMindfulSession(uuid: UUID) async throws {
        let type = HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        let predicate = HKQuery.predicateForObjects(with: [uuid])
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
                guard let raw = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let samples = Self.includedSources(raw, excluded: HealthSourcePrefs.excluded)
                let totalSeconds = samples.reduce(0.0) {
                    $0 + $1.endDate.timeIntervalSince($1.startDate)
                }
                continuation.resume(returning: totalSeconds / 60.0)
            }
            store.execute(query)
        }
    }
}
