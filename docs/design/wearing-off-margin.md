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

## ⬜ Open: sleep clipping (replaces the 600-minute cap) — DESIGN AGREED, not built

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

### Open questions before building

1. **Does HealthKit record naps at all?** Apple's sleep tracking is built around a scheduled sleep window. If a 3pm nap isn't recorded, the mechanism silently doesn't fire for it. **Verify — do not assume** [[feedback_verify_before_recommending]].
2. **`inBed` vs `asleep*`.** Use `asleepCore/Deep/REM` only — lying in bed awake with tremor is real OFF.
3. **`maxWindow = 300` is untouched by this** and breaks the same once-daily scenario independently: a long-acting dose censors at 5 h and KM never resolves.

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
