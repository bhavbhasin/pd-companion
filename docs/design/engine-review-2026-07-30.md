# Outside review — correlation engine, Insights tab, day forecast

*Jul 30 2026. Adversarial read of `CorrelationEngine.swift` (3599 lines), `InsightRegistry.swift`, `InsightsView.swift`, `DayAheadPanel.swift`, the design docs, and the test suite. Every quantitative claim below was measured against the 07-29 backup (109,934 tremor readings, 364 dose rows, 82 days) — not inferred from the code.*

**Verdict: the architecture is sound and unusually disciplined. One serious statistical defect, one data-integrity gap, one multiplicity gap. None is structural — all three sit inside the existing seams.**

---

## Reproduction check (does the code do what the docs say?)

Rebuilt `substrateBand` from the raw CSVs — sleep + dose-window exclusions, 30-min bin means, whole-bin containment:

| | q25 | median | q75 | bins |
|---|---|---|---|---|
| doc (Jul 24, 78 days) | 1.40 | 1.71 | 1.95 | 899 |
| independent rebuild (Jul 29, 82 days) | 1.404 | 1.696 | 1.942 | 1011 |

The shipped band is exactly what the doc claims. The unit-mismatch and boundary-contamination fixes are real and correctly implemented.

---

## Defect 1 — the dose-confound guard shifts the null off zero (serious)

**The guard is right in intent and introduces a bias in effect.** `doseCleanEvents` keeps only events with no dose in `[start − 192min, end + postMin]`. Surviving events therefore sit deep inside dose-free stretches — which are precisely the stretches where tremor is drifting upward as a dose wears off. Both windows ride that drift; the post window rides more of it. So the expected delta for an event that does *nothing* is positive, and `windowedEffect` tests against zero.

Measured with placebo events (random timestamps, no exposure at all):

| | n | mean delta | p |
|---|---|---|---|
| placebo, no guard | 38,396 | **+0.003** | 0.51 |
| placebo, guard applied (15/120 window) | 13,936 | **+0.123** | 3e-133 |
| placebo, guard applied (30/120 window) | 14,064 | **+0.146** | 3e-180 |
| placebo, guard applied, duration-matched to real 41-min walks | 9,082 | **+0.202** | — |

The primitive itself is unbiased (+0.003, p=0.51). The guard is what moves the null. Note the bias **scales with event duration**, so no single constant corrects it.

Type-I error at realistic card sizes — a pure placebo clearing the gate's `p ≤ 0.05`:

| n | rate | nominal |
|---|---|---|
| 13 | 9.0 – 9.5% | 5% |
| 20 | 13.2 – 15.0% | 5% |
| 32 | 20.2 – 25.8% | 5% |

**It is already distorting two live cards, in opposite directions:**

- **Caffeine** — engine computes +0.177 (+11% of a 1.59 baseline), p vs zero = 0.137. Net of the placebo null: **+0.045, p = 0.70**. The residual "caffeine nudges tremor up" is the artifact, not caffeine. `intelligence-architecture.md` currently reads the post-guard **+9%** as caffeine's own effect; it is the guard's drift, and the sign-flip story should stop at "the −32% was the medication" (which remains correct).
- **Walking** — engine computes −0.163, p = 0.128 → **Emerging**, card reads "about the same". Net of the duration-matched null: **−0.365, p = 0.0019**. A real benefit is being suppressed.

**Fix direction:** the null must be empirical, not zero. Resample placebo events under the same guard, matched on duration and position-within-gap, and test the observed delta against *that* distribution — a permutation test. The event streams, the guard, and the gate are all already in place; this is a new null, not new architecture. Do not attempt a constant offset.

---

## Defect 2 — 22% of dose records are dropped silently (moderate)

`HealthKitManager` filters to `logStatus == .taken` (lines 239, 1058). The dose log:

| status | rows |
|---|---|
| taken | 279 |
| **notInteracted** | **79 (21.7%)** |
| notLogged | 4 |
| skipped | 2 |

`notInteracted` = a reminder the user never responded to. Genuinely ambiguous — not the same as `skipped`. But it is 28.3% more doses than the engine sees, it touches **59 of 82 days (72%)**, and **36 of the 79 sit more than 90 minutes from any taken dose**, so they are not duplicates of a logged dose.

Consequences, measured:

| | app's view | if notInteracted counted |
|---|---|---|
| median inter-dose gap | **6.12 h** | 4.38 h |
| mean doses/day | 3.40 | 4.37 |
| crude uncovered waking time | 5.37 h/day | 4.09 h/day |

The wearing-off card's headline uncovered-hours figure and the 68-day review's "dose coverage is the biggest lever (r = −0.47)" both rest on gap lengths that a 22% ambiguous stratum could move by roughly a quarter. The card states the number as fact with no uncertainty from this source.

**Not a request to include them.** The ask is that a 22% ambiguous stratum be visible — either as a range on the claim, or as a prompt to confirm-or-dismiss those doses.

**Scoped down, honestly:** this barely touches the forecast band. Rebuilding the band with `notInteracted` windows also excluded moves it 1.3% (q25 1.404 → 1.380, median 1.696 → 1.682, q75 1.942 → 1.916). Material for the coverage claim; inert for the forecast.

---

## Defect 3 — the confidence badge has an uncontrolled multiplicity (moderate)

Cards that can reach a badge (dose-clean n ≥ 5) on current data: **caffeine (n=31), sugar (n=35), walking (n=22)**. The other workout types fall below the n≥3 floor and correctly stay hidden.

At the measured 9–15% type-I rate, P(at least one false Moderate/Strong badge) ≈ **27–39%**.

`intelligence-architecture.md` defends this as: *"observational cards state facts and declare no verdict — no per-card claim to over-fire, so no family-wise error to control."* **That defence does not cover the badge.** The body is facts; the badge is a three-tier verdict derived directly from `p`. Whatever is true of the sentence is not true of the dots.

Cheapest honest fix: for observational cards, drop the p-derived tier and let the badge carry n only — the body already states the effect against the user's own daily swing, which is the comparison that actually informs. Reserve p-tiered badges for the MCID-gated cards (wearing-off, gait), which are few and were the doc's real justification.

---

## Defect 4 — `fitPulseModel`'s `sleep` default is live at one call site (minor, latent)

`CorrelationEngine.swift:3266`:

```swift
let combined = fitPulseModel(key: "__combined__", signal: sig, events: estimableDoses.map(\.timestamp))
```

No `sleep:`, no `cache:`. Every other production call passes sleep; this is the only one that runs uncensored, so the combined KM median inflates (overnight zeros read as the drug still working — exactly what the sleep-clipping fix exists to prevent).

**Blast radius is small today**: `combined.iqr` is only the fallback for `nextOffRange` (line 3336 usually matches a dose's own IQR first), and `durationsCount` drives the confidence tier but isn't changed by censoring. Probably no visibly wrong number right now.

**Fix the signature, not the call.** The Python lab already made `sleep` required with no default precisely to kill this class of bug (`wearing_off.analyze`); the Swift side still defaults it to `[]`. Same trap, still armed. The missing `cache:` also makes `dayForecast` redo full survival work it could reuse.

---

## Defect 5 — two sleep definitions inside `dayForecast` (minor, latent)

`censorSleep` (synthesized, dose-respecting) feeds the survival models at line 3247, but raw `sleep` feeds `substrateBand` (3316) and `PhaseVocabulary` (3317). Where a night is unrecorded, the band's "never overnight" rule silently lapses.

**Measured: inert for this user** — only 1 of 82 days lacks a sleep session. The Jul 25 audit's WON'T FIX is defensible. Flagging only because it degrades silently and the two definitions aren't documented as a deliberate split.

---

## Defect 6 — the null is only tested on synthetic stationary data (test gap)

`WindowedEffectTests.nullEffectIsNotSignificant` builds a flat 2.0 baseline with symmetric ±0.05 noise. By construction it has no drift, so it proves the primitive is unbiased *in isolation* — which is true and not where the problem is. Nothing tests the shipped **composition** (guard → primitive → gate) against a real-data null. Defect 1 lives exactly in that gap, which is why 3,486 lines of tests didn't catch it.

---

## Defect 7 — shipped guard and validation script don't use the same rule

`run_exercise_effect.py` strata by dose *state* (`pre_on`/`post_on`, "fully dose-free" = neither window ON, n=11 → +0.01, p=0.90 → NO-GO). `doseCleanEvents` requires no dose *within a time shadow* (n=22 → −0.163). Different rules, different answers, and the doc's "exercise NO-GO" verdict was reached with the rule that isn't shipped. Worth reconciling before either number gets quoted again.

---

## What is genuinely sound

Stated plainly because most of this codebase is better than the industry norm and the defects above shouldn't obscure it:

- **The three-layer wall holds.** Verified: no runtime LLM anywhere in the card path — cards are hand-written Swift over deterministic statistics. The claim that only the engine may call a pattern real is true in the code, not just in the doc.
- **Registry / primitive / renderer decomposition is real extensibility.** Dispatch on `renderer` (not primitive, not id) is the correct call and the reasoning for it is exactly right — `.longTermTrend` genuinely cannot distinguish the gait composite from a future step-length trend.
- **The constants ledger** (sourced / structural / provisional / arbitrary, with the class asserted at the constant) is a discipline almost nobody applies. It is what let the unsourced onset floors and the `minN` field get removed on principle rather than taste.
- **The validation culture is the strongest asset here.** Five forecast conditioners tested against real data and all five killed — including the ones that would have made a better demo. The exercise finding ("the signal was pills wearing off in an exercise costume") is the kind of result most health apps ship rather than catch.
- **`nonInferiorityP` is correct**, including the one-sided choice and the reasoning for it. Scoring an absence claim with a presence gate is a common and serious error; this avoids it deliberately.
- **The ON/OFF vs substrate vocabulary split** is subtle and right. Refusing to let medication language label a pharmacologically cleared hour is a distinction most clinical software gets wrong.
- **The magnitude floor on both substrate verdicts**, per-bin rather than band-level, with the explicit reasoning that a wholesale switch would have hidden a genuine 2.5 episode — that is a well-made decision.
- **Persistence NO-GO → flat projection.** Correct, and the discipline to leave the projection flat when a recentered one would look more impressive is the right instinct.
- **The Insights tab's framing** — facts-over-verdict body, the user's own daily swing as the yardstick where no MCID exists, and the "never change a dose without your neurologist" line on the surface — is well-judged.

---

## Recommended order

1. **Empirical null for the windowed-effect cards** (Defect 1) — it is changing what two live cards say, in both directions.
2. **Surface the `notInteracted` stratum** (Defect 2) — it moves the coverage headline by ~25%.
3. **Badge multiplicity** (Defect 3) — cheap; removing the p-tier from observational badges costs nothing the body doesn't already say.
4. **Make `sleep` required in `fitPulseModel`** (Defect 4) — signature change, minutes.
5. Reconcile the exercise rule (Defect 7), then add a real-data null regression test (Defect 6).
