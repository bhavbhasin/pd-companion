# Forecast composition model (baseline + envelope + modulators)

*Design note, Jul 21 2026. Generalizes the day-ahead forecast so one model serves medicated and unmedicated users. Design only — not built. Sequenced AFTER the insights confidence redesign (it consumes that gate).*

## Why

Today's day-ahead forecast is "flat OFF baseline + dose events projected forward." It has no answer for an **unmedicated / early-stage user** (no doses → panel hidden, `dayForecast` returns nil), and it assumes doses are the only driver. This note replaces that with a single composition model that degrades gracefully at every data volume.

## The model

**One baseline envelope + parameter-modulators. Never a sum of independent curves.**

- **Baseline (the envelope).** For a medicated user, levodopa defines the ON/OFF envelope (current behavior). For an unmedicated user, the **circadian baseline** is the envelope: the user's own by-hour tremor distribution (median + IQR), projected across today. This activates the dormant `circadianBaseline` primitive.
- **Modulators.** Exercise, food, sleep do NOT contribute their own additive curves. They adjust the envelope's **parameters** — onset, duration, depth — via the existing typed `WindowAdjustment` seam. A run doesn't create an ON state; it may sharpen/extend one. Protein lunch delays/blunts the following dose — already modeled in the afternoon-dose card; this generalizes that one interaction.

Same machinery, one code path, medicated or not.

## Composition rule

- **Adjust parameters, don't add curves.** Structurally prevents impossible states (two "improving" events can't stack tremor negative — you're nudging one bounded curve) and double-counting (a morning run + low circadian baseline aren't credited twice).
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

## What the unmedicated card is *for*

Not a mini dose-forecast (nothing to project, no lever to act on). Its value:
1. **Anticipation** — "your steadier window is morning; schedule demanding tasks there."
2. **Baseline establishment** — a documented pre-medication rhythm for the neurologist, and a reference to diff against once meds start. No competitor has this.

## Open items

- **Circadian stability at n-of-1** — pressure-test that unmedicated PD tremor is reliably diurnal per-individual before committing. If it isn't stable, the baseline (and the whole card) falls apart.
- **`circadianBaseline` primitive** — never built (one of the four dormant primitives).
- **Joint interaction term** — the learned override for co-firing modulators; data-gated, likely rare.

## Links

- Day-ahead forecast (current, medicated): `Views/DayAheadPanel.swift`, `CorrelationEngine.dayForecast`
- Insights confidence redesign — defines the stably-computable gate this consumes: `docs/design/insights-card-confidence-redesign.md`
- Cold-start priors: `docs/design/cold-start-priors.md`
- Two-gate promotion architecture + `WindowAdjustment` seam: forecast memory / ParkinsonsProject.md
