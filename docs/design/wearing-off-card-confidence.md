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

1. **MEASURE FIRST.** On the reference data and on a thin synthetic substance: what is the daily-OFF
   interval, and does anything actually change tier? Bhav's Sinemet is ±2.5 min over ~2.2 daytime
   gaps/day ⇒ roughly ±6 min/day against a 60 min/day threshold, so his card should stay Strong and
   this should be a no-op for him. If the measurement disagrees, the design is wrong, not the data.
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
