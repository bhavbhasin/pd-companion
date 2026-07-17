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

## ⬜ Open: the 600-minute cap hides 26% of days

`intervalMin < 600` (`CorrelationEngine.swift:1048`) stands in for "daytime". **18 of Bhav's daytime gaps exceed it** (largest 1207 min) — days he skipped the evening dose. They're dropped whole, so the card sees no evening OFF at all on 26% of days. Removing the cap → **389 min/day**, but that's wrong too: those gaps run overnight and would credit sleep as OFF.

**Fix = clip a gap at a real daytime boundary instead of dropping it** (a 3:30pm dose would contribute its 3:30→20:00 shortfall). Lands between 234 and 389. Deferred — separate decision from the estimator, needs the boundary chosen on data, not in the abstract [[feedback_no_arbitrary_thresholds]].

## Decisions

1. ✅ Margin = **60 min/day of OFF** (published MCID, not tuned).
2. ✅ **Switch the estimator** to `Σ max(0, gap − duration)`, per day, averaged over dosed days. Medians demoted to descriptive copy.
3. ✅ **DROPPED** — no scheduled-vs-as-needed split, no drug dictionary. The estimability gate already is the classifier.
4. ✅ `wearingOffGate` gets an effect axis (`minEffect` = the MCID). Firing condition becomes "≥ 60 min/day uncovered", replacing `medianGap > medianDuration`. The `?? .moderate` fallback that defeated the gate is removed.
5. ✅ `gapH`/`durH` precision mismatch fixed (one formatter; `%.0f` was printing a 4.14 h gap as "~4 h").

## Consequence for the Desai email

The draft cites *"a median of 193 minutes against daytime gaps of about four hours."* True but understating. The honest sharper version: **dose spacing leaves ~234 min/day uncovered, 64% of it from the afternoon doses.** Send only once the card shows it. [[project_kampa_apple_outreach]]
