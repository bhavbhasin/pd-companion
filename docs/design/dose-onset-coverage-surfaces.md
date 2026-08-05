# Onset and coverage: the two per-dose quantities, and every surface that shows them

**Status:** map + 2 designs, Jul 29 2026. One surface SHIPPED, one DESIGNED elsewhere, one NEW
(the reference user's Day-in-Review panel). Written as one doc because the same two numbers appear at three
altitudes and it was already unclear which existed.
**Aug 4 2026 — the panel's last two open decisions are closed and its row copy is approved.** All
four decisions below are now settled; see [Row states](#row-states).

**✅ BUILT Aug 5 2026** — `CorrelationEngine.dosePanelRows`, 11 tests in `DosePanelRowTests`.

⭐ **RELOCATED the same day: there is NO Doses panel.** It shipped as a panel on Day in Review,
was device-tested across five days, and Bhav moved it: *"instead of a Doses panel separately, can
that be added to the dose detail card we show when we click on the dose glyph?"* It now lives in
`EventDetailSheet` under **"What this dose did"**, rendered by `DoseRowCopy`. Three reasons, in order:
1. A per-dose fact belongs on the per-dose object, and the glyph already sits on the chart at the
   dose time — so the sentence appears next to the tremor curve it describes.
2. It removes a permanent block of small grey text from the day's main scroll (the panel was six-plus
   lines every day, and legibility was the complaint that started this).
3. ⚠️ These sentences are still wrong in places while AutoSleep and the baseline window are unfixed.
   On the main screen a wrong sentence is asserted at the user daily; behind a tap it is seen by
   someone who went looking. The quieter placement is the honest one until Layer 1 is fixed.
⇒ **The engine is untouched.** `dosePanelRows` still returns one row per dose for a day; the sheet
looks up the tapped one. Only the display moved.
⛔ Cost, accepted: the within-day sequence (the Jul 21 "22 → 42 → 52" argument for this surface) is
no longer visible at a glance. It was already in tension with decision 4's ban on row-vs-row
comparison, and the chart shows the day's shape anyway.

⚠️ **One row state SPLIT IN TWO during the build, and the reason is a measurement.** The spec's
"reading lost (watch off)" row assumed `durationMin` was a watched span. It is not: `offReturn`
returns the **horizon** when it never sees a sustained return (`CorrelationEngine.swift:1579/1584/1596`),
so a dose with no next dose and no sleep reports the **24 h observation ceiling**. Rendering that as
*"watched 24h, then we lost the reading"* would have been a fabrication. Now two states, separated by
whether readings actually reached the end of the window:
- `watchedToEnd` → *"watched 5h without seeing it wear off"* (real span, bounded by the ceiling)
- `endedByLostReading` → *"watched 40 min, then we lost the reading"* (span measured from the **last
  real sample**, not the horizon)

⚠️ Also added: `noReading`, for a dose with no tremor record around it at all. ⛔ It must not reuse the
`learnedNothing` sentence — that copy asserts tremor was already quiet, which we never observed.
⇒ A logged dose is **never dropped** from the panel; a dose the user logged and cannot find reads as
data loss.

⚠️ The panel does **not** ride `recomputeForecast` — that returns early for any day that is not
today. It has its own `recomputeDoseRows` over a bounded ~25 h window (day ± baseline/ceiling) rather
than the all-history fetch, so navigating to a past day does not hydrate the whole tremor record.

**The two quantities, both computed PER DOSE and then usually averaged away:**

- **onset** — minutes from the dose until tremor has fallen halfway to its low point
  (`DoseTrace.tHalf`, from `doseResponseByTimeOfDay`).
- **coverage** — minutes the dose held before tremor returned to OFF (`DoseDuration`, from
  `survivalDuration`). Censored when the next dose arrives or the person falls asleep, in which case
  it is an *at-least* floor, not a blank.

## The three altitudes

| altitude | surface | status |
|---|---|---|
| **one dose** | Day in Review → **Doses panel** | ⬜ **NEW — the reference user's idea, designed below** |
| **per dose TIME**, all history | Insights → dose-timing card | ⬜ designed, `dose-timing-card.md` |
| **per SUBSTANCE**, all history | Insights → medication cards | ✅ **SHIPPED** `9a00939` |

⚠️ **The per-substance aggregate already exists** — the Sinemet card reads *"holds about 3h 3m …
starting about 43 min in"*, the Mucuna card *"1h 33m … 48 min"*. The reference user's second idea (aggregate as far
back as we can go) is largely this, already shipped. `historyStart` is the earliest tremor sample and
`fetchMedicationDoses(since:)` is called with it, so the engine already gets the whole dose record;
the binding limit is when dose logging began (2026-05-09, so 81 days), not a fetch cap.

⇒ The genuinely unbuilt aggregate is **trend over time**: is onset getting slower, or coverage
shorter, across months? Not built anywhere, and it is the one that matters while someone is reducing
their intake — it is how they would see whether coming off is costing them anything. Logged as its
own item, not folded in here.

---

## NEW: the Day-in-Review Doses panel

**The reference user's framing, confirmed:** a per-day representation. Every dose taken that day gets its own row
with that dose's own onset and coverage. Not an average, not a comparison — what today did.

**Why this altitude earns its place:** the engine computes both numbers per dose and every shipped
surface averages them. A single day's rows carry texture the aggregate destroys, and a measurement of
one dose is not a statistical claim needing n. The reference record, Jul 21:

```
10:37  Sinemet   onset 22 min   coverage 172 min
14:20  Sinemet   onset 42 min   coverage 178 min
19:00  Sinemet   onset 52 min   coverage 158 min
01:28  Mucuna    onset —        coverage at least 72 min
```

That is the effect the retired afternoon-dose card was reaching for, legible in one day, as
measurement rather than a verdict badged Strong. ⇒ **Day in Review is the honest home for it.**

### Measured feasibility (07-29 export, 279 taken doses)

| | a number | otherwise |
|---|---|---|
| onset | **185/279 (66%)** | 82 "already covered", 12 no pre-dose reading |
| coverage | **169/279 (61%)** | 97 at-least floors, 13 nothing |

⚠️ **Thinner during a reduction**: over the last 7 days onset drops to 50% and coverage to 36%,
because night doses land while already covered or asleep. Richest on a full daytime schedule.

### Four decisions, each forced by the real data

1. ⛔ **AMENDED Aug 5 2026 — this decision was WRONG, and it shipped before anyone checked it.**
   Original text: *"'Already covered' is INFORMATION, not a blank. It is the single most common reason
   onset is missing (82 of 279) and it means you dosed while the previous one was still working —
   arguably the most actionable row on the panel."*

   **The first clause holds; the rest does not.** The engine's test is `baseline < onThreshold` —
   tremor sat low in the 30 min before the dose. That is a **state** observation. "Still covered by
   the previous dose" is an **attribution**, and nothing in the estimator supports it.

   Measured counter-example, Jul 11 22:44 (07-30 dump): baseline **0.82** ⇒ classified "covered".
   But the previous dose was **376 min** earlier, the panel's own row above said that dose held
   **1h 3m**, and tremor ran **1.15-2.14 for the two hours before**. He was OFF in a quiet patch.
   ⇒ The panel contradicted itself four lines apart, and the wrong claim came from THIS decision.

   ⇒ **Render the state, never the cause: "tremor was already low".** Engine case renamed
   `alreadyCovered` → `tremorAlreadyLow` so the conflation cannot re-enter through the type.
   ⇒ **It is NOT "the most actionable row."** We cannot distinguish *still covered* from *OFF in a
   low patch*, and on the worked example it was the second.
   ⚠️ **The same wrong claim still ships on the medication card** (`CorrelationEngine.swift` ~:2160,
   ~:2218: *"you were still covered from…"*, *"taken while still covered by the previous one"*).
   Not fixed here — flagged, and it must move with this or the two surfaces will disagree.
2. ✅ **The at-least floors — DECIDED Aug 4 2026. Name what ended the watching; never print a floor
   as if it were coverage.** The 07-27 01:13 dose read *"coverage at least 1 min"*. The defect isn't
   the wording: **a floor is the length of the observation window, not a fact about the drug.** That
   dose was censored because the next one arrived a minute later, so "at least 1 min" prints the
   dosing schedule and labels it coverage — and next to a real "172 min" it reads as a dose that
   failed. The aggregate gets away with this because Kaplan–Meier absorbs a 1-min floor to nearly
   nothing; a per-dose row has no estimator underneath it.
   ⇒ Row copy states the ending. **No threshold, so there is no cutoff to defend.** See
   [Row states](#row-states).
   ⚠️ **Twin fix, same commit:** the medication card's *"up to about 10 min"* is `max()` of those
   same window lengths presented as a bound on the drug. It is the longest we **watched**, not the
   longest it **held**.
3. ✅ **What counts as a day — VERIFIED Aug 4.** Day in Review uses `Calendar.current.startOfDay`
   (`DayInReviewView.swift:283`) — plain midnight. Match it; do not invent a second definition.
   ⇒ Consequence to accept, not fix: the 00:47 and 01:13 doses land on the **next** calendar day,
   split from the evening run they belong to. (A 05:00-anchored day is what the slot analysis used.)
4. **Colour needs an absolute anchor, not only the user's percentiles.** Already paid for in `f6d43a4`:
   purely relative shading painted "worse than usual" on a level the user could not feel. Faster
   onset and longer coverage are "better", but better must be pinned to something real, not just to
   their own spread.

### Row states

**A row is two clauses, chosen independently: first = onset, second = coverage.** Approved Aug 4 2026.

```
10:37  Sinemet   on in 22 min · still working 2h 23m later, when you took Sinemet
13:00  Sinemet   taken while still covered · held 3h 10m
```

| situation | row reads |
|---|---|
| measured start to finish | `on in 22 min · held 2h 52m` |
| taken while still covered | `taken while still covered · held 2h 58m` |
| re-dosed before it wore off | `on in 15 min · still working 10 min later, when you took Sinemet` |
| slept before it wore off | `on in 52 min · watched 2h 38m, then you slept` |
| reading lost (watch off) | `on in 30 min · watched 40 min, then we lost the reading` |
| already covered, **then slept** | *the only blank* — reuse the shipped line: *"Your tremor was already quiet and you fell asleep soon after, so we never saw what it did."* |

⚠️ **"taken while still covered" and "re-dosed before it wore off" are the same clock moment seen
from two adjacent rows** — one dose's ending is the next dose's beginning. Both can land on one row
on a tight schedule (`taken while still covered · still working 2h 10m later, when you took Sinemet`).
Read as near-synonyms in isolation; the two-clause structure is what disambiguates them.

⭐ **Onset and coverage gate SEPARATELY — do not apply one exclusion to both.**
`CorrelationEngine.swift:1803-1805`: `fellFrom` (baseline ≥ `onThreshold`) gates **onset only** — an
already-covered dose has nowhere to fall from. `readable` gates **coverage**, and an already-covered
dose stays in it: *"low baseline + watching ran to the NEXT DOSE ⇒ a genuine coverage floor. Keep
it."* ⛔ The note at `:1783` records what happened when one exclusion was applied to both — a card
reading *"180 couldn't be measured"* and nothing else, for a six-doses-a-day patient whose drug never
lets them go OFF. Exactly the failure `medication-cards.md` predicts by name.
⇒ **The panel calls `readable` / `fellFrom` / `learnedNothing` directly. It re-derives none of this.**

### Not in scope
No verdict, no badge, no comparison between rows. The moment the panel says one dose beat another it
is the retired card again at a smaller scale.
