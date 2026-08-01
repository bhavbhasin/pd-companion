# Therapy logging: record the session, report the facts, never the verdict

**Status:** DESIGNED Jul 31 2026, not built. Originated with tester John S, who wants Kampa to
measure whether home therapies (ozone, CO₂, PEMF) and clinical ones (TPS, bodywork, acupuncture)
help his tremor and his non-motor symptoms.

**One line:** users log therapy sessions as timed events; Kampa shows what its data actually holds
around those sessions — each session, a fixed window, and the usual range beside it — and never
states whether the therapy worked.

---

## Why the effect answer is withheld

John asked for the effect answer. The honest response is that Kampa's data cannot support one, and
that saying so is the feature, not a limitation of it.

### 1. Event frequency is 10-100× too low

Levodopa doses arrive 3-5×/day, so weeks of use produce hundreds of events. Acupuncture is weekly.
A TPS course is ~6 sessions total. The existing gates already produce no card for protein at higher
n than that. A therapy card either says nothing for months, or it fires on n=6 and is wrong.

### 2. The confound is worse than caffeine's

The Jul 31 re-measurement found caffeine's apparent +0.212 was indistinguishable from its own null
(permutation p 0.84), and walking survived only marginally (p~0.049, not 0.0019). Therapies carry a
confound caffeine does not: **people book treatment when they feel worse.** The "before" window is
selected for being bad, so regression to the mean improves the "after" on its own. A naive pre/post
comparison will show every therapy working.

### 3. Non-motor outcomes make it worse, not better

The only non-motor outcomes available are self-reported mood and fatigue — the channel most exposed
to expectation effects. Measuring an expensive elective therapy against self-report is close to
guaranteed to produce a positive result. (HealthKit has no apathy/depression type; see
`project_kampa_symptom_logging`.)

### 4. The claim is stronger than anything Kampa currently makes

These are unregulated, out-of-pocket treatments. "PEMF helped your tremor" is a purchase
recommendation wearing the clothes of data, and it cannot be retracted after someone has paid for a
course. The launch checklist commits to observation-only. This is the line it was written for.

**⛔ Do not add an effect verdict, a confidence tier, or a recommendation to any therapy surface.
If the engine ever earns one, it earns it through the experiment loop with a control arm — not
through passive correlation.**

---

## What ships

### Logging

`+ → Therapy` (**not** "Custom" — see [Naming](#naming)). The screen lists previously logged
therapies and offers a free-text field to add a new one. Selecting one logs a session with a start
and an end time, the same shape as Mindfulness.

New SwiftData `@Model`, CloudKit-synced. Unlike Mindfulness, there is **no HealthKit type for this**,
so it lives entirely in Kampa's own store — always editable, no `source`, no `isEditable` rule.
Requires an additive Production schema deploy before shipping.

> ⚠️ **Add it to `CSVBackupExporter`, `cleanupDuplicates`, and `SupportDiagnostics` in the same
> commit.** `DyskinesiaReading` missed all three for a month because each was treated as a separate
> afterthought; the gap was only found during a delete/reinstall test (`73ee63a`).

### Timeline

Therapy sessions appear on the day timeline like any other event. One `DayEvent` case plus the
`id` / `time` / `symbol` / `color` / `label` arms, and the mirrored set in `VoiceLogView`.

`label` returns the **user's own therapy name**, not a fixed string — the one shape change, since
every existing case returns a constant.

**One shared icon and colour for all therapies.** Users do not pick per-therapy glyphs. A single
symbol makes therapy a legible band on the timeline regardless of modality; per-item icons are noise
and a maintenance surface. The name carries specificity, the glyph carries the category.

### The facts panel (later, not v1)

Ship logging with the engine silent. The first analysis surface is facts, no verdict:

- **One row per session, never an average.** Six rows of real numbers stay facts. One averaged
  number looks like an estimate, and at n=6 it is not one.
- **A fixed before-window, declared once.** Always the same span before every session (24h). Never
  chosen per session — that is exactly how the comparison anchors onto the bad patch that prompted
  the booking.
- **The usual range beside it**, reusing the band from `e0ec548`. If the post-session value sits
  inside the user's usual range, the panel says so. That single line removes most of the false
  signal and needs no new machinery.

Two numbers side by side are already a claim. The control context is what keeps this factual.

---

## Naming

**"Therapy," not "Custom."** Not a wording preference — it decides what is being built.

"Custom" is an empty box, so it fills with naps, travel, work stress, arguments. That makes Kampa a
general life-event logger: more flexible, unbounded, and useless to an engine that needs repeated
instances of a defined thing. "Therapy" stays a bounded concept with free-text names inside it,
which is what an experiment loop can eventually work on. "Custom" is also a developer's word — nobody
thinks *"I am logging a custom."*

---

## Why log at all, if no effect answer

Independent of any verdict, these sessions are currently **invisible variance**. If John has
acupuncture on Tuesdays, his Wednesday readings are already shaped by something the record does not
contain. Logging makes every *other* insight more honest. That value does not depend on ever
measuring the therapy itself.

---

## Open

- **Duration vs point-in-time.** Bodywork and acupuncture have a clear start/end; "took an ozone
  sauna this morning" may not. Does end time stay required, or optional with a default?
- **Voice path.** The in-app "+" mic is the reliable logging route
  (`project_kampa_voice_logging`). "Log PEMF for 20 minutes" needs a parse rule, and the therapy
  name is open-vocabulary — unlike food, there is no corpus to match against.
- **Rename/merge.** Free text guarantees "PEMF", "pemf", and "P.E.M.F." become three therapies.
  Needs at least case-insensitive matching on entry, and probably a merge affordance later.
- **Does a therapy belong in the lever audit matrix** (`lever-audit.md`), or is it deliberately
  outside it because no effect claim is ever made?
