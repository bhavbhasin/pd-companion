# Confidence: presence vs. absence claims

**Status:** gait ✅ BUILT (Jul 14 2026) — card now reads *Strong*. windowed-effect family still open (needs a tremor MID). Origin: Jul 13 2026 — the gait "Your mobility hasn't declined" card reads *Emerging* despite 5.8 years / 71 monthly medians, because a flat slope can't be statistically significant.

**Two corrections the build forced** (details in the sections below):
1. The test is **one-sided non-inferiority**, not two-sided equivalence. The card claims "hasn't *declined*"; two-sided would fail a genuine improvement.
2. The margin is the **MCID alone**, not `max(own detectable, MCID)`. That rule was circular.

## The defect

The confidence gate (`CorrelationEngine.gate`) scores **presence of an effect**: a low slope/effect p-value → Strong. That is correct for a card claiming an effect exists. It is **backwards** for a card claiming an effect is *absent* (stability, or "no clear effect"):

- A true null/flat result has an effect ≈ 0 → never significant → structurally capped at *Emerging*, forever, no matter how much confirming data arrives.
- It conflates two very different states the user needs distinguished:
  - **"no effect — not enough data yet"** (genuinely weak → low confidence is right), vs.
  - **"no effect — and we're now sure of it"** (strong evidence of *absence*; reassuring, useful).

Gait made it visible because it's the richest dataset. It is **systemic**, not bespoke.

## The principle

Presence and absence are properties of the **verdict**, not the question — most directional cards can resolve either way. The gate must branch on which verdict fired:

| Verdict | Right test | Confidence rises with |
|---|---|---|
| **Presence** ("X eases tremor −32%") | significance (current p-value gate) | effect size + significance |
| **Absence / stability** ("no decline", "no clear effect") | **non-inferiority** — rule out a *meaningful decline* | precision: a tight interval whose bad-direction bound clears the margin |

**One-sided, not two-sided** (corrected Jul 14). The original note specified equivalence — the whole interval sitting inside ±margin. That is the wrong claim: the card says "hasn't *declined*", not "hasn't *changed*". Under two-sided, a patient whose walking genuinely **improved** past the margin would fail the test and see the card downgrade — punishing good news on a reassurance card, which is the same shape of bug as scoring absence with a presence gate. The test asks only: *is a decline larger than the margin ruled out?*

Implementation note: this needs no confidence interval and no t-quantile table. Non-inferiority (H₀: decline ≥ margin) yields a **p-value** — `t = (change + margin) / SE`, one tail — so it feeds the existing gate's `maxP` axis directly. Same tiers, same machinery; only the question underneath changes. Wide interval (thin/noisy data) → large p → stays Emerging. It degrades gracefully, because SE sits in the denominator.

**The one cost:** each absence claim needs a *meaningful-effect margin* (minimal important difference) — e.g. "a gait decline rate that would actually matter," "a tremor change worth noticing." Anchor each to functional meaning and state it explicitly; not a tuned knob. This is real work but it's the right work — those margins are worth defining regardless.

**Why this matters more than presence:** an n-of-1 app testing many plausible-but-mostly-inert hypotheses will have **most cards resolve to nulls**. Absence-confidence is the common case, not the edge.

## Inventory — every gate / renderer today

Live = renderer built and shipping. Dormant = registered, renderer `nil`, will inherit the fix when built.

| Renderer / gate | Cards | Null path today | Verdict |
|---|---|---|---|
| **gaitComposite** / `gaitTrendGate` | gait "hasn't declined" | ~~*Emerging* on a flat slope~~ | ✅ **FIXED Jul 14** — origin case; card now reads Strong |
| **windowedEffect** / `windowedEffectGate` | caffeine, sugar, all exercise (tai-chi, boxing, yoga, cycling, walking, strength, table-tennis, pickleball, tango, climbing), mindfulness, dyskinesia-peak | floor is `minN:5` with **no p** → null shows as *Emerging* regardless of how confidently no-effect | **AFFECTED** — a matured "no effect" (e.g. caffeine over 18 servings) is capped at Emerging, same as at 5 servings |
| **doseResponse** / `doseResponseGate` | afternoon-dose onset | floor needs `minEffect:15` → a null (small effect) clears nothing → **hidden**, not shown | Different: absence = silence, not a mislabeled card. Question worth raising: is "your dose speed is uniform" a reassurance we're dropping? |
| **wearingOff** / `wearingOffGate` | doses wear off early | n-only gate; presence-shaped, always fires | Presence-only. **Gap:** no absence verdict ("doses last as long as your gaps — no wearing-off") is produced today |
| **doseResponseByTimeOfDay → circadianBaseline** | when control is weakest | dormant (renderer nil) | Descriptive, not presence/absence — likely N/A |
| **overnightLag** (sleep dur/deep → next-day) | dormant | — | Will be AFFECTED when built (same null trap as windowedEffect) |
| **withinDayAssociation** (HRV ↔ tremor) | dormant | — | Will be AFFECTED when built |
| **mealTimingCompetition** (protein / meal-fullness → onset) | dormant | — | Will be AFFECTED when built |

**Active blast radius today:** ~~gait +~~ the windowed-effect family's null branch, blocked on a tremor MID (decision 3). Everything else is either presence-only, silent-on-null, or dormant (inherits the fix at build time).

## How the meaningful-effect margin is calculated (methodology + citations)

An equivalence test needs a **margin** = the smallest change that counts as "real." How we set it, and where the numbers come from (this is the reference for "how were these percentages calculated?"):

**Rule: margin = the clinical MCID.** (Corrected Jul 14 — the original `max(own detectable, MCID)` rule is **circular**; see below.)

**MCID** = *minimal clinically important difference*: the smallest change studies find a clinician/patient actually calls meaningful. A published constant, same for everyone, in **native units** (m/s — never a percentage, which would silently scale the margin with the patient's baseline and hand a slower patient a smaller margin than the literature supports). Display copy derives the % from it, not the reverse.

### Why not `max(own detectable, MCID)` — the circularity

The original rule took the stricter of the MCID and *the user's own detectable margin* (≈1.96·SE from their own month-to-month scatter). It reads well and it is wrong: **the own margin is a function of the same SE the test divides by.** Whenever it binds:

```
t = (change + margin) / SE  →  (0 + 1.96·SE) / SE  ≈  1.96  →  p ≈ 0.03  →  Moderate
```

…*regardless of how noisy the data is*. The margin grows with the very noise it is supposed to survive, so the test can never fail. A user with garbage data gets a permanent Moderate. Caught by `shortNoisyRecordCannotClaimAbsence`, which expected Emerging and got Moderate.

Testing against the **fixed** clinical floor removes the circularity: SE stays in the denominator, so noisy data fails honestly on its own and no separate noise rule is needed.

### What the own-margin is still for

It keeps its real job — **reporting what this user can resolve** (`MetricTrend.ownDetectableMargin`, `canResolveMCID`) — it is simply not an input to the test. It remains per-user, on-device, computed only from that user's own scatter. **Never** compute it from anyone else's data: statistically wrong (everyone's scatter differs) and it's the privacy line the app is built on (no raw cross-user data leaves the device).

Its diagnostic reading is still the honest one the `max` rule was reaching for: **own margin > MCID ⇒ this user cannot yet resolve a clinically meaningful change.** The difference is that the non-inferiority test now *produces* that verdict on its own rather than needing the margin bent to encode it.

**Grounding numbers (gait speed, Parkinson's):**
- **MCID for gait speed ≈ 0.06 m/s** (small; moderate 0.14, large 0.22) — Hass et al., n=324 PD; a 2023 re-analysis lands ~0.082 m/s. At a typical PD speed ~1.0–1.1 m/s that's **~5–6% of baseline** (so an early hand-wave of "2–3%/yr" was too low — corrected here).
- **Annual PD decline ≈ 1.24 cm/s/yr** (6-yr cohort), up to **3.4–4 cm/s/yr** in early PD; ~2%/yr in early-stage step metrics. Over multiple years this accumulates well past the MCID — so a *flat-to-positive* multi-year slope is genuinely reassuring, not noise.
- **Worked example (Bhav, Jul 2026 — computed from the Jul 6 CSV export, `walking_speed_m_s`, foreign-device samples excluded):** 71 monthly medians, 5.83 y span, baseline 1.001 m/s. Slope **+0.70 cm/s/yr** (SE 0.39, t=1.8 — *not* significant, which is exactly why the presence gate capped this card at Emerging). Total change **+4.10 cm/s (+4.1%)**, lower bound −0.4 cm/s. Own detectable margin **0.045 m/s < MCID 0.060** ⇒ this user can resolve a clinically meaningful change, so the MCID binds. Non-inferiority: t = (0.041+0.06)/0.0225 ≈ **4.5**, one-sided p ≈ **1.4e−5** → **Strong**. ✅ reproduces the shipped card's +4%.
  - 🔎 **Device contamination — resolved Jul 14, and a lesson.** A first pass over the same export computed **+0.8%** and contradicted the card's +4%. Cause: the export pools **all** HealthKit sources, and `Japnit kaur's iPhone` — another person's device — contributed 6,631 walking-speed samples concentrated in **2020–22**, the earliest part of the record, where foreign data pivots a multi-year slope hardest. The app was right: it filters gait to the user's own devices (`GaitSourceInfo`, the "which devices are yours?" review), and excluding that source reproduces +4.1% exactly. **Any offline analysis of a HealthKit export must apply the same device filter the engine applies, or it is analysing a household, not a patient.** The device-review feature is load-bearing for correctness, not a nicety.

Each *other* absence family (tremor vs food/exercise, etc.) needs its own MCID floor sourced the same way (published MID for the outcome), with the per-user margin computed from that user's own data. TODO as each renderer is built.

Sources:
- Hass et al., *Defining the Clinically Meaningful Difference in Gait Speed in Persons with Parkinson Disease*, JNPT 2014 — https://pubmed.ncbi.nlm.nih.gov/25198866/
- *Minimal Clinically Important Differences of Spatiotemporal Gait Variables in PD*, 2023 — https://pubmed.ncbi.nlm.nih.gov/38150946/
- *Gait Progression Over 6 Years in Parkinson's Disease*, Frontiers 2020 — https://pmc.ncbi.nlm.nih.gov/articles/PMC7593770/
- *Progressive Gait Deficits in PD: a Wearable-Based 5-Year Study*, Frontiers 2019 — https://pmc.ncbi.nlm.nih.gov/articles/PMC6381067/

## Decisions

1. ✅ **Option A**, as **one-sided non-inferiority** (not the two-sided equivalence first written), margin = **the clinical MCID** (not `max(own, MCID)` — circular). Both corrected Jul 14; rationale in the sections above. Option B (precision-only, direction-agnostic) was dropped: it rates "confidently flat" and "confidently mild-effect" the same.
2. ✅ **Reassurance verdicts:** **wearing-off YES** ("your doses last long enough" — a PD patient wants to know their meds still last); **afternoon-dose NO** (uniform dose speed is too abstract to be worth a card). Neither built.
3. ⬜ Per-family MCIDs still to source as each renderer is built (gait done; tremor-change MID for food/exercise TODO — start with one shared line). **This is what blocks `windowedEffectGate`** — it's a research question, not a coding one.
4. ⬜ Sequencing: `gaitTrendGate` ✅ done Jul 14; `windowedEffectGate` still open (blocked on 3); dormant renderers adopt the branch when built.
5. ✅ Bhav's own-data gait margin computed — **0.037 m/s, so the MCID binds**. See the worked example above.

## What shipped (Jul 14 2026)

`CorrelationEngine.swift`:
- `linregress` now also returns **`slopeStdErr`** — the note claimed the SE was "in hand", but it was never surfaced; nothing downstream could see it.
- **`nonInferiorityP(change:stdErr:margin:df:)`** — one-sided p for "a decline ≥ margin is ruled out". Reuses the existing `regularizedIncompleteBeta`.
- **`GaitMetric.mcid`** — 0.06 m/s for walking speed, `nil` for the other three (no sourced PD value yet ⇒ they can't drive an absence claim).
- **`MetricTrend`**: `slopeStdErr`, `orientedChange` (better-is-positive, so one test serves metrics that worsen in opposite directions), `ownDetectableMargin`, `canResolveMCID`, `noDeclineP`.
- **`gaitInsight`** branches on the verdict: `declining ? speed.pValue : speed.noDeclineP` → same `gaitTrendGate`, same tiers.

`GaitConfidenceTests.swift` — 8 tests, synthetic, deterministic. Pins: the origin case (long flat → Strong), improvement not penalised (the one-sided point), noisy → Emerging (the circularity regression), real decline → presence branch, margin never noise-scaled, and `nonInferiorityP` against the hand-computed Jul 2026 figures.

Related: `feedback_no_arbitrary_thresholds`, `observation_accuracy`, `docs/intelligence-architecture.md` (engine-judges layer). **Next project (Bhav, Jul 13):** build out all dormant renderers so any valid correlation lights up as soon as it's earned — the "delightful secret sauce." Scope after this confidence work lands.
