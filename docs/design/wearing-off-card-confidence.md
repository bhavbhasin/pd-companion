# Wearing-off card: confidence from precision, not dose count

**Status:** DESIGNED Jul 28 2026, **not built**. The last of the three group 3 sites; the other two
shipped in `817ff95`. Sibling: `insights-card-confidence-redesign.md` (the general "facts over
verdict" rule), `medication-cards.md` (per-substance cards), BACKLOG → *Dose-sufficiency floor*.

**One line:** the card's confidence tier should come from how well its own claim is known, compared
against the published threshold it is already measured against — not from how many doses produced it.

---

## What it does today

```swift
static let wearingOffCardGate = GateSpec(
    strong:   GateBar(minN: 40, minEffect: wearingOffMCIDMinPerDay),
    moderate: GateBar(minN: 20, minEffect: wearingOffMCIDMinPerDay),
    floor:    GateBar(minN: 1,  minEffect: wearingOffMCIDMinPerDay))
```

`minEffect` is sourced and stays: 60 min/day of OFF, the stricter end of the pramipexole pivotal
trials (`wearing-off-margin.md`). The `40 / 20 / 1` dose counts are not sourced. They are the same
class of number the whole `20` item exists to remove, one shelf higher — exactly the trap
`insights-card-confidence-redesign.md:60` names when it says raw n-tiers must be replaced "where they
were doing 'is the estimate real yet' duty".

## The decision

**Tier on the uncertainty of the card's own claim.**

- **Strong** — the LOWER bound of the daily-OFF interval still exceeds the MCID. We are confident the
  shortfall is clinically meaningful, not merely that our point estimate is.
- **Moderate** — the point estimate clears the MCID but the lower bound does not.
- **No card** — the point estimate does not clear it. Unchanged; `minEffect` already does this.

### Getting the uncertainty without inventing a method

The claim is `Σ max(0, gap − duration)` per day, averaged over dosed days. Rather than derive error
propagation through that sum, **re-evaluate the existing function at `duration ± precisionMin`** and
take half the spread. Exact rather than linearised, no new statistics, and it costs two extra
evaluations of code already written. `precisionMin` is the Brookmeyer–Crowley half-width shipped in
`817ff95` and parity-pinned in `d9eca94`.

### ⛔ Deliberately NOT a ratio

No "uncertainty < half the MCID" or similar. BACKLOG records why `±30 min` was rejected: *"width ≤
MCID (rather than half, or twice) was a choice dressed as a derivation."* Comparing the interval to
the threshold directly reuses a number that is already sourced and introduces none.

## Order of work

1. ✅ **MEASURED Jul 28 2026 on the 07-24 export — the design holds.**

   | | |
   |---|---|
   | pooled duration | 182.5 min, precision **±2.5** |
   | daily OFF from spacing | 513.6 min/day |
   | recomputed at duration −2.5 / +2.5 | 518.8 / 508.4 |
   | **uncertainty on the claim** | **±5.2 min/day** (predicted ~±6) |
   | lower bound vs MCID | 508.4 vs 60 ⇒ **Strong** |

   A no-op for Bhav, which is the right outcome: this replaces an arbitrary gate, it should not move
   anyone's tier. ⚠️ The 513.6 comes from a scratch reimplementation of the sum that does not handle
   the first/last dose of a day as the engine does (the app reads ~495) — the RATIO is what the
   design turns on, and ±5.2 against a 60-min bar is ~9%, robust to the base value.
2. Build the interval, then the gate. Fail-first test verified against the old gate.
3. Parity + device check before anything builds on it.

## Open

- **`precisionMin` is `.nan` when the median does not exist.** The card cannot fire then anyway
  (`kmMedian.isFinite` guards it), but the interval code must not propagate NaN into a tier.
- **Per-substance vs pooled.** The card is pooled across formulations by design; its duration is the
  pooled KM median, so its precision is the pooled precision. Per-substance precision belongs to the
  per-substance cards (group 4), not here.
- **Not the drawing.** Soft-vs-crisp edges are the UI half of group 3 and are not in this note.

## ⚠️ Do not touch

`wearingOffGate` is a different spec answering "can this be estimated at all", and its doc-comment
warns against adding `minEffect` — its callers pass no effect and would silently make every
formulation inestimable. Three consumers. Leave it alone.
