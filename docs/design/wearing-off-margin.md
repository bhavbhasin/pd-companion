# Wearing-off: margin + the estimator defect

**Status:** design note, NOTHING BUILT. Jul 14 2026. Started as "pick a margin for the wearing-off reassurance verdict" ([[confidence-presence-vs-absence]] decision 2); the margin turned out to be the easy part. **Open decision at the bottom — needs Bhav.**

## TL;DR

The card compares **median gap** to **median ON-duration**. That estimator is wrong, and it **understates Bhav's wearing-off by ~3–4×**. Fix the estimator before the margin means anything.

## The margin (settled)

**MCID for daily OFF time = 1.0 h/day.** Verified Jul 14 (not recalled): −1.0 to −1.3 h in the pramipexole IR/ER pivotal trials; a 1.0–1.3 h/day threshold is the accepted line for a patient-perceptible change. Take **1.0 h = 60 min/day**, the stricter end.

- Sources: [Hauser et al., MCID in PD — pramipexole ER pivotal trials (PMC3995302)](https://pmc.ncbi.nlm.nih.gov/articles/PMC3995302/) · [PubMed 24800101](https://pubmed.ncbi.nlm.nih.gov/24800101/) · [Off-time treatment options review, Neurol Ther 2022](https://link.springer.com/article/10.1007/s40120-022-00435-8)
- **Work in daily OFF minutes, not per-dose shortfall.** The MCID is defined per day. Converting it to a per-dose margin (÷ gaps/day → ~21 min/dose for Bhav) is arithmetically fine but throws away the concentration structure that turns out to be the whole finding.

## The estimator defect (the real one)

Bhav's schedule is **rough, not fixed**: Sinemet ~8am / 11:30 / 3:30pm / 10pm. So his daytime gaps are **3.5 h, 4 h, and 6.5 h** — against a ~3.2 h dose. Two gaps are near-fine; the 3:30pm→10pm gap is catastrophic. **Two medians cannot see this**: a day with three fine gaps and one terrible one has the same median as a day of four mediocre ones.

Daily OFF attributable to spacing, computed from the Jul 6 dose export (`medication_doses_2026-05-09_to_2026-07-06.csv`, 59 days, ON-duration = the engine's KM median 193 min):

| dose set | median gap | median−median est. | **Σ max(0, gap − duration)** | vs 60 min MCID |
|---|---|---|---|---|
| pooled (engine today) | 210 min | 52 min/day | **238 min/day** (4.5×) | (A) below · (B) **ABOVE** |
| Sinemet only | 225 min | 95 min/day | **258 min/day** (2.7×) | (A) above · (B) **ABOVE** |

- **~60% of the OFF comes from gaps starting 2–4pm** — the 3:30pm→10pm stretch. Matches the afternoon/evening OFF clustering already on the card (60–70%).
- On the median estimator the **pooled** reading lands *below* the MCID → he'd get a **reassurance card while spending ~4 h/day OFF**. That is the failure mode to design against.
- ⚠️ (B) assumes ON-duration is exactly the KM median every time; real durations vary. It's an estimate, not measured OFF — see "Route B" below.

## Medication type matters — three distinct ways

Bhav's Mucuna is **PRN**, confirmed in his words: *"whenever I need that extra boost… could be the afternoon, could be 3am when I wake up and can't sleep and don't want another Sinemet."* Data agrees: 32 doses on 28 of 59 days, almost always exactly one.

1. **Durations differ** → a pooled KM median describes neither formulation. `wearingOffInsight` already computes per-formulation rows, but they only enrich the **copy** — the pooled curve still drives the **firing gate + the chart**. Live mixed-regimen trust bug. [[project_kampa_lever_audit]]
2. **Gap semantics** → a PRN pill isn't part of the *schedule*, but the gap calc counts every dose. Pooling shortens apparent gaps (3.50 h vs 3.76 h Sinemet-only) and **understates** the shortfall (+17 vs +32 min/dose).
3. **A PRN dose is an OUTCOME, not an input** ← the deep one. It's evidence the schedule already failed; the engine treats it as part of a schedule that's working. The KM duration measured *from* a rescue dose also starts from an OFF state, so it isn't the same quantity as a scheduled dose's. A 3am rescue is itself a signal worth surfacing.

## Also found (cheap, unrelated to the above)

- 🔴 **`wearingOffGate` has no effect-size axis.** `GateSpec(strong: GateBar(minN: 40), …)` — n only. It fires **Strong** on *any* shortfall above zero given enough doses, never asking whether it matters. Same bug family as gait: the gate doesn't ask the card's question. The margin here is needed by the **presence** card, not just the reassurance twin.
- 🟡 **Rounding exaggerates the gap.** `gapH` = `%.0f` vs `durH` = `%.1f` (`CorrelationEngine.swift`, in `wearingOffInsight`) → a 3.5 h gap prints "**~4 h**" against "~3.2 h", showing a ~48 min shortfall where the median is ~17. Mixed precision on the two halves of the same comparison.

## Route B (considered, not chosen — revisit)

The app **measures** tremor every minute, so it could compute **observed** daily OFF minutes directly (tremor ≥ `offThreshold`) and test that against the 60 min/day MCID — n = days, plain t-test, no KM variance, and it's the exact quantity the literature defines. Rejected for *this* card because it answers a different question: "you're not spending meaningful time OFF" ≠ "your doses last as long as your gaps" (a patient could have low OFF because their disease is mild), and measured OFF includes OFF from causes other than spacing. Worth its own card later.

## Engineering note

Absence here is **not** a cheap port of the gait fix. Gait had an OLS slope with a closed-form SE; this estimate is a **KM median minus a median interval** — neither has a closed-form SE in the current code. Cheapest honest route = **bootstrap over doses** (resample n≈239, recompute, ~500 reps): reuses `survivalDuration`, no new statistical machinery, fine off-main.

## Decisions

1. ✅ Margin = **60 min/day of OFF** (published MCID, not tuned).
2. ⬜ **OPEN — needs Bhav.** Is `Σ max(0, gap − duration)` the card's quantity, or does median-vs-median stay the claim with the margin bolted on? Everything downstream depends on this. Recommendation: **switch the estimator** — on median-vs-median the pooled reading hands him a reassurance card at ~4 h/day OFF.
3. ⬜ Exclude PRN/rescue doses from schedule gaps; re-home them as an outcome signal.
4. ⬜ Give `wearingOffGate` an effect-size axis (needs 2 first).
5. ⬜ Fix `gapH`/`durH` precision mismatch (independent, ~1 line).

## Consequence for the Desai email

The current draft cites *"each holds a median of 193 minutes against daytime gaps of about four hours."* True but weak, and it's the understating estimator. The real finding is sharper: **the afternoon dose is followed by a 6.5 h gap against a 3.2 h dose, and that single gap accounts for most of the OFF.** Don't send the stronger version until the card can show it. [[project_kampa_apple_outreach]]
