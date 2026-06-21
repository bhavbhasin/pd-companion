import Foundation

// MARK: - Correlation engine (Swift port of the Python lab)
//
// Deterministic statistics on the patient's own timeline — NOT machine learning.
// The engine computes; narration/LLM comes later. This is the Swift + Accelerate
// port of the validated `analysis/` lab. Plain Swift is used where the work is
// event-alignment/binning (clearer + correct); Accelerate/vDSP can optimize the
// bulk reductions later without changing results.
//
// PURE: takes arrays in, returns [Insight] out. No HealthKit / SwiftData access
// here — data plumbing (multi-day dose fetch) and view wiring live elsewhere, so
// this stays unit-testable for parity against the Python output.
//
// Parity targets (from analysis/NOTES.md, 18-06-2026 backup):
//   • afternoon onset ~67 min vs morning ~38 min
//   • KM median ON-duration ~192 min   (wearing-off module — next step)

/// A levodopa dose event (Sinemet / Mucuna). In the app these come from HealthKit;
/// in tests they come from the CSV backup. `Sendable` so it can be handed to the
/// engine on a background thread.
struct Dose: Sendable {
    let timestamp: Date
    let name: String
}

/// A discrete workout event — the canonical shape the engine's event primitives
/// (windowed-effect, etc.) consume. The activity type is carried as a raw `UInt`
/// (HealthKit's `HKWorkoutActivityType.rawValue`) so the engine stays
/// HealthKit-free and CSV-testable; the adapter (`HealthKitManager
/// .fetchWorkoutEvents`) maps `HKWorkout` into this. One adapter brings in every
/// activity type — Tai Chi, boxing, pickleball, tango — each tagged, not coded.
struct WorkoutEvent: Sendable {
    let start: Date
    let duration: TimeInterval
    let activityRawValue: UInt
}

/// A lightweight, `Sendable` snapshot of a tremor reading — only the fields the
/// engine reads. The app maps its SwiftData `TremorReading`s into these *on the main
/// actor*, so the engine can run off the main thread without ever touching managed
/// objects (which are not thread-safe). Keeps the engine fully decoupled from
/// SwiftData, as its header promises.
struct TremorPoint: Sendable {
    let timestamp: Date
    let tremorScore: Double
}

/// One mobility-metric reading (a value at a time). `Sendable` so the gait analysis
/// runs off the main thread like the tremor work. Foreign-source filtering happens at
/// fetch time, so by here every sample is the user's own.
struct GaitSample: Sendable {
    let date: Date
    let value: Double
}

/// A distinct device/source contributing gait data, with how much and over what span —
/// powers the "which devices are yours?" review. `Identifiable` for the SwiftUI list.
struct GaitSourceInfo: Sendable, Identifiable {
    let name: String
    let count: Int
    let firstDate: Date
    let lastDate: Date
    var id: String { name }
}

/// The four Apple mobility metrics tracked for PD *progression* (years, not days).
/// Each carries the physiological clip range and which direction means worsening —
/// the analysis parameters validated in the Python lab (analysis/src/gait.py). The
/// HealthKit identifier/unit mapping lives in HealthKitManager so HK specifics stay
/// out of the engine. `nonisolated` so the off-main engine can read these properties.
nonisolated enum GaitMetric: String, CaseIterable, Sendable {
    case walkingSpeed, stepLength, doubleSupport, asymmetry

    var display: String {
        switch self {
        case .walkingSpeed:  "Walking speed"
        case .stepLength:    "Step length"
        case .doubleSupport: "Double support"
        case .asymmetry:     "Walking asymmetry"
        }
    }

    /// Display unit. The percentage metrics are stored as fractions; a view that shows
    /// them as "%" must scale by 100 (the hero chart is walking speed, in m/s).
    var unit: String {
        switch self {
        case .walkingSpeed:  "m/s"
        case .stepLength:    "m"
        case .doubleSupport, .asymmetry: "%"
        }
    }

    /// Physiological clip [lo, hi]; values outside are sensor noise and get dropped.
    /// The percentage metrics are fractions (HealthKit `.percent()` returns 0–1),
    /// matching the lab's clip ranges.
    var clip: (lo: Double, hi: Double) {
        switch self {
        case .walkingSpeed:  (0.3, 2.0)
        case .stepLength:    (0.3, 1.0)
        case .doubleSupport: (0.1, 0.45)
        case .asymmetry:     (0.0, 0.30)
        }
    }

    /// True when an INCREASE is the worsening direction (double-support, asymmetry);
    /// false when a DECREASE is worsening (walking speed, step length).
    var higherIsWorse: Bool {
        switch self {
        case .doubleSupport, .asymmetry: true
        case .walkingSpeed, .stepLength: false
        }
    }
}

// `nonisolated`: the project defaults types to `@MainActor` isolation
// (SWIFT_DEFAULT_ACTOR_ISOLATION). The engine is pure, stateless computation that we
// deliberately run off the main thread — so it must opt out of main-actor isolation.
nonisolated enum CorrelationEngine {

    /// Calendar used for all time-of-day bucketing. Defaults to the device's
    /// calendar (= the patient's local time); tests override it to pin a timezone
    /// so parity against the Pacific-based Python lab is deterministic.
    /// `nonisolated(unsafe)`: single-writer (only a test sets it, before running) —
    /// the app never mutates it, so there is no concurrent access to guard.
    nonisolated(unsafe) static var calendar: Calendar = .current

    // Entry point: run every module, return the surfaced insights.
    static func generateInsights(samples: [TremorPoint], doses: [Dose],
                                 gait: [GaitMetric: [GaitSample]] = [:],
                                 workouts: [WorkoutEvent] = []) -> [Insight] {
        // The registry now DRIVES execution: walk the active questions in order
        // and dispatch each to its analysis. Entries whose primitive isn't built
        // yet (the exercise / sleep / diet cluster) return nil and stay dormant —
        // the "ship the question, light up when the data earns it" model.
        InsightRegistry.starter
            .filter { $0.status == .active }
            .compactMap { run($0, samples: samples, doses: doses, gait: gait, workouts: workouts) }
    }

    /// Dispatch one registry entry to the analysis that answers it.
    ///
    /// TRANSITIONAL: the three validated analyses are still bespoke functions, so
    /// they're routed explicitly by `entry.id`. As each generic primitive lands
    /// (windowed-effect, overnight-lag, …) these explicit routes collapse into a
    /// real dispatch keyed on `entry.primitive` over catalog-extracted shapes —
    /// at which point a new exercise entry needs no code here, only its registry line.
    /// `workouts` is now plumbed in (the adapter is live); the windowed-effect
    /// primitive that consumes it is the next step.
    static func run(_ entry: RegistryEntry, samples: [TremorPoint], doses: [Dose],
                    gait: [GaitMetric: [GaitSample]], workouts: [WorkoutEvent]) -> Insight? {
        // The three validated analyses are still bespoke functions (transitional,
        // routed by id). Everything else dispatches generically on the primitive —
        // a new registry line over a built primitive needs no code here.
        switch entry.id {
        case "dose-tremor-by-tod":      return afternoonDoseInsight(samples: samples, doses: doses)
        case "dose-tremor-wearing-off": return wearingOffInsight(samples: samples, doses: doses)
        case "gait-speed-trend":        return gaitInsight(series: gait)
        default:                        break
        }
        switch entry.primitive {
        case .windowedEffect(let preMin, let postMin):
            return windowedEffectInsight(entry: entry, samples: samples,
                                         workouts: workouts, preMin: preMin, postMin: postMin)
        default:
            return nil   // primitive not yet implemented
        }
    }

    /// Render a windowed-effect registry entry into a card. Today only the
    /// workout → tremor path is wired (workouts are adapted in; tremor is in the
    /// snapshot). Other exposures/outcomes return nil until their adapters land —
    /// the entries stay registered but dormant.
    static func windowedEffectInsight(
        entry: RegistryEntry, samples: [TremorPoint], workouts: [WorkoutEvent],
        preMin: Double, postMin: Double
    ) -> Insight? {
        guard let raw = entry.exposure.workoutRawValue, entry.outcome.isTremor else { return nil }
        let events = workouts
            .filter { $0.activityRawValue == raw }
            .map { (start: $0.start, end: $0.start.addingTimeInterval($0.duration)) }
        guard !events.isEmpty else { return nil }
        let signal = samples.map { (time: $0.timestamp, value: $0.tremorScore) }
        guard let eff = windowedEffect(events: events, signal: signal,
                                       preMin: preMin, postMin: postMin) else { return nil }
        guard let confidence = gate(Self.windowedEffectGate, n: eff.n,
                                    effect: abs(eff.delta), p: eff.pValue) else { return nil }

        let activity = entry.exposure.workoutDisplayName ?? "this activity"
        let lower = activity.lowercased()
        let hours = max(1, Int((postMin / 60).rounded()))
        let pct = abs(eff.pctChange).isFinite ? String(format: "%.0f%%", abs(eff.pctChange)) : "—"
        let days = Set(events.map { calendar.startOfDay(for: $0.start) }).count
        let significant = confidence != .emerging
        let eased = eff.delta < 0

        let title: String, summary: String
        switch (significant, eased) {
        case (true, true):
            title = "\(activity) may ease your tremor"
            summary = "In the \(hours)h after \(lower), your tremor ran about \(pct) lower than the stretch just before."
        case (true, false):
            title = "\(activity) may stir your tremor"
            summary = "In the \(hours)h after \(lower), your tremor ran about \(pct) higher than the stretch just before."
        default:
            title = "\(activity): no clear tremor effect yet"
            summary = "Across \(eff.n) sessions, the before-vs-after difference is still within the noise. Keeping watch."
        }

        let finding = "From \(eff.n) \(lower) session\(eff.n == 1 ? "" : "s") over \(days) day\(days == 1 ? "" : "s"): tremor \(eased ? "down" : "up") ~\(pct) in the \(hours)h after vs. the \(Int(preMin)) min before. An association in your own data — a hypothesis to test, not proof."
        let mechanism = "Exercise can shift PD motor symptoms for a while afterward, but daily tremor has many drivers — sleep, stress, and medication timing among them. Treat this as a lead to test, not a conclusion."

        var insight = Insight(
            title: title, summary: summary, stage: .hypothesis,
            finding: finding, mechanism: mechanism,
            confidence: confidence, evidenceDays: days)
        insight.chart = windowedEffectChart(
            events: events, signal: signal, preMin: preMin, postMin: postMin,
            activityLabel: activity)
        return insight
    }
}

// MARK: - Confidence gate (one shared function, per-hypothesis thresholds)
//
// Different analyses speak different statistical languages: autocorrelated
// within-person series (dose-response, wearing-off) lean on n + effect size;
// independent monthly gait medians can honestly use a slope p-value. So the
// gate LOGIC is shared, but the THRESHOLDS and which axes apply are per-
// hypothesis config — a universal threshold set would be statistically wrong.
// `nil` = gate not cleared = "watching" / hidden (NOT a 4th tier).
// Each primitive can ship a default spec; a registry entry may override it.
// See docs/intelligence-architecture.md + InsightRegistry.swift.

extension CorrelationEngine {

    /// One tier's bar. The tier is met when ALL specified axes pass; unspecified
    /// (nil) axes are ignored. `minEffect` is compared SIGNED — callers pass a
    /// magnitude (abs) when only size, not direction, should matter.
    struct GateBar {
        var minN: Int? = nil
        var minEffect: Double? = nil
        var maxP: Double? = nil
        var minStability: Double? = nil
    }

    /// Tiered thresholds for one hypothesis. Highest met tier wins; if not even
    /// `floor` is met the result is nil (hidden).
    struct GateSpec {
        var strong: GateBar
        var moderate: GateBar
        var floor: GateBar
    }

    /// The shared gate. Evidence in (n / effect / significance / stability),
    /// a confidence tier or nil out.
    static func gate(_ spec: GateSpec, n: Int, effect: Double? = nil,
                     p: Double? = nil, stability: Double? = nil) -> Insight.Confidence? {
        func meets(_ bar: GateBar) -> Bool {
            if let m = bar.minN, n < m { return false }
            if let e = bar.minEffect { guard let effect, effect >= e else { return false } }
            if let mp = bar.maxP { guard let p, p <= mp else { return false } }
            if let ms = bar.minStability { guard let stability, stability >= ms else { return false } }
            return true
        }
        if meets(spec.strong) { return .strong }
        if meets(spec.moderate) { return .moderate }
        if meets(spec.floor) { return .emerging }
        return nil
    }

    // Per-hypothesis specs. The first two reproduce the previously-inline gates
    // exactly; the gait spec finally uses the t-test p-value the trend already
    // computes (it was hard-coded .moderate, discarding that p).

    /// Afternoon-dose: n (afternoon doses) + effect (afternoon−morning onset min, signed).
    static let doseResponseGate = GateSpec(
        strong:   GateBar(minN: 20, minEffect: 25),
        moderate: GateBar(minN: 10, minEffect: 20),
        floor:    GateBar(minN: 5,  minEffect: 15))

    /// Wearing-off: n (doses) only — a survival estimate has no single effect/p axis.
    static let wearingOffGate = GateSpec(
        strong:   GateBar(minN: 40),
        moderate: GateBar(minN: 1),
        floor:    GateBar(minN: 1))

    /// Gait trend: significance (slope t-test p) + n (months of medians).
    static let gaitTrendGate = GateSpec(
        strong:   GateBar(minN: 24, maxP: 0.01),
        moderate: GateBar(minN: 12, maxP: 0.05),
        floor:    GateBar(minN: 6))

    /// Windowed-effect (exercise / diet): significance (paired t-test p) + n sessions.
    /// Floor n=5 ⇒ nothing shows until five sessions; at five-plus but not significant
    /// the card surfaces as "no clear effect yet" (an honest null, not a hidden one).
    static let windowedEffectGate = GateSpec(
        strong:   GateBar(minN: 10, maxP: 0.01),
        moderate: GateBar(minN: 5,  maxP: 0.05),
        floor:    GateBar(minN: 5))
}

// MARK: - Windowed-effect primitive (event → signal change in the window after)
//
// The workhorse for the exercise/diet cluster. Variable-agnostic by construction:
// it takes event intervals and a continuous signal and asks "did the signal move
// in the window after each event, vs the window before?" — the SAME math whether
// the event is a Tai Chi session, a coffee, or a dose. The dispatch layer supplies
// the events (workouts filtered by type) and the signal (tremor); this never knows
// which variable it's looking at. That's why one primitive serves every exercise
// registry line. See InsightRegistry.swift + docs/intelligence-architecture.md.

extension CorrelationEngine {

    /// Aggregated per-event baseline (pre-window mean) vs response (post-window
    /// mean). A negative `delta` means the signal fell after the event (e.g. tremor
    /// dropped after exercise). `pValue` is a two-sided one-sample t-test of the
    /// per-event deltas against zero — the honest "is this distinguishable from no
    /// effect?" the gate consumes.
    struct WindowedEffect: Sendable {
        let n: Int                 // events with usable before AND after data
        let meanBefore: Double
        let meanAfter: Double
        let delta: Double          // meanAfter − meanBefore (signed)
        let pctChange: Double      // 100·delta / meanBefore (NaN if baseline ≈ 0)
        let pValue: Double?
        let perEvent: [Double]     // per-event (after − before), for stability / split-half
    }

    /// For each event, mean signal in `[start − preMin, start)` vs
    /// `(end, end + postMin]`, baseline-corrected per event then averaged. Events
    /// lacking signal on either side are skipped. nil if no event has usable data.
    static func windowedEffect(
        events: [(start: Date, end: Date)],
        signal: [(time: Date, value: Double)],
        preMin: Double, postMin: Double,
        minPrePoints: Int = 1, minPostPoints: Int = 1
    ) -> WindowedEffect? {
        var befores: [Double] = [], afters: [Double] = [], deltas: [Double] = []
        for ev in events {
            let preLo = ev.start.addingTimeInterval(-preMin * 60)
            let postHi = ev.end.addingTimeInterval(postMin * 60)
            var preSum = 0.0, preN = 0, postSum = 0.0, postN = 0
            for p in signal {
                if p.time >= preLo && p.time < ev.start { preSum += p.value; preN += 1 }
                else if p.time > ev.end && p.time <= postHi { postSum += p.value; postN += 1 }
            }
            guard preN >= minPrePoints, postN >= minPostPoints else { continue }
            let before = preSum / Double(preN), after = postSum / Double(postN)
            befores.append(before); afters.append(after); deltas.append(after - before)
        }
        guard !deltas.isEmpty else { return nil }
        let nD = Double(deltas.count)
        let meanBefore = befores.reduce(0, +) / nD
        let meanAfter = afters.reduce(0, +) / nD
        let delta = deltas.reduce(0, +) / nD
        let pct = meanBefore != 0 ? 100 * delta / meanBefore : .nan
        return WindowedEffect(
            n: deltas.count, meanBefore: meanBefore, meanAfter: meanAfter,
            delta: delta, pctChange: pct,
            pValue: oneSampleTTestP(deltas), perEvent: deltas)
    }

    /// Two-sided p for a one-sample t-test of `xs` mean vs 0 (the paired test across
    /// per-event deltas). Reuses the same t-distribution tail (regularized incomplete
    /// beta) as `linregress`, so significance is computed consistently engine-wide.
    static func oneSampleTTestP(_ xs: [Double]) -> Double? {
        let n = xs.count
        guard n >= 2 else { return nil }
        let nD = Double(n)
        let mean = xs.reduce(0, +) / nD
        let ss = xs.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) }
        let variance = ss / (nD - 1)
        guard variance > 0 else { return mean == 0 ? 1.0 : 0.0 }
        let se = (variance / nD).squareRoot()
        let t = mean / se
        let df = nD - 1
        return regularizedIncompleteBeta(a: df / 2, b: 0.5, x: df / (df + t * t))
    }
}

// MARK: - Dose-response (port of analysis/src/dose_response.py)

nonisolated extension CorrelationEngine {

    // Tunables mirror the Python constants exactly.
    static let preMin = 30.0       // baseline window before the dose
    static let postMin = 180.0     // max trajectory window after the dose
    static let binMin = 5.0        // resampling resolution relative to dose
    static let keyWindow = 90.0    // window we require coverage in (onset happens here)
    static let minCoverage = 0.5   // require >=50% of key-window bins present

    enum Bucket: String, CaseIterable {
        case morning = "Morning"
        case preLunch = "Pre-lunch"
        case afternoon = "Afternoon"
        case eveningNight = "Evening/Night"
    }

    struct DoseTrace {
        let t0: Date
        let hour: Double
        let bucket: Bucket
        let baseline: Double
        let trough: Double
        let drop: Double
        let tTrough: Double
        let tHalf: Double      // onset latency proxy; .nan if the drop never reaches 50%
        let coverage: Double
        let postEff: Double
        // Raw (pre-smoothing) per-bin tremor on the shared [-preMin, postMin) grid,
        // .nan where a bin had no readings. Retained so curves can be aggregated
        // across doses without re-binning; bin centers are `binCenters(-preMin, postMin)`.
        let binValues: [Double]
    }

    static func bucketOf(_ hour: Double) -> Bucket {
        switch hour {
        case 6..<9.5:    return .morning
        case 9.5..<12.5: return .preLunch
        case 12.5..<17:  return .afternoon
        default:         return .eveningNight   // 17–24 and 0–6 (wrap)
        }
    }

    /// Local wall-clock hour (+ minute fraction). Time-of-day questions are
    /// meaningless in UTC, so we read components in the device's calendar — the
    /// Swift equivalent of the Python loader's tz-convert to Pacific.
    static func hourOfDay(_ date: Date) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
    }

    /// Build one trace per dose that has adequate tremor coverage.
    static func buildTraces(samples: [TremorPoint], doses: [Dose]) -> [DoseTrace] {
        let series = samples.sorted { $0.timestamp < $1.timestamp }
        let ds = doses.sorted { $0.timestamp < $1.timestamp }
        var traces: [DoseTrace] = []

        for (i, dose) in ds.enumerated() {
            let t0 = dose.timestamp

            // Guard 1: truncate the post window at the next dose.
            let postEff: Double
            if i + 1 < ds.count {
                let gap = ds[i + 1].timestamp.timeIntervalSince(t0) / 60.0
                postEff = min(postMin, max(0, gap))
            } else {
                postEff = postMin
            }

            let lo = t0.addingTimeInterval(-preMin * 60)
            let hi = t0.addingTimeInterval(postEff * 60)
            let win = series.filter { $0.timestamp >= lo && $0.timestamp <= hi }
            if win.count < 3 { continue }

            let rel = win.map { $0.timestamp.timeIntervalSince(t0) / 60.0 }
            let vals = win.map { $0.tremorScore }
            let (centers, binnedVals) = binned(rel: rel, vals: vals, lo: -preMin, hi: postMin)

            // Coverage in the clinically key [0, min(keyWindow, postEff)] window.
            let keyHi = min(keyWindow, postEff)
            var keyTotal = 0, keyPresent = 0
            for (idx, c) in centers.enumerated() where c >= 0 && c <= keyHi {
                keyTotal += 1
                if !binnedVals[idx].isNaN { keyPresent += 1 }
            }
            let coverage = Double(keyPresent) / Double(max(1, keyTotal))
            if coverage < minCoverage { continue }

            // Baseline = mean of pre-dose bins in [-preMin, 0).
            var baseSum = 0.0, baseN = 0
            for idx in centers.indices where centers[idx] >= -preMin && centers[idx] < 0 && !binnedVals[idx].isNaN {
                baseSum += binnedVals[idx]; baseN += 1
            }
            if baseN == 0 { continue }
            let baseline = baseSum / Double(baseN)

            let sm = smooth(binnedVals)
            var postCenters: [Double] = [], postVals: [Double] = []
            for (idx, c) in centers.enumerated() where c > 0 && c <= postEff {
                postCenters.append(c); postVals.append(sm[idx])
            }
            if postVals.allSatisfy({ $0.isNaN }) { continue }

            // Trough = smoothed minimum post-dose (nanargmin).
            var ti = -1; var minV = Double.infinity
            for (k, v) in postVals.enumerated() where !v.isNaN && v < minV { minV = v; ti = k }
            if ti < 0 { continue }
            let trough = postVals[ti]
            let tTrough = postCenters[ti]
            let drop = baseline - trough

            // Onset latency proxy: first post-dose time reaching 50% of the drop.
            var tHalf = Double.nan
            if drop > 0 {
                let target = baseline - 0.5 * drop
                var best = Double.infinity
                for k in postVals.indices where !postVals[k].isNaN && postVals[k] <= target {
                    if postCenters[k] < best { best = postCenters[k] }
                }
                if best.isFinite { tHalf = best }
            }

            let hour = hourOfDay(t0)
            traces.append(DoseTrace(
                t0: t0, hour: hour, bucket: bucketOf(hour),
                baseline: baseline, trough: trough, drop: drop,
                tTrough: tTrough, tHalf: tHalf, coverage: coverage, postEff: postEff,
                binValues: binnedVals
            ))
        }
        return traces
    }

    /// The afternoon-dose finding, or nil if the pattern doesn't clear the gate.
    static func afternoonDoseInsight(samples: [TremorPoint], doses: [Dose]) -> Insight? {
        let traces = buildTraces(samples: samples, doses: doses)

        func onset(_ bucket: Bucket) -> (mean: Double, n: Int) {
            let xs = traces.filter { $0.bucket == bucket && !$0.tHalf.isNaN }.map { $0.tHalf }
            return (nanmean(xs), xs.count)
        }
        let aft = onset(.afternoon)
        let morn = onset(.morning)

        // Surfacing gate (logic-based; see Insights design): need enough afternoon
        // doses, a morning comparator, and a meaningfully slower afternoon onset.
        guard morn.n >= 3, !aft.mean.isNaN, !morn.mean.isNaN else { return nil }
        let delta = aft.mean - morn.mean
        // Gate on afternoon-dose count + the signed onset gap. The floor
        // (n≥5, delta≥15) subsumes the old explicit guards: nil = don't surface.
        guard let confidence = gate(Self.doseResponseGate, n: aft.n, effect: delta) else { return nil }

        let scored = traces.filter { !$0.tHalf.isNaN }.count
        let days = Set(traces.map { calendar.startOfDay(for: $0.t0) }).count
        let aftMin = Int(aft.mean.rounded())
        let mornMin = Int(morn.mean.rounded())

        // Single string literals (no `+` chains — those blow up Swift's type-checker).
        let summary = "Takes ~\(aftMin) min to kick in vs. ~\(mornMin) min in the morning — but lasts a normal length."
        let finding = "It also peaks weaker, while duration stays normal — so the issue is getting the dose *in*, not it wearing off early. From \(scored) scored doses over \(days) days."
        let mechanism = "Levodopa is absorbed in the gut and enters the brain through the same transporter dietary protein uses, so a protein lunch can slow and blunt the dose after it. PD also slows stomach emptying, more after meals and later in the day. Both point to one lever you control: when you eat relative to the dose. Likely, not proven."

        return Insight(
            title: "Your afternoon dose works slower",
            summary: summary,
            stage: .hypothesis,
            finding: finding,
            mechanism: mechanism,
            confidence: confidence,
            evidenceDays: days,
            chart: doseResponseChart(traces: traces)
        )
    }

    /// Plot-ready overlay of mean tremor-vs-time curves, one per daytime bucket
    /// (the morning-vs-afternoon contrast the card describes). Evening/night is
    /// omitted — it's sleep-confounded and not part of the story.
    static func doseResponseChart(traces: [DoseTrace]) -> InsightChart {
        let centers = binCenters(lo: -preMin, hi: postMin)
        var curves: [DoseCurve] = []
        for bucket in [Bucket.morning, .preLunch, .afternoon] {
            let inBucket = traces.filter { $0.bucket == bucket }
            guard inBucket.count >= 3 else { continue }   // too few to mean meaningfully
            curves.append(DoseCurve(
                label: bucket.rawValue,
                bucket: bucket,
                doseCount: inBucket.count,
                points: aggregateCurve(series: inBucket.map(\.binValues), centers: centers)
            ))
        }
        return .doseResponse(DoseResponseChart(curves: curves, threshold: offThreshold, doseMinute: 0))
    }
}

// MARK: - Wearing-off / ON-duration (port of analysis/src/wearing_off.py)

nonisolated extension CorrelationEngine {

    static let offThreshold = 1.0   // tremor >= this == OFF
    static let maxWindow = 300.0    // look up to 5h post-dose for the natural decay
    static let gapIso = 240.0       // "isolated" dose = next dose >= this many min away
    static let sustainBins = 2      // consecutive OFF bins required to call OFF-return

    struct DoseDuration {
        let t0: Date
        let hour: Double
        let bucket: Bucket
        let baseline: Double
        let trough: Double
        let intervalMin: Double   // to next dose; .nan if last of the series
        let durationMin: Double   // dose → OFF-return (or censor time)
        let observed: Bool        // true = OFF-return seen; false = right-censored
        let isolated: Bool        // eligible for the canonical curve
        // SMOOTHED (k=3, nan-aware) per-bin tremor on the [-preMin, maxWindow) grid,
        // for the canonical wearing-off curve. Smoothed (not raw) to match the Python
        // lab, whose iso_traces averages the smoothed per-dose series.
        let binValues: [Double]
    }

    static func analyzeWearingOff(samples: [TremorPoint], doses: [Dose]) -> [DoseDuration] {
        let series = samples.sorted { $0.timestamp < $1.timestamp }
        let ds = doses.sorted { $0.timestamp < $1.timestamp }
        var results: [DoseDuration] = []

        for (i, dose) in ds.enumerated() {
            let t0 = dose.timestamp
            var interval = Double.nan
            if i + 1 < ds.count { interval = ds[i + 1].timestamp.timeIntervalSince(t0) / 60.0 }
            let isolated = interval.isNaN || interval >= gapIso

            let lo = t0.addingTimeInterval(-preMin * 60)
            let hi = t0.addingTimeInterval(maxWindow * 60)
            let win = series.filter { $0.timestamp >= lo && $0.timestamp <= hi }
            if win.count < 4 { continue }

            let rel = win.map { $0.timestamp.timeIntervalSince(t0) / 60.0 }
            let vals = win.map { $0.tremorScore }
            let (centers, rawBins) = binned(rel: rel, vals: vals, lo: -preMin, hi: maxWindow)
            let sm = smooth(rawBins)

            // Baseline (smoothed) over pre-dose bins.
            var baseSum = 0.0, baseN = 0
            for idx in centers.indices where centers[idx] >= -preMin && centers[idx] < 0 && !sm[idx].isNaN {
                baseSum += sm[idx]; baseN += 1
            }
            let baseline = baseN > 0 ? baseSum / Double(baseN) : Double.nan

            // Trough = smoothed minimum post-dose; skip if no post coverage.
            var trough = Double.infinity, anyPost = false
            for idx in centers.indices where centers[idx] > 0 && !sm[idx].isNaN {
                anyPost = true
                if sm[idx] < trough { trough = sm[idx] }
            }
            if !anyPost { continue }

            // Observation horizon: truncate at the next dose.
            let horizon = interval.isNaN ? maxWindow : min(maxWindow, interval)
            let (duration, observed) = offReturn(centers: centers, sm: sm, horizon: horizon, thr: offThreshold)

            let hour = hourOfDay(t0)
            results.append(DoseDuration(
                t0: t0, hour: hour, bucket: bucketOf(hour),
                baseline: baseline, trough: trough, intervalMin: interval,
                durationMin: duration, observed: observed, isolated: isolated,
                binValues: sm   // smoothed series → canonical curve (Python parity)
            ))
        }
        return results
    }

    /// Time from dose to a sustained OFF-return after control is achieved; else
    /// censored at the horizon. Mirrors `wearing_off._off_return`.
    static func offReturn(centers: [Double], sm: [Double], horizon: Double, thr: Double) -> (Double, Bool) {
        var cc: [Double] = [], yy: [Double] = []
        for idx in centers.indices where centers[idx] > 0 && centers[idx] <= horizon {
            cc.append(centers[idx]); yy.append(sm[idx])
        }
        if cc.isEmpty || yy.allSatisfy({ $0.isNaN }) { return (horizon, false) }

        // Did the dose achieve control (drop below threshold) at all?
        var minY = Double.infinity
        for v in yy where !v.isNaN && v < minY { minY = v }
        if !(minY < thr) { return (horizon, false) }

        guard let onI = yy.firstIndex(where: { !$0.isNaN && $0 < thr }) else { return (horizon, false) }
        var run = 0
        for j in onI..<yy.count {
            if !yy[j].isNaN && yy[j] >= thr {
                run += 1
                if run >= sustainBins { return (cc[j - sustainBins + 1], true) }
            } else {
                run = 0
            }
        }
        return (cc[cc.count - 1], false)
    }

    /// Kaplan–Meier median survival with right-censoring (hand-rolled; the Python
    /// lab uses statsmodels SurvfuncRight). Returns the first event time where the
    /// survival estimate drops to <= 0.5.
    static func kmMedian(durations: [Double], observed: [Bool]) -> Double {
        var time: [Double] = [], event: [Bool] = []
        for (d, o) in zip(durations, observed) where !d.isNaN && d > 0 { time.append(d); event.append(o) }
        if time.isEmpty { return .nan }

        let eventTimes = Set(zip(time, event).filter { $0.1 }.map { $0.0 }).sorted()
        var surv = 1.0
        for t in eventTimes {
            let nAtRisk = time.filter { $0 >= t }.count
            if nAtRisk == 0 { break }
            var d = 0
            for (tt, ev) in zip(time, event) where ev && tt == t { d += 1 }
            surv *= 1 - Double(d) / Double(nAtRisk)
            if surv <= 0.5 { return t }
        }
        return .nan
    }

    /// The wearing-off insight (the "discuss with your neurologist" card), or nil.
    static func wearingOffInsight(samples: [TremorPoint], doses: [Dose]) -> Insight? {
        let results = analyzeWearingOff(samples: samples, doses: doses)
        guard results.count >= 20 else { return nil }

        let km = kmMedian(durations: results.map(\.durationMin), observed: results.map(\.observed))
        guard !km.isNaN else { return nil }

        // Daytime inter-dose gaps (exclude overnight gaps > 600 min).
        var dayIntervals: [Double] = []
        for r in results where r.hour >= 6 && r.hour < 20 && !r.intervalMin.isNaN && r.intervalMin < 600 {
            dayIntervals.append(r.intervalMin)
        }
        let medInterval = median(dayIntervals)
        // Gate: the gap between doses must exceed how long a dose lasts.
        guard !medInterval.isNaN, medInterval > km else { return nil }

        let durH = String(format: "%.1f", km / 60)
        let gapH = String(format: "%.0f", medInterval / 60)
        let kmMin = Int(km.rounded())
        let gapMin = Int(medInterval.rounded())
        let observedCount = results.filter { $0.observed }.count
        let days = Set(results.map { calendar.startOfDay(for: $0.t0) }).count
        let confidence: Insight.Confidence = gate(Self.wearingOffGate, n: results.count) ?? .moderate

        let summary = "Daytime gaps (~\(gapH) h) exceed how long each dose lasts (~\(durH) h), opening predictable OFF windows."
        let finding = "Each dose holds for a median of \(kmMin) min (about \(durH) h), but your daytime doses are spaced ~\(gapH) h apart — so tremor returns before the next dose. From \(results.count) doses over \(days) days."
        let consider = "When the gap between doses is longer than a dose lasts, predictable OFF windows open up. Neurologists have several levers for this — for example adjusting dose timing or frequency, or a longer-acting formulation. These are decisions only your neurologist can make. The value here is bringing them this pattern, with the data behind it."
        let bring = [
            "Median ON-duration: \(kmMin) min (Kaplan–Meier, n=\(results.count) doses)",
            "Median daytime gap between doses: ~\(gapH) h (\(gapMin) min)",
            "\(observedCount) of \(results.count) doses observed wearing off before the next dose",
        ]

        return Insight(
            title: "Your doses are spaced wider than they last",
            summary: summary,
            stage: .clinicalDiscussion,
            finding: finding,
            mechanism: "This is the classic wearing-off pattern: the interval between doses is longer than a single dose lasts.",
            confidence: confidence,
            evidenceDays: days,
            chart: wearingOffChart(results: results, km: km),
            clinical: ClinicalDiscussion(whatTheyMightConsider: consider, bringThisData: bring)
        )
    }

    /// The canonical single-dose response curve (mean tremor vs minutes since dose)
    /// averaged across *isolated* doses, plus the reference levels the card annotates:
    /// the pre-dose baseline, the OFF threshold, the deepest-ON minute, and the KM
    /// median ON-duration (where tremor is expected to have crossed back into OFF).
    static func wearingOffChart(results: [DoseDuration], km: Double) -> InsightChart {
        let isolated = results.filter { $0.isolated }
        let centers = binCenters(lo: -preMin, hi: maxWindow)
        let points = aggregateCurve(series: isolated.map(\.binValues), centers: centers)

        let preVals = points.filter { $0.minute < 0 && !$0.value.isNaN }.map(\.value)
        let baseline = nanmean(preVals)

        // Deepest ON = minute of the lowest post-dose point on the mean curve.
        let postPts = points.filter { $0.minute > 0 && !$0.value.isNaN }
        let bestOnMinute = postPts.min(by: { $0.value < $1.value })?.minute ?? .nan

        let curve = DoseCurve(label: "Typical dose", bucket: nil, doseCount: isolated.count, points: points)
        return .wearingOff(WearingOffChart(
            curve: curve, threshold: offThreshold, baseline: baseline,
            bestOnMinute: bestOnMinute, medianDurationMin: km
        ))
    }

    static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted(); let n = s.count
        if n == 0 { return .nan }
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}

// MARK: - Chart data (plot-ready engine output)
//
// Pure values (Foundation only) so the engine stays UI-free and parity-testable.
// The SwiftUI chart view consumes these; the engine never imports SwiftUI/Charts.
// All curves are expressed in minutes *relative to the dose* (t=0 = dose taken).

nonisolated extension CorrelationEngine {

    /// One point on an aggregated curve: mean tremor at a minute offset, plus how
    /// many doses contributed (so the view can fade or drop thin-evidence tails —
    /// e.g. afternoon doses truncated by the evening dose have falling `n`).
    struct CurvePoint {
        let minute: Double
        let value: Double   // mean tremor across contributing doses; .nan if none
        let n: Int
    }

    /// A mean tremor trajectory for one group of doses (a time-of-day bucket, or
    /// the pooled "typical dose" for the wearing-off curve).
    struct DoseCurve: Identifiable {
        let label: String       // "Morning" / "Afternoon" / "Typical dose"
        let bucket: Bucket?     // nil for the pooled wearing-off curve
        let doseCount: Int
        let points: [CurvePoint]
        var id: String { label }
    }

    /// Overlay of per-bucket curves for the afternoon-dose card.
    struct DoseResponseChart {
        let curves: [DoseCurve]
        let threshold: Double    // OFF reference line
        let doseMinute: Double   // x where the dose was taken (0)
    }

    /// The canonical levodopa response for the wearing-off card.
    struct WearingOffChart {
        let curve: DoseCurve
        let threshold: Double          // OFF reference line
        let baseline: Double           // pre-dose mean tremor
        let bestOnMinute: Double       // deepest-ON point on the mean curve
        let medianDurationMin: Double  // KM median ON-duration (vertical marker)
    }

    /// One point on a multi-year gait trajectory (a monthly median at a date). Unlike
    /// the dose curves (minutes relative to a dose), the gait x-axis is calendar time.
    struct GaitPoint {
        let date: Date
        let value: Double
    }

    /// Plot-ready payload for the gait hero chart: one metric's monthly medians plus
    /// its fitted trend line, over years. We render walking speed as the hero; the
    /// other three metrics ride along as a one-line summary in the card text.
    struct GaitTrendChart {
        let metricLabel: String     // "Walking speed"
        let unitLabel: String       // "m/s"
        let points: [GaitPoint]     // monthly medians
        let fitStart: GaitPoint     // fitted trend-line endpoints (over the observed span)
        let fitEnd: GaitPoint
        let higherIsWorse: Bool     // axis/caption semantics (false for speed)
    }

    /// Plot-ready payload for a windowed-effect (exercise) card: the mean tremor
    /// trajectory in the window AFTER each session, against the pre-session baseline.
    /// Reuses `CurvePoint` so the view machinery matches the dose curves.
    struct WindowedEffectChart {
        let activityLabel: String   // "Boxing"
        let curve: [CurvePoint]     // mean tremor vs minutes after session end
        let baseline: Double        // pre-session mean tremor (horizontal reference)
        let postMin: Double         // x-axis upper bound (minutes)
    }

    /// Plot-ready payload attached to an `Insight`. Each case maps to one chart view.
    enum InsightChart {
        case doseResponse(DoseResponseChart)
        case wearingOff(WearingOffChart)
        case gaitTrend(GaitTrendChart)
        case windowedEffect(WindowedEffectChart)
    }

    /// Mean post-session tremor trajectory across events, on a shared [0, postMin]
    /// grid, plus the pre-session baseline — built with the same bin/smooth/aggregate
    /// machinery as the dose curves. nil if no session has post-window coverage.
    static func windowedEffectChart(
        events: [(start: Date, end: Date)], signal: [(time: Date, value: Double)],
        preMin: Double, postMin: Double, activityLabel: String
    ) -> InsightChart? {
        var series: [[Double]] = []
        var preMeans: [Double] = []
        for ev in events {
            let postHi = ev.end.addingTimeInterval(postMin * 60)
            let post = signal.filter { $0.time > ev.end && $0.time <= postHi }
            guard !post.isEmpty else { continue }
            let rel = post.map { $0.time.timeIntervalSince(ev.end) / 60.0 }
            let (_, raw) = binned(rel: rel, vals: post.map(\.value), lo: 0, hi: postMin)
            series.append(smooth(raw))

            let preLo = ev.start.addingTimeInterval(-preMin * 60)
            let pre = signal.filter { $0.time >= preLo && $0.time < ev.start }.map(\.value)
            if !pre.isEmpty { preMeans.append(pre.reduce(0, +) / Double(pre.count)) }
        }
        guard !series.isEmpty else { return nil }
        let curve = aggregateCurve(series: series, centers: binCenters(lo: 0, hi: postMin))
        let baseline = preMeans.isEmpty ? .nan : preMeans.reduce(0, +) / Double(preMeans.count)
        return .windowedEffect(WindowedEffectChart(
            activityLabel: activityLabel, curve: curve, baseline: baseline, postMin: postMin))
    }

    /// Build the hero gait chart from a metric's trend: its monthly medians plus the
    /// straight fitted line across the observed span.
    static func gaitTrendChart(_ t: MetricTrend) -> InsightChart? {
        guard let first = t.months.first?.month, let last = t.months.last?.month else { return nil }
        let years = last.timeIntervalSince(first) / (365.25 * 86_400)
        let pts = t.months.map { GaitPoint(date: $0.month, value: $0.median) }
        return .gaitTrend(GaitTrendChart(
            metricLabel: t.metric.display,
            unitLabel: t.metric.unit,
            points: pts,
            fitStart: GaitPoint(date: first, value: t.intercept),
            fitEnd: GaitPoint(date: last, value: t.intercept + t.slopePerYear * years),
            higherIsWorse: t.metric.higherIsWorse))
    }

    /// Bin centers for a [lo, hi) grid at `binMin` resolution — the same grid
    /// `binned(...)` produces, so stored `binValues` align index-for-index.
    static func binCenters(lo: Double, hi: Double) -> [Double] {
        let n = Int((hi - lo) / binMin)
        return (0..<n).map { lo + Double($0) * binMin + binMin / 2 }
    }

    /// Mean-of-means across per-dose binned trajectories on a shared grid. Each
    /// dose is weighted equally (one trajectory, one vote) and bins are nan-aware,
    /// so the result is the average dose response, not a reading-count-weighted one.
    static func aggregateCurve(series: [[Double]], centers: [Double]) -> [CurvePoint] {
        centers.indices.map { i in
            var sum = 0.0, c = 0
            for s in series where i < s.count && !s[i].isNaN { sum += s[i]; c += 1 }
            return CurvePoint(minute: centers[i], value: c > 0 ? sum / Double(c) : .nan, n: c)
        }
    }
}

// MARK: - NaN-aware numeric helpers (mirror numpy's nan* semantics)

nonisolated extension CorrelationEngine {

    /// Mean-bin `vals` by relative minute into binMin bins over [-preMin, postMin),
    /// returning bin centers and per-bin means (.nan where a bin is empty).
    static func binned(rel: [Double], vals: [Double], lo: Double, hi: Double) -> (centers: [Double], values: [Double]) {
        let n = Int((hi - lo) / binMin)
        var sums = [Double](repeating: 0, count: n)
        var counts = [Int](repeating: 0, count: n)
        for (r, v) in zip(rel, vals) {
            let idx = Int(((r - lo) / binMin).rounded(.down))
            if idx >= 0 && idx < n { sums[idx] += v; counts[idx] += 1 }
        }
        var centers = [Double](repeating: 0, count: n)
        var out = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            centers[i] = lo + Double(i) * binMin + binMin / 2
            if counts[i] > 0 { out[i] = sums[i] / Double(counts[i]) }
        }
        return (centers, out)
    }

    /// Light nan-aware centered moving average (k=3), for trough finding.
    static func smooth(_ y: [Double]) -> [Double] {
        let n = y.count
        var out = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let lo = max(0, i - 1), hi = min(n - 1, i + 1)
            var s = 0.0, c = 0
            for j in lo...hi where !y[j].isNaN { s += y[j]; c += 1 }
            if c > 0 { out[i] = s / Double(c) }
        }
        return out
    }

    static func nanmean(_ xs: [Double]) -> Double {
        var s = 0.0, c = 0
        for v in xs where !v.isNaN { s += v; c += 1 }
        return c > 0 ? s / Double(c) : .nan
    }
}

// MARK: - Gait progression (multi-year mobility-metric trends)
//
// Ports analysis/src/gait.py. For each metric: clip to a physiological range, reduce
// to MONTHLY MEDIANS (≥20 samples/month so the median is trustworthy), then fit a
// linear trend over years. Reports per-year slope, % change, and a two-sided p-value
// (the slope's t-test, df = months−2). Unlike the dose work, this is *progression*
// tracking — a noisy multi-year trajectory, explicitly not a clinical assessment.

nonisolated extension CorrelationEngine {

    struct GaitMonth: Sendable {
        let month: Date       // first of month (UTC-anchored; see monthlyMedians)
        let median: Double
        let n: Int
    }

    struct MetricTrend: Sendable {
        let metric: GaitMetric
        let nMonths: Int
        let slopePerYear: Double   // native units per year
        let intercept: Double      // fitted value at the first month
        let r: Double
        let pValue: Double         // two-sided, t-test on the slope
        let spanYears: Double
        let pctChange: Double      // relative %, vs the fitted baseline
        let months: [GaitMonth]    // monthly medians, for the chart

        var isSignificant: Bool { pValue < 0.05 }
        /// Worsening = moving in the bad direction for this metric.
        var isWorsening: Bool { metric.higherIsWorse ? slopePerYear > 0 : slopePerYear < 0 }
        /// % change is meaningless when the baseline sits near zero (e.g. asymmetry ~0,
        /// where a tiny absolute move is a huge %). Mirrors the lab's |pct|>60 guard.
        var pctReliable: Bool { pctChange.isFinite && abs(pctChange) <= 60 }
    }

    struct GaitProgression: Sendable {
        let metrics: [MetricTrend]
        var spanYears: Double { metrics.map(\.spanYears).max() ?? 0 }
        /// The reassuring verdict holds when nothing is significantly worsening.
        var anySignificantWorsening: Bool { metrics.contains { $0.isWorsening && $0.isSignificant } }
        func trend(_ m: GaitMetric) -> MetricTrend? { metrics.first { $0.metric == m } }
    }

    /// Run the gait analysis across the four metrics. Returns nil if no metric has
    /// enough monthly data to fit a trend.
    static func analyzeGait(series: [GaitMetric: [GaitSample]]) -> GaitProgression? {
        let trends = GaitMetric.allCases.compactMap { metricTrend($0, samples: series[$0] ?? []) }
        return trends.isEmpty ? nil : GaitProgression(metrics: trends)
    }

    /// Build the reassurance card from the gait analysis: walking speed is the hero
    /// (chart + headline), the other three metrics ride along as a one-line summary.
    /// Returns nil until there's enough span to say anything — gait is multi-year.
    static func gaitInsight(series: [GaitMetric: [GaitSample]]) -> Insight? {
        guard let prog = analyzeGait(series: series),
              let speed = prog.trend(.walkingSpeed),
              speed.nMonths >= 12, prog.spanYears >= 1.5 else { return nil }

        let years = String(format: "%.1f", prog.spanYears)
        let declining = prog.anySignificantWorsening
        let speedPct = speed.pctReliable ? String(format: "%+.0f%%", speed.pctChange) : "flat"

        func phrase(_ m: GaitMetric) -> String? {
            guard let t = prog.trend(m) else { return nil }
            let word: String
            if !t.isSignificant { word = "flat" }
            else if t.isWorsening { word = "declining" }
            else { word = (m == .doubleSupport) ? "steadier" : "improving" }
            return "\(m.display.lowercased()) \(word)"
        }
        let others = [GaitMetric.stepLength, .doubleSupport, .asymmetry]
            .compactMap(phrase).joined(separator: " · ")

        // Confidence now flows from the hero metric's actual slope p-value + month
        // count (was hard-coded .moderate). Floor (n≥6) always holds here, since the
        // card already requires nMonths≥12, so the card never disappears.
        let confidence = gate(Self.gaitTrendGate, n: speed.nMonths, p: speed.pValue) ?? .emerging

        var insight = Insight(
            title: declining ? "Your walking shows some change" : "Your walking hasn't declined",
            summary: declining
                ? "Over \(years) years, a gait marker is trending down — worth mentioning to your neurologist."
                : "Over \(years) years: walking speed \(speedPct), with no measurable decline across your gait markers.",
            stage: .verdict,
            finding: "Walking speed \(speedPct) over \(years)y; \(others). Monthly medians from Apple mobility metrics (\(speed.nMonths) months).",
            mechanism: "Multi-year mobility metrics are noisy and shift with footwear, walking surface, phone placement, and device — read the direction, not the decimals. Not a clinical assessment.",
            confidence: confidence,
            evidenceDays: Int(prog.spanYears * 365.25),
            verdict: Verdict(
                outcome: declining ? .inconclusive : .worked,
                controlLabel: "Earliest", controlValue: "baseline",
                changeLabel: "Now", changeValue: "speed \(speedPct)",
                summary: declining
                    ? "Some gait change over \(years) years — bring it up at your next appointment."
                    : "No measurable gait decline over \(years) years — quietly reassuring for a progressive condition.",
                nextStep: declining
                    ? "Mention this trend to your neurologist."
                    : "Nothing to change. The app keeps watching the trend."
            )
        )
        insight.chart = gaitTrendChart(speed)
        return insight
    }

    /// Clip → monthly medians (≥20/month) → linear trend for one metric.
    static func metricTrend(_ metric: GaitMetric, samples: [GaitSample]) -> MetricTrend? {
        let months = monthlyMedians(samples, clip: metric.clip)
        guard months.count >= 6 else { return nil }   // need a real span to trust a slope
        let t0 = months[0].month
        let t = months.map { $0.month.timeIntervalSince(t0) / (365.25 * 86_400) }   // years
        let y = months.map(\.median)
        guard let fit = linregress(x: t, y: y) else { return nil }
        let span = (t.last ?? 0) - (t.first ?? 0)
        let total = fit.slope * span
        let pct = fit.intercept != 0 ? 100 * total / fit.intercept : .nan
        return MetricTrend(
            metric: metric, nMonths: months.count, slopePerYear: fit.slope,
            intercept: fit.intercept, r: fit.r, pValue: fit.pValue,
            spanYears: span, pctChange: pct, months: months)
    }

    /// Month-start anchoring in UTC so month-to-month gaps are exact integer days
    /// (no DST hour drift), matching the Python lab's naive `.dt.days / 365.25`.
    private static let utcMonthCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Group clipped samples into months (bucketed by the engine `calendar`'s wall
    /// clock — Pacific in the parity test, the device's zone in the app), keeping only
    /// months with ≥20 samples. The month key is a UTC-anchored first-of-month so the
    /// downstream time axis is DST-free.
    static func monthlyMedians(_ samples: [GaitSample], clip: (lo: Double, hi: Double)) -> [GaitMonth] {
        var buckets: [Date: [Double]] = [:]
        for s in samples where s.value >= clip.lo && s.value <= clip.hi {
            let comps = calendar.dateComponents([.year, .month], from: s.date)
            guard let m = utcMonthCal.date(from: comps) else { continue }
            buckets[m, default: []].append(s.value)
        }
        return buckets.compactMap { month, vals in
            vals.count >= 20 ? GaitMonth(month: month, median: median(vals), n: vals.count) : nil
        }
        .sorted { $0.month < $1.month }
    }

    // MARK: Linear regression + significance (plain Swift; trivial at ~70 points)

    /// Ordinary least squares plus the two-sided p-value SciPy's `linregress` reports:
    /// the slope's t-statistic against df = n−2, evaluated via the regularized
    /// incomplete beta (the t-distribution tail).
    static func linregress(x: [Double], y: [Double]) -> (slope: Double, intercept: Double, r: Double, pValue: Double)? {
        let n = x.count
        guard n >= 3, x.count == y.count else { return nil }
        let nD = Double(n)
        let mx = x.reduce(0, +) / nD
        let my = y.reduce(0, +) / nD
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for i in 0..<n {
            let dx = x[i] - mx, dy = y[i] - my
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        let intercept = my - slope * mx
        let r = syy > 0 ? sxy / (sxx.squareRoot() * syy.squareRoot()) : 0
        let df = nD - 2
        let tiny = 1e-20
        let tStat = r * (df / ((1 - r + tiny) * (1 + r + tiny))).squareRoot()
        // two-sided p = I_{df/(df+t²)}(df/2, 1/2)
        let p = regularizedIncompleteBeta(a: df / 2, b: 0.5, x: df / (df + tStat * tStat))
        return (slope, intercept, r, p)
    }

    /// Regularized incomplete beta Iₓ(a,b) via the Lentz continued fraction
    /// (Numerical Recipes). Backs the t-distribution tail above.
    static func regularizedIncompleteBeta(a: Double, b: Double, x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let logBeta = lgamma(a + b) - lgamma(a) - lgamma(b)
        let front = exp(logBeta + a * log(x) + b * log(1 - x))
        if x < (a + 1) / (a + b + 2) {
            return front * betaContinuedFraction(a: a, b: b, x: x) / a
        } else {
            return 1 - front * betaContinuedFraction(a: b, b: a, x: 1 - x) / b
        }
    }

    private static func betaContinuedFraction(a: Double, b: Double, x: Double) -> Double {
        let tiny = 1e-30
        let qab = a + b, qap = a + 1, qam = a - 1
        var c = 1.0
        var d = 1 - qab * x / qap
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d
        for m in 1...300 {
            let mD = Double(m), m2 = 2 * Double(m)
            var aa = mD * (b - mD) * x / ((qam + m2) * (a + m2))
            d = 1 + aa * d; if abs(d) < tiny { d = tiny }
            c = 1 + aa / c; if abs(c) < tiny { c = tiny }
            d = 1 / d; h *= d * c
            aa = -(a + mD) * (qab + mD) * x / ((a + m2) * (qap + m2))
            d = 1 + aa * d; if abs(d) < tiny { d = tiny }
            c = 1 + aa / c; if abs(c) < tiny { c = tiny }
            d = 1 / d
            let del = d * c
            h *= del
            if abs(del - 1) < 1e-12 { break }
        }
        return h
    }
}
