# Confidence: presence vs. absence claims

**Status:** design note, nothing built. Origin: Jul 13 2026 — the gait "Your mobility hasn't declined" card reads *Emerging* despite 5.8 years / 71 monthly medians, because a flat slope can't be statistically significant.

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
| **Absence / stability** ("no decline", "no clear effect") | **equivalence** — rule out a *meaningful* effect | precision: a tight interval that excludes the meaningful-effect margin |

Equivalence uses the estimate's confidence interval (already derivable — the p-value comes from the same t-test, so the standard error is in hand). "Confidently flat" = interval narrow and sitting inside the no-meaningful-effect zone → Strong. Wide interval (thin/noisy data) → can't establish equivalence → stays Emerging. It degrades gracefully.

**The one cost:** each absence claim needs a *meaningful-effect margin* (minimal important difference) — e.g. "a gait decline rate that would actually matter," "a tremor change worth noticing." Anchor each to functional meaning and state it explicitly; not a tuned knob. This is real work but it's the right work — those margins are worth defining regardless.

**Why this matters more than presence:** an n-of-1 app testing many plausible-but-mostly-inert hypotheses will have **most cards resolve to nulls**. Absence-confidence is the common case, not the edge.

## Inventory — every gate / renderer today

Live = renderer built and shipping. Dormant = registered, renderer `nil`, will inherit the fix when built.

| Renderer / gate | Cards | Null path today | Verdict |
|---|---|---|---|
| **gaitComposite** / `gaitTrendGate` | gait "hasn't declined" | *Emerging* on a flat slope | **AFFECTED** — origin case; the absence *is* the finding |
| **windowedEffect** / `windowedEffectGate` | caffeine, sugar, all exercise (tai-chi, boxing, yoga, cycling, walking, strength, table-tennis, pickleball, tango, climbing), mindfulness, dyskinesia-peak | floor is `minN:5` with **no p** → null shows as *Emerging* regardless of how confidently no-effect | **AFFECTED** — a matured "no effect" (e.g. caffeine over 18 servings) is capped at Emerging, same as at 5 servings |
| **doseResponse** / `doseResponseGate` | afternoon-dose onset | floor needs `minEffect:15` → a null (small effect) clears nothing → **hidden**, not shown | Different: absence = silence, not a mislabeled card. Question worth raising: is "your dose speed is uniform" a reassurance we're dropping? |
| **wearingOff** / `wearingOffGate` | doses wear off early | n-only gate; presence-shaped, always fires | Presence-only. **Gap:** no absence verdict ("doses last as long as your gaps — no wearing-off") is produced today |
| **doseResponseByTimeOfDay → circadianBaseline** | when control is weakest | dormant (renderer nil) | Descriptive, not presence/absence — likely N/A |
| **overnightLag** (sleep dur/deep → next-day) | dormant | — | Will be AFFECTED when built (same null trap as windowedEffect) |
| **withinDayAssociation** (HRV ↔ tremor) | dormant | — | Will be AFFECTED when built |
| **mealTimingCompetition** (protein / meal-fullness → onset) | dormant | — | Will be AFFECTED when built |

**Active blast radius today:** gait + the entire windowed-effect family's null branch. Everything else is either presence-only, silent-on-null, or dormant (inherits the fix at build time).

## How the meaningful-effect margin is calculated (methodology + citations)

An equivalence test needs a **margin** = the smallest change that counts as "real." How we set it, and where the numbers come from (this is the reference for "how were these percentages calculated?"):

**Rule: margin = max( the user's own detectable margin, the clinical MCID ).** Take the *stricter* (larger) of two floors:

1. **The user's own detectable margin — per-user, on-device, from their own data's noise.** Derived from the month-to-month scatter in *that user's* measurements (≈ the confidence-interval half-width on their own slope / a multiple of their residual SD). A change smaller than a user's own measurement wobble is undetectable *for them*, so it can't be claimed. **Never** compute this from anyone else's data — it is statistically wrong (everyone's scatter differs) and it is the privacy line we've already drawn (no raw cross-user data leaves the device). One margin per person, self-calibrating, local. This is the elegant, threshold-free anchor — no invented number.
2. **The clinical MCID — a published floor, same for everyone.** MCID = *minimal clinically important difference*: the smallest change studies find a clinician/patient actually calls meaningful. It stops us flagging a sub-clinical wiggle just because a very clean dataset *can* resolve it.

Why `max`: if the user's data is **noisy**, their detectable line exceeds the MCID → we honestly can't resolve clinically-meaningful change yet (don't overclaim). If their data is **clean/long**, their line is below the MCID → the MCID becomes the floor (don't flag sub-clinical noise). The published constant is a **cross-check and floor**, never a replacement for the personal margin — this keeps every claim both personalized *and* research-defensible. The two are *not* expected to coincide; taking the stricter is the point.

**Grounding numbers (gait speed, Parkinson's):**
- **MCID for gait speed ≈ 0.06 m/s** (small; moderate 0.14, large 0.22) — Hass et al., n=324 PD; a 2023 re-analysis lands ~0.082 m/s. At a typical PD speed ~1.0–1.1 m/s that's **~5–6% of baseline** (so an early hand-wave of "2–3%/yr" was too low — corrected here).
- **Annual PD decline ≈ 1.24 cm/s/yr** (6-yr cohort), up to **3.4–4 cm/s/yr** in early PD; ~2%/yr in early-stage step metrics. Over multiple years this accumulates well past the MCID — so a *flat-to-positive* multi-year slope is genuinely reassuring, not noise.
- **Worked example (Bhav, Jul 2026):** 71 monthly medians → own detectable margin is small → the **MCID (~5–6%) is the binding floor**; slope flat-to-+4%, well inside "no meaningful decline," tight interval → **confidently Strong** under Option A.

Each *other* absence family (tremor vs food/exercise, etc.) needs its own MCID floor sourced the same way (published MID for the outcome), with the per-user margin computed from that user's own data. TODO as each renderer is built.

Sources:
- Hass et al., *Defining the Clinically Meaningful Difference in Gait Speed in Persons with Parkinson Disease*, JNPT 2014 — https://pubmed.ncbi.nlm.nih.gov/25198866/
- *Minimal Clinically Important Differences of Spatiotemporal Gait Variables in PD*, 2023 — https://pubmed.ncbi.nlm.nih.gov/38150946/
- *Gait Progression Over 6 Years in Parkinson's Disease*, Frontiers 2020 — https://pmc.ncbi.nlm.nih.gov/articles/PMC7593770/
- *Progressive Gait Deficits in PD: a Wearable-Based 5-Year Study*, Frontiers 2019 — https://pmc.ncbi.nlm.nih.gov/articles/PMC6381067/

## Options (recap)

- **A — Equivalence (recommended).** Absence verdict → confidence = how firmly the interval rules out the meaningful-effect margin. Directly answers the card's actual claim; rewards a long stable record. Cost: one margin per absence family.
- **B — Precision-only.** Confidence = how tightly the trend is pinned, direction-agnostic; existing title carries direction. No margin to pick (more threshold-free), but rates "confidently flat" and "confidently mild-effect" the same on the dots.

## Decisions (Jul 13 2026)

1. ✅ **Option A (equivalence).** Margin = `max(user's own detectable margin, clinical MCID)` — see methodology section.
2. ✅ **Reassurance verdicts:** **wearing-off YES** ("your doses last long enough" — a PD patient wants to know their meds still last); **afternoon-dose NO** (uniform dose speed is too abstract to be worth a card).
3. ⬜ Per-family MCIDs still to source as each renderer is built (gait done above; tremor-change MID for food/exercise TODO — start with one shared line).
4. ⬜ Sequencing: fix `gaitTrendGate` + `windowedEffectGate` now (live surfaces); dormant renderers adopt the branch when built.
5. ⬜ Compute Bhav's actual own-data gait margin (needs a HealthKit/backup export) and check it vs the 0.06 m/s MCID — confirm which floor binds.

Related: `feedback_no_arbitrary_thresholds`, `observation_accuracy`, `docs/intelligence-architecture.md` (engine-judges layer). **Next project (Bhav, Jul 13):** build out all dormant renderers so any valid correlation lights up as soon as it's earned — the "delightful secret sauce." Scope after this confidence work lands.
