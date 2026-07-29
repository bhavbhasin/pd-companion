# Wearing-off card: confidence from precision, not dose count

**Status:** ✅ **BUILT Jul 29 2026.** The last of the three group 3 sites; the other two shipped in
`817ff95`. Sibling: `insights-card-confidence-redesign.md` (the general "facts over verdict" rule),
`medication-cards.md` (per-substance cards), BACKLOG → *Dose-sufficiency floor*.

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
- **Emerging** — the point estimate clears the MCID but the duration's precision **cannot be
  established at all**, so there is no interval to read. Added Jul 29; see below.
- **No card** — the point estimate does not clear it. Unchanged; `minEffect` already did this.

Two questions, deliberately kept apart: **whether to speak** is the point estimate against the MCID
(a PERCEPTIBILITY question — confidence cannot rescue a shortfall nobody can feel), and **how firmly**
is where the MCID falls inside the interval. That split is why this is a plain function rather than a
`GateSpec`: the shared `gate` applies one effect value to every bar and cannot score two quantities.

### Keeping Emerging (the reference user, Jul 29)

The first cut of this design dropped Emerging, because the only thing producing it was the `minN: 1`
floor bar. That was an accident, not a decision — the tier is a legitimate idea and only the
hardcoded `20` behind it was arbitrary. Rejected alternative: *Emerging = the interval reaches the
MCID but the point estimate doesn't*. It is the tidier ladder (four positions of one threshold
against one interval) but it would show a card whose headline number is **below** the bar, which
quietly repurposes a perceptibility floor as a significance test. Firing stays where it was.

The rule adopted instead needs no constant: **`kmMedianPrecisionMin` returns `.nan` when the
estimator never engaged**, and that reads as Emerging. Rare in steady state, correct at cold start —
2 or 3 doses of a new substance that all measured the same length is exactly "we see it, we can't
vouch for it yet", and it resolves itself into Moderate or Strong as real variation appears.

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

   A no-op for the reference user, which is the right outcome: this replaces an arbitrary gate, it should not move
   anyone's tier. ⚠️ The 513.6 comes from a scratch reimplementation of the sum that does not handle
   the first/last dose of a day as the engine does (the app reads ~495) — the RATIO is what the
   design turns on, and ±5.2 against a 60-min bar is ~9%, robust to the base value.
2. ✅ **BUILT Jul 29.** Interval, then the gate. `WearingOffCardConfidenceTests`, both directions
   verified to FAIL against the old count tiers before they passed:

   | test | fixture | old gate | new rule |
   |---|---|---|---|
   | `countNoLongerCapsTheTier` | 30 doses, ±2.5 | Moderate (n < 40) | **Strong** |
   | `wideUncertaintyDemotesTheTier` | 48 doses, ±20, claim 69 min/day | Strong (n ≥ 40) | **Moderate** |
   | `precisionIsUnmeasurable…` | 3/5/16/144 identical durations | ±2.5 | **`.nan`** |

   No-op on the real record confirmed inside `matchesPythonOracleOnRealBackup`: still **Strong**.
   Full suite 82 tests green, `engineMatchesPythonLab` unchanged.
3. ⬜ Device check before anything builds on it.

## What the build found (Jul 29, measured — none of this was in the design)

1. **The precision floor was fabricating precision.** `kmMedianPrecisionMin` fell back to ±half a bin
   whenever no confidence band straddled 0.5, and that fallback was covering two different
   situations. Bands computed but none straddling = the interval really is finer than the 5-min grid
   (measured: 40 tightly-clustered doses, 2 bands) — the floor is honest. **Zero** bands computed =
   S(t) never took a value strictly between 0 and 1, so nothing was measured at all — the floor was a
   resolution claim made on no measurement, and it now returns `.nan`.
   ⚠️ **Driven by TIES, not sample size**: 144 identical durations were as uninformative as 3, and
   both reported ±2.5. The "this only bites at tiny n" reading was wrong.
   Harmless until now (nothing read precision); load-bearing the moment a tier depends on it.
2. **Both statsmodels-pinned cases take the band path** (11 and 5 bands), so `d9eca94`'s oracle is
   untouched by the change. That was the thing worth checking before touching a pinned function.
3. **The card is not a `PulseModel` consumer.** It holds a `SurvivalDuration` from a direct
   `survivalDuration` call, so storing `PulseModel.precisionMin` (step 1) does NOT feed this gate —
   it is the group-4 prerequisite. The card computes its own pooled precision in one call.

## Open

- **The one case the `.nan` rule misses.** 5 identical durations plus one late censored observation
  computes exactly ONE band, which doesn't straddle 0.5 ⇒ keeps ±2.5 ⇒ can still read Strong. The
  estimator did engage on real data there, and separating "one thin band" from "enough bands" needs a
  count threshold — precisely the kind of number this work exists to remove. Left flagged, not fixed.
- **Per-substance vs pooled.** The card is pooled across formulations by design; its duration is the
  pooled KM median, so its precision is the pooled precision. Per-substance precision belongs to the
  per-substance cards (group 4), not here.
- **Not the drawing.** Soft-vs-crisp edges are the UI half of group 3 and are not in this note.

## ⚠️ Do not touch

`wearingOffGate` is a different spec answering "can this be estimated at all", and its doc-comment
warns against adding `minEffect` — its callers pass no effect and would silently make every
formulation inestimable. Three consumers. Leave it alone.
