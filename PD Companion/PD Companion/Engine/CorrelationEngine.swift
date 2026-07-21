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

/// A span the patient was ASLEEP. Deliberately not "in bed": HealthKit's `inBed`
/// includes lying down awake, and tremor during that span is real OFF the patient
/// lived through. Verified on Bhav's 3pm nap — he lay down ~3:00 but Apple detected
/// sleep only from 4:08, and that first hour carried genuine tremor. So the adapter
/// maps `asleepCore/Deep/REM/Unspecified` only, and an `awake` interruption inside a
/// night is simply absent from this list (correctly counted as waking time).
///
/// Sleep matters to the engine twice, in two DIFFERENT ways:
///   1. Uncovered time is a WAKING quantity — you don't experience OFF while asleep,
///      so sleep is SUBTRACTED from a dose gap.
///   2. Dose duration is a WALL-CLOCK, pharmacological quantity — levodopa keeps
///      metabolising while you sleep, so sleep is NEVER subtracted from a duration.
///      We simply stop being able to observe (tremor flattens in sleep regardless of
///      drug state), so the survival observation is CENSORED at sleep onset.
/// Conflating these two inflates duration and erases OFF at the same time.
/// docs/design/wearing-off-margin.md.
struct SleepInterval: Sendable, Equatable {
    let start: Date
    let end: Date
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

/// A discrete food/drink intake event — the canonical shape the food cluster feeds
/// into the same windowed-effect primitive the exercise cluster uses. Carries the
/// detected `FoodAttribute`s as a set (one intake can be caffeine + sugar + fat), so
/// a registry entry filters by `attributes.contains(attr)` exactly as the exercise
/// path filters workouts by activity type. Unlike `WorkoutEvent` (which carries a raw
/// `UInt` to keep the engine HealthKit-free), `FoodAttribute` is a plain app enum, so
/// it's carried directly. The adapter (`InsightsView`) snapshots SwiftData `FoodEvent`s
/// into these on the main actor, deriving attributes from the stored field OR
/// `FoodAttribute.detect` when the ML field is still empty. Instantaneous, so the
/// windowed-effect primitive treats `timestamp` as a zero-length event.
struct FoodIntakeEvent: Sendable {
    let timestamp: Date
    let attributes: Set<FoodAttribute>
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

/// A distinct device/app that has written to HealthKit — powers the app-wide "which
/// devices are yours?" review. `Identifiable` for the SwiftUI list.
///
/// Two-phase: the name comes first via `HKSourceQuery` (no sample pull, so the list is
/// instant), then `stats` (entry count + date span) fills in from a background tally.
/// `nil` stats = "still loading" — the row shows just the name until they arrive.
struct HealthSourceInfo: Sendable, Identifiable {
    let name: String
    var stats: Stats?
    var id: String { name }

    struct Stats: Sendable, Equatable {
        let count: Int
        let firstDate: Date
        let lastDate: Date
    }
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

    /// Minimal clinically important difference — the smallest change studies find a
    /// clinician or patient actually calls meaningful. In NATIVE units (m/s here), never
    /// a percentage: a % constant would silently scale the margin with the person's
    /// baseline, handing a slower patient a smaller margin than the literature supports.
    /// Display copy derives the % from this, not the reverse.
    ///
    /// Used as the published FLOOR under an absence claim, so a very clean dataset can't
    /// flag a sub-clinical wiggle just because it has the precision to resolve one.
    /// nil ⇒ no PD value sourced yet, so that metric's absence claim rests on the user's
    /// own detectable margin alone.
    ///
    /// Walking speed: small MCID ≈ 0.06 m/s — Hass et al., *Defining the Clinically
    /// Meaningful Difference in Gait Speed in Persons with Parkinson Disease*, JNPT 2014
    /// (n=324). Rationale + the other metrics' TODO: docs/design/confidence-presence-vs-absence.md
    var mcid: Double? {
        switch self {
        case .walkingSpeed: 0.06
        case .stepLength, .doubleSupport, .asymmetry: nil
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
                                 workouts: [WorkoutEvent] = [],
                                 food: [FoodIntakeEvent] = [],
                                 sleep: [SleepInterval] = []) -> [Insight] {
        // The registry now DRIVES execution: walk the active questions in order
        // and dispatch each to its analysis. Entries whose primitive isn't built
        // yet (the sleep cluster, etc.) return nil and stay dormant — the
        // "ship the question, light up when the data earns it" model.
        //
        // Every levodopa-specific analysis (wearing-off card, afternoon-onset card, the
        // dose-confound guard) runs on the LEVODOPA-CANDIDATE doses, not the raw medication log:
        // estimable formulations PLUS data-thin ones (< 20 doses — too few to judge, so benefit
        // of the doubt: probably real levodopa like an occasional Mucuna), EXCLUDING only
        // CONFIRMED non-pulsatile substances (≥ 20 doses that show no dose→ON→OFF pulse — a
        // supplement like CDP-Choline, or an agonist). This is the SAME thin-vs-inert rule the
        // forecast uses: a supplement can't pollute the pooled wearing-off curve or over-shadow a
        // food/exercise window, while a rarely-taken real levodopa still counts. The gate is the
        // classifier (measured per-user), not a drug dictionary; 20+ doses are needed to judge.
        // Computed here in the wiring — the pinned parity functions are called directly with full
        // doses, so this filtering never touches them.
        //
        // MEASURED sleep is what flows down here. Everything reached from this line censors
        // an observation rather than adjusting a sum, and censoring must never rest on a
        // guessed bedtime — see `wearingOffInsight`, which synthesises the conservative
        // fallback itself, for the gap side only.
        let sig = samples.map { (time: $0.timestamp, value: $0.tremorScore) }
        let effSleep = mergeSleep(sleep)
        let estimableKeys = Set(estimableFormulations(signal: sig, doses: doses, sleep: effSleep).keys)
        let groupSizes = Dictionary(grouping: doses, by: { formulationKey($0.name) }).mapValues(\.count)
        let levodopaDoses = doses.filter { d in
            let k = formulationKey(d.name)
            return estimableKeys.contains(k) || (groupSizes[k] ?? 0) < 20
        }

        // Per-user dose-confound ON-window, from the SAME validated KM median the wearing-off
        // card uses. Computed once here (not per entry); skip the extra survival pass when
        // there are no non-medication exposures to guard.
        let onWindow = (workouts.isEmpty && food.isEmpty)
            ? doseOnWindowFallback
            : doseOnWindowMinutes(samples: samples, doses: levodopaDoses, sleep: effSleep)
        return InsightRegistry.starter
            .filter { $0.status == .active }
            .compactMap { run($0, samples: samples, doses: levodopaDoses,
                              gait: gait, workouts: workouts, food: food,
                              onWindow: onWindow, sleep: effSleep) }
    }

    /// Dispatch one registry entry to the renderer that draws it.
    ///
    /// Dispatch keys on `entry.renderer` — the self-describing display axis — NOT on
    /// the id (the old transitional shim is gone) and NOT on the primitive alone
    /// (which can't distinguish the gait *composite* renderer from a future
    /// single-metric trend that shares `.longTermTrend`). Each renderer reads its
    /// statistical parameters from `entry.primitive`, so a new question over a built
    /// renderer + primitive needs no code here — only its registry line. A nil
    /// renderer (or a primitive that doesn't match) = registered but dormant.
    static func run(_ entry: RegistryEntry, samples: [TremorPoint], doses: [Dose],
                    gait: [GaitMetric: [GaitSample]], workouts: [WorkoutEvent],
                    food: [FoodIntakeEvent], onWindow: Double = doseOnWindowFallback,
                    sleep: [SleepInterval] = []) -> Insight? {
        // `doses` here is the LEVODOPA-CANDIDATE set (see generateInsights): confirmed
        // non-pulsatile substances are already filtered out, so every renderer below is safe.
        switch entry.renderer {
        case .doseResponse:
            guard case .doseResponseByTimeOfDay(let preMin, let postMin) = entry.primitive else { return nil }
            guard var insight = afternoonDoseInsight(samples: samples, doses: doses, preMin: preMin, postMin: postMin) else { return nil }
            insight.stage = stage(for: entry)
            return insight
        case .wearingOff:
            guard case .survivalDuration(let onThreshold) = entry.primitive else { return nil }
            // wearingOffInsight stratifies by formulation internally over the levodopa-candidate set.
            guard var insight = wearingOffInsight(samples: samples, doses: doses,
                                                  onThreshold: onThreshold, sleep: sleep) else { return nil }
            insight.stage = stage(for: entry)
            return insight
        case .gaitComposite:
            // The one documented exception: gait is a progression readout, not a
            // lifestyle/medication lever, so its stage isn't safety-derived. It always
            // renders as `.verdict` and shifts only its COPY by trend direction —
            // reassuring when stable, "worth mentioning to your neurologist" when a
            // marker declines. So it sets its own stage and is passed through
            // unmodified (not routed via stage(for:)).
            return gaitInsight(series: gait)
        case .windowedEffect:
            guard case .windowedEffect(let preMin, let postMin) = entry.primitive else { return nil }
            guard var insight = windowedEffectInsight(entry: entry, samples: samples, doses: doses,
                                                      workouts: workouts, food: food,
                                                      preMin: preMin, postMin: postMin, onWindowMin: onWindow) else { return nil }
            insight.stage = stage(for: entry)
            return insight
        case .none:
            return nil   // no renderer wired yet — registered but dormant
        }
    }

    /// Derive a card's STAGE from its question's `SafetyClass` — the single place
    /// this policy lives. A patient-controllable finding (`.lifestyleExperiment`)
    /// invites action, so it enters the hypothesis → experiment → verdict track; a
    /// medication- or progression-related finding (`.clinicalReferral`) refers out
    /// via a discuss-with-your-neurologist card and never offers an experiment.
    ///
    /// Deriving here, not per-renderer, is the fix: a renderer can no longer stamp a
    /// stage that disagrees with the question's safety class. That decoupling is how
    /// the afternoon-dose AND dyskinesia-peak cards — both `.clinicalReferral`, but
    /// both drawn by experiment-offering renderers (`.doseResponse` / `.windowedEffect`)
    /// — ended up showing a "Try an experiment" button they should never have.
    ///
    /// Gait is the one documented exception and is intentionally NOT routed through
    /// here (see `run()`). The experiment lifecycle (running → `.experiment`,
    /// concluded → `.verdict`) will hook in here once persisted experiments exist.
    static func stage(for entry: RegistryEntry) -> Insight.Stage {
        switch entry.safety {
        case .lifestyleExperiment: return .hypothesis
        case .clinicalReferral:    return .clinicalDiscussion
        }
    }

    /// Resolved inputs for a windowed-effect card: the event stream (filtered from
    /// whichever cluster this exposure belongs to) plus the copy that varies by
    /// cluster. This is the ONE place the food and exercise clusters diverge — the
    /// math (`windowedEffect`), the gate, the chart, and the card shape are all
    /// shared. Adding a third windowed cluster later = another branch here, not a
    /// new renderer.
    struct WindowedExposure {
        let events: [(start: Date, end: Date)]
        let displayName: String   // title-case noun ("Tai Chi", "Caffeine")
        let unitWord: String      // how occurrences are counted ("sessions" / "servings")
        let mechanism: String     // the cluster-appropriate hedge / explanation
    }

    /// Map a windowed-effect registry entry to its event stream + copy. Workout
    /// exposures draw from `workouts` (filtered by activity); food exposures draw
    /// from `food` (filtered by attribute, each intake a zero-length event). Returns
    /// nil for an exposure this renderer doesn't serve (it stays dormant).
    static func windowedExposure(
        entry: RegistryEntry, workouts: [WorkoutEvent], food: [FoodIntakeEvent]
    ) -> WindowedExposure? {
        if let raw = entry.exposure.workoutRawValue {
            let events = workouts
                .filter { $0.activityRawValue == raw }
                .map { (start: $0.start, end: $0.start.addingTimeInterval($0.duration)) }
            let name = entry.exposure.workoutDisplayName ?? "this activity"
            return WindowedExposure(
                events: events, displayName: name, unitWord: "sessions",
                mechanism: "Exercise can shift PD motor symptoms for a while afterward, but daily tremor has many drivers — sleep, stress, and medication timing among them. Treat this as a lead to test, not a conclusion.")
        }
        if let attr = entry.exposure.foodAttribute {
            let events = food
                .filter { $0.attributes.contains(attr) }
                .map { (start: $0.timestamp, end: $0.timestamp) }   // intake is instantaneous
            return WindowedExposure(
                events: events, displayName: attr.displayName, unitWord: "servings",
                mechanism: foodMechanism(attr))
        }
        return nil
    }

    /// Cluster-appropriate hedge for a food exposure. Caffeine's bakes in the
    /// wearing-off confound (coffee is often taken when a dose is fading), since
    /// this pooled windowed-effect doesn't control for dose state.
    static func foodMechanism(_ attr: FoodAttribute) -> String {
        switch attr {
        case .caffeine:
            return "Caffeine's effect on Parkinson's tremor is genuinely mixed. It blocks adenosine A2A receptors — the same target as some PD medications — and higher caffeine intake is linked to lower PD risk, which leans toward benefit; but as a stimulant it can also nudge tremor up in some people, and no clear acute effect is established. Servings near a dose are set aside first, so what's left leans toward caffeine on its own — a lead to test, not proof."
        case .sugar:
            return "A sugar load drives a glucose spike and crash, and glucose swings may track with how steady your symptoms feel. The link is indirect with many other drivers — treat this as a lead to test, not a conclusion."
        default:
            return "This is an association in your own data with many possible drivers — treat it as a lead to test, not a conclusion."
        }
    }

    /// Conservative default ON-window (minutes) used when the per-user KM median isn't
    /// estimable. ≈ the validated median ON-duration (~192 min).
    static let doseOnWindowFallback: Double = 190

    /// The dose-confound guard's ON-window, sourced from the SAME validated KM median
    /// ON-duration the wearing-off card computes — so the guard adapts per user instead
    /// of using a magic constant (someone with a shorter ON-duration gets a tighter
    /// shadow). Falls back when the median isn't yet estimable (too few doses) or is
    /// physiologically implausible; the [90, 360]-min rails only catch degenerate
    /// estimates from sparse early data (sanity bounds, not tuning).
    static func doseOnWindowMinutes(samples: [TremorPoint], doses: [Dose],
                                    sleep: [SleepInterval] = []) -> Double {
        guard !doses.isEmpty else { return doseOnWindowFallback }
        let surv = survivalDuration(
            signal: samples.map { (time: $0.timestamp, value: $0.tremorScore) },
            events: doses.map(\.timestamp), onThreshold: offThreshold, sleep: sleep)
        let km = surv.kmMedian
        guard km.isFinite, km >= 90, km <= 360 else { return doseOnWindowFallback }
        return km
    }

    /// Dose-confound guard. Drops events whose measurement window could be contaminated
    /// by levodopa's ON-effect, so a non-medication exposure (food, exercise) isn't
    /// credited with the dose's tremor reduction. An event is kept ("dose-clean") only
    /// if NO dose falls within `[eventStart − onWindowMin, eventEnd + postMin]`: a dose
    /// up to ~ON-duration before the event may still be modulating tremor during
    /// measurement, and any dose during/after directly contaminates the post-window.
    /// Deliberately conservative — for an exposure habitually taken near doses
    /// (caffeine) it collapses n toward zero, and the honest result is "can't separate
    /// from your medication" (no card) rather than a confounded claim. `onWindowMin`
    /// from the validated ON duration (~192 min). General: every non-medication
    /// windowed exposure uses it (food + exercise + mindfulness); the dose-as-exposure
    /// entry never reaches this path. Reverse causation matters for exercise too —
    /// sessions done only while ON would otherwise read as "exercise lowered tremor."
    static func doseCleanEvents(
        _ events: [(start: Date, end: Date)], doses: [Dose],
        postMin: Double, onWindowMin: Double = 190
    ) -> [(start: Date, end: Date)] {
        guard !doses.isEmpty else { return events }
        let doseTimes = doses.map(\.timestamp)
        return events.filter { ev in
            let shadowStart = ev.start.addingTimeInterval(-onWindowMin * 60)
            let shadowEnd = ev.end.addingTimeInterval(postMin * 60)
            return !doseTimes.contains { $0 >= shadowStart && $0 <= shadowEnd }
        }
    }

    /// Render a windowed-effect registry entry into a card. The exposure resolver
    /// supplies the event stream + cluster copy (workout or food); everything below
    /// — primitive, gate, chart, card shape — is shared across clusters. Other
    /// exposures/outcomes return nil until their adapters land (dormant).
    static func windowedEffectInsight(
        entry: RegistryEntry, samples: [TremorPoint], doses: [Dose] = [],
        workouts: [WorkoutEvent], food: [FoodIntakeEvent],
        preMin: Double, postMin: Double, onWindowMin: Double = doseOnWindowFallback
    ) -> Insight? {
        guard entry.outcome.isTremor,
              let exposure = windowedExposure(entry: entry, workouts: workouts, food: food),
              !exposure.events.isEmpty else { return nil }
        // Dose-confound guard: a non-medication exposure must not be credited with the
        // levodopa ON-effect. Drop dose-shadowed events; if nothing clean survives,
        // there's no honest read — return nil rather than a confounded claim.
        let events = doseCleanEvents(exposure.events, doses: doses,
                                     postMin: postMin, onWindowMin: onWindowMin)
        guard !events.isEmpty else { return nil }
        let signal = samples.map { (time: $0.timestamp, value: $0.tremorScore) }
        guard let eff = windowedEffect(events: events, signal: signal,
                                       preMin: preMin, postMin: postMin) else { return nil }
        guard let confidence = gate(Self.windowedEffectGate, n: eff.n,
                                    effect: abs(eff.delta), p: eff.pValue) else { return nil }

        let name = exposure.displayName
        let lower = name.lowercased()
        let unit = exposure.unitWord
        let hours = max(1, Int((postMin / 60).rounded()))
        let pct = abs(eff.pctChange).isFinite ? String(format: "%.0f%%", abs(eff.pctChange)) : "—"
        let days = Set(events.map { calendar.startOfDay(for: $0.start) }).count
        let doseNote = doses.isEmpty ? "" : " clear of your dose windows"
        let significant = confidence != .emerging
        let eased = eff.delta < 0

        // Summary = the takeaway; finding = sample size + hedge. No field restates
        // another's numbers (summary carries the effect, finding carries the n/days).
        let title: String, summary: String, finding: String
        switch (significant, eased) {
        case (true, true):
            title = "\(name) may ease your tremor"
            summary = "In the \(hours)h after \(lower), your tremor ran about \(pct) lower than just before."
            finding = "Seen across \(eff.n) \(unit)\(doseNote) over \(days) days — an association in your own data, a hypothesis to test, not proof."
        case (true, false):
            title = "\(name) may stir your tremor"
            summary = "In the \(hours)h after \(lower), your tremor ran about \(pct) higher than just before."
            finding = "Seen across \(eff.n) \(unit)\(doseNote) over \(days) days — an association in your own data, a hypothesis to test, not proof."
        default:
            title = "\(name): no clear tremor effect yet"
            summary = "Across \(eff.n) \(unit)\(doseNote), any before-and-after difference stays within normal day-to-day swing."
            finding = "The point estimate is about \(pct) \(eased ? "lower" : "higher") afterward, but over \(days) days that's within the noise — not a real effect yet. Still watching."
        }

        // Stage is not set here — `run()` derives it from the entry's safety class
        // via `stage(for:)`. This renderer serves both lifestyle exposures (→ hypothesis)
        // and the clinical dyskinesia-peak entry (→ clinicalDiscussion), so it cannot
        // know the right stage on its own — which is exactly why deriving it centrally.
        var insight = Insight(
            title: title, summary: summary,
            finding: finding, mechanism: exposure.mechanism,
            confidence: confidence, evidenceDays: days)
        insight.chart = windowedEffectChart(
            events: events, signal: signal, preMin: preMin, postMin: postMin,
            activityLabel: name)
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

nonisolated extension CorrelationEngine {

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

    /// One-sided p for an ABSENCE claim — "this has not declined by anything that
    /// matters" — so it can feed the same `maxP` axis `gate` already scores.
    ///
    /// The presence gate asks *does an effect exist?* (H₀: change = 0). That question is
    /// backwards for a card claiming absence: a truly flat signal never reaches
    /// significance, so it would be capped at Emerging forever no matter how much
    /// confirming data arrives. This asks the card's actual question instead —
    /// H₀: decline ≥ `margin` — and rejecting it earns the reassurance honestly.
    ///
    /// ONE-SIDED by design. The claim is "hasn't declined", not "hasn't changed", so a
    /// genuine IMPROVEMENT must strengthen the card, not fail it. (A two-sided
    /// equivalence test would reject a real improvement — the same shape of bug as
    /// scoring absence with a presence gate.)
    ///
    /// - Parameters:
    ///   - change: observed change over the span, oriented so BETTER IS POSITIVE.
    ///   - stdErr: standard error of that change, same units.
    ///   - margin: smallest decline that would matter. Never a tuned knob — it is
    ///     `max(the user's own detectable margin, the published MCID)`; see
    ///     docs/design/confidence-presence-vs-absence.md.
    ///   - df: degrees of freedom of the underlying fit.
    /// - Returns: p for H₀ *decline ≥ margin*. Small p ⇒ decline confidently ruled out.
    static func nonInferiorityP(change: Double, stdErr: Double, margin: Double, df: Double) -> Double? {
        guard stdErr > 0, margin > 0, df > 0, change.isFinite, stdErr.isFinite else { return nil }
        let t = (change + margin) / stdErr
        let twoSided = regularizedIncompleteBeta(a: df / 2, b: 0.5, x: df / (df + t * t))
        // Halve to one tail: t>0 means the estimate sits above −margin (the direction
        // that supports the claim), so the evidence lives in the upper tail.
        return t > 0 ? twoSided / 2 : 1 - twoSided / 2
    }

    // Per-hypothesis specs. The first two reproduce the previously-inline gates
    // exactly; the gait spec finally uses the t-test p-value the trend already
    // computes (it was hard-coded .moderate, discarding that p).

    /// Afternoon-dose: n (afternoon doses) + effect (afternoon−morning onset min, signed).
    static let doseResponseGate = GateSpec(
        strong:   GateBar(minN: 20, minEffect: 25),
        moderate: GateBar(minN: 10, minEffect: 20),
        floor:    GateBar(minN: 5,  minEffect: 15))

    /// Minimum clinically important difference in daily OFF time: 60 min/day, the
    /// stricter end of the −1.0…−1.3 h seen in the pramipexole pivotal trials.
    /// Published, not tuned on our data. docs/design/wearing-off-margin.md.
    static let wearingOffMCIDMinPerDay = 60.0

    /// Dose-sufficiency: n (doses) only. Reused by formulation estimability and the
    /// forecast, which ask "are there enough doses to fit a curve?" — a question with no
    /// effect axis. Do NOT add `minEffect` here: those call sites pass no effect, and a
    /// bar they can't satisfy silently makes every formulation inestimable.
    static let wearingOffGate = GateSpec(
        strong:   GateBar(minN: 40),
        moderate: GateBar(minN: 1),
        floor:    GateBar(minN: 1))

    /// The wearing-off CARD: n (doses) + daily OFF minutes attributable to spacing.
    /// Separate from `wearingOffGate` because the card asks a different question — not
    /// "can we estimate this?" but "does the spacing cost enough OFF to matter?" Without
    /// the effect axis the card fired Strong on any shortfall above zero.
    static let wearingOffCardGate = GateSpec(
        strong:   GateBar(minN: 40, minEffect: wearingOffMCIDMinPerDay),
        moderate: GateBar(minN: 20, minEffect: wearingOffMCIDMinPerDay),
        floor:    GateBar(minN: 1,  minEffect: wearingOffMCIDMinPerDay))

    /// Gait trend: n (months of medians) + a p-value whose MEANING depends on the card's
    /// verdict — slope significance when it claims a decline, `nonInferiorityP` when it
    /// claims one is absent. The tiers are deliberately shared: "how sure are we" reads the
    /// same to the user either way, so only the question underneath differs.
    /// See `gaitInsight` and docs/design/confidence-presence-vs-absence.md.
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

nonisolated extension CorrelationEngine {

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

    /// Result of the dose-response-by-time-of-day PRIMITIVE: one response trace per
    /// event with adequate coverage, plus the onset latency aggregated into time-of-day
    /// buckets. The renderer (`afternoonDoseInsight`) gates this and draws the card —
    /// mirroring how `gaitInsight` renders `longTermTrend`. `buildTraces` is the
    /// tremor/dose adapter over this; the test pins it for parity.
    struct DoseResponseByToD {
        let traces: [DoseTrace]
        /// Mean onset latency (t½, the 50%-of-drop time) + contributing dose count
        /// for one time-of-day bucket. Doses whose drop never reached 50% (`tHalf`
        /// NaN) are excluded, as in the lab.
        func onset(_ bucket: Bucket) -> (mean: Double, n: Int) {
            let xs = traces.filter { $0.bucket == bucket && !$0.tHalf.isNaN }.map(\.tHalf)
            return (CorrelationEngine.nanmean(xs), xs.count)
        }
    }

    /// The dose-response-by-time-of-day PRIMITIVE, generic over the two canonical
    /// shapes: a continuous `signal` and discrete `events`. For each event it builds
    /// a baseline-corrected post-event trajectory (truncated at the next event),
    /// keeps only events with adequate coverage, and tags each by time-of-day bucket.
    /// Variable-agnostic by construction — tremor-vs-dose today, any signal-vs-event
    /// tomorrow. `preMin`/`postMin` come from the registry entry.
    static func doseResponseByTimeOfDay(
        signal: [(time: Date, value: Double)], events: [Date],
        preMin: Double, postMin: Double
    ) -> DoseResponseByToD {
        let series = signal.sorted { $0.time < $1.time }
        let ds = events.sorted()
        var traces: [DoseTrace] = []

        for (i, t0) in ds.enumerated() {
            // Guard 1: truncate the post window at the next event.
            let postEff: Double
            if i + 1 < ds.count {
                let gap = ds[i + 1].timeIntervalSince(t0) / 60.0
                postEff = min(postMin, max(0, gap))
            } else {
                postEff = postMin
            }

            let lo = t0.addingTimeInterval(-preMin * 60)
            let hi = t0.addingTimeInterval(postEff * 60)
            let win = series.filter { $0.time >= lo && $0.time <= hi }
            if win.count < 3 { continue }

            let rel = win.map { $0.time.timeIntervalSince(t0) / 60.0 }
            let vals = win.map { $0.value }
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
        return DoseResponseByToD(traces: traces)
    }

    /// Tremor/dose adapter over the generic primitive. Kept as the parity surface the
    /// test pins; uses the dose-response window constants (= the registry's params).
    static func buildTraces(samples: [TremorPoint], doses: [Dose]) -> [DoseTrace] {
        doseResponseByTimeOfDay(
            signal: samples.map { (time: $0.timestamp, value: $0.tremorScore) },
            events: doses.map(\.timestamp),
            preMin: preMin, postMin: postMin
        ).traces
    }

    /// The afternoon-dose finding, or nil if the pattern doesn't clear the gate.
    /// The bespoke RENDERER over the `doseResponseByTimeOfDay` primitive: it runs the
    /// primitive, gates on the afternoon-vs-morning onset gap, and composes the card.
    static func afternoonDoseInsight(samples: [TremorPoint], doses: [Dose],
                                     preMin: Double = CorrelationEngine.preMin,
                                     postMin: Double = CorrelationEngine.postMin) -> Insight? {
        let dr = doseResponseByTimeOfDay(
            signal: samples.map { (time: $0.timestamp, value: $0.tremorScore) },
            events: doses.map(\.timestamp),
            preMin: preMin, postMin: postMin)
        let traces = dr.traces

        let aft = dr.onset(.afternoon)
        let morn = dr.onset(.morning)

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

        // Stage omitted — `run()` derives it from the entry's safety class. This entry
        // is .clinicalReferral (a medication-regimen finding), so it renders as a
        // clinical-discussion card, NOT a hypothesis with an experiment button.
        // The clinical payload populates BOTH the card's "what your neurologist might
        // consider" detail and the matching section of the shareable report — without
        // it the card (and the PDF section) would render bare.
        return Insight(
            title: "Your afternoon dose works slower",
            summary: summary,
            finding: finding,
            mechanism: mechanism,
            confidence: confidence,
            evidenceDays: days,
            chart: doseResponseChart(traces: traces),
            clinical: ClinicalDiscussion(
                whatTheyMightConsider: "A dose that comes on slowly and incompletely — more so later in the day — can stem from absorption, slowed stomach emptying, protein and meal timing around the dose, or the formulation itself. Your neurologist has the levers here that only they can weigh: for example dose timing or amount, a faster- or longer-acting formulation, or guidance on meal timing around the dose. The value is bringing them this pattern, with the data behind it.",
                bringThisData: [
                    "Afternoon onset ~\(aftMin) min vs ~\(mornMin) min in the morning",
                    "Afternoon dose also peaks weaker (shallower ON)",
                    "Duration stays normal — the issue is onset, not early wearing-off",
                    "From \(scored) scored doses over \(days) days"
                ]
            )
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

    // MARK: - Waking time
    //
    // Fallback clock window, used ONLY for a day with no recorded sleep (no overnight
    // Watch wear). Without it such a user gets silence. 22:00 is deliberately
    // conservative rather than accurate — typical adult bedtime is ~10:30-11pm and PD
    // often earlier, so this slightly UNDER-counts waking OFF, the right direction to
    // err for a health claim. It is not tuned to Bhav: his own worst hours are 20:00-23:00
    // with sleep onset ~midnight, which is precisely why anyone WITH sleep data must
    // never reach this path. 20:00 was never chosen — it was inherited from the old gap
    // filter, and his 10pm dose disproves it. Rejected alternative: deriving the window
    // from the user's own dose times — skipping the evening dose would then close the
    // window at 3:30pm and erase the very evening the skip created.
    static let fallbackWakeHour = 6      // 06:00
    static let fallbackBedHour = 22      // 22:00 the PREVIOUS evening

    /// Merge overlapping/touching intervals. Sleep arrives fragmented (stage changes,
    /// multiple sources, overlapping syncs); every consumer below assumes merged+sorted.
    static func mergeSleep(_ ivs: [SleepInterval]) -> [SleepInterval] {
        var out: [SleepInterval] = []
        for iv in ivs.sorted(by: { $0.start < $1.start }) where iv.end > iv.start {
            if let last = out.last, iv.start <= last.end {
                out[out.count - 1] = SleepInterval(start: last.start, end: max(last.end, iv.end))
            } else {
                out.append(iv)
            }
        }
        return out
    }

    /// Recorded sleep, plus a synthetic clock night for any day with NO recorded sleep.
    /// Making the fallback a data-prep step (rather than a branch inside the math) means
    /// every consumer downstream sees one uniform list and can't forget the no-data case.
    /// A day with real sleep never receives a synthetic interval.
    static func effectiveSleep(recorded: [SleepInterval],
                               covering range: ClosedRange<Date>) -> [SleepInterval] {
        let real = recorded.filter { $0.end > $0.start }
        // Attribute a night to the day it ENDED — the day the patient woke up.
        let wokeOn = Set(real.map { calendar.startOfDay(for: $0.end) })
        var all = real
        var day = calendar.startOfDay(for: range.lowerBound)
        let lastDay = calendar.startOfDay(for: range.upperBound)
        while day <= lastDay {
            if !wokeOn.contains(day),
               let bed = calendar.date(byAdding: .hour, value: fallbackBedHour - 24, to: day),
               let wake = calendar.date(byAdding: .hour, value: fallbackWakeHour, to: day) {
                all.append(SleepInterval(start: bed, end: wake))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return mergeSleep(all)
    }

    /// Minutes of `[a, b)` spent asleep. `sleep` must be merged + sorted.
    static func asleepMinutes(from a: Date, to b: Date, sleep: [SleepInterval]) -> Double {
        guard b > a, !sleep.isEmpty else { return 0 }
        var total = 0.0
        for iv in sleep {
            if iv.start >= b { break }
            if iv.end <= a { continue }
            total += min(b, iv.end).timeIntervalSince(max(a, iv.start)) / 60
        }
        return total
    }

    /// The moment observation of a dose must stop — the next onset of sleep, or `t`
    /// itself if already asleep. nil = no sleep ahead in the record.
    static func sleepOnset(after t: Date, sleep: [SleepInterval]) -> Date? {
        for iv in sleep {
            if iv.end <= t { continue }
            return iv.start <= t ? t : iv.start
        }
        return nil
    }

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

    /// Result of the survival/ON-duration PRIMITIVE: per-dose durations (observed or
    /// right-censored) plus the Kaplan–Meier median and the observed-event count. The
    /// renderer (`wearingOffInsight`) gates and draws the card; `analyzeWearingOff` is
    /// the tremor/dose adapter the parity test pins.
    struct SurvivalDuration {
        let durations: [DoseDuration]
        let kmMedian: Double        // KM median ON-duration (.nan if not estimable)
        let observedCount: Int      // doses observed to wear off before the next dose
    }

    /// The survival / ON-duration PRIMITIVE, generic over a continuous `signal` and
    /// discrete `events`. For each event: build the post-event trajectory, find when
    /// the signal sustains a return above `onThreshold` (OFF-return) — or right-censor
    /// at the next event — then estimate the Kaplan–Meier median duration. Variable-
    /// agnostic; the threshold comes from the registry entry.
    /// `sleep` defaults to empty = observe purely on the dose clock, which is exactly
    /// what the Python lab did — so the parity fixture keeps pinning a faithful port.
    /// The APP always passes real sleep, so the censoring below applies everywhere the
    /// duration is used (card, forecast, formulation estimability), not just one card:
    /// a duration inflated by sleep is wrong on every surface that reads it.
    static func survivalDuration(
        signal: [(time: Date, value: Double)], events: [Date], onThreshold: Double,
        sleep: [SleepInterval] = []
    ) -> SurvivalDuration {
        let series = signal.sorted { $0.time < $1.time }
        let ds = events.sorted()
        var results: [DoseDuration] = []

        for (i, t0) in ds.enumerated() {
            var interval = Double.nan
            if i + 1 < ds.count { interval = ds[i + 1].timeIntervalSince(t0) / 60.0 }
            let isolated = interval.isNaN || interval >= gapIso

            let lo = t0.addingTimeInterval(-preMin * 60)
            let hi = t0.addingTimeInterval(maxWindow * 60)
            let win = series.filter { $0.time >= lo && $0.time <= hi }
            if win.count < 4 { continue }

            let rel = win.map { $0.time.timeIntervalSince(t0) / 60.0 }
            let vals = win.map { $0.value }
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

            // Observation horizon: truncate at the next dose, and at sleep onset.
            //
            // Tremor flattens in sleep regardless of drug state (Bhav's 1-6am runs a
            // median of 0.00), so looking past sleep scores "no OFF-return" from a
            // signal we cannot read, and credits the dose with coverage it never gave.
            // His evening doses were 67% censored that way, inflating pooled KM
            // 177.5 -> 192.5 min. This is a CENSOR, not a subtraction: the drug keeps
            // metabolising while he sleeps, so the dose's clock never pauses — we just
            // stop being able to observe it, and record "held at least this long".
            var horizon = interval.isNaN ? maxWindow : min(maxWindow, interval)
            if let onset = sleepOnset(after: t0, sleep: sleep) {
                horizon = min(horizon, max(0, onset.timeIntervalSince(t0) / 60))
            }
            // Dosed while already asleep (or within a bin of it): nothing observable.
            if horizon <= 0 { continue }
            let (duration, observed) = offReturn(centers: centers, sm: sm, horizon: horizon, thr: onThreshold)

            let hour = hourOfDay(t0)
            results.append(DoseDuration(
                t0: t0, hour: hour, bucket: bucketOf(hour),
                baseline: baseline, trough: trough, intervalMin: interval,
                durationMin: duration, observed: observed, isolated: isolated,
                binValues: sm   // smoothed series → canonical curve (Python parity)
            ))
        }
        let km = kmMedian(durations: results.map(\.durationMin), observed: results.map(\.observed))
        return SurvivalDuration(
            durations: results, kmMedian: km,
            observedCount: results.filter { $0.observed }.count)
    }

    /// Tremor/dose adapter over the survival primitive. The parity surface the test
    /// pins; uses the engine's OFF threshold (= the registry entry's `onThreshold`).
    static func analyzeWearingOff(samples: [TremorPoint], doses: [Dose]) -> [DoseDuration] {
        survivalDuration(
            signal: samples.map { (time: $0.timestamp, value: $0.tremorScore) },
            events: doses.map(\.timestamp), onThreshold: offThreshold
        ).durations
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
    /// The bespoke RENDERER over the `survivalDuration` primitive: it runs the
    /// primitive, gates on dose count + the gap-exceeds-duration condition, and
    /// composes the clinical-discussion card.
    static func wearingOffInsight(samples: [TremorPoint], doses: [Dose],
                                  onThreshold: Double = CorrelationEngine.offThreshold,
                                  sleep rawSleep: [SleepInterval] = []) -> Insight? {
        let sig = samples.map { (time: $0.timestamp, value: $0.tremorScore) }

        // The two uses of sleep take DIFFERENT inputs, and the difference is load-bearing.
        //
        //   • CENSORING a duration uses MEASURED sleep only. Censoring discards a real
        //     observation, so it must never rest on a guess: the fallback would claim "asleep
        //     at 22:00" for a patient who demonstrably took a dose at 22:00 — taking a pill is
        //     evidence of being awake. Guessing here dropped 35 of 106 doses off the parity
        //     fixture's curve. With no measured sleep we simply don't censor: we can't know
        //     when observation stopped, so we don't pretend to.
        //   • SUBTRACTING from a gap uses EFFECTIVE sleep (measured + a conservative
        //     22:00-06:00 night for any day with none). Removing the 600-min cap removed the
        //     thing that was accidentally keeping sleep out of the count, so a sleep-blind
        //     caller would score a whole unconscious night as waking OFF. Erring conservative
        //     on a SUM is safe in a way that erring on a MEASUREMENT is not.
        //
        // Normalised here rather than trusted from the caller — a default that silently means
        // "wrong" rather than "unset" is the same footgun as one GateSpec shared across
        // callers asking different questions. Idempotent, so callers may pre-merge.
        let measuredSleep = mergeSleep(rawSleep)
        let effectiveSleepIntervals: [SleepInterval]
        if let lo = samples.map(\.timestamp).min(), let hi = samples.map(\.timestamp).max() {
            effectiveSleepIntervals = effectiveSleep(recorded: measuredSleep, covering: lo...hi)
        } else {
            effectiveSleepIntervals = measuredSleep
        }

        // POOLED wearing-off over all doses drives the FIRING gate + the chart, and matches the
        // validated Python-lab curve (the parity test pins it). Firing is unchanged from before
        // stratification; the per-formulation rows below only enrich the copy. Keeping the chart
        // pooled is also the honest CLINICAL choice: the "gap" is a coverage concept spanning
        // formulations, while "how long it lasts" is per-formulation — so the aggregate curve
        // stays the visual, and the by-formulation medians go in the text.
        let pooled = survivalDuration(signal: sig, events: doses.map(\.timestamp),
                                      onThreshold: onThreshold, sleep: measuredSleep)
        let pooledResults = pooled.durations
        guard pooledResults.count >= 20, pooled.kmMedian.isFinite else { return nil }
        // Daily OFF attributable to dose SPACING: sum every gap's shortfall against how long a
        // dose actually holds, SUBTRACT the part the patient slept through, then average over
        // dosed days. NOT median gap minus median duration — two medians can't see one
        // catastrophic gap (a day with three fine gaps and one terrible one has the same median
        // as a day of four mediocre ones), which understated this ~2x. The sum is also the
        // quantity the MCID is defined on, so the gate can ask whether the shortfall matters.
        //
        // Uncovered time is a WAKING quantity — you don't experience OFF asleep — which is why
        // sleep is subtracted HERE but only censors the duration above. The two old magic
        // numbers (`intervalMin < 600`, `hour >= 6 && < 20`) both stood in for "was he awake?";
        // measured sleep answers that directly, so both are gone. They dropped a long gap WHOLE
        // rather than clipping it: that erased the evening on 26% of Bhav's days, erased the
        // 7-8am pre-first-dose stretch on MOST days, and silenced the card entirely for a
        // once-daily regimen (24h gap -> dropped -> zero uncovered -> no card for the patient
        // with the worst wearing-off). docs/design/wearing-off-margin.md.
        var pooledDayIntervals: [Double] = []
        var allIntervals: [Double] = []
        var uncoveredByDay: [Date: Double] = [:]
        var dosedDays: Set<Date> = []
        for r in pooledResults {
            dosedDays.insert(calendar.startOfDay(for: r.t0))
            guard !r.intervalMin.isNaN else { continue }
            allIntervals.append(r.intervalMin)
            // Descriptive only (the copy's "typical daytime gap"). Deliberately still the
            // daytime subset: it describes the rhythm a reader recognises, while the headline
            // number below counts every waking uncovered minute.
            if r.hour >= 6, r.hour < 20, r.intervalMin < 600 { pooledDayIntervals.append(r.intervalMin) }

            let coverageEnd = r.t0.addingTimeInterval(pooled.kmMedian * 60)
            let nextDose = r.t0.addingTimeInterval(r.intervalMin * 60)
            let uncovered = nextDose.timeIntervalSince(coverageEnd) / 60
            guard uncovered > 0 else { continue }
            let waking = uncovered - asleepMinutes(from: coverageEnd, to: nextDose,
                                                   sleep: effectiveSleepIntervals)
            uncoveredByDay[calendar.startOfDay(for: r.t0), default: 0] += max(0, waking)
        }
        guard !dosedDays.isEmpty else { return nil }
        let dailyUncovered = uncoveredByDay.values.reduce(0, +) / Double(dosedDays.count)
        // Fall back to ALL gaps when there's no daytime-to-daytime gap at all — a once-daily
        // regimen has exactly one 24h gap, so the daytime subset is empty. Bailing on a NaN
        // median here would silence the card for precisely the patient this change exists to
        // serve. The median is descriptive copy, never the estimate; it must not gate firing.
        let pooledMedInterval = pooledDayIntervals.isEmpty
            ? median(allIntervals) : median(pooledDayIntervals)
        guard !pooledMedInterval.isNaN else { return nil }

        // Per-formulation rows: a single median across a mixed regimen (IR vs plant-source
        // levodopa last different lengths) describes neither. A formulation becomes a row only
        // if it independently clears the floor AND shows the gap-exceeds-duration pattern.
        struct Row { let key: String; let km: Double; let medInterval: Double; let count: Int; let observedCount: Int }
        var rows: [Row] = []
        for (key, ds) in Dictionary(grouping: doses, by: { formulationKey($0.name) }) {
            let surv = survivalDuration(signal: sig, events: ds.map(\.timestamp),
                                        onThreshold: onThreshold, sleep: measuredSleep)
            let results = surv.durations
            guard results.count >= 20, surv.kmMedian.isFinite else { continue }
            var dayIntervals: [Double] = []
            for r in results where r.hour >= 6 && r.hour < 20 && !r.intervalMin.isNaN && r.intervalMin < 600 {
                dayIntervals.append(r.intervalMin)
            }
            let medInterval = median(dayIntervals)
            guard !medInterval.isNaN, medInterval > surv.kmMedian else { continue }
            rows.append(Row(key: key, km: surv.kmMedian, medInterval: medInterval,
                            count: results.count, observedCount: surv.observedCount))
        }
        rows.sort { $0.count > $1.count }

        let days = dosedDays.count
        // The MCID is now the firing condition — no card when spacing costs less OFF than a
        // patient could perceive. Replaces the old `medianGap > medianDuration` test, and the
        // `?? .moderate` fallback that quietly handed out a tier the gate had refused.
        guard let confidence = gate(Self.wearingOffCardGate, n: pooledResults.count,
                                    effect: dailyUncovered) else { return nil }

        func name(_ key: String) -> String { key.split(separator: " ").map { $0.capitalized }.joined(separator: " ") }
        // ONE formatter for both halves of the comparison: `%.0f` on the gap alone printed a
        // 4.1 h gap as "~4 h" against a "~3.2 h" dose, inflating the very shortfall being read.
        func hrs(_ min: Double) -> String { String(format: "%.1f", min / 60) }
        let uncoveredMin = Int(dailyUncovered.rounded())

        let title: String, summary: String, finding: String, mechanism: String, consider: String
        let bring: [String]

        // Multi-formulation copy only when ≥ 2 formulations independently show the pattern;
        // otherwise today's pooled copy — byte-identical to before for a single-formulation user.
        let kmMin = Int(pooled.kmMedian.rounded())
        let gapMin = Int(pooledMedInterval.rounded())
        // The TITLE carries the number, in HOURS — a glance shouldn't require dividing by 60,
        // and precise minutes belong in the detail below, not the headline. Every other line
        // does different work: repeating one figure three times is cognitive load, not
        // emphasis. So: title = the total (hours), summary = why it happens, finding = method
        // + provenance (precise minutes), bullets = the clinician's numbers.
        //
        // ⚠️ The summary deliberately prints ONE number, not two. It used to read "doses hold
        // ~3.0 h but your daytime gaps run ~4.1 h", which invited the reader to subtract and
        // land on ~2 h — against a headline of 8.3. Most of the total comes from gaps that
        // aren't daytime gaps at all (the stretch before the first dose, the evening after the
        // last), so no pair of medians can reconcile with it. Handing someone arithmetic that
        // doesn't add up is the same defect this card was rewritten to fix.
        let spacingLine = "Estimated OFF from dose spacing: ~\(uncoveredMin) min/day (each gap's waking shortfall, added up and averaged over \(days) days)"
        let mcidLine = "A change of 60 min/day in OFF time is the published threshold for a clinically meaningful difference"

        if rows.count >= 2 {
            let parts = rows.map { "\(name($0.key)) holds ~\(hrs($0.km)) h (doses ~\(hrs($0.medInterval)) h apart)" }
            title = "Your doses leave about \(hrs(dailyUncovered)) hours a day uncovered"
            summary = "Your formulations don't last the same length, so one schedule can't fit them all."
            finding = "Adding up every gap that outlasts the dose before it, counting only the time you were awake: ~\(uncoveredMin) min a day of OFF from spacing alone. By formulation: " + parts.joined(separator: "; ") + ". From \(pooledResults.count) doses over \(days) days."
            mechanism = "This is the classic wearing-off pattern — the gap between doses is longer than a single dose lasts — and because your formulations last different lengths, it opens at a different point for each."
            bring = [spacingLine] + rows.map {
                "\(name($0.key)): median ON \(Int($0.km.rounded())) min (~\(hrs($0.km)) h) vs ~\(hrs($0.medInterval)) h between doses — n=\($0.count), \($0.observedCount) observed wearing off"
            } + [mcidLine]
            consider = "When the gap between doses is longer than a dose lasts, predictable OFF windows open up. Neurologists have several levers for this — for example adjusting dose timing or frequency, or a longer-acting formulation. On a mixed regimen the timing that fits one formulation may not fit another. These are decisions only your neurologist can make. The value here is bringing them this pattern, with the data behind it."
        } else {
            title = "Your doses leave about \(hrs(dailyUncovered)) hours a day uncovered"
            summary = "Each dose holds ~\(hrs(pooled.kmMedian)) h, but your doses don't span your waking day — the uncovered stretches add up."
            finding = "Adding up every gap that outlasts the dose before it, counting only the time you were awake: ~\(uncoveredMin) min a day of OFF from spacing alone. From \(pooledResults.count) doses over \(days) days."
            mechanism = "This is the classic wearing-off pattern: the interval between doses is longer than a single dose lasts."
            bring = [
                spacingLine,
                "Median ON-duration: \(kmMin) min (Kaplan–Meier, n=\(pooledResults.count) doses)",
                "Median daytime gap between doses: \(gapMin) min (~\(hrs(pooledMedInterval)) h)",
                "\(pooled.observedCount) of \(pooledResults.count) doses observed wearing off before the next dose",
                mcidLine,
            ]
            consider = "When the gap between doses is longer than a dose lasts, predictable OFF windows open up. Neurologists have several levers for this — for example adjusting dose timing or frequency, or a longer-acting formulation. These are decisions only your neurologist can make. The value here is bringing them this pattern, with the data behind it."
        }

        // Stage omitted — `run()` derives it from the entry's safety class
        // (.clinicalReferral → clinical-discussion card). Chart is the POOLED aggregate curve
        // (validated / parity-pinned); per-formulation medians live in the finding + clinical data.
        return Insight(
            title: title,
            summary: summary,
            finding: finding,
            mechanism: mechanism,
            confidence: confidence,
            evidenceDays: days,
            chart: wearingOffChart(results: pooledResults, km: pooled.kmMedian),
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
        let slopeStdErr: Double    // SE of that slope, native units per year
        let intercept: Double      // fitted value at the first month
        let r: Double
        let pValue: Double         // two-sided, t-test on the slope
        let spanYears: Double
        let pctChange: Double      // relative %, vs the fitted baseline
        let months: [GaitMonth]    // monthly medians, for the chart

        var isSignificant: Bool { pValue < 0.05 }
        /// Worsening = moving in the bad direction for this metric.
        var isWorsening: Bool { metric.higherIsWorse ? slopePerYear > 0 : slopePerYear < 0 }

        // MARK: Absence-claim support ("hasn't declined")

        /// Total change across the observed span, ORIENTED so better is positive —
        /// which is what lets one test serve metrics that worsen in opposite directions
        /// (speed falling vs. double-support rising both read as negative here).
        var orientedChange: Double {
            let total = slopePerYear * spanYears
            return metric.higherIsWorse ? -total : total
        }

        /// SE of `orientedChange`. Sign-free, so orientation doesn't touch it.
        var orientedChangeStdErr: Double { slopeStdErr * spanYears }

        /// The user's OWN detectable margin: the ~95% half-width on their total change.
        /// A move smaller than this is inside their personal measurement wobble, so it
        /// can't honestly be claimed for them. Computed only from this user's own data —
        /// never pooled across users (statistically wrong, since everyone's scatter
        /// differs, and it's the privacy line the app is built on).
        /// t≈1.96 + 2.4/df approximates the 97.5th t percentile without a quantile table;
        /// exact enough here, and only the reported interval leans on it — the confidence
        /// verdict itself flows through `nonInferiorityP`, which needs no quantile.
        var ownDetectableMargin: Double {
            guard nMonths > 2 else { return .infinity }
            let df = Double(nMonths - 2)
            return (1.96 + 2.4 / df) * orientedChangeStdErr
        }

        /// The margin an absence claim is tested against: the published MCID, full stop.
        ///
        /// ⚠️ NOT `max(own detectable, MCID)` — that rule (design note, Jul 13) is CIRCULAR
        /// and was corrected here. The own margin is ≈1.96·SE, so whenever it binds the
        /// test collapses to t = (0 + 1.96·SE)/SE ≈ 1.96 → p ≈ 0.03 → *always* Moderate,
        /// however noisy the data: the margin grows with the very noise it's meant to
        /// survive. Testing against the fixed clinical floor instead makes noisy data fail
        /// honestly on its own, because SE sits in the test's denominator.
        ///
        /// `ownDetectableMargin` keeps its real job — reporting what this user can resolve
        /// (and see `canResolveMCID`) — it just isn't an input to the test.
        var absenceMargin: Double? { metric.mcid }

        /// Whether this user's data is precise enough to speak to a clinically meaningful
        /// change at all. False ⇒ their own wobble is larger than the MCID, so even a
        /// "flat" reading can't rule out a decline that would matter — the honest answer
        /// is low confidence, which `noDeclineP` produces on its own.
        var canResolveMCID: Bool {
            guard let mcid = metric.mcid else { return false }
            return ownDetectableMargin <= mcid
        }

        /// p for "a decline of at least `absenceMargin` is ruled out". Small ⇒ the
        /// reassurance is earned. nil when there's no sourced MCID for this metric or the
        /// fit is degenerate — the gate then falls back to its n-only floor.
        var noDeclineP: Double? {
            guard let margin = absenceMargin else { return nil }
            return CorrelationEngine.nonInferiorityP(
                change: orientedChange, stdErr: orientedChangeStdErr,
                margin: margin, df: Double(nMonths - 2))
        }
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

        // Confidence branches on WHICH VERDICT FIRED, because presence and absence are
        // different claims and need different tests:
        //   declining → the card asserts a trend EXISTS → significance (slope p).
        //   otherwise → the card asserts a decline is ABSENT → non-inferiority, which
        //     rewards a long flat record instead of capping it at Emerging forever.
        // Both feed the same tiers via `maxP`; only the question changes. Floor (n≥6)
        // always holds here since the card already requires nMonths≥12, so it never
        // disappears — a null p just lands it on Emerging, which is the honest read.
        // See docs/design/confidence-presence-vs-absence.md.
        let scoredP = declining ? speed.pValue : speed.noDeclineP
        let confidence = gate(Self.gaitTrendGate, n: speed.nMonths, p: scoredP) ?? .emerging

        var insight = Insight(
            title: declining ? "Your mobility shows some change" : "Your mobility hasn't declined",
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

    /// A long-term trend fit over a dated signal — the reusable primitive behind the
    /// gait card. Variable-agnostic: gait metrics today, any slow-moving signal (a
    /// tremor baseline, a monthly HRV) tomorrow. The gait `MetricTrend` is this plus a
    /// metric tag; the gait card is the bespoke *renderer* that runs this across four
    /// metrics and composes one reassurance card.
    struct TrendResult: Sendable {
        let nMonths: Int
        let slopePerYear: Double
        let slopeStdErr: Double    // SE of the per-year slope, native units
        let intercept: Double
        let r: Double
        let pValue: Double
        let spanYears: Double
        let pctChange: Double
        let months: [GaitMonth]
    }

    /// Clip → monthly medians (≥`minPerMonth`) → OLS slope with a two-sided t-test p,
    /// over years. nil if fewer than `minMonths` months survive (need a real span to
    /// trust a slope). The math is exactly what `metricTrend` did inline before.
    static func longTermTrend(
        samples: [(date: Date, value: Double)], clip: (lo: Double, hi: Double),
        minMonths: Int = 6, minPerMonth: Int = 20
    ) -> TrendResult? {
        let months = monthlyMedians(samples, clip: clip, minPerMonth: minPerMonth)
        guard months.count >= minMonths else { return nil }
        let t0 = months[0].month
        let t = months.map { $0.month.timeIntervalSince(t0) / (365.25 * 86_400) }   // years
        let y = months.map(\.median)
        guard let fit = linregress(x: t, y: y) else { return nil }
        let span = (t.last ?? 0) - (t.first ?? 0)
        let total = fit.slope * span
        let pct = fit.intercept != 0 ? 100 * total / fit.intercept : .nan
        return TrendResult(
            nMonths: months.count, slopePerYear: fit.slope, slopeStdErr: fit.slopeStdErr,
            intercept: fit.intercept, r: fit.r, pValue: fit.pValue,
            spanYears: span, pctChange: pct, months: months)
    }

    /// Gait's per-metric wrapper around the generic `longTermTrend` primitive.
    static func metricTrend(_ metric: GaitMetric, samples: [GaitSample]) -> MetricTrend? {
        let dated = samples.map { (date: $0.date, value: $0.value) }
        guard let t = longTermTrend(samples: dated, clip: metric.clip) else { return nil }
        return MetricTrend(
            metric: metric, nMonths: t.nMonths, slopePerYear: t.slopePerYear,
            slopeStdErr: t.slopeStdErr, intercept: t.intercept, r: t.r, pValue: t.pValue,
            spanYears: t.spanYears, pctChange: t.pctChange, months: t.months)
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
    static func monthlyMedians(_ samples: [(date: Date, value: Double)],
                               clip: (lo: Double, hi: Double), minPerMonth: Int = 20) -> [GaitMonth] {
        var buckets: [Date: [Double]] = [:]
        for s in samples where s.value >= clip.lo && s.value <= clip.hi {
            let comps = calendar.dateComponents([.year, .month], from: s.date)
            guard let m = utcMonthCal.date(from: comps) else { continue }
            buckets[m, default: []].append(s.value)
        }
        return buckets.compactMap { month, vals in
            vals.count >= minPerMonth ? GaitMonth(month: month, median: median(vals), n: vals.count) : nil
        }
        .sorted { $0.month < $1.month }
    }

    // MARK: Linear regression + significance (plain Swift; trivial at ~70 points)

    /// Ordinary least squares plus the two-sided p-value SciPy's `linregress` reports:
    /// the slope's t-statistic against df = n−2, evaluated via the regularized
    /// incomplete beta (the t-distribution tail).
    static func linregress(x: [Double], y: [Double]) -> (slope: Double, intercept: Double, r: Double, pValue: Double, slopeStdErr: Double)? {
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
        // SE of the slope: √(SSE/df / Sxx), with SSE = Syy(1−r²). Needed by absence
        // claims, which are scored on the slope's PRECISION rather than its
        // significance (see `nonInferiorityP`).
        let slopeStdErr = (syy * (1 - r * r) / df / sxx).squareRoot()
        return (slope, intercept, r, p, slopeStdErr)
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

// MARK: - Day-ahead forecast (Tier-1: run the wearing-off model forward)
//
// The retrospective wearing-off card describes what HAPPENED; this projects the SAME
// validated per-user curve FORWARD from today's logged doses to show the rest of the
// day's expected ON/OFF cycle. Pure + Sendable like the rest of the engine; rendered
// by DayAheadPanel on the Day-in-Review screen (today only). No new statistics — it
// reuses the parity-pinned survival + onset primitives; the only new work is arithmetic.
//
// SAFETY: forecast/observation only. It never proposes a dose. The OFF window is framed
// as "what to expect", and the panel carries the same .clinicalReferral posture as the
// wearing-off card (bring the pattern to your neurologist).
//
// EXTENSIBILITY: `WindowAdjustment` is the typed seam for a future gate-2-promoted lever
// (e.g. a validated workout→window effect). v1 passes none — doses only. See
// docs/intelligence-architecture.md (two-gate promotion; a lever feeds the forecast only
// once its validated effect is shaped as an ON/OFF-window adjustment).

nonisolated extension CorrelationEngine {

    struct DayForecast: Sendable {
        enum Phase: Sendable { case on, off, unknown }
        struct Segment: Sendable {
            let start: Date
            let end: Date
            let phase: Phase
            let observed: Bool   // true = reconstructed from measured tremor; false = projected
            // Mean measured tremor over the segment (observed only; nil for projected or a
            // not-worn gap). Lets the view shade an OFF band by how severe it actually was —
            // a Mild wearing-off ≠ a Strong one — instead of one flat alarm-red. `var` with a
            // default so the many nil call sites stay untouched.
            var meanTremor: Double? = nil
        }
        let segments: [Segment]              // chronological, covers [dayStart, dayEnd]
        let now: Date
        let nextOffStart: Date?              // first projected OFF onset after `now`, if any
        let nextOffRange: ClosedRange<Date>? // uncertainty band around nextOffStart
        let confidence: Insight.Confidence
        // Responsive "right now" ON/OFF from the last few minutes of raw tremor — bypasses the
        // 30-min bin + 60-min despeckle that make `segments` lag ~30min at the live edge. Drives the
        // headline's current-state call ONLY; the band stays smoothed (honest after the fact). nil
        // when too little recent data to override the reconstructed segment. See design note Symptom 2.
        var nowState: Phase? = nil
    }

    /// A signed adjustment a future validated lever applies to the projection (shifts
    /// onset and/or ON-duration, with its own confidence) — the shape a gate-2-promoted
    /// wearing-off-family primitive must emit. v1 wires none.
    struct WindowAdjustment: Sendable {
        let onsetDelta: TimeInterval
        let durationDelta: TimeInterval
        let confidence: Insight.Confidence
    }

    // MARK: - Per-formulation modeling (the estimability gate is the classifier)

    /// Normalize a raw medication name into a stable stratification key. Lowercase, drop
    /// pure dosage/strength tokens (numbers, `mg`/`ml`/`mcg`, `25-100`) so "Sinemet 25-100"
    /// and "sinemet" collapse to one stratum. NOT a drug dictionary — it only canonicalizes
    /// the name the user logged; WHICH formulations are pulsatile levodopa is decided
    /// downstream by the estimability gate (`estimableFormulations`), never by name here.
    static func formulationKey(_ name: String) -> String {
        let tokens = name.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "/" })
            .map(String.init)
            .filter { tok in
                if tok == "mg" || tok == "ml" || tok == "mcg" { return false }
                return !tok.allSatisfy { $0.isNumber || $0 == "-" || $0 == "." }
            }
        let key = tokens.joined(separator: " ")
        return key.isEmpty ? "unspecified" : key
    }

    /// A fitted wearing-off / onset model for one formulation (or the combined estimable
    /// set) — everything `dayForecast` needs to project a single dose forward. Reuses the
    /// `survivalDuration` + `doseResponseByTimeOfDay` primitives UNCHANGED; a formulation is
    /// just their inputs filtered to one name, so the pinned parity primitives are untouched.
    struct PulseModel: Sendable {
        let key: String
        let surv: SurvivalDuration
        let onDuration: Double              // clamped ON-window minutes (forecast duration)
        let iqr: Double                     // spread of observed ON-durations (uncertainty band)
        let onsetByBucket: [Bucket: Double]
        let pooledOnset: Double             // fallback onset when a bucket has no clean estimate

        /// Onset latency (min) for a dose in `bucket`, pooled-fallback for a thin bucket.
        func onset(_ bucket: Bucket) -> Double { onsetByBucket[bucket] ?? pooledOnset }
        var durationsCount: Int { surv.durations.count }
        /// Estimable = enough doses + a real KM median + a real onset. Exactly the floor the
        /// forecast has always used, now applied per formulation: an inert / non-pulsatile
        /// substance can't clear it and self-excludes.
        var isEstimable: Bool {
            surv.durations.count >= 20 && surv.kmMedian.isFinite && pooledOnset.isFinite
        }
    }

    /// Fit a `PulseModel` over one dose set. Onset uses per-time-of-day buckets with a
    /// pooled fallback; ON-duration is the clamped KM median (same [90,360] sanity rails +
    /// fallback as `doseOnWindowMinutes`).
    static func fitPulseModel(
        key: String, signal: [(time: Date, value: Double)], events: [Date],
        sleep: [SleepInterval] = []
    ) -> PulseModel {
        let surv = survivalDuration(signal: signal, events: events,
                                    onThreshold: offThreshold, sleep: sleep)
        let dr = doseResponseByTimeOfDay(signal: signal, events: events, preMin: preMin, postMin: postMin)
        var onsetByBucket: [Bucket: Double] = [:]
        for b in Bucket.allCases {
            let o = dr.onset(b)
            if o.n > 0, o.mean.isFinite { onsetByBucket[b] = o.mean }
        }
        let pooledOnset = nanmean(dr.traces.filter { !$0.tHalf.isNaN }.map(\.tHalf))
        let km = surv.kmMedian
        let onDuration = (km.isFinite && km >= 90 && km <= 360) ? km : doseOnWindowFallback
        let band = iqr(surv.durations.filter { $0.observed && !$0.durationMin.isNaN }.map(\.durationMin))
        return PulseModel(key: key, surv: surv, onDuration: onDuration, iqr: band,
                          onsetByBucket: onsetByBucket, pooledOnset: pooledOnset)
    }

    /// Group doses by formulation, fit a model per group, and keep ONLY the strata that
    /// clear the wearing-off floor. This set — data-derived, per user — replaces the old
    /// hard-coded `sinemet/mucuna` name filter everywhere: the gate IS the classifier.
    static func estimableFormulations(
        signal: [(time: Date, value: Double)], doses: [Dose], sleep: [SleepInterval] = []
    ) -> [String: PulseModel] {
        var out: [String: PulseModel] = [:]
        for (key, ds) in Dictionary(grouping: doses, by: { formulationKey($0.name) }) {
            let m = fitPulseModel(key: key, signal: signal, events: ds.map(\.timestamp), sleep: sleep)
            if m.isEstimable, gate(wearingOffGate, n: m.durationsCount) != nil { out[key] = m }
        }
        return out
    }

    private static let forecastObservedBinMin = 30.0
    // A measured ON/OFF flip must persist ≥ this many bins to count as a distinct episode.
    // Binary-thresholding a continuous tremor that hovers near the OFF line produces
    // spurious single-bin flips; a real wearing-off episode isn't sub-hour. 2 × 30-min = a
    // 60-min floor — the de-noise, not a tuning knob.
    private static let forecastMinRunBins = 2

    /// Project the validated wearing-off / dose-response curve forward from today's logged
    /// doses. Returns nil (panel hidden) when the model isn't estimable — the correct
    /// cold-start behavior. The elapsed part of the day is reconstructed from measured
    /// tremor (`observed`), the rest is projected.
    static func dayForecast(
        history: [TremorPoint],
        allDoses: [Dose],
        todaysDoses: [Dose],
        todaysReadings: [TremorPoint],
        dayStart: Date,
        dayEnd: Date,
        now: Date,
        adjustments: [WindowAdjustment] = [],
        sleep: [SleepInterval] = []
    ) -> DayForecast? {
        let doses = todaysDoses.sorted { $0.timestamp < $1.timestamp }
        guard !doses.isEmpty else { return nil }

        // Fit a wearing-off/onset model PER FORMULATION from full history. Each dose is then
        // projected with its OWN formulation's timing (IR vs plant-source levodopa have
        // different onset + ON-duration; pooling them describes neither). A formulation
        // appears only if its own data clears the estimability floor — the gate is the
        // classifier, so inert/non-pulsatile substances self-exclude with no drug list.
        let sig = history.map { (time: $0.timestamp, value: $0.tremorScore) }
        let models = estimableFormulations(signal: sig, doses: allDoses, sleep: sleep)
        guard !models.isEmpty else { return nil }

        // Combined model over the union of estimable-formulation doses: the confidence + IQR
        // source, AND the fallback timing for a dose whose formulation is present but too thin
        // to time on its own (both are real levodopa → a pulse genuinely exists, so keep the
        // band using combined timing rather than under-painting it).
        let estimableDoses = allDoses.filter { models[formulationKey($0.name)] != nil }
        let combined = fitPulseModel(key: "__combined__", signal: sig, events: estimableDoses.map(\.timestamp))
        guard let confidence = gate(wearingOffGate, n: combined.durationsCount) else { return nil }

        // Which model times a given dose? Group sizes tell a data-THIN formulation (too few
        // doses to time on its own → benefit of the doubt, fall back to combined levodopa
        // timing so a real dose still paints its band) from a CONFIRMED non-pulsatile one
        // (enough doses but no estimable pulse → nil: never invent an ON band for a vitamin).
        let groupSizes = Dictionary(grouping: allDoses, by: { formulationKey($0.name) }).mapValues(\.count)
        func model(for dose: Dose) -> PulseModel? {
            let key = formulationKey(dose.name)
            if let m = models[key] { return m }                 // own estimable model
            if (groupSizes[key] ?? 0) >= 20 { return nil }      // judged, no pulse → omit
            return combined                                     // data-thin → combined fallback
        }

        let onsetAdj = adjustments.reduce(0) { $0 + $1.onsetDelta }
        let durAdj = adjustments.reduce(0) { $0 + $1.durationDelta }

        // Projected ON intervals, one per dose, merged where they overlap (closely spaced
        // doses → one continuous ON). ON spans [dose+onset, dose+duration], both measured
        // from the dose using THAT dose's formulation model. OFF is the complement. A dose
        // with no projectable model (confirmed non-pulsatile) contributes no ON band.
        var onIntervals: [(start: Date, end: Date)] = []
        var doseEnds: [(end: Date, iqr: Double)] = []   // for the per-formulation OFF-onset band
        for d in doses {
            guard let m = model(for: d) else { continue }
            let onsetSec = m.onset(bucketOf(hourOfDay(d.timestamp))) * 60 + onsetAdj
            let durSec = m.onDuration * 60 + durAdj
            let start = d.timestamp.addingTimeInterval(onsetSec)
            let end = d.timestamp.addingTimeInterval(max(onsetSec + 60, durSec)) // ON stays positive
            if end > start { onIntervals.append((start, end)); doseEnds.append((end, m.iqr)) }
        }
        // Bridge ON windows separated by a gap shorter than one observed bin so a few-minute
        // wearing-off dip between two close doses isn't painted as a real OFF sliver — the same
        // de-jitter floor the observed side gets. Reused for `nextOffStart` so the bar and the
        // headline's next-OFF time agree.
        let mergedOn = mergeIntervals(onIntervals, gapTolSec: forecastObservedBinMin * 60)
        let projected = phaseTimeline(on: mergedOn,
                                      dayStart: dayStart, dayEnd: dayEnd)

        // Observed phase for the elapsed day from measured tremor (honest reconstruction).
        let observed = observedTimeline(readings: todaysReadings, dayStart: dayStart,
                                        end: min(now, dayEnd))

        // Compose: observed up to `now`, projected after; split the straddling segment.
        let segments = spliceAtNow(observed: observed, projected: projected,
                                   now: now, dayStart: dayStart, dayEnd: dayEnd)

        // Next OFF onset = end of the merged ON interval still open after `now`. The merged
        // end equals some dose's projected end, so its formulation's IQR sets the band width
        // (fallback: combined) — a data-derived ±, not an arbitrary one.
        let nextOffStart = mergedOn.first { $0.end > now }?.end
        var nextOffRange: ClosedRange<Date>? = nil
        if let off = nextOffStart {
            let bandIqr = doseEnds.first { abs($0.end.timeIntervalSince(off)) < 1 }?.iqr ?? combined.iqr
            let half = bandIqr / 2 * 60
            if half > 0 { nextOffRange = off.addingTimeInterval(-half)...off.addingTimeInterval(half) }
        }

        // Responsive current-state read from raw tremor near `now` (the historical part of the
        // band stays smoothed). It drives both the headline (nowState) AND the band's trailing
        // sliver (applyLiveEdge), so the two agree at the live edge instead of the bar lagging.
        let live = liveEdgeState(readings: todaysReadings, now: now)
        let segmentsWithEdge = applyLiveEdge(segments, live: live, now: now)

        return DayForecast(segments: segmentsWithEdge, now: now,
                           nextOffStart: nextOffStart, nextOffRange: nextOffRange,
                           confidence: confidence, nowState: live?.phase)
    }

    // MARK: forecast helpers

    /// Union of overlapping/touching intervals, sorted by start. `gapTolSec` also bridges
    /// intervals separated by a gap no longer than the tolerance — used by the forecast to
    /// absorb a sub-bin OFF sliver between two closely-spaced doses' projected ON windows, the
    /// SAME de-jitter floor `observedTimeline`/`despeckle` already apply to the measured side.
    /// Without it a few-minute wearing-off dip between consecutive doses paints a hairline OFF.
    static func mergeIntervals(_ intervals: [(start: Date, end: Date)],
                               gapTolSec: TimeInterval = 0) -> [(start: Date, end: Date)] {
        var out: [(start: Date, end: Date)] = []
        for iv in intervals.sorted(by: { $0.start < $1.start }) {
            if var last = out.last, iv.start.timeIntervalSince(last.end) <= gapTolSec {
                last.end = max(last.end, iv.end)
                out[out.count - 1] = last
            } else {
                out.append(iv)
            }
        }
        return out
    }

    /// ON/OFF timeline over [dayStart, dayEnd] from merged ON intervals (everything
    /// outside an ON interval is OFF). Every segment here is a projection.
    static func phaseTimeline(on: [(start: Date, end: Date)],
                              dayStart: Date, dayEnd: Date) -> [DayForecast.Segment] {
        var segs: [DayForecast.Segment] = []
        var cursor = dayStart
        for iv in on {
            let s = max(iv.start, dayStart), e = min(iv.end, dayEnd)
            guard e > cursor else { continue }
            if s > cursor {
                segs.append(.init(start: cursor, end: s, phase: .off, observed: false))
                cursor = s
            }
            segs.append(.init(start: cursor, end: e, phase: .on, observed: false))
            cursor = e
            if cursor >= dayEnd { break }
        }
        if cursor < dayEnd {
            segs.append(.init(start: cursor, end: dayEnd, phase: .off, observed: false))
        }
        return segs
    }

    /// Observed ON/OFF over [dayStart, end] from measured tremor: 30-min bins, OFF when
    /// the bin mean ≥ offThreshold, ON below, unknown when the bin has no readings
    /// (not-worn). De-noised (sub-hour flips absorbed) then coalesced. Marked observed=true.
    static func observedTimeline(readings: [TremorPoint], dayStart: Date, end: Date)
        -> [DayForecast.Segment] {
        guard end > dayStart else { return [] }
        let binSec = forecastObservedBinMin * 60
        var bounds: [(start: Date, end: Date)] = []
        var raw: [DayForecast.Phase] = []
        var binMean: [Double?] = []   // nil = not-worn bin (no reading)
        var binStart = dayStart
        while binStart < end {
            let binEnd = min(binStart.addingTimeInterval(binSec), end)
            let inBin = readings.filter { $0.timestamp >= binStart && $0.timestamp < binEnd }
            if inBin.isEmpty {
                raw.append(.unknown); binMean.append(nil)
            } else {
                let mean = inBin.map(\.tremorScore).reduce(0, +) / Double(inBin.count)
                raw.append(mean >= offThreshold ? .off : .on); binMean.append(mean)
            }
            bounds.append((binStart, binEnd))
            binStart = binEnd
        }
        guard !bounds.isEmpty else { return [] }
        let phases = despeckle(raw, means: binMean, minRun: forecastMinRunBins)
        // Coalesce equal-phase runs, averaging the measured tremor across each run so the
        // segment carries how severe it actually was (drives OFF shading in the view).
        var segs: [DayForecast.Segment] = []
        var runLo = 0
        for i in 1...bounds.count where i == bounds.count || phases[i] != phases[runLo] {
            let means = (runLo..<i).compactMap { binMean[$0] }
            let avg = means.isEmpty ? nil : means.reduce(0, +) / Double(means.count)
            segs.append(.init(start: bounds[runLo].start, end: bounds[i - 1].end,
                              phase: phases[runLo], observed: true, meanTremor: avg))
            runLo = i
        }
        return segs
    }

    /// Absorb ON/OFF runs shorter than `minRun` bins into their stronger (longer)
    /// non-unknown neighbor, repeatedly, until none remain — the eye's "ignore a lone
    /// flip near the threshold." Unknown (not-worn) runs are LEFT intact: a real data gap
    /// is honest signal, not noise. A short run flanked only by unknowns is also left (no
    /// evidence to absorb it into).
    ///
    /// Confidence gate: pass per-bin `means` (aligned to `phases`) to SPARE a short run whose
    /// severity sits a clear margin past the OFF line — a lone 30-min bin at, say, 1.6 is a real
    /// wearing-off episode, not threshold jitter, so deleting it hides an OFF the user actually had.
    /// `confidentMargin` is half a severity band on the 0–4 scale (bands are 1.0 wide): a bin this
    /// far from the line has decisively left the ambiguous zone the de-noise was meant to clean up.
    /// Empty `means` = gate off (legacy behavior: absorb every short run).
    static func despeckle(_ phases: [DayForecast.Phase], means: [Double?] = [], minRun: Int,
                          confidentMargin: Double = 0.5) -> [DayForecast.Phase] {
        guard phases.count > 1, minRun > 1 else { return phases }
        var out = phases
        while true {
            var runs: [(phase: DayForecast.Phase, lo: Int, hi: Int)] = []
            for (i, p) in out.enumerated() {
                if var last = runs.last, last.phase == p { last.hi = i; runs[runs.count - 1] = last }
                else { runs.append((p, i, i)) }
            }
            func length(_ idx: Int) -> Int { idx < 0 || idx >= runs.count ? -1 : runs[idx].hi - runs[idx].lo + 1 }
            // True when a run's measured severity is a clear margin past the threshold (either side)
            // — a decisive episode the de-noise must not erase. Measurement-based, so it doesn't
            // change as we relabel phases. Gate off when means weren't supplied.
            func confident(_ idx: Int) -> Bool {
                guard means.count == phases.count else { return false }
                let ms = (runs[idx].lo...runs[idx].hi).compactMap { means[$0] }
                guard !ms.isEmpty else { return false }
                return abs(ms.reduce(0, +) / Double(ms.count) - offThreshold) >= confidentMargin
            }
            // Shortest sub-minRun ON/OFF run that has a non-unknown neighbor to absorb into AND
            // isn't a confident (decisively-past-threshold) episode.
            var target = -1, targetLen = Int.max
            for (idx, r) in runs.enumerated() where r.phase != .unknown {
                let len = r.hi - r.lo + 1
                let prevOK = idx > 0 && runs[idx - 1].phase != .unknown
                let nextOK = idx < runs.count - 1 && runs[idx + 1].phase != .unknown
                if len < minRun, prevOK || nextOK, !confident(idx), len < targetLen { target = idx; targetLen = len }
            }
            guard target >= 0 else { break }
            let prevOK = target > 0 && runs[target - 1].phase != .unknown
            let nextOK = target < runs.count - 1 && runs[target + 1].phase != .unknown
            let usePrev = prevOK && (!nextOK || length(target - 1) >= length(target + 1))
            let newPhase = usePrev ? runs[target - 1].phase : runs[target + 1].phase
            for i in runs[target].lo...runs[target].hi { out[i] = newPhase }
        }
        return out
    }

    /// Linear-interpolated percentile (type-7). Shared robust-peak helper (chart buckets +
    /// live-edge state): P90 over a ~30-sample window lands near the top few readings, so a real
    /// spike lifts it but one lone jitter sample can't set it (unlike a raw max).
    static func percentile(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        guard s.count > 1 else { return s[0] }
        let rank = p * Double(s.count - 1)
        let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (rank - Double(lo))
    }

    /// Responsive current-state read: MEDIAN of the last `windowMin` of raw tremor, OFF when that
    /// level clears the threshold and tremor isn't clearly falling (a dose kicking in). Median (not
    /// a peak) so a single motion-artifact minute — e.g. a walk or eating — can't flip the headline
    /// to OFF; it still beats the reconstructed band's ~30min lag (30-min bin + despeckle floor).
    /// Returns nil when there aren't enough recent samples to responsibly override the band.
    static func liveEdgeState(readings: [TremorPoint], now: Date,
                              windowMin: Double = 15) -> (phase: DayForecast.Phase, level: Double)? {
        let lo = now.addingTimeInterval(-windowMin * 60)
        let window = readings.filter { $0.timestamp >= lo && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }
        guard window.count >= 3 else { return nil }
        let level = percentile(window.map(\.tremorScore), 0.5)
        // Trend: later-half mean vs earlier-half mean. "Clearly falling" means improving enough that
        // a brief lingering peak shouldn't flip us to OFF — avoids live-edge flicker as a dose lands.
        let mid = window.count / 2
        let earlyMean = window[..<mid].map(\.tremorScore).reduce(0, +) / Double(mid)
        let lateMean = window[mid...].map(\.tremorScore).reduce(0, +) / Double(window.count - mid)
        let falling = lateMean < earlyMean - 0.15
        return (level >= offThreshold && !falling) ? (.off, level) : (.on, level)
    }

    /// Overlay the responsive live-edge read onto the tail of the band so the bar's `now` end
    /// agrees with the headline (both use `liveEdgeState`). Only the trailing `windowMin` is
    /// touched — the rest of the reconstruction stays smoothed. No-op when `live` is nil. An OFF
    /// sliver carries the live median as its severity so it shades like the tremor line, matching
    /// how observed OFF segments shade. Observed segments end at `now` (spliced), so the window
    /// falls entirely within them.
    static func applyLiveEdge(_ segments: [DayForecast.Segment],
                              live: (phase: DayForecast.Phase, level: Double)?,
                              now: Date, windowMin: Double = 15) -> [DayForecast.Segment] {
        guard let live else { return segments }
        let edgeStart = now.addingTimeInterval(-windowMin * 60)
        var out: [DayForecast.Segment] = []
        for seg in segments {
            // Untouched: fully before the edge window, or at/after now (the projected future).
            if seg.end <= edgeStart || seg.start >= now { out.append(seg); continue }
            if seg.start < edgeStart {   // keep the pre-window part as-is
                out.append(.init(start: seg.start, end: edgeStart, phase: seg.phase,
                                 observed: seg.observed, meanTremor: seg.meanTremor))
            }
            let lo = max(seg.start, edgeStart), hi = min(seg.end, now)
            if hi > lo {                 // overwrite the edge window with the live read
                out.append(.init(start: lo, end: hi, phase: live.phase, observed: true,
                                 meanTremor: live.phase == .off ? live.level : nil))
            }
            if seg.end > now {           // preserve any future part (defensive; splice prevents it)
                out.append(.init(start: now, end: seg.end, phase: seg.phase,
                                 observed: seg.observed, meanTremor: seg.meanTremor))
            }
        }
        return out
    }

    /// Observed segments up to `now`, projected segments after — splitting whichever
    /// segment straddles `now` so the seam is exact.
    static func spliceAtNow(observed: [DayForecast.Segment], projected: [DayForecast.Segment],
                            now: Date, dayStart: Date, dayEnd: Date) -> [DayForecast.Segment] {
        let seam = min(max(now, dayStart), dayEnd)
        var out = observed.compactMap { seg -> DayForecast.Segment? in
            guard seg.start < seam else { return nil }
            return .init(start: seg.start, end: min(seg.end, seam), phase: seg.phase,
                         observed: true, meanTremor: seg.meanTremor)
        }
        for seg in projected where seg.end > seam {
            out.append(.init(start: max(seg.start, seam), end: seg.end,
                             phase: seg.phase, observed: false))
        }
        return out
    }

    /// Interquartile range (Q3 − Q1); 0 when the sample is too small to bracket. Linear
    /// interpolation on the sorted order — enough for a display uncertainty band.
    static func iqr(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        guard s.count >= 4 else { return 0 }
        func q(_ p: Double) -> Double {
            let idx = p * Double(s.count - 1)
            let lo = Int(idx.rounded(.down)), hi = Int(idx.rounded(.up))
            return lo == hi ? s[lo] : s[lo] + (idx - Double(lo)) * (s[hi] - s[lo])
        }
        return q(0.75) - q(0.25)
    }
}
