# Forecast composition model (circadian substrate + dose events + modulators)

*Design note, Jul 21 2026; foundation reworked Jul 22 (Bhav). Generalizes the day-ahead forecast so one model serves any day regardless of how many doses were taken. Design only — not built. Sequenced AFTER the insights confidence redesign (it consumes that gate).*

## Why

Today's day-ahead forecast is "flat OFF baseline + dose events projected forward." It has no answer for a **day with no doses** (`dayForecast` returns nil), and it assumes doses are the only driver. This note replaces that with a single composition model that degrades gracefully at every data volume.

## The model

**One always-present circadian substrate + events layered on it. No user roles.**

Medication is an **event, not a user trait**. A given day may have 0, 1, or 4 doses — Bhav is weaning off pills — so the model describes a *day by the events that happened*, never classifies the user as "medicated" vs "unmedicated." (An earlier draft branched the envelope by user type; Bhav found the flaw — that dichotomy dissolves the moment you take no pills on a day. Dropped.)

- **Substrate (always present).** Every day rides on the user's own **circadian tremor rhythm** — their by-hour tremor distribution (median + IQR = middle-50% spread), learned across days. It is the base shape whether or not pills are taken. Activates the dormant `circadianBaseline` primitive.
- **Dose events.** A levodopa dose is a strong event superimposed on the substrate: it imposes an ON window `[dose+onset, dose+duration]` that dominates the substrate where active. Zero doses → the substrate shows through all day; four doses → substrate under four ON bumps.
- **Modulators.** Food, sleep, exercise do NOT contribute their own additive curves. They adjust the **parameters** of the events (and, later, the substrate) — onset, duration, depth — via the typed `WindowAdjustment` seam. A run doesn't create an ON state; it may sharpen/extend one. **First modulator built = food→dose** (protein competes with levodopa absorption — established PK; makes the afternoon-dose card's observed onset gap explicit). Every other event — exercise, sleep, stress — plugs into the identical seam once its own effect is stably estimable on the user's data. Food goes first because its mechanism is strongest and its data densest (a lunch precedes most afternoon doses), not because it is privileged.

Same machinery, one code path, any dose count.

## Estimating the substrate (sampling rule)

Learn the substrate only from tremor that actually reflects the circadian baseline — **awake AND dose-free (OFF)** readings, binned by hour of day across history:

- **Never overnight.** Parkinsonian rest tremor is suppressed during sleep, so a night reading is ~0 regardless of circadian or dose state — sampling it fakes a calm baseline. Reuses the sleep **censor** decision already shipped in the wearing-off card ("counting only the time you were awake"). (Bhav's catch — the first draft proposed overnight, contradicting our own sleep-clipping decision.)
- **Awake dose-free windows** = pre-first-dose mornings + the awake portions of wearing-off gaps (the OFF segments the wearing-off model already finds).
- **Coverage-weighted band.** These windows cluster (mornings, gaps); heavily-dosed midday hours get few clean samples. The by-hour band widens where samples are thin; hours below the estimability floor are shown as non-estimable, never guessed.
- **Residual-drug caveat.** A gap labeled OFF may still carry a fading drug tail, so a medicated person's extracted substrate is *slightly drug-suppressed* — a mild underestimate of the true off-pills rhythm. Directionally right for the weaning question; state it, don't over-read it.

## Composition rule

- **Substrate is the floor; dose events override where active; modulators adjust parameters — never sum independent curves.** Structurally prevents impossible states (two "improving" events can't stack tremor negative — you nudge one bounded curve) and double-counting (a morning run + low circadian baseline aren't credited twice).
- **When two modifiers fire together** (e.g. lunch + a run before the same dose): **max wins (dominant modifier), widen the band.** Summing re-introduces the additive trap. A learned joint interaction term overrides `max` only once that specific combination has enough repeated cells to estimate — self-selects through the stably-computable gate, else stays dormant.

## Data-growth ceiling (honest limit)

"Smarter as data grows" is true but bounded. Interaction effects are the most data-hungry thing in statistics; at n-of-1 the exact combo (run + fasted + OFF + late) rarely repeats.

- **Main effects sharpen**, band narrows — real, keep building.
- **A few strong first-order interactions light up** (food→dose exists; maybe sleep→dose-onset).
- **Higher-order interplay mostly never gets enough cells.** That is NOT modeled into the mean — it lives in the **dispersion band**. Band width = the model's honest admission of unmodeled interplay. Do not try to shrink it away; it is the release valve that keeps the forecast truthful.

Roadmap is therefore: one envelope + a growing set of *validated* modulators + honest dispersion — not "eventually model all physiology."

## Gating & framing (non-negotiable)

- **Gate:** baseline shows only when its shape is **stably computable** across enough days; each modulator applies only when its effect is stably estimable. Reuses the insights confidence redesign gate — the dependency that sets build order.
- **Cold-start (first ~week):** no stable pattern → show the passive chart + "learning your rhythm," never a fabricated band. Optional: shade a literature diurnal prior (see cold-start-priors) marked *as a prior* until own data overtakes it — Bhav's call, stronger claim.
- **Observational, not causal.** "Your tremor tends to run higher late afternoon" — a measured pattern from own data. Never "your PD is worse in the evening."
- **Descriptive, never prescriptive.** Especially with Bhav's titration goal (4 Sinemet → fewer): the forecast shows "your day on 3 doses vs 4" for the neurologist. It must never read as "safe to skip a dose." `.clinicalReferral` framing holds.

## What the substrate / zero-dose view is *for*

On a day (or stretch) with no doses, the substrate shows through — nothing to project, no lever to act on. Its value:
1. **Anticipation** — "your steadier window is morning; schedule demanding tasks there."
2. **Baseline establishment** — a documented low-medication rhythm for the neurologist, and a reference to diff against — directly serves Bhav's weaning goal (his day on 3 doses vs 4 vs 0). No competitor has this.

## Open items

- **Circadian stability at n-of-1 — VALIDATED Jul 22, verdict = NO-GO on Bhav's data.** `analysis/run_circadian_substrate.py` on the 69-day backup (246 doses), awake + dose-free readings only: split-half reproducibility r ≈ 0.58 (fair, covered daytime hours), peak-to-trough swing across hours = **0.84**, but typical **within-hour day-to-day IQR = 1.18** — i.e. the time-of-day signal is *smaller than the day-to-day noise at a single hour*. There is a faint tendency (mornings ~9–11 higher, ~6 PM lower) but it's swamped; not a foundation for a confident "your steady window is X" card. **Do not build the substrate card now.** Caveats: (1) this is residual-suppressed medicated data — a true off-pills rhythm may differ; (2) as Bhav weans, clean awake data grows and dose interference shrinks — **re-run periodically**, build only if r climbs AND the swing exceeds the within-hour noise; (3) says nothing about an early-stage *unmedicated* user — that still needs such a tester.

- **⏸ RESUME HERE (Jul 22) — validate the unmedicated substrate on real unmedicated testers.** We HAVE two: **John S + Harpal** (both unmedicated, both have tremor data). This is the true go/no-go for the unmedicated / no-dose card — validate on THEM, not Bhav's drug-suppressed data. Blocked only on getting their CSVs (Bhav will request a full data dump from each; drop into `PD Companion/PD Companion Backups/<name>/`). When data lands: run `analysis/run_circadian_substrate.py <folder>` on each (for unmedicated users it's simpler — no dose windows to remove, just exclude sleep). **If the rhythm holds on John S/Harpal → build the descriptive baseline card, validated. If flat+noisy like Bhav → it dies honestly for everyone.** Note: John S's older backup had NO `tremor_readings` file → check his Motion & Fitness permission (may be the same gap as Jon K, which build `8aa9f2e` now surfaces).
- **`circadianBaseline` primitive** — never built (one of the four dormant primitives). Blocked on the validation above.
- **Joint interaction term** — the learned override for co-firing modulators; data-gated, likely rare.
- **Build order (Jul 22):** Phase 1 = food→dose modulator; Phase 2 = `circadianBaseline` + zero-dose view (gated on the validation above).
- **Phase-1 lever VALIDATED Jul 22, verdict = WEAK, recommend HOLD.** `analysis/run_meal_timing.py` on the 69-day backup (217 scored doses): fasting-gap→onset Spearman **r = −0.14, p=0.04** — correct direction (fuller stomach → slower dose) but tiny; fed vs fasted onset 53 vs 46 min (~7 min), trough unaffected (p=0.6). Crucially, fullness does **not** explain the afternoon slowdown — afternoon doses are slow even when fasted (64 vs 38 min morning), i.e. the dominant effect is **time-of-day, which the forecast already models** via bucketed onset. So the food modulator would add a ~7–12 min, low-r adjustment that is largely redundant and may not clear the confidence gate. **Recommendation: don't build the modulator machinery to carry this weak lever yet.** Re-run as Bhav weans (dose interference drops, effect may sharpen); build only if the effect strengthens or a stronger modulator (measured on data) appears.

## Links

- Day-ahead forecast (current, medicated): `Views/DayAheadPanel.swift`, `CorrelationEngine.dayForecast`
- Insights confidence redesign — defines the stably-computable gate this consumes: `docs/design/insights-card-confidence-redesign.md`
- Cold-start priors: `docs/design/cold-start-priors.md`
- Two-gate promotion architecture + `WindowAdjustment` seam: forecast memory / ParkinsonsProject.md
