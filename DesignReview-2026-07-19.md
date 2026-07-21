# Kampa - Design & Architecture Review (Jul 19 2026)

**Status: review only - no code changed.** Requested by Bhav: are the design decisions sound and future-proof, and is the architecture robust, secure, scalable? Named examples: hard-coded Insights gating; hand-picked workout types.

**⚠ Do NOT commit this file while the repo is public** - §6 is a map of where personal health data sits in tracked files. Add to .gitignore first, or keep untracked (like BACKLOG.md).

---

## Verdict

The architecture itself is sound - the 3-layer split (LLM proposes / engine judges / LLM narrates), the walled-off Judge, the dose-confound guard, primitive-vs-renderer, censoring-vs-subtraction, the estimability-gate-as-classifier are all above-bar design and correctly reasoned. The re-evaluation churn you're feeling is not bad architecture. It is **three recurring habits** that keep landing inside a good architecture:

1. **Picked constants where the structure needed a rule.** The n≥5 gate, the 15-min onset floor, the 600-min gap cap, the 0.5 dyskinesia floor, the clock-bucket cliffs - each shipped as a plausible number, each later re-litigated. You already named this (`feedback_no_arbitrary_thresholds`); the Jul 17 gating redesign is the correct generalization. §3.
2. **Instance enumeration disguised as hypothesis curation.** The 13 hand-listed workout types are not 13 hypotheses - they are one hypothesis stamped 13 times. That mistake is structural, and it recurs (food attributes, sleep facets). §2.
3. **Config and docs that overclaim what the code does.** `RegistryEntry.minN` is dead config - never read. The architecture doc claims multiple-comparison correction and stability replication - neither exists. A registry entry looks live (`dose-dyskinesia-peak`) but structurally can never render. For a health app whose trust story is "auditable, deterministic," the paper trail overstating the code is itself a defect. §4, §5.

None of these is expensive to fix. All three compound if left: every new card inherits them.

---

## 1. Why decisions keep getting re-visited (the pattern)

Trace of re-litigated decisions, all the same shape:

| Decision as first shipped           | What it actually was            | Resolution                                          |
| ----------------------------------- | ------------------------------- | --------------------------------------------------- |
| Gate: show at n≥5                   | picked constant                 | Jul 17 redesign: "stably computable" rule           |
| Dose-window 15-min effect floor     | picked constant, no MCID exists | Jul 17: dropped, facts-over-verdict                 |
| 600-min gap cap + 6am-8pm filter    | two proxies for "was he awake"  | sleep clipping (measured sleep answers it directly) |
| Chart gap-break threshold           | picked constant                 | reverted; dashed-bridge design noted                |
| `bucketOf` 9.5/12.5/17 clock cliffs | picked constants + a proxy axis | logged Jul 17, unfixed                              |
| `sinemet/mucuna` name filter        | hand list                       | replaced by estimability gate (the right pattern)   |

The last row is the model answer: **replace the hand-picked value/list with a structure the data already provides** (the gate is the classifier). Where that was done - estimable formulations, per-user ON-window from the KM median, MCID-sourced margins - the decision has *stayed* decided. Where a constant was picked, it got re-opened.

**Recommendation - a constants ledger.** One table (a doc section or a `Constants.swift` with doc comments) classifying every numeric constant in the engine as one of: **sourced** (citation - e.g. 60 min/day OFF MCID, 0.06 m/s gait MCID), **structural** (derived from the data or a mathematical minimum - e.g. per-user ON-window, n≥3 to compute a mean), **provisional** (needs data to tune - e.g. dyskinesia 0.5 floor, waiting on a dyskinetic tester), or **arbitrary** (tech debt, listed as such). New rule: a constant may not ship without a classification. This makes the next "is this number defensible?" conversation a lookup instead of a re-derivation. The cold-start plan already demands exactly this for `doseOnWindowFallback = 190` and the [90,360] rails ("formalize + cite or delete") - extend that discipline engine-wide.

Current inventory that would land in the ledger (partial): `offThreshold 1.0` (tested, ~6% swing - fine), `maxWindow 300` (breaks once-daily regimens, already flagged), `gapIso 240`, `sustainBins 2`, `minCoverage 0.5`, `keyWindow 90`, gate tier numbers (§3), `fetchWorkoutEvents(days: 120)` / `fetchMedicationDoses(days: 120)` (§5.2), forecast `30-min bin / 2-bin` de-jitter (documented as de-noise, fine).

---

## 2. The workout list - instance enumeration disguised as curation

**What exists.** The adapter is genuinely generic - `fetchWorkoutEvents` (HealthKitManager.swift:633) ingests *every* `HKWorkoutActivityType`, tagged. But the registry (InsightRegistry.swift:265-367) hand-enumerates 13 activity types, each with the **identical** primitive (`windowedEffect(30, 120)`), identical gate, identical minN, identical safety class. Only the id and rationale string differ. A user who swims, hikes, rows, does elliptical, Zumba, or golf gets **silence** - their data is fetched every session and dropped on the registry floor. Boxing was only in the list because someone remembered Rock Steady.

**Why the "curation prevents false discovery" defense does not apply here.** Curation earns its keep when entries differ in *statistical treatment* - different priors, different gates, different windows. Thirteen identical entries are already thirteen simultaneous tests with no multiple-comparison handling (§4) - you are already paying the full false-discovery cost of "test every workout type," you're just not getting the coverage. The current design has the risk of breadth without the benefit.

**The design that fixes it: two kinds of registry entry.**
- **Singular hypothesis** - a genuinely distinct question with its own mechanism and treatment (`protein-meal-dose-onset`, `caffeine-tremor` with its guard note). Stays a hand-authored line. This is what the registry concept is actually for.
- **Question template, quantified over a domain** - "does ⟨activity the user actually does⟩ shift tremor in the 2h after?" One template entry; the engine instantiates it per activity type **observed in the user's own data** (the adapter already tags them; `displayName` already exists for every type). A per-type override table keeps the curated touches where they exist (Tai Chi's literature note, boxing's Rock Steady rationale); unlisted types get honest generic copy ("an association in your own data"). New Apple activity types arrive for free. Nobody ever hand-wires pickleball again.

This is not "scan all variable pairs" (the rejected extreme) - the *question* is still human-approved once, at the template level. What's removed is the pretense that stamping the same question per type is curation.

**Guardrail that must ship with it:** instantiating over the observed domain makes the test count explicit and per-user-variable, so the cluster needs family-wise handling - either a correction across the exercise cluster, or (better, and already decided Jul 17) the facts-over-verdict presentation, which reduces multiplicity harm because no per-type verdict is declared. Do the template and the Jul 17 redesign together; they are the same change viewed from two sides.

**The same disease elsewhere (fix the pattern, not the instance):**
- **Food attributes** - the classifier detects 5 (`caffeine, protein, sugar, fiber, fat` - FoodEvent.swift:57); only 2 have registry entries. Every food log classifies protein/fiber/fat and then no question ever consumes fat or fiber. Same template treatment applies (protein legitimately waits on `mealTimingCompetition`).
- **Sleep facets** - `SleepFacet` defines 4 (duration, deep, rem, interruptions); 2 have entries; rem/interruptions are silently unreachable.
- **Labeling debt from enumeration:** `tango-tremor` claims Argentine tango but `socialDance` is any partner dance - the rationale asserts more than the data can know. The `mindAndBody` entry already confesses it's a blended bucket. Template + honest generic copy retires both problems.

---

## 3. The Insights gate (your first example) - diagnosis confirmed, design right, not built

You already caught this correctly: the Jul 17 redesign (`docs/design/insights-card-confidence-redesign.md`) is the sound answer - "a card shows once every quantity its statement depends on is stably computable," effect gates only where a sourced MCID exists, facts-over-verdict elsewhere. This review **affirms that design**; the churn on gating ends when it's built. What the redesign still leaves open, found in this pass:

- **The gate tier numbers themselves are unclassified constants.** `windowedEffectGate` (10/5/5, p .01/.05), `doseResponseGate` (n 5/10/20 + effect floors **15/20/25 min** - the redesign drops the 15 floor but the 20/25 tier floors have the same no-MCID problem and survive untouched), `gaitTrendGate` (24/12/6 months). The p-value tiers (.01/.05) are conventional - fine, say so in the ledger. The n-tiers and onset-minute tiers are picked. The redesign's "stably computable" rule should replace the n-tiers; the onset-minute tiers should fall to the same facts + onset-variability yardstick the floor did.
- **"Strong" means a different thing per card** (significance / effect-vs-MCID / non-inferiority). Already noted in the redesign as a deferred cleanup - agree with deferring, but put it in the ledger so it stops being re-discovered.
- **The one residual knob** ("stably computable" needs an operational definition per card) is honestly acknowledged in the doc. Suggest defining it as a *convergence criterion* (estimate stops moving more than X% as days accrue) rather than a min-days count, or it quietly becomes n≥5 wearing a new name.

---

## 4. Config and docs that overclaim the code (trust-surface defects)

For an app whose differentiator is "the judge is deterministic and auditable," these matter more than their size suggests:

1. **`RegistryEntry.minN` is dead config.** Documented as "sufficiency floor the gate enforces before showing anything" (InsightRegistry.swift:182). It is never read - the only `minN` the gate consults lives in the hard-coded per-renderer `GateSpec`s (CorrelationEngine.swift:508 reads `GateBar.minN`). Every registry entry carries a number that looks load-bearing and does nothing. Wire it (entry overrides spec, as intelligence-architecture.md:480 promises: "a registry entry may override it") or delete the field. A config surface that lies is worse than no config surface.
2. **`dose-dyskinesia-peak` looks live but can never render.** It has `renderer: .windowedEffect` (InsightRegistry.swift:215-221) - but `windowedEffectInsight` guards `entry.outcome.isTremor` (CorrelationEngine.swift:415) and `windowedExposure` has no `.levodopaDose` branch (only workout and food, :321-342). Doubly unreachable, yet unlike the honest `renderer: nil` dormants it *claims* to be wired - and `confidence-presence-vs-absence.md:44` lists it among live windowed-effect cards. Either set `renderer: nil` with a comment (honest dormant) or build the dose-exposure + dyskinesia-signal branches.
3. **The `outcome` axis is decorative in the windowed path.** The signal is always tremor (`samples`), regardless of what the entry declares. The advertised generality ("any signal-vs-event") is real at the *primitive* level but the dispatch layer has no signal resolver - the first non-tremor outcome (dyskinesia above, HRV) needs one. This is the actual generalization gap between the architecture doc and the code; name it in the doc so nobody assumes a new outcome is "a registry line."
4. **The architecture doc claims disciplines the gate does not have.** intelligence-architecture.md:132: "the gate then enforces discipline: multiple-comparison correction... and replication across time windows." Neither exists. `GateBar.minStability` exists (CorrelationEngine.swift:492) and **no spec sets it** - split-half stability was decided in the Jun 18 design ("stability: holds across split halves," ParkinsonsProject.md:234) and `perEvent` deltas are already returned for exactly that purpose (:627), then never consumed. Fix the doc or build the axis - with ~24 active questions, one shared correction (or the facts-over-verdict reframe) is the honest minimum. The Jul 17 supersession note fixed the *gating* claims; this sentence survived it.
5. **Registry comment drift:** InsightRegistry.swift:17 says the registry has "26 entries" in one doc and 23 in memory; the starter list is 23. Trivial, but the counts in docs keep drifting from the file - a symptom of hand-maintained parallel records (`feedback_verify_backlog_against_git` exists for the same reason).

---

## 5. Robustness & scalability

**Genuinely strong (keep, and don't re-litigate):** pure `Sendable` engine off-main with parity tests against the Python oracle; dose-confound guard at the Judge layer with per-user ON-window; the censor-vs-subtract sleep distinction (and "never censor a measurement on a guess"); estimability-gate-replacing-drug-dictionary; stage derived centrally from `SafetyClass` (a renderer can't contradict the safety class); one-sided non-inferiority for absence claims with the circularity fix. This is a defensible statistical core most health apps do not have.

**5.1 Dormant questions are shipped invisibly.** 6 entries have `renderer: nil`; 4 primitives (`overnightLag`, `withinDayAssociation`, `circadianBaseline`, `mealTimingCompetition`) are declared and unbuilt. The empty-state "what we're watching for" implies watching things that are structurally dark. You've already named building these out as the next project - this review agrees and adds a priority argument: **`overnightLag` (sleep → next-day) first.** Sleep is the one exposure *every* user has from day one with zero logging - it's the best cold-start card in the registry and the largest population that currently gets silence. `withinDayAssociation` (HRV) second for the same reason. Until built, the honest interim is to make dormancy legible (the X-ray design, or simply excluding dormant entries from "watching for" copy).

**5.2 Data-window asymmetry - an undecided decision hiding in adapter defaults.** Tremor samples = full history (SwiftData query), gait = 12 years, food = full history, but doses and workouts = `days: 120` adapter defaults (HealthKitManager.swift:633, 652). Consequences nobody chose: at month 5+ of use, the wearing-off and dose cards silently become "last 120 days" while the tremor series they're scored against is all-time; a workout done 121 days ago vanishes from its card's n. 120 is a reasonable *recency* choice for stationarity (meds change; old dose-response is stale) - but then it should be a per-entry, documented property ("this question reads a rolling 120-day window because regimens drift"), not a fetch default two layers below the registry. The BACKLOG latency item already notes "each analysis needs its required multi-day range - don't blindly window"; this is the same decision surfacing earlier. Fold the required/allowed window into the registry entry when the latency work happens.

**5.3 Compute scales linearly with history and runs on every tab open.** Full recompute, all entries, all history, per Insights visit - already off-main, already backlogged as a latency item. Fine at solo scale; becomes the cohort's first perceived-quality complaint. The right shape (when triggered): cache last results keyed by a data watermark (max timestamp per stream), recompute only when the watermark moves. No design risk - flagging that the trigger should be *before* TestFlight cohort growth, not after complaints.

**5.4 Experiment-loop mockup is reachable in a shipping build.** "Try an experiment" on every exercise card mutates in-memory state, pastes a hard-coded protocol, computes no verdict, and evaporates on reload (BACKLOG: InsightsView.swift ~628). A tester who starts one experiences silent data loss in the feature whose whole story is rigor. Cheapest honest fix: hide the button behind `#if DEBUG` until the persistence half lands. This is the only finding in this review I'd act on before anything else in §5.

---

## 6. Privacy finding - personal health data in a public repo (highest-severity finding)

The rule is non-negotiable and yours: never publicly disclose that you have PD. The repo is public, and the gitignore discipline that protects BACKLOG/ParkinsonsProject/analysis (and the AI failure log, gitignored for exactly this reason in `f58eb8b`) was **not applied to engine comments and design docs**, which are tracked:

- `CorrelationEngine.swift:942-946` - your typical worst hours, sleep onset, and a specific dose time, by name.
- `CorrelationEngine.swift:1087-1090` - your overnight tremor median and evening-dose censoring rate, by name.
- `docs/design/confidence-presence-vs-absence.md` - a worked example on your own gait record (span, baseline speed, slope), by name; also names a family member's device.
- `docs/design/wearing-off-margin.md`, `docs/design/tremor-averaging.md` - your dose counts, gap medians, uncovered-minutes figures, felt-state calibration, by name.
- `docs/intelligence-architecture.md` - your caffeine servings / ON-duration figures (softer: framed as "this user," but adjacent to your name elsewhere in the doc).

Anyone connecting the public repo to the founder - trivial, it's under github.com/bhavbhasin and the site names you - reads a partial symptom diary. Options:

| Option | Cost | Residual |
|---|---|---|
| **A. Make the repo private** | loses public build-in-the-open value; the hiring-signal story survives (the app, site, LinkedIn all remain public) | none going forward; history exposure ends when visibility flips |
| B. Scrub tracked files + rewrite history | heavy (force-push rewrite, like the June privacy-policy scrub); comments lose real explanatory value | forks/clones/caches may retain history |
| C. Move personal-data docs to gitignored paths + de-personalize code comments ("the reference dataset" not "Bhav") going forward | moderate | history still contains everything to date |

Recommendation: **A now** (one click, reversible, stops the bleeding), then decide between staying private vs B/C at leisure. Note this review file itself belongs behind the same line - hence the header warning. Separately: `docs/ask-kampa/Kampa-FAQ.md` and `faq-knowledge.md` mention you by name and feed a public chatbot - verify they carry only founder-of-Kampa facts, no health facts.

---

## 7. Future-proofing

- **The remote-config deployment story is designed but unbuildable as written.** intelligence-architecture.md promises "registry entry → remote config, no resubmit." The registry is a compiled Swift static array of enums with associated values - there is no serialization, no remote fetch, and (correctly) a decision that the registry is "a typed Swift struct, NOT a CMS." Fine at solo scale - but the doc presents remote config as the deployment mechanism at App Store scale. When that day comes it needs a versioned, signed, Codable registry schema (remotely pushing statistics to a health app needs integrity protection + rollback, as the doc itself says). Not urgent; downgrade the doc claim to "designed, requires the Codable-registry build" so future-you doesn't assume it exists.
- **Cold-start priors plan** (`docs/design/cold-start-priors.md`) - sound, and its Phase 1 finding (the forward model is a 3-parameter box, so extract only 3 numbers) is exactly the right scope discipline. The IR-only v1 + single-stratum + forecast-surface-first recommendations are right. This work is also the answer to §5.1's cold-start argument from the *medication* side; sleep-lag is the answer from the *lifestyle* side. They complement, not compete.
- **Per-medication stratification, ET broadening, multi-outcome** - the registry axes (exposure/outcome/primitive/renderer/safety/category) hold up for all three; nothing in this review found a schema that would need migration. The one missing axis is the required-data-window (§5.2) and, if the template model lands (§2), an `instantiation: singular | perObservedType` marker.
- **SwiftData vs HealthKit as system-of-record** remains genuinely open (memory `project_kampa_data_architecture`) and becomes load-bearing at CSV-import time (Gate A blocker) - the import's dedup/merge semantics depend on which store is authoritative. Decide SoR before building import, or the import bakes the decision in silently.

---

## 8. Security posture

- **App: structurally clean.** No networking code in the app target (verified - zero `URLSession`/Network imports); the "raw data never leaves the device" claim is currently *enforced by absence*, the strongest form. CloudKit private DB only. Entitlement bundle-ID binding documented as app-breaking - good.
- **When the LLM narration layer lands, the enforcement model changes** from "no network code exists" to "network code exists and must only carry derived summaries." That boundary should be structural, not disciplinary: a single narrow `NarrationPayload` type that is the *only* thing the API client can serialize, unit-tested to contain no raw streams - so the privacy claim survives code review by construction. Design this seam before the first `URLSession` line.
- **Known gaps, ranking confirmed:** CSV import/restore as the single-point-of-restore-failure fix is correctly the Gate A blocker; research-consent screen before first non-self data share; privacy-first analytics choice (no third-party SDK) already correctly constrained in BACKLOG.
- **Website chatbot** (`docs/ask-kampa/netlify/functions/ask.js`) is the one piece of server code in the project - confirm the API key lives in Netlify env (not the file) and the knowledge corpus stays free of personal health facts (§6).

---

## 9. Recommended order

1. **Repo visibility (§6)** - flip private today; decide the long-term option deliberately. Cheapest, highest-severity, and every day public adds history.
2. **Hide the experiment button (§5.4)** - one `#if DEBUG`. User-visible trust damage in shipping builds.
3. **"Make the gate honest" work package** - build the Jul 17 gating redesign + wire-or-delete `minN` + fix the doc overclaims (§4.4) + constants ledger (§1). One coherent package; it ends the gating churn and makes the paper trail match the code.
4. **Workout template entries (§2)** - retires the boxing class of problem permanently; do together with the facts-over-verdict card change (same change, two sides).
5. **Dormant-renderer build-out (§5.1)** - sleep-lag first, HRV second; your named next project, unchanged - plus the honest-dormancy fix for `dose-dyskinesia-peak` (§4.2) as a 5-minute part of it.
6. **Data-window into the registry (§5.2)** - fold into the latency/caching work when it triggers.

Items 3-5 are the same theme from three angles: *the registry should be the single honest source of what the engine does* - every entry either runs as described or is visibly dormant, every threshold is classified, every doc claim is true.
