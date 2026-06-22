import Foundation
import HealthKit

// MARK: - Insight Registry
//
// The list of QUESTIONS the engine is allowed to ask. Pure configuration: each
// entry wires one `exposure` → one `outcome` through one `primitive`, plus the
// rationale that admitted it and the gate's sufficiency floor (`minN`).
//
// This is the substrate the LLM proposes over and the human approves INTO.
// Adding a question is a one-line diff in `starter` below — not new statistical
// code. A NEW primitive or a NEW adapter is code (and a real build); a new
// question over an existing primitive + already-adapted variable is config.
// Full design: docs/intelligence-architecture.md.
//
// STATUS: this file is the SCHEMA + the starter "pre-wired 80%", and it now
// DRIVES execution — `CorrelationEngine.generateInsights` iterates these entries
// and dispatches each on its `renderer`. Entries whose primitive/renderer aren't
// built yet stay dormant (return nil) until their adapter + renderer land.
//
// ⚠ Add to the iOS app target ONLY.

// MARK: Variables — everything reduces to two canonical shapes

/// A variable in the catalog, in one of the two shapes a primitive understands.
enum Variable: Hashable {
    // — Continuous signals (a value over time) —
    case tremor
    case dyskinesia
    case hrv                       // SDNN, timestamped
    case restingHeartRate
    case gaitSpeed
    case gaitStepLength
    case gaitAsymmetry
    case gaitDoubleSupport

    // — Discrete events (a thing at a timestamp) —
    case levodopaDose
    case workout(HKWorkoutActivityType)
    case mindfulSession
    case meal(MealFilter)
    case foodAttribute(FoodAttribute)   // caffeine, sugar, … — the food cluster; mirrors .workout(type)
    case sleep(SleepFacet)

    // — Implicit predictors (for trend / circadian questions) —
    case timeOfDay                 // hour-of-day axis (circadian)
    case calendarTime              // long-term progression axis
}

/// Narrows a meal event to a PD-relevant subset (we never need exact grams).
enum MealFilter: Hashable { case any, proteinRich, large }

/// A facet of a night's sleep, used as an overnight predictor.
enum SleepFacet: Hashable { case duration, deep, rem, interruptions }

// Bridges that let the (HealthKit-free) engine match a registry entry's variables
// without importing HealthKit — the HealthKit knowledge stays here, in the config
// layer, and the engine only ever sees plain values (UInt, String, Bool).
extension Variable {
    /// HealthKit raw value if this is a workout exposure, else nil.
    var workoutRawValue: UInt? {
        if case .workout(let t) = self { return t.rawValue }
        return nil
    }
    /// Human label for a workout exposure ("Boxing", "Tai Chi", "Social Dance").
    var workoutDisplayName: String? {
        if case .workout(let t) = self { return t.displayName }
        return nil
    }
    /// The food attribute if this is a food-cluster exposure, else nil. Mirrors
    /// `workoutRawValue` — the bridge the windowed-effect renderer uses to resolve
    /// which event stream (food vs workout) an entry draws from.
    var foodAttribute: FoodAttribute? {
        if case .foodAttribute(let a) = self { return a }
        return nil
    }
    /// True when this is the tremor signal — the only outcome wired into the
    /// windowed-effect path today.
    var isTremor: Bool {
        if case .tremor = self { return true }
        return false
    }
}

// MARK: Primitives — reusable methods over the two shapes (built once)

/// A statistical method that operates on *shapes*, not specific variables.
/// One primitive serves many registry entries — that is the whole point.
enum Primitive: Hashable {
    /// Effect of an event on a signal in the window after it (baseline-corrected).
    case windowedEffect(preMin: Double, postMin: Double)
    /// Onset latency + completeness of a dose, split by time-of-day bucket.
    case doseResponseByTimeOfDay(preMin: Double, postMin: Double)
    /// Kaplan–Meier ON-duration / wearing-off with right-censoring.
    case survivalDuration(onThreshold: Double)
    /// Periodic within-day baseline of a signal across hour-of-day.
    case circadianBaseline
    /// Regression of a signal over monthly medians (long-term direction).
    case longTermTrend
    /// Prior-night facet → next-day signal.
    case overnightLag
    /// Within-day association between two co-occurring signals.
    case withinDayAssociation
    /// How an event's timing relative to a dose modulates that dose's onset.
    case mealTimingCompetition(windowMin: Double)
}

// MARK: Renderers — how a validated finding is presented (generic OR bespoke)

/// Which card view + copy a finding renders into. This is a SEPARATE axis from the
/// primitive (the math): a primitive is always generic, but a renderer may be
/// bespoke when the card genuinely is. Dispatch keys on this, not the primitive —
/// because `.longTermTrend` alone can't distinguish the gait *composite* renderer
/// (which fuses four mobility markers into one reassurance card) from a future
/// single-metric trend card that would share the same primitive. A nil renderer =
/// the question is registered but its card path isn't built yet (it stays dormant,
/// like its primitive). See docs/intelligence-architecture.md → "renderer dimension".
enum Renderer: Hashable {
    case doseResponse      // per-time-of-day onset overlay (afternoon-dose card)
    case wearingOff        // pooled survival curve (the "discuss with neurologist" card)
    case gaitComposite     // bespoke: 4 mobility markers → 1 reassurance card
    case windowedEffect    // generic event→signal change card (exercise/diet cluster)
}

// MARK: Provenance + safety + lifecycle

/// Where a hypothesis came from — the provenance trail a health app must keep.
enum HypothesisSource: Hashable {
    case curated                       // human-authored, literature/mechanism-motivated
    case llmProposed(model: String)    // proposed by the hypothesis layer, human-approved
}

/// Governs how a validated finding may be PRESENTED. The medication line is
/// non-negotiable — Kampa never issues a dosing instruction.
enum SafetyClass: Hashable {
    /// Patient-controllable behavior — a finding may propose an experiment.
    case lifestyleExperiment
    /// Touches the medication regimen or disease progression — surface the
    /// observation and refer to the neurologist. Never prescribe or instruct.
    case clinicalReferral
}

enum RegistryStatus: Hashable {
    case active        // shipped; the engine runs it (may still be gated-hidden per user)
    case candidate     // proposed; awaiting human approval into the engine
    case disabled
}

/// The domain a question belongs to — the SEMANTIC home of the variable, set once
/// per entry. This is the grouping axis the Insights screen clusters on, and it is
/// INDEPENDENT of `primitive`/`renderer` (the math + card) and of `safety` (clinical
/// vs lifestyle): mindfulness and walking share a primitive but sit in different
/// categories; gait and dose are both clinical but different categories. A new case
/// is added only when a real entry needs it (no speculative empty categories) —
/// glucose/CGM, environment, GI, etc. each get a case when their first entry lands.
/// Cheap to reassign or split later: it's static config, never persisted — no
/// CloudKit migration. The UI applies a separate display policy on top (e.g. fold
/// single-card categories into a shared section), so an entry's category can be
/// honest without forcing an ugly one-item header.
enum InsightCategory: Hashable {
    case medication    // dose response, wearing-off, dyskinesia, circadian control
    case exercise      // the workout cluster (any activity type)
    case food          // caffeine, sugar, protein / meal-timing
    case sleep         // overnight → next-day
    case stress        // autonomic + mental state: HRV, mindfulness / meditation
    case mobility      // long-term gait / progression
}

/// One question. Configuration, not code.
struct RegistryEntry: Identifiable, Hashable {
    let id: String
    let category: InsightCategory   // semantic home — the Insights screen's grouping axis
    let exposure: Variable
    let outcome: Variable
    let primitive: Primitive
    /// Which card this finding renders into — the dispatch key. nil = no card path
    /// built yet (registered but dormant, like an unimplemented primitive).
    var renderer: Renderer? = nil
    let rationale: String          // why this hypothesis exists — preserved as provenance
    let source: HypothesisSource
    let safety: SafetyClass
    let minN: Int                  // sufficiency floor the gate enforces before showing anything
    var status: RegistryStatus = .active
}

// MARK: - The pre-wired 80%

enum InsightRegistry {

    /// The shipped, curated question set. Every entry is mechanism- or
    /// literature-motivated (NOT every possible pair — that would be a
    /// false-discovery machine). Entries the user hasn't "earned" yet (e.g. an
    /// activity they don't do) simply never clear the gate until their own data
    /// supports them — Tai Chi can light up for one user and stay dark for another.
    static let starter: [RegistryEntry] = [

        // ───────────── Medication (strongest, already-validated methods) ─────────────
        RegistryEntry(
            id: "dose-tremor-by-tod", category: .medication,
            exposure: .levodopaDose, outcome: .tremor,
            primitive: .doseResponseByTimeOfDay(preMin: 30, postMin: 180),
            renderer: .doseResponse,
            rationale: "Levodopa onset latency and completeness vary by time of day; afternoon doses observed slower and less complete.",
            source: .curated, safety: .clinicalReferral, minN: 5),

        RegistryEntry(
            id: "dose-tremor-wearing-off", category: .medication,
            exposure: .levodopaDose, outcome: .tremor,
            // onThreshold matches the engine's offThreshold (tremor ≥ this = OFF).
            primitive: .survivalDuration(onThreshold: 1.0),
            renderer: .wearingOff,
            rationale: "ON-duration per dose (Kaplan–Meier) reveals wearing-off; daytime dose gaps can exceed the effect window.",
            source: .curated, safety: .clinicalReferral, minN: 5),

        RegistryEntry(
            id: "dose-dyskinesia-peak", category: .medication,
            exposure: .levodopaDose, outcome: .dyskinesia,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Peak-dose dyskinesia: involuntary movement can RISE 30–120 min post-dose (inverse of the tremor benefit).",
            source: .curated, safety: .clinicalReferral, minN: 5),

        // ───────────── Diet ↔ medication (your 3 PM question) ─────────────
        RegistryEntry(
            id: "protein-meal-dose-onset", category: .food,
            exposure: .meal(.proteinRich), outcome: .tremor,
            primitive: .mealTimingCompetition(windowMin: 90),
            rationale: "Dietary protein competes with levodopa absorption; a protein meal near a dose may slow or blunt its onset.",
            source: .curated, safety: .lifestyleExperiment, minN: 8),

        RegistryEntry(
            id: "meal-fullness-dose-onset", category: .food,
            exposure: .meal(.large), outcome: .tremor,
            primitive: .mealTimingCompetition(windowMin: 90),
            rationale: "A full stomach slows gastric emptying; a large meal near a dose may delay onset versus an empty-stomach dose.",
            source: .curated, safety: .lifestyleExperiment, minN: 8),

        // Food cluster. Both .active, but PROTECTED by the dose-confound guard
        // (CorrelationEngine.doseCleanEvents): caffeine/sugar are habitually consumed
        // near doses, so the naive windowed-effect would credit the levodopa ON-effect
        // to the food (the observed false "Caffeine eases tremor / Strong / −32%" card).
        // The guard drops dose-shadowed servings, so a card surfaces ONLY if a
        // de-confounded signal still clears the gate — otherwise the honest result is
        // silence ("can't separate from your medication"). The gate, not the status
        // flag, decides visibility from here. PD caffeine evidence is itself mixed /
        // possibly-beneficial (A2A-antagonist; istradefylline) — a plausible mechanism
        // makes a confounded result more seductive, not more proven, hence the guard.
        RegistryEntry(
            id: "caffeine-tremor", category: .food,
            exposure: .foodAttribute(.caffeine), outcome: .tremor,
            primitive: .windowedEffect(preMin: 15, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Caffeine has mixed/possibly-beneficial PD effects (A2A-antagonist mechanism; istradefylline precedent); test its short-window association with tremor — dose-confound guarded, since intake co-times with doses.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        RegistryEntry(
            id: "sugar-tremor", category: .food,
            exposure: .foodAttribute(.sugar), outcome: .tremor,
            primitive: .windowedEffect(preMin: 15, postMin: 120),
            renderer: .windowedEffect,
            rationale: "A sugar load drives a glucose spike-and-crash; glucose swings may track with symptom steadiness. Second food-cluster entry — same primitive + renderer as caffeine, one registry line. Same dose-confound guard applies.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        // ───────────── Exercise cluster (ONE primitive, many activity types) ─────────────
        RegistryEntry(
            id: "taichi-tremor", category: .exercise,
            exposure: .workout(.taiChi), outcome: .tremor,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Tai Chi is well-supported in the PD literature for reducing tremor and improving balance.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        RegistryEntry(
            id: "boxing-tremor", category: .exercise,
            exposure: .workout(.boxing), outcome: .tremor,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Non-contact boxing (Rock Steady–style) is a common PD exercise program; test its post-session tremor effect.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        RegistryEntry(
            id: "yoga-tremor", category: .exercise,
            exposure: .workout(.yoga), outcome: .tremor,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Yoga is associated with reduced rigidity and stress in PD; test its post-session tremor effect.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        RegistryEntry(
            id: "cycling-tremor", category: .exercise,
            exposure: .workout(.cycling), outcome: .tremor,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Forced-rate aerobic cycling has notable PD motor evidence; test its post-session tremor effect.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        RegistryEntry(
            id: "walking-tremor", category: .exercise,
            exposure: .workout(.walking), outcome: .tremor,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Aerobic walking is the most accessible PD exercise; test its post-session tremor effect.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        RegistryEntry(
            id: "strength-tremor", category: .exercise,
            exposure: .workout(.functionalStrengthTraining), outcome: .tremor,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Resistance training improves PD motor scores; test its post-session tremor effect.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        RegistryEntry(
            id: "tabletennis-tremor", category: .exercise,
            exposure: .workout(.tableTennis), outcome: .tremor,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Table tennis demands rapid aiming, reaction, and footwork; anecdotal and emerging evidence suggests benefit for PD motor symptoms.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        RegistryEntry(
            id: "pickleball-tremor", category: .exercise,
            exposure: .workout(.pickleball), outcome: .tremor,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Pickleball combines aerobic movement, agility, and social engagement; anecdotally reported to help PD symptoms.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        RegistryEntry(
            id: "tango-tremor", category: .exercise,
            exposure: .workout(.socialDance), outcome: .tremor,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Argentine tango has documented PD benefits for balance and gait (partner dance maps to HealthKit social dance); test its post-session tremor effect.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        RegistryEntry(
            id: "rock-climbing-tremor", category: .exercise,
            exposure: .workout(.climbing), outcome: .tremor,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Climbing demands focus, grip, and full-body coordination; anecdotally reported to ease PD symptoms — test its post-session tremor effect.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        RegistryEntry(
            id: "mindfulness-tremor", category: .stress,
            exposure: .mindfulSession, outcome: .tremor,
            primitive: .windowedEffect(preMin: 30, postMin: 120),
            renderer: .windowedEffect,
            rationale: "Mental stillness lowers sympathetic arousal, which can amplify tremor; test the post-session effect.",
            source: .curated, safety: .lifestyleExperiment, minN: 5),

        // ───────────── Sleep (overnight → next day) ─────────────
        RegistryEntry(
            id: "sleep-duration-next-day-tremor", category: .sleep,
            exposure: .sleep(.duration), outcome: .tremor,
            primitive: .overnightLag,
            rationale: "Sleep deprivation worsens PD motor control; test prior-night duration against next-day tremor.",
            source: .curated, safety: .lifestyleExperiment, minN: 14),

        RegistryEntry(
            id: "sleep-deep-next-day-tremor", category: .sleep,
            exposure: .sleep(.deep), outcome: .tremor,
            primitive: .overnightLag,
            rationale: "Restorative deep sleep may matter more than raw duration; test prior-night deep sleep against next-day tremor.",
            source: .curated, safety: .lifestyleExperiment, minN: 14),

        // ───────────── Autonomic state ─────────────
        RegistryEntry(
            id: "hrv-tremor-within-day", category: .stress,
            exposure: .hrv, outcome: .tremor,
            primitive: .withinDayAssociation,
            rationale: "HRV indexes autonomic/stress state; low-HRV stretches may co-occur with higher tremor within a day.",
            source: .curated, safety: .lifestyleExperiment, minN: 8),

        // ───────────── Circadian baseline ─────────────
        RegistryEntry(
            id: "circadian-tremor-baseline", category: .medication,
            exposure: .timeOfDay, outcome: .tremor,
            primitive: .circadianBaseline,
            rationale: "Medication control drifts across the day; an hour-of-day tremor baseline shows when control is weakest.",
            source: .curated, safety: .clinicalReferral, minN: 10),

        // ───────────── Long-term progression ─────────────
        RegistryEntry(
            id: "gait-speed-trend", category: .mobility,
            exposure: .calendarTime, outcome: .gaitSpeed,
            primitive: .longTermTrend,
            renderer: .gaitComposite,
            rationale: "Walking speed is a sensitive PD progression marker; a multi-month trend tracks mobility over time.",
            source: .curated, safety: .clinicalReferral, minN: 6),
    ]
}
