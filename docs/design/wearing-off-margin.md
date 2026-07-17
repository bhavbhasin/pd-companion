# Wearing-off: margin + the estimator defect

**Status:** decisions resolved Jul 16 2026; estimator switched in code. Numbers below recomputed on the `07-16-2026` export (May 9 – Jul 15, **246 taken doses, 68 days**).

## TL;DR

The card compared **median gap** to **median ON-duration**. That estimator understates daily OFF ~2×. Replaced with **`Σ max(0, gap − duration)` per day, averaged over days**.

## The margin (settled)

**MCID for daily OFF time = 60 min/day.** Verified Jul 14: −1.0 to −1.3 h in the pramipexole IR/ER pivotal trials; take the stricter end.

- Sources: [Hauser et al. (PMC3995302)](https://pmc.ncbi.nlm.nih.gov/articles/PMC3995302/) · [PubMed 24800101](https://pubmed.ncbi.nlm.nih.gov/24800101/) · [Neurol Ther 2022](https://link.springer.com/article/10.1007/s40120-022-00435-8)
- Work in **daily OFF minutes** — the unit the MCID is defined on.

## The estimator defect

Two medians can't see one catastrophic gap: a day with three fine gaps and one terrible one has the same median as a day of four mediocre ones. Bhav's OFF is concentrated — **64% of the shortfall comes from doses at 14:00–16:00**.

| estimator | value | vs 60 min/day MCID |
|---|---|---|
| median gap (249 min) − median ON (192.5 min) = 56 min/dose × 2.19 daytime gaps/day | **123 min/day** | above |
| **`Σ max(0, gap − duration)`** (chosen) | **234 min/day** | above (3.9×) |

## ⚠️ Corrections to this doc's first version (Jul 14 → Jul 16)

The Jul 14 numbers were computed from an ad-hoc script that **counted `notInteracted` rows (untouched reminder slots) as doses**. The engine filters `logStatus == .taken` (`HealthKitManager.swift:735`); the script didn't. Phantom doses close gaps ⇒ every gap-derived number was too small.

1. **"32 Mucuna doses" → 16 taken** (+16 phantom) in the Jul 6 export; 18 taken in the Jul 15 export.
2. **Median gap 210 min → 249 min.** This drove per-dose shortfall 17 → 56 min, a 3.3× error.
3. **RETRACTED: "median-vs-median hands him a reassurance card below the MCID."** False. Corrected, median-vs-median = **123 min/day, above the MCID**. It understates (~2×) and can't see concentration — that justifies the switch — but there is **no false-reassurance failure** on real data. Do not carry that claim anywhere.
4. Also false in framing: the card could never have *silently reassured* — `wearingOffInsight` returned nil when median gap ≤ median duration. The absence twin doesn't exist yet.

## Per-formulation stratification = **no-op on Bhav's data**

Charging each gap against its own formulation's duration yields **234.4 min/day — identical to pooled, to the decimal.** Sinemet is 228/246 doses, so pooled KM *is* Sinemet's KM (both 192.5 min); Mucuna (KM 152.5) is n=18, under the `>= 20` bar, so it falls back to pooled. Still correct architecturally for a genuinely mixed regimen (Rytary + Sinemet); buys nothing here. Don't sell it as part of this fix.

## Medication type — resolved, simpler than feared

**No schedule classification, no drug dictionary.** The engine already classifies substances *empirically*: `estimableFormulations` (`CorrelationEngine.swift:174-191`) admits anything showing a real dose→ON→OFF pulse, excludes confirmed non-pulsatile substances at ≥20 doses, and gives thin ones benefit of the doubt. Line 182: *"The gate is the classifier (measured per-user), not a drug dictionary."* This handles Ayurvedic supplements a drug database has never heard of — strictly better than RxNorm (`HKMedicationConcept.relatedCodings`) or an as-needed/scheduled split (`HKMedicationDoseEvent.scheduleType`), both of which were investigated and dropped.

## ✅ Sleep clipping (replaced the 600-minute cap) — BUILT + device-verified Jul 16

### Plain-language statement of the problem (start here)

> **The problem.** The card adds up how much of your day your medication isn't covering. To avoid counting sleep as OFF time, it throws away any gap between doses longer than 10 hours. But it throws away the *whole* gap, not just the sleeping part.
>
> Two things break:
> - On 26% of Bhav's days he skips the 10pm dose. The gap runs 3:30pm to 8am, exceeds 10 hours, gets discarded — so the entire evening vanishes from the count.
> - Someone on one pill a day has a 24-hour gap. Always discarded. **They get no card at all**, despite having the worst wearing-off.
>
> **The solution.** Stop throwing away long gaps. Instead, subtract just the part the user was actually asleep for, and keep the waking part. A skipped-evening day contributes 3:30pm to bedtime — real OFF they lived through.
>
> **The second half.** The same sleep data fixes a related thing. When you sleep, tremor drops to zero — because you're asleep, not because the drug is working. The engine sees flat tremor after the 10pm dose and concludes it worked for five hours. So doses look longer-lasting than they are (192.5 min pooled, vs 182.5 daytime-only). Fix: stop measuring a dose once the user falls asleep, and record that we simply don't know what happened after.
>
> **One sleep signal, two uses. Subtract it from gaps. Stop the clock on durations.**
>
> If a user has no sleep data, assume awake 6am–10pm.

### The defect

Two invented numbers stand in for "was he awake?": `intervalMin < 600` and `hour >= 6 && hour < 20` (`CorrelationEngine.swift:1048`). Both drop a gap **whole** rather than clipping it.

- **18 of Bhav's 68 days (26%)** exceed the cap (largest 1207 min) — evenings he skipped the 10pm dose. The entire evening's OFF is invisible.
- **A once-daily regimen gets NO card at all**: 24 h gap → over the cap → dropped → zero uncovered → gate can't fire. The patient with the *most* wearing-off is told nothing. This is the scenario that makes it a real bug, not a Bhav quirk.
- Removing the cap → **389 min/day**, also wrong: it credits sleep as OFF, and the 60 min/day MCID is defined on **waking** OFF (trial diaries). The number would lose its benchmark.

### The design

For each gap, take the uncovered part (dose + duration → next dose), **subtract any overlap with measured sleep**, sum per day, average over dosed days. Both magic numbers disappear — sleep defines the boundary, not a clock.

- Overnight gap: almost all sleep → contributes ~0. No cap needed to exclude it.
- Skipped evening dose: the dose→bedtime part counts. Today discarded whole.
- Once-daily: only the waking part counts. Card fires.
- **Nap (e.g. 3–4pm): no special case** — it's a sleep interval, subtracted like any other.

### ⚠️ Sleep must come out of BOTH sides, not just the gap

Bhav's tremor is ~0 from 1am–6am (median 0.00; <4% of readings above the OFF line) — parkinsonian rest tremor abates in sleep regardless of drug state. So `survivalDuration` looking 300 min past a 10pm dose **never sees OFF-return** and records the dose as still working:

| doses | KM duration | censored |
|---|---|---|
| all (engine today) | 192.5 min | 31% |
| daytime only | 182.5 min | 15% |
| evening/night | **won't resolve** | 67% |

Evening doses are **67% censored by sleep**, and pooling them inflates the duration 182.5 → 192.5 min. A nap does the same on a smaller scale. If sleep is subtracted from the gap but left inside the survival window, the nap is removed from the gap while simultaneously inflating the duration being subtracted from it — inconsistent, and partly self-cancelling so it hides.

### Fallback when there is no sleep data — **fallback ONLY**

Many users won't wear the Watch overnight; without a fallback they'd get silence. Clip to **06:00–22:00**.

- **Why 22:00, not 20:00:** 20:00 was never chosen — it was inherited from the existing filter. Bhav's own 10pm dose proves he's awake then; on a skipped-evening day, clipping at 20:00 counts 1.3 h of the uncovered stretch vs 3.3 h at 22:00.
- **Deliberately conservative**, not accurate: typical adult bedtime ~10:30–11pm, PD often earlier ⇒ 22:00 slightly *under*counts. Right direction to err for a health claim.
- **⚠️ 22:00 is wrong for Bhav specifically** — his worst hours are 20:00–23:00 (73% OFF at 21:00, 68% at 22:00) and sleep onset looks like ~midnight (36% OFF at 00:00, 15% at 01:00, 4% by 02:00). He is a night owl. This is not an argument to move the constant; it's the argument that anyone with sleep data must never touch the fallback.
- **Rejected: deriving the window from the user's own dose times.** If the last dose marks "still awake", skipping the 10pm dose closes the window at 3:30pm — erasing the exact evening the skip created. Self-defeating.

### Resolved on real data (Jul 16, offline run before any Swift)

1. ✅ **HealthKit DOES record naps.** Verified on Bhav's device: a 3pm nap appears as Core sleep; Apple's own Sleep app shows *"ASLEEP 44 min, 4:08–4:52 PM"* as its own block. Question closed.
2. ✅ **`asleep*` only, never `inBed`** — settled empirically by that nap. Bhav lay down ~3:00 but Apple detected sleep only from 4:08. That first hour he was awake with real tremor. Subtracting `inBed` would erase an hour of genuine OFF. Sleep-stage counts in-window: asleepCore 961 · awake 492 · asleepDeep 299 · asleepREM 254 · asleepUnspecified 154 · inBed 87.
3. ✅ **Night interruptions work correctly.** An awake segment (e.g. wake 2:00–2:30am, take a rescue dose, back to sleep) is NOT subtracted, so the OFF that drove the rescue is counted. Strongest case for `asleep*`-only.
4. ✅ **Sleep coverage is complete** — all 68 dosed days have >60 min recorded, median 408 min (6.8 h). The fallback would not have fired for him at all.
5. ✅ **Evening dose needs no hour filter.** The 10pm dose covers to ~1am, he's asleep from 11:25 ⇒ contributes 0. Stay up to 2am and it correctly counts the last hour. **Both magic numbers really can go.**
6. ⬜ **`maxWindow = 300` is untouched by this** and breaks the same once-daily scenario independently: a long-acting dose censors at 5 h and KM never resolves.

### As built

Card now reads **"Your doses leave about 8.3 hours a day uncovered"** (device-verified: 495 min/day, dose duration 178 min — against the Python oracle's 501.7 / 177.5 predicted before any Swift existed).

**⚠️ The two uses of sleep take DIFFERENT inputs. This was NOT in the agreed design — the parity test surfaced it.**

- **Censoring a duration uses MEASURED sleep only.** Censoring discards a real observation, so it must never rest on a guess. The fallback claims "asleep at 22:00" for a patient who demonstrably took a dose at 22:00 — taking a pill is evidence of being awake. Guessing here dropped **35 of 106 doses** off the parity fixture's curve. With no measured sleep we simply don't censor.
- **Subtracting from a gap uses EFFECTIVE sleep** (measured + a conservative 22:00–06:00 night for days with none). Erring conservative on a *sum* is safe in a way that erring on a *measurement* is not. Without it, removing the cap would score a whole unconscious night as waking OFF.

Fallback path yields **483** vs 502 measured — it under-claims, by design (22:00 is early for Bhav, and nothing is censored so doses read longer-lasting).

Copy contract: **title = hours** (a glance shouldn't need dividing by 60), **finding = precise minutes + method + provenance**, **bullets = the clinician's numbers**. The summary prints **ONE** number deliberately — it used to read "doses hold ~3.0 h but your daytime gaps run ~4.1 h", inviting a subtraction that lands on ~2 h against a headline of 8.3. Most of the total comes from gaps that aren't daytime gaps at all (before the first dose, after the last), so no pair of medians can reconcile with it.

Tests: `SleepClippingTests` (oracle vs Python on the real backup, + nap / night-interruption / once-daily / evening-dose / fallback / never-censor-on-a-guess). Python-lab parity untouched.

### Measured result of the full design (offline, 69 days)

| variant | KM duration | result |
|---|---|---|
| shipped (`4911ce6`) | 192.5 min | 234.4 min/day |
| sleep-subtracted gaps only | 192.5 min | 488.2 min/day |
| sleep-censored duration only | 177.5 min | 260.5 min/day |
| **FULL DESIGN (both)** | **177.5 min** | **501.7 min/day** |

Most of the jump is NOT the skipped-evening days — it's the **normal-night morning gap**. 10pm dose → asleep 11:25 → wake 7am → dose 8am is a 600-min gap, excluded today by *both* the cap and the hour filter. Under the new rule it contributes the 7–8am waking stretch on **most days**, not rare ones. (Bhav's hour 7 = 21% OFF, hour 8 = 47%.)

### ⬜ KNOWN LIMITATION: uncovered ≠ OFF (Bhav's retreat case)

**The card models uncovered time; it never checks whether the patient was symptomatic.** Uncovered = gap − pooled KM duration − sleep. It knows when the drug was gone. It does not know how you felt.

**The case that breaks it (Bhav, Dec 2025 — Joe Dispenza retreats, OUTSIDE the current 69-day record):** one dose, taken before sleep, covering a 24h period; meditation carried the day. The card would announce **~16 h uncovered** on a day he was fine. Two consequences:

1. **Never let the observation window run unbounded** to "fix" the once-daily case. On that retreat the engine would have watched tremor stay low for 20 h and recorded *"this dose held for 20 hours"* — crediting levodopa with what meditation did. The retreat is the strongest argument **for** a plausibility bound, not against one. Related: the known "low tremor ≠ medicated" gap [[project_kampa_tremor_smoothing]].
2. The copy says *"predictable OFF"*. True on an ordinary day, false on a retreat day.

**Candidate design — count the INTERSECTION:** minutes where no drug was on board **AND** tremor was actually above the OFF line. Retreat day → ~0. Ordinary day → unchanged. A dose that fails outright (absorption/protein) → tremor high *during* coverage → correctly NOT blamed on spacing (that's the afternoon-dose card's territory).

**⚠️ But do not oversell it — Bhav's objection is correct and decisive.** The two conditions are **not independent instruments**: "drug gone" is *defined* as t0 + the median tremor-crossing time, so both halves derive from the same tremor signal. The only genuinely independent ingredient is the **clock** (minutes since the dose, from the dose log); the lone tremor-derived term is the constant 178. So the intersection is a model checked against the data it was fitted on — it catches only where the median's extrapolation fails on a given day.

**On Bhav's data it would be ~a no-op**, and this explains the 502-vs-486 agreement properly: they coincide at threshold 1.0 because once his drug wears off his tremor reliably sits above 1.0 for the rest of the gap. At 2.0 they diverge (470 vs 262) — post-wear-off tremor is often above 1.0 but below 2.0. The agreement is a real finding about him, not a tautology, but it also means the intersection buys him nothing.

**Verdict: log, don't build.** Robustness for edge cases and other patients (retreat-like days, wildly varying doses, patients whose tremor doesn't clear the line when unmedicated), not a correctness fix today. ⚠️ Real cost if ever built: the model needs only the dose log; the intersection needs tremor coverage. Bhav's watch covers ~933 waking min/day of ~16-17 h, so unmonitored minutes would score as "not OFF" — silence that looks like an answer, the same class of defect as the 600-min cap. It would need an explicit unmonitored bucket.

**The interesting half:** the *difference* between the two (drug gone, patient fine anyway) is a signal in its own right — small on an ordinary day, the whole day on a retreat. That is where a meditation/lifestyle effect would surface, from data already collected, without new logging. A different route to [[project_kampa_mindfulness]]'s dormant question: not "does meditation lower my tremor" (needs many sessions) but "which days was my drug absent and I was fine, and what did they share?"

### The OFF threshold does NOT block this — tested, ~6% swing

An earlier revision of this note claimed `offThreshold` was "the dominant term" and blocked shipping. **That was wrong** — it ran the sensitivity on *direct measurement* and asserted the same of the design without testing it. Bhav caught it. Measured:

| OFF line | KM duration | **design** | direct measure |
|---|---|---|---|
| 0.75 | 177.5 | **501.7** | 528.3 |
| **1.00 (engine)** | 177.5 | **501.7** | 485.7 |
| 1.25 | 177.5 | **501.7** | 422.2 |
| 1.50 | 182.5 | **490.8** | 376.8 |
| 2.00 | 192.5 | **470.2** | 262.2 |

**The design moves 502 → 470 across a 2.7× threshold change — 6%.** The threshold is self-cancelling here: raise the line and the dose reads longer-lasting, which shrinks uncovered time by the same stroke. And it isn't the driver anyway — Bhav's gaps (390–600 min) dwarf his dose duration (~180 min), so a 15-min shift in duration can't move a 400-min shortfall. **1.0 stands; the design is unblocked.**

Also retracted: the claim that design-vs-direct agreement at 1.0 is "by construction." If it were, they'd agree at *every* threshold — they diverge hard at 2.0 (470 vs 262). They measure genuinely different things (time without effective coverage vs time above a severity line); landing close at 1.0 is a real result.

**Still true, but scoped elsewhere:** the felt-vs-measured calibration [[project_kampa_tremor_smoothing]] matters for surfaces where the threshold is *labelled* — the forecast bar's ON/OFF wording, the chart's severity words — because those must match what the patient feels. It does not touch this card's arithmetic.

⬜ Unchecked: design and direct measurement agree on the 69-day **average**; day-by-day agreement was never tested.

### Cost

Not free. `fetchSleepHours` (`HealthKitManager.swift:198`) reduces sleep to a **scalar** (hours) — needs a fetch that keeps intervals [[feedback_preserve_raw_sensor_data]]. And `run()` receives tremor, doses, gait, workouts, food — **no sleep at all**; it must be plumbed through. Result lands between 234 (drop) and 389 (count all).

### Not covered by this change

The calc measures **dose-to-dose** gaps only, so waking OFF **before the first dose** (e.g. 06:00 wake → 08:00 dose) is invisible either way. Separate question.

## Decisions

1. ✅ Margin = **60 min/day of OFF** (published MCID, not tuned).
2. ✅ **Switch the estimator** to `Σ max(0, gap − duration)`, per day, averaged over dosed days. Medians demoted to descriptive copy.
3. ✅ **DROPPED** — no scheduled-vs-as-needed split, no drug dictionary. The estimability gate already is the classifier.
4. ✅ `wearingOffGate` gets an effect axis (`minEffect` = the MCID). Firing condition becomes "≥ 60 min/day uncovered", replacing `medianGap > medianDuration`. The `?? .moderate` fallback that defeated the gate is removed.
5. ✅ `gapH`/`durH` precision mismatch fixed (one formatter; `%.0f` was printing a 4.14 h gap as "~4 h").

## Consequence for the Desai email

The draft cites *"a median of 193 minutes against daytime gaps of about four hours."* True but understating. The honest sharper version: **dose spacing leaves ~234 min/day uncovered, 64% of it from the afternoon doses.** Send only once the card shows it. [[project_kampa_apple_outreach]]
