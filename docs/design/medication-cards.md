# Medication cards: one per substance, existence decoupled from effect

**Status:** BUILT Jul 29 2026 (groups 4 steps 1-5, `4855a75` `9a00939` `e728842`). 2 open questions parked, 1 leftover logged. Supersedes the narrower "per-drug insight cards"
scope in BACKLOG (which was: give Mucuna its own card). The scope grew during design because the
narrow version turned out to be circular — see [The circularity](#the-circularity).

**One line:** every substance a person logs regularly earns a card; the card reports what their data
can support about that substance — including "nothing detectable" and "not enough yet" — and no card
is ever hidden for producing an unwelcome or imprecise answer.

---

## The two defects this fixes

### 1. The registry cannot express a per-substance question

`Variable` has one flat `.levodopaDose`. There is no `.medication(key)` / `.anyMedication` pair
mirroring `.workout(type)` / `.anyWorkout`. Nothing gated Mucuna out — **the sentence has no
grammar.**

Keep this distinction, it recurs: a **gate** makes a card dark *temporarily, pending data*
(self-resolving); **missing expressiveness** makes it dark *permanently*, and no amount of data
fixes it. Same family as the dormant-renderer backlog item.

### 2. The circularity

The obvious fix — show a per-drug card once the drug shows an effect — is circular in a way that
matters. The card's *content* is "this substance changes your tremor by X, for Y minutes." The card's
*existence test* would be "does this substance change your tremor?" Same numbers answering both.

Two consequences:

- **Not an independent check.** The gate restates the content rather than validating it.
- **Selection bias, worst where data is thinnest.** If a card only appears when the measured effect
  is large enough, the effects on display are biased upward — the substances that clear the bar early
  are disproportionately those whose noise pointed the right way. The newest substance, with the
  least data, gets the most overstated number. Exactly backwards.

---

## The principle

**A card's existence depends on whether the person takes the substance, not on what the substance
did.**

Once existence is unconditional, the count stops being a hidden gate and becomes content: *what we
have, and what is still missing.* There is then nothing to threshold — "is there enough evidence?"
is only a question you must answer if the card disappears when the answer is no.

This is the same resolution the confidence work reached from the other direction
(`insights-card-confidence-redesign.md`): **facts over verdict.** Show the before/after and the
person's own variability; let them judge. Applied here, "this substance does nothing" stops being a
verdict the engine must be confident enough to issue, and becomes a set of numbers the reader can
weigh.

---

## What a card says

**Six independent statements, each appearing only when its own estimator is *defined*** — a
mathematical condition, not a chosen threshold. The card is composed, never written as prose per
substance: a first draft written as paragraphs read fluently for one drug and did not generalise.

| # | Statement | Appears when | Sinemet (measured) | Mucuna (measured) |
|---|---|---|---|---|
| 1 | how many doses, over how long | always | 249 doses, 77 days | 24 doses, 22 days |
| 2 | how long it holds | the survival curve reaches 50% (`kmMedian.isFinite`) | ~3h 0m, 162 endings | ~48m, 8 endings |
| 3 | the at-least floor | some doses were still working when the next dose arrived | — | 3 doses, up to ~2h |
| 4 | what could not be measured, and why | some doses had no readable window | — | 11 night doses |
| 5 | how far tremor falls | ≥2 doses taken while actually OFF (see Observability) | 1.60 → 0, 174 doses | too few (6) |
| 6 | how fast it acts | onset resolvable on those same doses | yes | ~22 min |

A brand-new substance with 3 doses shows row 1 and says plainly that the rest is not yet knowable.
A long-acting once-daily shows rows 1 and 3 but not 2 — it never wears off before the next dose, and
that IS the finding. Nothing is hidden, nothing is per-drug, and no row assumes a levodopa shape.

⚠️ **Row 4 is not an apology and must never read as one.** "These doses tell us nothing" is both
wrong and dismissive — the substance may well be doing something we are not equipped to see. The
honest sentence names the instrument, not the drug: *we measure this through tremor, and while you
are asleep tremor tells us nothing.*

Duration is the scarce one. On the reference dataset one formulation is 59% censored: more than half
its doses never showed an ending.

### Censoring is a floor, not a blank

**A dose that never showed an ending is not missing data — it is a lower bound.** "It had not worn
off by the time the next dose arrived, in 8 of 10 cases" is a measurement, and for coverage purposes
it is the one that matters: the substance covered *at least* that gap.

This matters more than it first appears, because **the substance least likely to produce a measurable
duration is a long-acting one taken on a tight schedule** — i.e. a drug that is working. Left
unhandled, the design would be least able to describe the drugs that help most. Read censoring as a
floor and that inverts correctly.

(Note the subtlety: doses that were never seen ending still contribute to the survival curve for as
long as they were watched. "The median exists" is not the same as "half the doses were observed".)

**When none of the three can be stated, the card still appears and says why.** Shape:

> **Naltrexone** — 28 doses logged over six weeks. None have yet been followed by a clear return of
> tremor while you were awake, so we can't say how long it lasts. What we can see: tremor is 8% lower
> in the two hours after a dose, which is inside your ordinary day-to-day range.

That tells the reader what is known, what isn't, and *why* — instead of silence, which they cannot
distinguish from the app never having looked. For anyone running a personal experiment with an
unproven substance, this is the point of the feature.

### Observability: a dose you cannot see is not evidence — DECIDED Jul 29 2026

**Measured first, and the obvious rule turned out to be a no-op.** Mucuna, 07-24 export, 24 doses
(22 with windows), under the cross-substance rule:

- **8 seen wearing off** — every one a daytime dose (08:55–14:00).
- **11 cut short by falling back asleep** — every one a night dose (01:00–05:00), a median of
  **10 minutes** of observation. The next dose was typically 5–10 h away, so "the next dose arrived"
  was never the reason. (An earlier draft of this card said it was. It was not checked.)
- **3 cut by the next dose** — daytime, median 114 min. These are genuine coverage floors.

| rule | rows | endings | duration |
|---|---|---|---|
| censor as-is (today) | 22 | 8 | **92.5 min** ±37.5 |
| drop censored rows shorter than the onset (22.5 min) | 16 | 8 | 92.5 ±37.5 |
| drop censored rows shorter than 30 min | 13 | 8 | 92.5 ±37.5 |
| **daytime doses only** | 11 | 8 | **47.5 min** ±37.5 |

Dropping *short* observations changes nothing; dropping the *night* doses nearly halves the figure.
The reason: a censored row normally means "still ON at t", a legitimate floor that pushes the
estimate up — but **during sleep tremor is near zero regardless of medication**, so that floor is
measuring sleep, not the drug. Today's Mucuna headline is ~2× what its daytime doses alone support.

**DECISION — one rule, both halves.** A dose whose **pre-dose baseline is already below the OFF
threshold** is excluded from every statement: the drop, the onset, *and* the duration. You cannot
measure a fall from a floor, and you cannot watch a return to a level you never left. Rejected
alternative: a minimum-observation-window length — measured as a no-op above, and it would have been
a new arbitrary number.

- Reuses `offThreshold`; introduces no constant.
- Generalises past sleep: it also covers a dose taken while still ON from the previous one.
- ⚠️ **PREDICTION, NOT YET MEASURED:** this should bring Mucuna's headline near 48 min. The build
  must verify that, not assume it.

### The night-dose question belongs to the experiment loop, not to a card

The reference user reports the 01:00–05:00 Mucuna doses help him get back to sleep. Tremor cannot see that, and
the observational sleep comparison **cannot settle it either** — measured on matched dates:

| | n | median time awake |
|---|---|---|
| night wakings **with** a Mucuna dose | 10 | 42 min |
| night wakings **without** | 126 | 4 min |

This is **not** evidence the substance keeps him awake. It is confounding by indication in its
purest form: he takes it on the awakenings that are already bad, and the comparison group is 126
mostly-brief stirrings. No retrospective slice separates the indication from the effect.
⇒ Route to the **experiment loop** (Hypothesis → Experiment → Verdict, BACKLOG): it needs a
prospective label — qualifying awakenings treated and comparable ones not. The card must claim
nothing about sleep in the meantime.

### ⚠️ Observability asks TWO questions, not one — CORRECTED Jul 29 2026

The rule as first written ("exclude any dose whose pre-dose tremor is already below the OFF
threshold, from every statement") is **wrong for the duration**, and rendering the card for six
different user shapes is what exposed it. A low pre-dose tremor means two opposite things:

| | what the low reading means | duration | fall / onset |
|---|---|---|---|
| asleep soon after the dose | circumstance; nothing was observed either | ⛔ exclude | ⛔ exclude |
| still covered by the previous dose, awake | **a drug is working** | ✅ keep | ⛔ exclude |

One exclusion for both deleted the second case, and produced this card for a six-doses-a-day
patient whose drug never lets them go OFF: *"180 doses of Rytary on 30 different days. We can't yet
say how long a dose lasts. 180 couldn't be measured."* Nothing else. That is **precisely the failure
this document names** — "least able to describe the drugs that help most" — reintroduced by the fix
for the opposite problem.

**Corrected rule — it takes BOTH facts to disqualify a dose:** low baseline **and** the watching cut
short by sleep. Low baseline with the watching running to the next dose is a coverage floor, kept.

⚠️ **Sleep BEFORE the dose is the wrong test** (tried first): the reference user wakes at 03:59 and doses at 04:45,
so his night doses have *awake* pre-windows and sailed straight through, putting Mucuna back to
93 min. What disqualifies them is sleep arriving AFTER, ending the watching within minutes.

### Three more copy defects the six-profile render caught

- *"Tremor typically falls from 1.90 to 1.90."* A drop of 0.000002 is arithmetically a drop, so the
  guard must compare what is **printed**, not the raw doubles. Now says it doesn't measurably change.
- *"usually asleep" was asserted, never measured* — the same error as claiming observations ended
  because the next dose arrived. Now checked per dose against sleep onset, and the clause only
  appears when sleep actually explains the majority.
- *"Cbd Oil".* Names were the canonical key re-cased, which breaks every acronym (LDN, MAO-B). The
  card now shows the spelling the person typed, most-frequent form winning, ties broken
  alphabetically so a title cannot flicker between runs.

### Fixed rules

- **⛔ Each card speaks only about its own substance.** Cross-substance ranking is not established on
  the reference data (log-rank between the two formulations p=0.52) *and* is a dosing judgment the
  safety line forbids. This must be a property of the renderer, not of the copy.
- **No dosing suggestion, ever.** `.clinicalReferral` safety class.
- **Precision is shown, not used to hide.** Deferred until the `20` redesign lands — see
  [Open](#open-questions).

---

## When a substance earns a card

**Logged on more than one day.** A single day is a trial or a mis-entry; a second day is a pattern
the person chose to continue. This is a screen-clutter decision, not a claim about evidence — which
is a far more defensible home for an arbitrary line than inside "does this work."

---

## Classification: what the engine treats as acting on tremor

This is *separate* from whether a card appears. It decides whether a substance's doses join the
pooled levodopa analyses (coverage card, forecast, dose-confound guards). A supplement swept into
that pool contributes doses that never produced a pulse, flattening the pooled curve.

Today: include if the substance clears an estimability test **or** has fewer than 20 doses (benefit
of the doubt); exclude if it has ≥20 doses and shows no pulse. That rule is written **twice, with the
polarity flipped** (`CorrelationEngine.swift:244` and `:2531`) — one decision, two copies, either
editable without the other. Both are sites in the `20` redesign; `:244` was missed in that item's
original survey of eight and makes nine.

### DECIDED — there is no classifier

The engine does not need to decide whether a substance "is levodopa". It needs to decide whether a
dose contributes coverage, and that is a question about the **estimate**, not about the drug:

> **A dose counts toward coverage only if its substance has a measurable duration** (including a
> censoring floor, per above). A substance with nothing measurable contributes nothing and never
> splits a gap.

Vitamin D is excluded by having nothing to contribute, not by being judged inert. Same sentence
covers a substance with two doses so far and one with fifty doses and no effect. **No verdict is
issued, so no margin is needed** — which matters, because `confidence-presence-vs-absence.md` records
that no validated tremor MID exists, and resting a margin on the user's own variability was corrected
there as circular. This sidesteps that dead end rather than solving it.

⇒ Sites `:244` and `:2531` are largely **deleted rather than converted**, taking two of the nine `20`
sites with them.

**Trade-off, DECIDED (the reference user, Jul 26 2026): conservative-but-wrong.** A genuinely effective new drug
contributes no coverage until its duration is estimable, so the coverage card temporarily reads worse
than reality. The alternative — falling back to the average of the person's established drugs — is
more useful but asserts something never measured about the new substance. Reading censoring as a
floor keeps this window short.

### Literature as a classifier — considered, rejected as a gate

Sourcing drug class from published literature would break the circularity cleanly: pharmacology
answers "is this substance plausibly dopaminergic," the person's data answers "how much, how long,
for you." It also solves cold start — a new levodopa formulation would be known on day one.

Rejected as a **gate** for three reasons:

1. **A list cannot recognise what it hasn't heard of** — international brands, compounded
   formulations, supplements. Unknown substances would need the measured route anyway, so both paths
   get maintained.
2. **The answer is often not binary.** Nicotine has a long-standing epidemiological association with
   lower PD incidence and has been trialled as a patch; it is neither established nor refuted. A
   yes/no list must file "studied, not established" as one or the other, and both are wrong. Low-dose
   naltrexone has no PD-specific evidence at all, which is not the same as evidence against.
3. **It answers the wrong question.** Literature says levodopa reduces tremor *on average across
   patients*. Tremor is the least reliably levodopa-responsive cardinal sign. A literature "yes" can
   light a card for someone whose tremor genuinely doesn't respond — the opposite failure to the one
   being fixed.

**Kept as provenance.** Every registry entry already carries a literature-motivated `rationale`; that
layer is the right home for drug-class knowledge. A substance with no established evidence should
carry that note explicitly, so an encouraging early number is not read as vindication.

**Consequence, deliberate:** unproven and traditional treatments — Ayurvedic preparations, a tester's
low-dose naltrexone — are first-class. They are measured on exactly the same terms as Sinemet, and
"we cannot detect an effect" is a publishable result rather than a card that fails to appear. No
literature can give someone that answer about themselves.

---

## Exclusion: the user's switch

A person may turn any substance off. Off means: **no card, and the substance's doses leave the
correlation engine entirely** — not merely hidden.

- **Where:** Settings already presents a *Data sources* row with per-source toggles ("on = mine",
  written through with no save step). Medications become a sibling row with the same pattern, so
  turning something back on is symmetrical.
- **Why it is not just cosmetic:** it is the user's lever against a substance being misclassified
  into the levodopa pool.
- **⚠️ Excluded substances must be listed in the clinical export.** The existing source exclusion
  removes *someone else's* data — data that was wrong to include. This removes the person's *own*
  correctly-recorded data. Same switch, different act. Listing them keeps the choice theirs and on the
  record.
- **⚠️ State the consequence when the substance is pharmacologically active.** Excluding a working
  drug makes the coverage card compute dose spacing as though it were not taken, inflating the
  uncovered-hours figure. Say so at the toggle; do not prevent it.
⬜ **NOT BUILT. Logged Jul 29 2026, and the reference user ranks it above the ordering rule.** ⭐ Their reason names
the trigger the substance count misses: **clutter arrives when a user starts confirming doses on a
schedule they already have, not when they add substances.** Verified — the fetch gates on
`logStatus == .taken` (`HealthKitManager.swift:1058`), so a scheduled-but-unconfirmed medication
produces no card today. A typical polypharmacy PD regimen is 5-8 medications sitting unconfirmed in
Health; the day someone taps "taken" across that list, every one becomes a card at once. Today no
record exceeds 2 substances, so this is preparation, not a fix.

- **Not a performance feature.** If per-substance model fitting proves expensive, the answer is
  caching or lazy computation — not asking the patient to prune their list. Build this for agency and
  classification hygiene.

---

## The pooled coverage card

Its two-formulation branch is **deleted**. Today it prints per-formulation figures inside one
sentence ("holds ~3.0 h … holds ~1.6 h"), which arranges two true facts so the reader concludes a
comparison that p=0.52 says is not established, and gives a 240-dose estimate and a 22-dose estimate
equal authority.

After this change the card does one job: how many waking hours a day the dose *spacing* leaves
uncovered. Per-substance numbers live on per-substance cards, each carrying its own dose count.

**Side effect:** the deleted branch contains one of the `20` sites. Removing the rows removes the
site rather than converting it.

✅ **DONE Jul 29 2026** (`eb7c6ab`), once the per-substance cards shipped — deferred until then so
the app was never thinner than before. Pinned by `theCoverageCardNamesNoSubstance`, which builds a
two-formulation regimen of exactly the shape that used to trigger the rows and asserts the coverage
copy names neither substance. **That leaves ONE `20` in the engine**: `doseResponseGate`, which waits
on the split-half stability rule.

---

## Three more hardcoded numbers, found in this path

`90`, `360` and `190` sit in the duration path and would each misfire once any substance can earn a
card. Same family as the `20`; fold into that item rather than treating separately.

| Number | What it does | Verdict |
|---|---|---|
| `190` (`doseOnWindowFallback`) | substituted whenever a duration isn't estimable. Its comment says "≈ the validated median ON-duration (~192 min)" — i.e. **one person's physiology, shipped as everyone's default**. Defensible for levodopa; fiction for a supplement | **split by consumer** — see below |
| `90` (lower rail, `:414` `:2311`) | any estimate under 90 min is discarded and replaced by the fallback | **drop on the per-substance path** — it would throw away a genuine 50-minute measurement and substitute a levodopa-shaped number |
| `360` (upper rail, same two sites) | rejects estimates over 360 min | **delete — dead code.** Durations are measured in a window capped at `maxWindow = 300`, so no estimate can ever exceed 300 and the test can never fail |

**The trap in the fallback: two consumers want opposite things.**

- **Coverage / forecast** want *nothing*. Substituting 190 invents coverage nobody measured — and the
  DECIDED rule above already says an unmeasurable dose contributes nothing.
- **The food / exercise dose-guard** (`doseOnWindowMinutes`) wants *something protective*. It uses the
  ON-window to avoid crediting a meal with the dose's effect; handed zero, it would treat every meal
  as uncontaminated, which is the unsafe direction. This consumer genuinely needs a default.

One constant, two questions, opposite right answers — the `20` pattern in a different number. Whether
the guard's default stays 190 or becomes something less person-specific is left open rather than
guessed.

## Build shape

**Steps 1-3 ✅ BUILT Jul 29 2026 (`4855a75`)** — config + plumbing only, nothing on screen. The
template ships `renderer: nil`, so its stamped entries are registered and dormant; `run()` returns
nil for each, verified. `MedicationCardVocabularyTests` pins the two properties the feature rests
on: **no substance is skipped for being unrecognised** (the contrast with the workout template,
which still drops unnameable types, is pinned in the same test), and **an inert substance is
stamped exactly like an effective one** while still contributing no coverage to the pooled
analyses. `.levodopaDose` survives untouched — the pooled coverage question is not replaced by
per-substance cards. 95 tests green, parity + both Python oracles unchanged.

**Steps 4-5 ✅ BUILT Jul 29 2026 (`9a00939`)** — `Renderer.medication` + `medicationInsight`, and
the chart came free (`wearingOffChart` over the substance's own readable rows). `run()` now takes
`allDoses` (the RAW log) alongside the levodopa-candidate set, so an inert substance's card has
doses to describe. Real record: **Mucuna 48 min ±38 from 6 observed returns** — the prediction
above, verified rather than assumed — and **Sinemet 183 min ±3 from 118**. `MedicationCardTests`
pins the inert-substance case, the cross-substance window, the observability exclusion, the
long-acting floor-only case, the 3-dose case, and that no card ever names another substance.
102 tests green, parity + both Python oracles unchanged.

⚠️ **Two defects the build surfaced, both fixed:**
- *Unmeasurable doses were counted against the wrong denominator.* `survivalDuration` silently drops
  a dose with no usable window, so counting against its output left those doses unexplained — the
  "24 logged, 22 measured" gap on the real Mucuna record. Now counted against doses LOGGED, which
  is what statement 1 tells the reader.
- *Only next-dose floors were reported.* A long-acting substance is censored by SLEEP night after
  night; those doses sat inside the duration figure and were mentioned nowhere. Every censored
  readable row is now a floor, split by reason (next dose / lost sight of you).

⚠️ **Copy rule learned here:** the fall statement no longer prints its own dose count. Statement 4
said "16 couldn't be measured" out of 24 logged, and statement 5 said "measured on 6" — the reader
subtracts, gets 8, and finds 2 unaccounted for (the two primitives have different window rules).
Same lesson the wearing-off card already carries: print ONE number, never two that invite a
difference. Exact counts live in the clinician bullets, where arithmetic is the point.

**Chart fixes Jul 29, all found on device — the curve must describe the same doses as the card:**
- *Drawn from ONE dose.* `wearingOffChart` keeps only doses isolated by 240 min, which the
  cross-substance window disqualifies nearly everything from: Mucuna had 8 readable doses and 1
  isolated. Per-substance cards pass `isolatedOnly: false`; the pooled card still filters.
- *Plotting the next substance.* The curve ran a fixed 300 min past every dose regardless of when
  watching stopped, putting Mucuna's deepest point at **242 min** — four hours out, and it was
  Sinemet. Bins are now blanked after each dose's own observation ends (trough moved 242 → 88,
  curve ends 168 min). Off by default, so the parity-pinned pooled curve is byte-identical.
- *The deepest-ON marker is withheld per-substance.* ⭐ Not a cosmetic call: the doses still watched
  late are BY CONSTRUCTION the ones that had not worn off, so the tail is a self-selected subset.
  Mucuna's marker rested on **3 of 8 doses** (curve thins 8 → 6 → 5 → 3 by 90 min) and sat at 88 min
  against a 48-min duration, reading as though the dose wore off before doing its best work.
  Sinemet's rests on 137 of 175 and is stable, so the pooled card keeps it. The curve is still
  drawn; only the point-claim is withheld.
- *The line fades on the ABSOLUTE dose count behind each point* (`0.10 + 0.90 × min(1, n/30)`),
  not on a share of that substance's own peak. Fading on share was the first attempt and it is
  wrong twice over: it grades every chart against itself, implying a 9-dose peak is as trustworthy
  as a 175-dose one, and it punishes density — Sinemet's mean at 4h rests on 90 real doses and
  would have been ghosted to 34% for having "lost" half its starting sample. On absolute count a
  thin substance reads faint ALL THE WAY ACROSS (Mucuna 0.13-0.37), which is the honest signal:
  its whole curve is thin, not merely its tail. Sinemet draws solid throughout. The saturation
  point is a labelled DISPLAY constant — it changes ink, never a number, a gate, or a claim.
- *The caption moved to the bottom-left,* and it states the RANGE behind each point
  ("1–9 doses per point"), not one figure — the top-left corner already carries the `dose` rule
  annotation and the two collided on a dense substance ("66–175 doses per point"). The first version said "avg of 9 doses", which
  implied all 9 stood behind every point — on Mucuna the truth ran 9 down to 1, making that label
  the most confidently wrong thing on the chart. Fading needs no cutoff: solid where every dose
  contributes, ghosted where one does. Drawn as per-pair segments because Swift Charts styles a
  series uniformly — a per-point style on one series is silently ignored.
- ⬜ **Logged, not solved (BACKLOG):** a mean-tremor curve is the wrong chart for a heavily-censored
  substance at all. The correct one is the survival curve — *what fraction of doses were still
  working at each minute* — which handles doses dropping out instead of averaging across them, and
  is the same Kaplan–Meier the duration already comes from. New chart type; real work, not a tweak.

⬜ **Still open:** ordering/clutter rule (open question 4) · precision drawing (open question 5 — the
thinning tail above is a concrete instance: fading the line where the dose count drops is the
general fix) · the Settings exclusion toggle. Cost re-measured Jul 29 (see open question 3) and DEFERRED.

1. **Vocabulary (small):** `Variable.medication(String)` + `.anyMedication`, plus the bridge
   accessor mirroring `workoutRawValue`. Easier than workouts — the substance key is engine-side
   (`formulationKey`), no HealthKit involved.
2. **Stamping (existing):** `.perObservedType` already stamps one approved template per value seen in
   the user's own data — how one person gets a Tai Chi card and another gets pickleball. Needs an
   `instantiate` overload keyed on substance strings rather than HealthKit raw values.
3. **Primitive (new name, existing math):** the card reads a fitted per-substance model combining
   onset and duration. `fitPulseModel` already computes it and already drives the daily forecast; it
   simply has no name in the registry. Declaring `.survivalDuration` would name the duration half
   only — mislabelling the method is the same class of defect as the `20`.
4. **Renderer (new, the real work):** a new card type, not a variant of `.wearingOff`. That card
   answers a scheduling question pooled across everything; this one answers "what does this substance
   do for me." Folding both into one renderer means branching internally on which question is being
   asked — the exact pattern the `20` item exists to remove.
5. **Chart (nearly free):** `wearingOffChart(results:km:)` already takes one dose set and draws its
   average shape — baseline, dip, return. Handing it one substance's doses yields that substance's
   own curve with no new drawing code.

⇒ A new formulation works on day one for a person we have never met, with no code change. That is
the point.

---

## Open questions

1. ~~**Cross-substance confounding — the clean window.**~~ — **CLOSED Jul 29 2026: adopt it for
   per-substance duration, and do NOT apply it to `estimableFormulations`.**

   Measured on all three testers, and the first finding is that **only one record can answer it** —
   Tester B has **zero** dose rows, Tester A has **1 taken of 28** (the rest `notInteracted`). On the reference user's:

   | | today (window ends at the next dose of ITSELF) | cross-substance |
   |---|---|---|
   | Sinemet, 249 doses | 182.5 ±2.5, 162 endings | **182.5 ±2.5**, 160 endings |
   | Mucuna, 24 doses | 92.5 ±32.5, 11 endings | **92.5 ±37.5**, 8 endings |
   | Mucuna watched window | **1600 min** | **167 min** |

   The 1600-minute window is the whole argument: today a Mucuna dose is watched until the next
   *Mucuna* dose ~26 h later, across several Sinemet doses in between. The headline barely moves,
   but its meaning changes from contaminated-and-precise-looking to honest-and-thin. A card labelled
   *Mucuna* printing a number that is substantially Sinemet is the exact failure per-substance cards
   would otherwise introduce.

   **Why `estimableFormulations` keeps the old rule:** it answers a different question — "does this
   substance contribute coverage" — and tightening it drops substances out of the pooled set, which
   inflates the uncovered-hours figure for precisely the heavily-medicated patient (window length
   scales ~960/total daily doses; see BACKLOG group 2 constraint A). Same split as `wearingOffGate`
   vs `wearingOffCardGate`: one question, one rule, no constant doing double duty.

   ⚠️ The old ordering constraint *"ship with censoring-as-floor, never alone"* **dissolves for
   group 4**: censoring-as-floor is not a separate feature here, it is statement 3 of the card.

   Superseded sub-question, kept for the record: A substance's observation window runs to the
   next dose of *itself*; another substance taken in between is invisible. So part of what is reported
   as one drug's duration may be another drug's effect. This is **not** a general oversight — the
   substrate band excludes every dose's active window regardless of substance, the food and exercise
   cards are dose-guarded, and the pooled medication analyses truncate at the next dose of any
   levodopa substance because they are pooled. The gap is specific to per-substance fitting, and it
   arrived with the stratified per-formulation work. Fix would be to end a substance's window at the
   next dose of *any* active substance. Cost: fewer usable windows, on top of 59% censoring already.
   **Note the current asymmetry: pooled figures and per-substance figures are cleaned to different
   standards on the same screen.**
2. ~~How the classifier decides "no detectable effect"~~ — **CLOSED.** There is no classifier; see
   [Classification](#classification-what-the-engine-treats-as-acting-on-tremor). The question became
   "does this substance have a measurable duration", which needs no margin and therefore never meets
   the missing-tremor-MID dead end.
3. ~~**Cost.**~~ — **MEASURED Jul 29 2026 on the 07-24 export** (104,256 tremor samples, 273 taken
   doses, 8,832 merged sleep intervals). **The reasoning was wrong.** Cost does *not* track total
   doses alone: there is a **fixed ~25 ms per substance** that does not shrink as its dose count
   falls. Same doses, relabelled into S substances:

   | substances | 1 | 2 | 4 | 8 | 16 | 32 | 64 |
   |---|---|---|---|---|---|---|---|
   | `estimableFormulations` | 238 ms | 324 | 352 | 411 | 653 | 997 | **1831 ms** |

   Dose count scales linearly and cheaply (69 → 137 → 273 doses = 187 → 264 → 452 ms at fixed S).

   **Cause located — it is not new work, it is the known re-sort.** With only 4 doses,
   `fitPulseModel` still costs 34 ms: `survivalDuration` 19 ms + `doseResponseByTimeOfDay` 14 ms.
   Both open with `let series = signal.sorted { $0.time < $1.time }` — **a full sort of the 104k
   signal on every call**, independent of how many doses that call is fitting. `estimableFormulations`
   therefore sorts the signal 2×S times. This is already the BACKLOG item *"windowed cards each
   re-sort the 100k signal → sort once in generateInsights, pass one indexed signal"*; group 4 does
   not create the defect, it **multiplies it by the substance count**.

   ✅ **FIXED Jul 29 (same session).** `survivalDuration` and `doseResponseByTimeOfDay` now skip the
   sort when the signal is already time-ascending, and `asleepMinutes` binary-searches its starting
   interval instead of walking the merged sleep list from the head. Both output-identical, pinned by
   `EngineScanInvariantsTests` against the pre-change algorithm kept verbatim as an oracle.

   | | before | after |
   |---|---|---|
   | `fitPulseModel`, 4 doses (the per-substance floor) | 34 ms | **9.3 ms** |
   | `estimableFormulations`, 64 substances | 1831 ms | **615 ms** |
   | `estimableFormulations`, 16 substances | 653 ms | **406 ms** |
   | one `uncoveredPerDay` pass | 206 ms | **0.09 ms** |
   | `wearingOffInsight` (the whole card) | 1008 ms | **613 ms** |

   ⚠️ **Per-substance cost is smaller, not gone** — ~6 ms of it survives, so 64 substances is still
   2.5× one substance. Group 4 should re-measure once cards exist rather than assume flatness. A
   realistic supplement-heavy user (~16 substances) now pays ~406 ms, down from ~653.

   ✅ **RE-MEASURED Jul 29 2026, cards included — and the ~6 ms was the smaller of two costs.**
   With a production-shaped shared `SurvivalCache`, a warm medication card costs **77 ms** (cold
   338), flat per card ⇒ 64 cards = 5.2 s; `estimableFormulations`' own residual is ~4.3 ms per
   substance (750 → 1028 ms at S=64), which is the ~6 ms above, confirmed and minor. Nearly all of
   the warm 77 ms is `mergeSleep` (12 ms over 30,689 rows) plus `censoringSleep` (84 ms, including
   two full `map` allocations over 104,256 tremor timestamps for the record's min/max) — identical
   inputs, identical output, recomputed per card. Fix = hoist out of `medicationInsight`, compute
   once per run, pass in; output-identical, same shape as `b6e6f69`.
   ⛔ **DEFERRED by the reference user Jul 29** — no felt problem at his 2 substances (~155 ms). Logged in
   BACKLOG under Insights tab performance, item 4.

   ⚠️ Simulator timings, median of 5, and run-to-run spread is ~10-40% — the SHAPE is the finding,
   the constants are soft.
4. **Ordering rule for clutter.** "Most informative first" needs a concrete definition. Six
   supplements each reporting "no detectable effect" is true and useless. Handle by ordering and
   collapsing, never by hiding — hiding is what this document removes.

   ⛔ **PARKED Jul 29 2026 — measured, no target.** No record has more than **2** distinct
   substances (reference user 2, Tester A 1, Tester B 0), and the shipped sort already ranks confidence then stage,
   so `.emerging` nulls sink on their own. Revisit when a record has a tail.

   ⚠️ **Separable and REAL today:** two `.moderate` + `.clinicalDiscussion` cards tie and fall
   through to registry order, so **Mucuna's 28 doses render above Sinemet's 251**. The fix is a
   tie-break on evidence, but it lives in `InsightsView.orderedInsights` and applies to every card,
   so it reorders unrelated equal-confidence pairs. Logged in BACKLOG, the reference user's call.
5. **How precision is drawn.** Downstream of the `20` redesign: one substance's duration is confident
   within ~5 minutes, another within ~32. Showing both as plain numbers implies an equal confidence
   that is not there.

---

## Rejected

| Proposal | Why not |
|---|---|
| Card appears once the substance shows an effect | Circular; biases displayed effects upward, worst where data is thinnest |
| Literature list as the gate on which substances are analysed | Cannot cover the unknown; answers are frequently "studied, not established"; says nothing about *this* person |
| Reuse the wearing-off renderer with an internal branch | One renderer answering two questions — the defect the `20` item exists to remove |
| Raise the dose count instead of removing it | Swaps one arbitrary number for a larger one |
| Cross-substance ranking in copy | p=0.52 on the reference data, and a dosing judgment the safety line forbids |
| A "does this substance work" classifier | Needs a margin; no validated tremor MID exists, and the own-variability margin is circular. Replaced by "does it have a measurable duration" |
| Blanket-deleting `doseOnWindowFallback` | Coverage wants nothing, the food/exercise guard wants a protective default. Split, don't delete |
