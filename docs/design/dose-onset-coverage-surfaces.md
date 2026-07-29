# Onset and coverage: the two per-dose quantities, and every surface that shows them

**Status:** map + 2 designs, Jul 29 2026. One surface SHIPPED, one DESIGNED elsewhere, one NEW
(Bhav's Day-in-Review panel). Written as one doc because the same two numbers appear at three
altitudes and it was already unclear which existed.

**The two quantities, both computed PER DOSE and then usually averaged away:**

- **onset** — minutes from the dose until tremor has fallen halfway to its low point
  (`DoseTrace.tHalf`, from `doseResponseByTimeOfDay`).
- **coverage** — minutes the dose held before tremor returned to OFF (`DoseDuration`, from
  `survivalDuration`). Censored when the next dose arrives or the person falls asleep, in which case
  it is an *at-least* floor, not a blank.

## The three altitudes

| altitude | surface | status |
|---|---|---|
| **one dose** | Day in Review → **Doses panel** | ⬜ **NEW — Bhav's idea, designed below** |
| **per dose TIME**, all history | Insights → dose-timing card | ⬜ designed, `dose-timing-card.md` |
| **per SUBSTANCE**, all history | Insights → medication cards | ✅ **SHIPPED** `9a00939` |

⚠️ **The per-substance aggregate already exists** — the Sinemet card reads *"holds about 3h 3m …
starting about 43 min in"*, the Mucuna card *"1h 33m … 48 min"*. Bhav's second idea (aggregate as far
back as we can go) is largely this, already shipped. `historyStart` is the earliest tremor sample and
`fetchMedicationDoses(since:)` is called with it, so the engine already gets the whole dose record;
the binding limit is when dose logging began (2026-05-09, so 81 days), not a fetch cap.

⇒ The genuinely unbuilt aggregate is **trend over time**: is onset getting slower, or coverage
shorter, across months? Not built anywhere, and it is the one that matters while someone is reducing
their intake — it is how they would see whether coming off is costing them anything. Logged as its
own item, not folded in here.

---

## NEW: the Day-in-Review Doses panel

**Bhav's framing, confirmed:** a per-day representation. Every dose taken that day gets its own row
with that dose's own onset and coverage. Not an average, not a comparison — what today did.

**Why this altitude earns its place:** the engine computes both numbers per dose and every shipped
surface averages them. A single day's rows carry texture the aggregate destroys, and a measurement of
one dose is not a statistical claim needing n. His Jul 21:

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

1. ⭐ **"Already covered" is INFORMATION, not a blank.** It is the single most common reason onset is
   missing (82 of 279) and it means *you dosed while the previous one was still working* — arguably
   the most actionable row on the panel. Render the reason; never an em dash.
2. **The at-least floors need a rule.** His 07-27 01:13 dose reads *"coverage at least 1 min"*, which
   tells the reader nothing. Same family as the medication card's *"up to about 10 min"*, which is
   still open — settle both together.
3. **What counts as a day.** His 00:47 and 01:13 doses belong to the previous evening's run; calendar
   midnight splits them off. ⚠️ Day in Review **already has a day definition** — match it, do not
   invent a second one. (A 05:00-anchored day is what the slot analysis used.)
4. **Colour needs an absolute anchor, not only his percentiles.** Already paid for in `f6d43a4`:
   purely relative shading painted "worse than usual" on a level the user could not feel. Faster
   onset and longer coverage are "better", but better must be pinned to something real, not just to
   his own spread.

### Not in scope
No verdict, no badge, no comparison between rows. The moment the panel says one dose beat another it
is the retired card again at a smaller scale.
