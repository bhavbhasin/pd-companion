import HealthKit
import Foundation

@MainActor
enum HealthKitExporter {
    static func exportAll(to folder: URL, store: HKHealthStore) async {
        await exportQuantity(.heartRate, unit: bpm, name: "heart_rate", folder: folder, store: store)
        await exportQuantity(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), name: "hrv_sdnn_ms", folder: folder, store: store)
        await exportQuantity(.restingHeartRate, unit: bpm, name: "resting_heart_rate", folder: folder, store: store)
        await exportQuantity(.respiratoryRate, unit: bpm, name: "respiratory_rate", folder: folder, store: store)
        await exportQuantity(.oxygenSaturation, unit: .percent(), name: "oxygen_saturation", folder: folder, store: store)
        await exportQuantity(.stepCount, unit: .count(), name: "step_count", folder: folder, store: store)
        await exportQuantity(.appleExerciseTime, unit: .minute(), name: "exercise_time_minutes", folder: folder, store: store)
        await exportQuantity(.timeInDaylight, unit: .minute(), name: "daylight_minutes", folder: folder, store: store)
        await exportQuantity(.activeEnergyBurned, unit: .kilocalorie(), name: "active_energy_kcal", folder: folder, store: store)
        await exportQuantity(.basalEnergyBurned, unit: .kilocalorie(), name: "basal_energy_kcal", folder: folder, store: store)
        await exportQuantity(.walkingSpeed, unit: HKUnit.meter().unitDivided(by: .second()), name: "walking_speed_m_s", folder: folder, store: store)
        await exportQuantity(.walkingAsymmetryPercentage, unit: .percent(), name: "walking_asymmetry_pct", folder: folder, store: store)
        await exportQuantity(.walkingDoubleSupportPercentage, unit: .percent(), name: "walking_double_support_pct", folder: folder, store: store)
        await exportQuantity(.walkingStepLength, unit: .meter(), name: "walking_step_length_m", folder: folder, store: store)

        await exportSleep(folder: folder, store: store)
        await exportMindfulness(folder: folder, store: store)
        await exportWorkouts(folder: folder, store: store)
        await exportMedicationDoses(folder: folder, store: store)
    }

    // MARK: - Quantity samples

    private static func exportQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        name: String,
        folder: URL,
        store: HKHealthStore
    ) async {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
        let samples = await fetchSamples(type: type, store: store)
        let quantity = samples.compactMap { $0 as? HKQuantitySample }

        var rows: [[String]] = []
        for s in quantity {
            rows.append([
                iso(s.startDate),
                iso(s.endDate),
                String(s.quantity.doubleValue(for: unit)),
                s.sourceRevision.source.name,
                s.device?.name ?? ""
            ])
        }
        writeCSV(
            header: ["startDate", "endDate", "value", "source", "device"],
            rows: rows,
            to: folder.appendingPathComponent(filename(name, range: dateRange(quantity.map(\.startDate))))
        )
        print("HK exported \(name): \(rows.count) samples")
    }

    // MARK: - Sleep stages

    private static func exportSleep(folder: URL, store: HKHealthStore) async {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let samples = await fetchSamples(type: type, store: store)
        let category = samples.compactMap { $0 as? HKCategorySample }

        var rows: [[String]] = []
        for s in category {
            rows.append([
                iso(s.startDate),
                iso(s.endDate),
                sleepStageName(s.value),
                s.sourceRevision.source.name,
                s.device?.name ?? ""
            ])
        }
        writeCSV(
            header: ["startDate", "endDate", "stage", "source", "device"],
            rows: rows,
            to: folder.appendingPathComponent(filename("sleep_stages", range: dateRange(category.map(\.startDate))))
        )
        print("HK exported sleep_stages: \(rows.count) segments")
    }

    private static func sleepStageName(_ value: Int) -> String {
        guard let stage = HKCategoryValueSleepAnalysis(rawValue: value) else {
            return "unknown(\(value))"
        }
        switch stage {
        case .inBed:             return "inBed"
        case .asleepUnspecified: return "asleepUnspecified"
        case .awake:             return "awake"
        case .asleepCore:        return "asleepCore"
        case .asleepDeep:        return "asleepDeep"
        case .asleepREM:         return "asleepREM"
        @unknown default:        return "unknown(\(value))"
        }
    }

    // MARK: - Mindfulness

    private static func exportMindfulness(folder: URL, store: HKHealthStore) async {
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return }
        let samples = await fetchSamples(type: type, store: store)
        let category = samples.compactMap { $0 as? HKCategorySample }

        var rows: [[String]] = []
        for s in category {
            let durationMin = s.endDate.timeIntervalSince(s.startDate) / 60
            rows.append([
                iso(s.startDate),
                iso(s.endDate),
                String(durationMin),
                s.sourceRevision.source.name
            ])
        }
        writeCSV(
            header: ["startDate", "endDate", "durationMinutes", "source"],
            rows: rows,
            to: folder.appendingPathComponent(filename("mindfulness_sessions", range: dateRange(category.map(\.startDate))))
        )
        print("HK exported mindfulness_sessions: \(rows.count) sessions")
    }

    // MARK: - Workouts

    private static func exportWorkouts(folder: URL, store: HKHealthStore) async {
        let samples = await fetchSamples(type: HKObjectType.workoutType(), store: store)
        let workouts = samples.compactMap { $0 as? HKWorkout }

        var rows: [[String]] = []
        for w in workouts {
            let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            let distance = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter()) ?? 0
            rows.append([
                iso(w.startDate),
                iso(w.endDate),
                String(w.duration / 60),
                workoutTypeName(w.workoutActivityType),
                String(energy),
                String(distance),
                w.sourceRevision.source.name
            ])
        }
        writeCSV(
            header: ["startDate", "endDate", "durationMinutes", "activityType", "activeEnergyKcal", "distanceMeters", "source"],
            rows: rows,
            to: folder.appendingPathComponent(filename("workouts", range: dateRange(workouts.map(\.startDate))))
        )
        print("HK exported workouts: \(rows.count) workouts")
    }

    private static func workoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .americanFootball: return "americanFootball"
        case .archery: return "archery"
        case .australianFootball: return "australianFootball"
        case .badminton: return "badminton"
        case .baseball: return "baseball"
        case .basketball: return "basketball"
        case .bowling: return "bowling"
        case .boxing: return "boxing"
        case .climbing: return "climbing"
        case .cricket: return "cricket"
        case .crossTraining: return "crossTraining"
        case .curling: return "curling"
        case .cycling: return "cycling"
        case .dance: return "dance"
        case .danceInspiredTraining: return "danceInspiredTraining"
        case .elliptical: return "elliptical"
        case .equestrianSports: return "equestrianSports"
        case .fencing: return "fencing"
        case .fishing: return "fishing"
        case .functionalStrengthTraining: return "functionalStrengthTraining"
        case .golf: return "golf"
        case .gymnastics: return "gymnastics"
        case .handball: return "handball"
        case .hiking: return "hiking"
        case .hockey: return "hockey"
        case .hunting: return "hunting"
        case .lacrosse: return "lacrosse"
        case .martialArts: return "martialArts"
        case .mindAndBody: return "mindAndBody"
        case .paddleSports: return "paddleSports"
        case .play: return "play"
        case .preparationAndRecovery: return "preparationAndRecovery"
        case .racquetball: return "racquetball"
        case .rowing: return "rowing"
        case .rugby: return "rugby"
        case .running: return "running"
        case .sailing: return "sailing"
        case .skatingSports: return "skatingSports"
        case .snowSports: return "snowSports"
        case .soccer: return "soccer"
        case .softball: return "softball"
        case .squash: return "squash"
        case .stairClimbing: return "stairClimbing"
        case .surfingSports: return "surfingSports"
        case .swimming: return "swimming"
        case .tableTennis: return "tableTennis"
        case .tennis: return "tennis"
        case .trackAndField: return "trackAndField"
        case .traditionalStrengthTraining: return "traditionalStrengthTraining"
        case .volleyball: return "volleyball"
        case .walking: return "walking"
        case .waterFitness: return "waterFitness"
        case .waterPolo: return "waterPolo"
        case .waterSports: return "waterSports"
        case .wrestling: return "wrestling"
        case .yoga: return "yoga"
        case .barre: return "barre"
        case .coreTraining: return "coreTraining"
        case .crossCountrySkiing: return "crossCountrySkiing"
        case .downhillSkiing: return "downhillSkiing"
        case .flexibility: return "flexibility"
        case .highIntensityIntervalTraining: return "highIntensityIntervalTraining"
        case .jumpRope: return "jumpRope"
        case .kickboxing: return "kickboxing"
        case .pilates: return "pilates"
        case .snowboarding: return "snowboarding"
        case .stairs: return "stairs"
        case .stepTraining: return "stepTraining"
        case .wheelchairWalkPace: return "wheelchairWalkPace"
        case .wheelchairRunPace: return "wheelchairRunPace"
        case .taiChi: return "taiChi"
        case .mixedCardio: return "mixedCardio"
        case .handCycling: return "handCycling"
        case .discSports: return "discSports"
        case .fitnessGaming: return "fitnessGaming"
        case .cardioDance: return "cardioDance"
        case .socialDance: return "socialDance"
        case .pickleball: return "pickleball"
        case .cooldown: return "cooldown"
        case .swimBikeRun: return "swimBikeRun"
        case .transition: return "transition"
        case .other: return "other"
        @unknown default: return "unknown(\(type.rawValue))"
        }
    }

    // MARK: - Medication doses

    private static func exportMedicationDoses(folder: URL, store: HKHealthStore) async {
        let type = HKObjectType.medicationDoseEventType()
        let medMap = await fetchMedicationNameMap(store: store)
        let samples = await fetchSamples(type: type, store: store)
        let doses = samples.compactMap { $0 as? HKMedicationDoseEvent }

        var rows: [[String]] = []
        for d in doses {
            let name = medMap[d.medicationConceptIdentifier] ?? ""
            rows.append([
                iso(d.startDate),
                iso(d.endDate),
                medicationDoseStatusName(d.logStatus),
                name,
                String(describing: d.medicationConceptIdentifier),
                d.sourceRevision.source.name
            ])
        }
        writeCSV(
            header: ["startDate", "endDate", "status", "medicationName", "conceptIdentifier", "source"],
            rows: rows,
            to: folder.appendingPathComponent(filename("medication_doses", range: dateRange(doses.map(\.startDate))))
        )
        print("HK exported medication_doses: \(rows.count) events")
    }

    private static func fetchMedicationNameMap(store: HKHealthStore) async -> [HKHealthConceptIdentifier: String] {
        let descriptor = HKUserAnnotatedMedicationQueryDescriptor(predicate: nil)
        do {
            let medications = try await descriptor.result(for: store)
            var map: [HKHealthConceptIdentifier: String] = [:]
            for med in medications {
                map[med.medication.identifier] = med.nickname ?? med.medication.displayText
            }
            return map
        } catch {
            print("fetchMedicationNameMap failed: \(error)")
            return [:]
        }
    }

    private static func medicationDoseStatusName(_ status: HKMedicationDoseEvent.LogStatus) -> String {
        switch status {
        case .taken:    return "taken"
        case .skipped:  return "skipped"
        case .snoozed:  return "snoozed"
        case .notLogged: return "notLogged"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    // MARK: - Helpers

    private static func fetchSamples(type: HKSampleType, store: HKHealthStore) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    print("HK fetch failed for \(type.identifier): \(error.localizedDescription)")
                }
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }
    }

    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    private static func writeCSV(header: [String], rows: [[String]], to url: URL) {
        var content = header.map(escape).joined(separator: ",")
        for row in rows {
            content += "\n" + row.map(escape).joined(separator: ",")
        }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dateRange(_ dates: [Date]) -> (first: Date, last: Date)? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return (first, last)
    }

    private static func filename(_ base: String, range: (first: Date, last: Date)?) -> String {
        guard let range else { return "\(base).csv" }
        let from = filenameDateFormatter.string(from: range.first)
        let to = filenameDateFormatter.string(from: range.last)
        return from == to ? "\(base)_\(from).csv" : "\(base)_\(from)_to_\(to).csv"
    }
}
