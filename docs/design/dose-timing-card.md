# Dose timing: what each of your dose times actually does

**Status:** DESIGNED Jul 29 2026, **not built.** Replaces the retired `dose-tremor-by-tod`
(afternoon-vs-morning) card, which is `.disabled` in `InsightRegistry.swift` with its renderer,
chart and mechanism copy left in place for reuse here.

**One line:** show every dose time the person actually uses, with onset, coverage, dose count and
span; make a comparative claim only when one time genuinely differs beyond noise.

**Name — DECIDED Jul 30 2026:** **"Each dose of your day"**, registry id `dose-by-position`.

Chosen because it has to survive a flat result. On the reference record the three well-populated
slots are 42/42/48 min onset and 182/178/162 min coverage, so the card's normal state is "your dose
timing behaves consistently" — a name that promises a comparison ("morning vs evening", "your best
dose time") would repeat exactly the defect that retired the old card. It also says *sequence*, not
clock, which is the grouping the data actually supports, and it does not collide with the two
neighbouring surfaces: **Doses panel** (today, per dose) and the **medication cards** (per
substance, all history).

Two headline states:
- neutral (the reference user's current data): *Each dose of your day*
- differentiated, only when a slot clears noise: *Your third dose starts slower than your first*

Rejected: "Your dose times" and "Dose timing" (drift back to clock language); "First dose to last"
(breaks at two doses).

---

## Why the old card was retired

The reference user asked the fundamental question — do we need a card comparing "afternoon" with "morning" when
doses are taken at any hour — and measuring it produced five defects, **none of which was the
unsourced `20` we were about to spend the session fixing.**

1. **The headline was a TAIL ARTIFACT.** The card reports means. On the reference record afternoon
   onset is mean **60.4** / median **42.5** (SD 41.4); morning is mean **37.5** / median **37.5**
   (SD 15.5). So a 22-minute claim badged **Strong / for your neurologist** is really a **5-minute**
   difference — one bin of the 5-minute resolution — plus a handful of very slow doses.
2. **It compared 2 of 4 buckets.** Pre-lunch and evening/night are computed and never looked at. On
   the reference record they hold **64%** of doses, and evening/night alone is the largest bucket
   (39% overall, 46% of the last 30 days, 54% of the last 14).
3. **`.afternoon` spans 12:30–17:00.** Actual afternoon doses run 12:30 to 16:56, median 15:05,
   quartiles 14:08 and 16:00 — averaging doses ~3 h apart into one number, which blurs the very
   time-of-day effect being claimed. This was the reference user's original objection and it was understated.
4. **The `.morning` comparator is disappearing.** 39 doses over the full record, **8** in the last
   30 days, **zero in two of the last three weeks**.
5. **It pools ~120 days with no recency**, so it keeps badging Strong about a regimen the person has
   already left, and it never self-corrects.

⇒ `doseResponseGate` (the last unsourced `20`, which was going to need the split-half stability
rule) has **no live consumer** while this entry is off.

## What the data says about the replacement

Grouping the same doses by **which dose of the day** it is — threshold-free, and immune to the
regimen drift that defeats clock buckets — the reference record gives:

| slot | n | days | onset (median) | coverage (median) | observed | hrs since prev dose |
|---|---|---|---|---|---|---|
| #1 ~09:27 | 77 | 77 | 42 min | 182 min | 80% | 9.1 |
| #2 ~12:30 | 75 | 75 | 42 min | 178 min | 68% | 3.8 |
| #3 ~17:55 | 65 | 65 | 48 min | 162 min | 67% | 6.1 |
| #4 ~22:53 | 30 | 30 | 35 min | 95 min | **29%** | 6.6 |

**Flat across the three well-populated slots, on both measures.** Slot 4's short coverage is the
sleep-censoring artifact (8 of 28 observed), not a short-acting dose. ⛔ **There is no "9am beats
4pm" finding on this record** — so the replacement must be able to say "your dose timing behaves
consistently" as a result, not fail to appear.

## Shape

**Facts over verdict**, the pattern the medication cards already ship. Body lists every dose time
the person uses with onset, coverage, dose count and span. The headline makes a comparative claim
only when one slot differs beyond noise. A neutral card is a real answer: *timing is not a lever for
you.* Silence would be indistinguishable from the app never looking — the same argument
`medication-cards.md` makes.

⭐ **Keep the chart.** The reference user specifically values the existing dose-curve visual; the retired
renderer's chart is the natural per-slot version (one curve per dose time) and is why the entry is
`.disabled` rather than deleted.

## Three decisions this needs, all with data behind them

1. **Slot labels cannot always be a single time.** Within-day rank is the right grouping (it gave
   clean groups of 77/75/65/30 with sensible medians), but slot #3's quartiles run **15:36 to
   23:00**. "Around 6pm" would be a fiction. ⇒ Print a **range** when the spread is wide. That is
   honest and it reports something true: after midday this person's dosing times are not slots at
   all. ⚠️ Deciding "wide" must come from the person's own regularity, not a typed tolerance —
   otherwise it is the `20` again in a new place.
2. **Coverage must be sleep-gated.** Slot 4 above is the worked example. The medication-card work
   already splits censoring by reason; reuse it or repeat the artifact.
3. **Recency.** Defect 5 above applies equally to a slot card. Cheap honest fix = print the span and
   day count (the reference user asked for exactly this). Weighting recent doses is the expensive version and is
   not proposed yet.

## The confound to state, not hide

Hours-since-previous-dose in the table above is **9.1 for slot #1 versus 3.8 for slot #2**. A first
dose of the day follows an overnight washout on an empty stomach; a midday dose follows food and
often a dose still partly active. So a slot difference is **not** evidence about the clock — it is
evidence about food and spacing, which is the actionable lever anyway. Copy must say so. The retired
card's mechanism text (levodopa competing with dietary protein for the same transporter, slowed
gastric emptying) is good and should carry over.

## Rejected

| Proposal | Why not |
|---|---|
| Keep morning-vs-afternoon, fix only the gate | Leaves all five defects above in place |
| Continuous onset-vs-hour slope | "Onset rises N min/hour" is not actionable and hides which dose to change |
| Fixed clock buckets with better boundaries | Swaps one set of typed boundaries for another |
| Cluster dose times by a proximity tolerance | The tolerance is a new unsourced constant, same family as the `20` |
| Retire with no replacement | Silence reads as "the app never looked"; a flat result is a real answer |
