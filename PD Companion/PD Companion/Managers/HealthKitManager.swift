import HealthKit
import Foundation
import Combine

@MainActor
class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var todaySnapshot: HealthSample?
    @Published var error: String?

    private let readTypes: Set<HKObjectType> = {
        let types: [HKObjectType] = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
        ]
        return Set(types)
    }()

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            error = "HealthKit is not available on this device."
            return
        }

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
        } catch {
            self.error = "HealthKit authorization failed: \(error.localizedDescription)"
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
