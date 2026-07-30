import HealthKit
import Foundation

/// Writes the user's HealthKit history out as CSV files.
///
/// Deliberately NOT `@MainActor`: every fetch, row build and file write used to hop to
/// the main thread, which is what made the export freeze the UI rather than merely take
/// a while. Nonisolated `async` work runs on the cooperative pool instead (SE-0338).
enum HealthKitExporter {

    /// How many exports run at once.
    ///
    /// This is a memory ceiling as much as a speed dial. `HKSampleQuery` hands back the
    /// whole result set at once, so each in-flight export holds its entire sample array —
    /// and the largest measured file was 1.53M samples (active energy). Unbounded
    /// concurrency would hold every one of those simultaneously and risk a jetsam kill on
    /// the iPhone 11 / SE2 device floor. Raise this only with the Xcode memory gauge open.
    private static let maxConcurrentExports = 3

    static func exportAll(to folder: URL, store: HKHealthStore) async {
        let exportStart = CFAbsoluteTimeGetCurrent()

        let quantities: [(id: HKQuantityTypeIdentifier, unit: HKUnit, name: String)] = [
            (.heartRate, bpm, "heart_rate"),
            (.heartRateVariabilitySDNN, HKUnit.secondUnit(with: .milli), "hrv_sdnn_ms"),
            (.restingHeartRate, bpm, "resting_heart_rate"),
            (.respiratoryRate, bpm, "respiratory_rate"),
            (.oxygenSaturation, .percent(), "oxygen_saturation"),
            (.stepCount, .count(), "step_count"),
            (.appleExerciseTime, .minute(), "exercise_time_minutes"),
            (.timeInDaylight, .minute(), "daylight_minutes"),
            (.activeEnergyBurned, .kilocalorie(), "active_energy_kcal"),
            (.basalEnergyBurned, .kilocalorie(), "basal_energy_kcal"),
            (.walkingSpeed, HKUnit.meter().unitDivided(by: .second()), "walking_speed_m_s"),
            (.walkingAsymmetryPercentage, .percent(), "walking_asymmetry_pct"),
            (.walkingDoubleSupportPercentage, .percent(), "walking_double_support_pct"),
            (.walkingStepLength, .meter(), "walking_step_length_m")
        ]

        var jobs: [() async -> Void] = quantities.map { quantity in
            { await exportQuantity(quantity.id, unit: quantity.unit, name: quantity.name, folder: folder, store: store) }
        }
        jobs.append { await exportSleep(folder: folder, store: store) }
        jobs.append { await exportMindfulness(folder: folder, store: store) }
        jobs.append { await exportWorkouts(folder: folder, store: store) }
        jobs.append { await exportMedicationDoses(folder: folder, store: store) }

        // Sliding window: start `maxConcurrentExports`, then start one more each time
        // one finishes. Files are independent and each writes its own path, so there is
        // no shared state to guard.
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            while next < min(maxConcurrentExports, jobs.count) {
                let job = jobs[next]
                group.addTask { await job() }
                next += 1
            }
            while await group.next() != nil {
                guard next < jobs.count else { continue }
                let job = jobs[next]
                group.addTask { await job() }
                next += 1
            }
        }

        print(String(format: "[export-timing] TOTAL exportAll %.2fs", CFAbsoluteTimeGetCurrent() - exportStart))
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
        let tFetch = CFAbsoluteTimeGetCurrent()
        let samples = await fetchSamples(type: type, store: store)
        let tBuild = CFAbsoluteTimeGetCurrent()
        let quantity = samples.compactMap { $0 as? HKQuantitySample }
        let url = folder.appendingPathComponent(filename(name, range: startDateRange(quantity)))

        let tWrite = CFAbsoluteTimeGetCurrent()
        guard let writer = CSVStreamWriter(
            destination: url,
            header: ["startDate", "endDate", "value", "source", "device"]
        ) else { return }
        for s in quantity {
            writer.write([
                iso(s.startDate),
                iso(s.endDate),
                String(s.quantity.doubleValue(for: unit)),
                s.sourceRevision.source.name,
                s.device?.name ?? ""
            ])
        }
        writer.finish()
        logPhases(name, count: quantity.count, unit: "samples", fetch: tFetch, build: tBuild, write: tWrite)
    }

    // MARK: - Sleep stages

    private static func exportSleep(folder: URL, store: HKHealthStore) async {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let tFetch = CFAbsoluteTimeGetCurrent()
        let samples = await fetchSamples(type: type, store: store)
        let tBuild = CFAbsoluteTimeGetCurrent()
        let category = samples.compactMap { $0 as? HKCategorySample }
        let url = folder.appendingPathComponent(filename("sleep_stages", range: startDateRange(category)))

        let tWrite = CFAbsoluteTimeGetCurrent()
        guard let writer = CSVStreamWriter(
            destination: url,
            header: ["startDate", "endDate", "stage", "source", "device"]
        ) else { return }
        for s in category {
            writer.write([
                iso(s.startDate),
                iso(s.endDate),
                sleepStageName(s.value),
                s.sourceRevision.source.name,
                s.device?.name ?? ""
            ])
        }
        writer.finish()
        logPhases("sleep_stages", count: category.count, unit: "segments", fetch: tFetch, build: tBuild, write: tWrite)
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
        let tFetch = CFAbsoluteTimeGetCurrent()
        let samples = await fetchSamples(type: type, store: store)
        let tBuild = CFAbsoluteTimeGetCurrent()
        let category = samples.compactMap { $0 as? HKCategorySample }
        let url = folder.appendingPathComponent(filename("mindfulness_sessions", range: startDateRange(category)))

        let tWrite = CFAbsoluteTimeGetCurrent()
        guard let writer = CSVStreamWriter(
            destination: url,
            header: ["startDate", "endDate", "durationMinutes", "source"]
        ) else { return }
        for s in category {
            let durationMin = s.endDate.timeIntervalSince(s.startDate) / 60
            writer.write([
                iso(s.startDate),
                iso(s.endDate),
                String(durationMin),
                s.sourceRevision.source.name
            ])
        }
        writer.finish()
        logPhases("mindfulness_sessions", count: category.count, unit: "sessions", fetch: tFetch, build: tBuild, write: tWrite)
    }

    // MARK: - Workouts

    private static func exportWorkouts(folder: URL, store: HKHealthStore) async {
        let tFetch = CFAbsoluteTimeGetCurrent()
        let samples = await fetchSamples(type: HKObjectType.workoutType(), store: store)
        let tBuild = CFAbsoluteTimeGetCurrent()
        let workouts = samples.compactMap { $0 as? HKWorkout }
        let url = folder.appendingPathComponent(filename("workouts", range: startDateRange(workouts)))

        let tWrite = CFAbsoluteTimeGetCurrent()
        guard let writer = CSVStreamWriter(
            destination: url,
            header: ["startDate", "endDate", "durationMinutes", "activityType", "activeEnergyKcal", "distanceMeters", "source"]
        ) else { return }
        for w in workouts {
            let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            let distance = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter()) ?? 0
            writer.write([
                iso(w.startDate),
                iso(w.endDate),
                String(w.duration / 60),
                workoutTypeName(w.workoutActivityType),
                String(energy),
                String(distance),
                w.sourceRevision.source.name
            ])
        }
        writer.finish()
        logPhases("workouts", count: workouts.count, unit: "workouts", fetch: tFetch, build: tBuild, write: tWrite)
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
        // `default` (not `@unknown default`): HKWorkoutActivityType is a large,
        // non-frozen Apple enum and the only "missing" known case is the deprecated
        // `.mixedMetabolicCardioTraining`, which we don't want to name (deprecation
        // warning). This is a debug/CSV name mapper — an unmapped type stringifies to
        // "unknown(N)" either way, so exhaustive future-proofing has no value here.
        default: return "unknown(\(type.rawValue))"
        }
    }

    // MARK: - Medication doses

    private static func exportMedicationDoses(folder: URL, store: HKHealthStore) async {
        let type = HKObjectType.medicationDoseEventType()
        let tFetch = CFAbsoluteTimeGetCurrent()
        let medMap = await fetchMedicationNameMap(store: store)
        let samples = await fetchSamples(type: type, store: store)
        let tBuild = CFAbsoluteTimeGetCurrent()
        let doses = samples.compactMap { $0 as? HKMedicationDoseEvent }
        let url = folder.appendingPathComponent(filename("medication_doses", range: startDateRange(doses)))

        let tWrite = CFAbsoluteTimeGetCurrent()
        guard let writer = CSVStreamWriter(
            destination: url,
            header: ["startDate", "endDate", "status", "medicationName", "conceptIdentifier", "source"]
        ) else { return }
        for d in doses {
            let name = medMap[d.medicationConceptIdentifier] ?? ""
            writer.write([
                iso(d.startDate),
                iso(d.endDate),
                medicationDoseStatusName(d.logStatus),
                name,
                String(describing: d.medicationConceptIdentifier),
                d.sourceRevision.source.name
            ])
        }
        writer.finish()
        logPhases("medication_doses", count: doses.count, unit: "events", fetch: tFetch, build: tBuild, write: tWrite)
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
        case .notInteracted: return "notInteracted"
        case .notificationNotSent: return "notificationNotSent"
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

    // MARK: - Export timing (TEMPORARY — Step 0 of the CSV-export performance fix)
    // Splits each export into fetch / build / write so the fix targets the phase that
    // actually dominates rather than the one that reads worst. Remove once that lands;
    // grep `[export-timing]`. Run a RELEASE build — Debug inflates build and write.
    //
    // ⚠️ Phase boundaries MOVED when the streaming writer landed: row construction used to
    // sit in `build` and now happens inside the write loop, so `build` is just the
    // `compactMap` and `write` covers row formatting plus I/O. Don't compare the two runs
    // phase-by-phase — compare totals. Per-file totals are also no longer additive, since
    // exports now overlap; `TOTAL exportAll` is the only true wall clock.

    private static func logPhases(
        _ name: String,
        count: Int,
        unit: String,
        fetch tFetch: CFAbsoluteTime,
        build tBuild: CFAbsoluteTime,
        write tWrite: CFAbsoluteTime
    ) {
        let end = CFAbsoluteTimeGetCurrent()
        let ms = { (seconds: CFAbsoluteTime) in String(format: "%.0f", seconds * 1000) }
        print("[export-timing] \(name): \(count) \(unit) | fetch \(ms(tBuild - tFetch))ms"
            + " | build \(ms(tWrite - tBuild))ms | write \(ms(end - tWrite))ms"
            + " | total \(ms(end - tFetch))ms")
    }

    /// First and last `startDate` of an already-sorted sample array.
    ///
    /// `fetchSamples` sorts ascending by `startDate`, so first/last ARE min/max — no need
    /// to materialise a second array of up to 1.5M dates just to find them.
    private static func startDateRange(_ samples: [HKSample]) -> (first: Date, last: Date)? {
        guard let first = samples.first, let last = samples.last else { return nil }
        return (first: first.startDate, last: last.startDate)
    }

    /// Streams CSV rows straight to disk instead of assembling the whole file in memory.
    ///
    /// The previous version built an intermediate `[[String]]` of every row AND a single
    /// concatenated `String` of the entire file, so four full representations of the data
    /// were alive at once — roughly 90MB of text for active energy alone, on top of the
    /// row array. This holds one small buffer instead.
    ///
    /// Output is byte-identical to the old `writeCSV`: header first with no leading
    /// newline, every subsequent row prefixed with one, and no trailing newline. The
    /// write goes to a `.partial` file that is moved into place at the end, preserving
    /// the atomicity that `String.write(to:atomically:)` used to provide.
    private final class CSVStreamWriter {
        /// Rows buffered before hitting the filesystem. A few hundred KB — rare syscalls,
        /// negligible next to the sample array itself. Counted in rows, not bytes, because
        /// measuring a Swift `String`'s length is itself O(n).
        private static let flushEveryRows = 8_192

        private let destination: URL
        private let temporary: URL
        private let handle: FileHandle
        private var buffer = ""
        private var rowsSinceFlush = 0
        private var failed = false

        init?(destination: URL, header: [String]) {
            self.destination = destination
            self.temporary = destination.appendingPathExtension("partial")

            let manager = FileManager.default
            try? manager.removeItem(at: temporary)
            guard manager.createFile(atPath: temporary.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: temporary) else {
                print("[export] could not open \(temporary.lastPathComponent) for writing")
                return nil
            }
            self.handle = handle
            append(header, leadingNewline: false)
        }

        func write(_ fields: [String]) {
            append(fields, leadingNewline: true)
            rowsSinceFlush += 1
            if rowsSinceFlush >= Self.flushEveryRows { flush() }
        }

        /// Flushes the tail and moves the completed file into place. Must be called, or
        /// the export leaves a `.partial` file and no real one.
        ///
        /// If any write failed (disk full, most likely), the partial file is discarded
        /// rather than published. Streaming would otherwise be a silent downgrade on the
        /// old atomic write: a truncated CSV that looks complete is worse than no CSV,
        /// because nothing downstream can tell it was cut short.
        func finish() {
            flush()
            try? handle.close()
            let manager = FileManager.default
            guard !failed else {
                try? manager.removeItem(at: temporary)
                return
            }
            try? manager.removeItem(at: destination)
            try? manager.moveItem(at: temporary, to: destination)
        }

        private func append(_ fields: [String], leadingNewline: Bool) {
            if leadingNewline { buffer.append("\n") }
            var isFirst = true
            for field in fields {
                if !isFirst { buffer.append(",") }
                isFirst = false
                appendEscaped(field)
            }
        }

        private func appendEscaped(_ field: String) {
            let needsQuoting = field.contains(",") || field.contains("\"")
                || field.contains("\n") || field.contains("\r")
            guard needsQuoting else {
                buffer.append(field)
                return
            }
            buffer.append("\"")
            buffer.append(field.replacingOccurrences(of: "\"", with: "\"\""))
            buffer.append("\"")
        }

        private func flush() {
            rowsSinceFlush = 0
            guard !buffer.isEmpty, let data = buffer.data(using: .utf8) else { return }
            do {
                try handle.write(contentsOf: data)
            } catch {
                failed = true
                print("[export] write failed for \(destination.lastPathComponent): \(error.localizedDescription)")
            }
            buffer.removeAll(keepingCapacity: true)
        }
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
