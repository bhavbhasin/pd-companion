# Movement checks: a standardized measurement the passive record cannot take

**Status:** v1 BUILT Aug 5 2026, then rebuilt around two measurement defects found in his own export
(below). Model + capture + result + history/trend + timeline event all in. Joins the CloudKit
Production schema deploy already owed for therapy logging — **not deployed, and the trial now carries
five more fields than when that was last scoped.** Originated with tester John S, who asked for
bradykinesia measurement and pointed at the SteadyHands app and "hand rotation, typical neurologist
tests."

### ⭐⭐ Two measurement defects, both found in data, both fixed Aug 5 2026

Neither was visible on screen; both were counted out of a CSV export. This is the section to read
before touching capture again.

1. **The gap between the drawn boxes was dead space.** 15mm of protocol gap renders ~79 pt, and
   landings hug the facing edges of both boxes — so an undershoot hit nothing and the app recorded
   nothing. Measured across 6 trials: **26.3% of intended bottom-box taps never registered** (73
   registered, 26 lost), against **2.9%** for the top box. Neither speed nor landing position
   predicted a miss — the slowest trial lost the most. ⇒ **The drawn boxes keep the protocol's
   dimensions; the LIVE area is the whole surface**, every touch assigned to the nearer target.
   ⚠️ This corrupted the between-hands gap, which is the entire control arm: restoring the lost taps
   moved one session from left −2 to left **+1**, and another from +6 to **+10**.
2. **Taps were stored in each target's own local coordinate space**, so the distance between the two
   boxes was absent from every stored tap and "travel" summed only the scatter inside a box. 37 taps
   reported 0.4 m where the geometry demands ~1.6 m; one trial implied 5.6 mm per crossing across a
   15 mm gap, which is impossible. ⇒ one shared coordinate space, **and the capture geometry is now
   stored on the trial** — raw taps are not self-describing without it, so "re-derivable without a
   retest" was false for anything positional.

⛔ **The capture surface is UIKit `touchesBegan`, not a SwiftUI gesture — do not convert it back.**
Every recognizer available can decline a touch: `SpatialTapGesture` needs a press-and-release that
stays roughly still, so a fast or tremor-affected tap that slides is discarded. This screen lost two
rounds of device testing to recognizers dropping or losing arbitration over taps (first to the
sheet's drag-to-dismiss, then to the tap recognizer itself). `touchesBegan` cannot decline. Touch-DOWN
is also the better timestamp for a speed test than touch-up, which adds a variable dwell.

**One line:** a short, user-initiated movement trial behind the `+` sheet, reporting raw physical
quantities against the user's own usual range — never a score, never a verdict, never a clinical grade.

---

## Why this earns an exception to the no-active-tests rule

BACKLOG's bradykinesia entry carries a hard line: **"NO active assessment tasks — collides with the
ambient/zero-burden principle."** This design narrows that line rather than deleting it. The principle
was always that Kampa must never *require* effort; it was never that a user may not reach for a tool.
Behind `+`, nothing nags: no streak, no badge, no daily prompt. A user who never taps it never learns
it exists.

⇒ **Amend the BACKLOG line to: no active task may be required, scheduled, streaked, or scored.**

### Why only bradykinesia, and ⛔ never tremor

SteadyHands' four tests (virtual glass of water, shape tracing, photo of a drawing, dot touching) are
**all tremor**, and Kampa already measures tremor ~1,351×/day passively. A once-daily 30-second sample
is a worse instrument for something already held continuously — and worse than redundant, it builds a
**contradiction surface**: the test reads steady, the passive record shows the hand shaking, and the
user has to decide which to believe. The Parkinson's UK panel reported exactly that failure (a
reviewer scored 10/10 "perfect" while visibly shaking). ⛔ Do not build a tremor check.

Bradykinesia is the opposite case: **no passive stream exists.** Apple's Movement Disorder API does not
provide it, and gait only reaches lower-limb slowness. Redundancy is the objection to an active test,
and here the objection does not apply.

---

## What ships

### Naming: **"Movement check"**

Not a preference — it decides what is built, the same way "Therapy" did in `therapy-logging.md`.

- ⛔ **"Test"** implies a grade and something to fail. The first question it invites is *"did I pass?"*,
  which is the question this surface must never answer.
- ⛔ **"Tap test"** locks the category to one instrument before the second one is designed.
- ✅ **"Check"** implies a reading taken, not a grade awarded. **"Movement"** is the honest category
  and the patient-facing word — it also matches the vocabulary Apple already put on screen.

### The `+` sheet

One new `LogEntrySheet.Destination` case beside `.food` / `.mindfulness` / `.symptom` (and `.therapy`).

### The tests — ⭐ ONE in v1

| test | neurologist analogue | instrument | ships |
|---|---|---|---|
| **Alternating tap** — two targets, 10 s | UPDRS 3.4 finger tapping | screen touch timestamps | ✅ **v1** |
| **Hand rotation** — hold the phone, rotate the wrist, 10 s | UPDRS 3.6 pronation/supination | gyroscope | ⬜ later |

**Start with the tap alone.** Touch timing is exact and needs no sensor calibration; rotation amplitude
needs a defensible unit and is the harder measurement to make honest. One test also keeps the
practice-effect baseline (below) readable while it is being established.

#### ⏸ Hand rotation — PARKED Aug 4 2026, and the reason is a decision rule, not a preference

⭐ **One watch measures one wrist.** The Watch is the better instrument in principle — it sits on the
rotating segment, it is already worn, and nothing has to be gripped. But Kampa's onboarding puts it on
the **more-affected** wrist, so a Watch-based rotation check can never produce the less-affected
control arm that the both-hands decision above depends on. The phone version can (hold and rotate each
hand in turn) but changes the movement it measures: added mass, a grip, and a real drop risk for
someone rotating fast with a tremor. ⛔ Mixing them — watch on one wrist, phone in the other hand — is
two instruments and not comparable.

⇒ **The choice is settled by an empirical question that cannot be answered yet:** does the
**gap between hands** carry signal in the tap data? If it does, both hands are mandatory and the Watch
is disqualified for this test. If it does not, the Watch wins outright. **Ship the tap, look at the
gap, then design rotation.**

⚠️ **Two facts to verify on-device before any rotation design, not to assume:**
1. The watchOS floor is **10.0** (`project.pbxproj`) ⇒ Series 4 and later, all of which carry
   gyroscope hardware. But raw gyro access on watchOS is not a given — a developer report has
   `isGyroAvailable` returning **false** on a Series 6 while the accelerometer returned true. The
   supported path is `CMDeviceMotion` (`rotationRate` + `attitude`), **not** `startGyroUpdates`. A
   20-minute device check settles it.
2. The Watch app today uses **only** `CMMovementDisorderManager` — no raw motion anywhere in the
   target. This is new ground there, and it adds an interactive Watch surface plus a new
   WatchConnectivity stream. ⚠️ The last new stream (build 6's full tremor distribution) is what
   caused the build-9 sync failure — see `watch-sync-payload-options.md`.

### ⭐ Both hands, every session — DECIDED Aug 4 2026

PD bradykinesia is **asymmetric**, so the two hands are the comparison. Bhav's call, and it matches the
validated protocol, which tested each hand separately. **The less-affected hand is the control arm** —
the one thing this design otherwise lacks. A slow day shows in both hands; disease progression or a
dose wearing off shows as the *gap between them* widening. That comparison is free, needs no
population norm, and is the only internal control available.

Every trial stores which hand; usual range, history and trend are all **per hand**. Same class of
decision as picking the more-affected wrist at onboarding — get it wrong and everything downstream is
quietly wrong.

### ⚠️ Posture is fixed and stated once

Phone flat on a table, tap with the index finger, same every time. A trial taken with the phone in the
other hand is not comparable to one taken on a table, and the app cannot tell the difference. The
instruction line is part of the measurement, not UI copy.

### Protocol — taken from the validated study, not invented

⚠️ **Corrected Aug 4 2026 after reading the literature.** The first draft of this doc asserted "10 s is
the common digital-tapping convention" as an assumption and starred **decrement** as the quantity that
mattered. Both needed checking; one was wrong.

| | this design | source |
|---|---|---|
| duration | **10 s** | [Lee et al., PLOS One 2016](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0158852) — validated against UPDRS. ⚠️ [mPower](https://www.nature.com/articles/s41598-022-06572-2) uses **20 s**; both exist, 10 s is the one validated against bradykinesia subscores |
| targets | two rectangles, 30 × 45 mm, 15 mm apart | same |
| finger | single index finger | same (mPower uses two fingers of one hand) |
| phone | flat on a surface | mPower states it explicitly |
| hands | **both, separately** | same — and it is what gives the asymmetry baseline |
| trials | **1 per hand** (study used 3, averaged) | ⚠️ **declared deviation** — 3 per hand is 6 trials a session and becomes the burden this design exists to avoid. Costs precision; say so rather than hide it |

### What a trial reports — no score

⛔ **Decrement is NOT the headline. Corrected.** The validation study *"failed to find parameters that
reflected fatigue (decrement response)"* — their variance measures did not separate PD from controls on
a phone. Decrement is what a neurologist watches for by eye, and it is apparently the thing a
touchscreen is worst at. It is free to store once the timestamps exist, so **store it, don't lead with
it, and claim nothing for it.**

| quantity | why |
|---|---|
| ⭐ **taps in 10 s** | *"correlated highest with bradykinesia"* of every measure tested. The simplest number is the one that works |
| **total finger travel** | AUC **0.92** — the strongest discriminator in the study after tap count |
| **inter-tap dwelling time** | significant discriminative power; the pause, not the movement |
| *(decrement, stored only)* | no evidence it works on a phone. Recorded for later, shown nowhere |

⚠️ **Travel is less independent than this table implies.** The targets are at fixed positions, so
correct total travel is close to (crossings × a constant) and therefore tracks the tap count. The part
that varies on its own is **accuracy** — how far each tap lands from the target centre — which is
computed and stored (`offTargetMean`) but not yet displayed. If travel ever needs to earn a surface of
its own, that is the quantity to put there, not the raw distance. ⚠️ Note the buggy local-coordinate
version was accidentally measuring roughly this, which is why it looked informative.

Each sits beside **the user's own usual range**, reusing the `p10`/`p90` band shipped in `e0ec548`,
and every range is **per hand**. ⭐ **Both hands render as a MATRIX, not as two stacked blocks** (his
call, Aug 5 2026): the between-hands gap is the signal, and stacking put the two numbers far enough
apart that comparing them required scrolling — the layout was hiding the comparison the feature exists
for. One dose line for the session, not one per hand.

```
                    Left      Right
Taps                  45         37
Spread              5 mm      11 mm

Last dose was Sinemet at 2:40 AM, Aug 5
Spread is how far your taps landed from the middle of the box, on average.
```

⛔ **Pause and Travel were both rows here and were both removed Aug 5 2026. Do not put either
back as a displayed metric.** Both restate the tap count: pause is the rate inverted, and with
fixed targets travel is close to (crossings × a constant). The matrix was showing one measurement
three times, and "Travel 2.4 m" invited "my finger moved two metres?" while adding the least. Both
are still computed and still exported.

⭐ **The displayed set is Taps + Spread, on EVERY surface** — matrix, result screen, history charts.
Consistency here is structural, not a per-screen choice: there is one `Metric` enum per surface and
both list the same two cases, and the definition sentence lives in `MovementCheckCopy` so it cannot
drift between them. ⛔ There is no `showsDefinitions` flag any more — whether a word needs defining
is a property of the word, not of the screen you meet it on.

### Pre-roll: 3-2-1 before the clock starts

⭐ **Protects the measurement, not just the nerves.** Starting the 10 s on the button press means
the finger is still travelling to the first target while the clock runs, so the opening gap measures
reaction time rather than tapping speed — and it rewards whoever felt least rushed. `startDate` is
set when the pre-roll ends, taps are ignored until then (`started` is still false), and each count
carries a haptic tick because during the pre-roll the eyes belong on the boxes, not on a number.
⚠️ **Spread is deliberately not called "accuracy"** — that reads as a grade, and this feature never
issues one. It is a distance. It earns its row by being the one recorded quantity free to vary when
the tap count doesn't; ⛔ it is NOT validated (the study measured count, travel and dwell) and it
carries its own confound: tap faster, land sloppier.

## Rotation (pronation-supination) — BUILT Aug 6 2026

⭐ **Better validated than Tapping, which we built first.** CloudUPDRS ran 16 smartphone subtests
against the same blinded raters: pronation/supination predicted its MDS-UPDRS subitem at **74.6% /
73.0%**, finger tapping at **53.2% / 62.9%**. Full evidence, citations and the rest of the battery
are in the research memory `reference_pd_active_test_protocols`.

**Protocol** (Roche PD Mobile Application v2, the version that shipped to 316 patients at ICC
0.92–0.95): phone **held flat on the palm**, arm outstretched, turn palm up / palm down as fast and
as fully as possible, **10 s per hand**. ⚠️ A 20 s variant exists in the analytical-validation
paper; 10 s is what shipped and it matches Tapping so a session stays one length.
⚠️ Declared deviation: Roche validates the dominant hand only. We do both, matching MDS-UPDRS 3.6,
which scores each hand separately — and both hands is the only control arm this design has.

**Algorithm:** `CMDeviceMotion` at 100 Hz → **PCA for the true axis of rotation** → project to one
channel → derived-cutoff zero-phase low pass → count reversals.
⭐ The PCA step is what makes it survive an arm held at whatever angle is comfortable; assuming roll
about the device's long edge would silently measure a projection of the real movement, and a test
pins that this under-reports by ~40% at a realistic arm angle.
⛔ **The filter cutoff is DERIVED (3x the trial's own dominant frequency), never a constant.** PD
rest tremor (4–6 Hz) overlaps the voluntary rotation band (~1–5 Hz), so no universal cutoff
separates them and a wrong fixed one is unrecoverable.
⛔ Turn counting is **threshold-free**: a half-turn ends where the signal reverses, so there is no
"how big must a wobble be" constant to get wrong. The filter is what stops noise inventing turns —
pinned by a test that rides 5 Hz tremor on 1.5 Hz rotation and still counts 30 ± 2.

**Displayed: Turns + Amplitude.** Both earn a row — MDS-UPDRS scores speed and amplitude separately,
someone can flip fast-and-shallow or slow-and-full, and a test pins that they separate on synthetic
signals. ⛔ **Turns/second is NOT shown** — with a fixed 10 s it is the turn count scaled, the same
restatement that removed Pause and Travel from Tapping. Peak velocity and decrement are computed and
exported, displayed nowhere.

**Stored:** the single-axis angular velocity series **plus the axis it was projected onto**, plus the
sample rate. One channel, not six. ⚠️ Without the axis and rate the series is unreadable — the same
rule the tapping geometry fields exist for: *storing a raw measurement means storing the frame it was
measured in.*

⚠️ **Safety copy is part of the design, not boilerplate:** this is the one test that has the user
waving an unsecured phone at arm's length. Instruction says sit down, over a lap or sofa.
🚨 **Needs a SECOND additive CloudKit Production deploy** (`CD_RotationTrial`) before it reaches a
TestFlight tester.

### The category is a chooser, not a list of tests

`+` shows ONE **Movement check** row; it opens a full-screen cover whose first screen picks
**Tapping** or **Rotation**. ⛔ The chooser SWAPS its content rather than pushing, so whichever
test runs is still the ROOT of that stack. That preserves two things each paid for with a
device-testing round: no `.sheet` drag-to-dismiss gesture competing with a tap, and exactly one
explicit Cancel per screen rather than a back button arguing with it.
⚠️ Two rows in the log sheet was tried first and was wrong for a plain reason: the list grew
past the voice button, and rows scrolled behind it. This is also where leg agility goes.

⭐ **Practice-effect disclosure MOVED to the result screens** (both instruments, one shared
constant). It exists to stop an improving number reading as a symptom change, so it belongs
next to the numbers — not before a test, where there is nothing yet to misread. It also left the
instructions screens with one block of grey text instead of two.

⭐ **Rotation's instruction is DEMONSTRATED**: a looping 180° flip of an `iphone` glyph, drawn in
SwiftUI. "Flat on your palm, arm out, turn it over" is three things to get right at once, and
this is the test where doing it wrong yields a plausible-looking wrong number rather than an
obvious failure. ⛔ Not a video — no asset to host, works offline, follows light/dark for free,
and it keeps the standing "no video inside the app" decision intact.

⚠️ **Rotation gets its own timeline glyph, tint and legend row** — not a shared "Movement check"
marker. Two instruments on one glyph would leave the timeline unable to say which you did.

### Naming: **Movement check** is the category, **Tapping** is the instrument

His call, Aug 5 2026, prompted by a detail card titled "Left hand" above a matrix showing both
hands. Screens (landing, capture, result, history) and the timeline legend say **Tapping**; the `+`
row and the detail-card eyebrow stay **Movement check**, which is the door a future rotation or
balance test comes through. ⛔ **"Tapping", not "Tap test"** — the `LogEntrySheet` guard still holds:
a *test* implies a grade and invites "did I pass?", which this surface must never answer. An action
name scales to "Rotation" and "Balance" without that.
⚠️ **The `@Model` stays `MovementCheckTrial`.** Renaming it changes the CloudKit record type
(`CD_MovementCheckTrial`) and orphans every synced record. This is display copy only — and the class
name is right for the hierarchy anyway, since the container is the category.

⛔ **No delta column, and no highlight on the faster side.** Two columns already invite a scoreboard
reading. The numbers sit next to each other; the reader does the comparing.

⛔ **No 1-10 score, no cross-person norm, no UPDRS number, no verdict.** Same grammar as every other
surface in the app. Cold start: withhold the range and say what is still needed, per
`insights-card-confidence-redesign.md` — never print a range built on two trials.

### Where medication shows up

**v1: as a fact on the row, never a comparison.** Each result and history row prints the trial's
position in the dose cycle, which the record already knows:

```
14:47   left hand   4.2 taps/sec   ·   2h 10m after your 12:37 Sinemet
```

Trials also appear as events on the day timeline, so they sit against the same dose markers as
everything else and the eye can do the work.

⛔ **No before/after verdict in v1**, inheriting the rule from `therapy-logging.md` verbatim: no effect
answer, no confidence tier, no recommendation. The confounds here are *worse* than therapy's, and there
are two:

1. **Selection.** This is the first Kampa surface where a user can generate a measurement on demand —
   so they will generate one when they notice something. The window is chosen for being unusual.
2. ⚠️ **Practice.** People get measurably faster at tapping over the first weeks regardless of
   medication. Early "improvement" is learning, not levodopa. ⇒ **The onboarding line for this feature
   must say so**, and any later effect analysis must model it or be wrong in the flattering direction.

**v2 (not v1): paired trials around a single dose.** The user opts into *one* pairing — a trial now,
an offer of a second at +90 min — and the two are shown side by side as two facts. One opt-in pairing,
never a standing schedule; a standing schedule is the streak mechanic through a side door.

### Trend and history

⛔ **Not a glance tile and not a Day-in-Review panel.** A movement check is sparser than gait, which was
already parked for a daily panel because it has no honest daily shape (`trend-surface-design`).

✅ It lives **inside the feature**: a history list and a trend reachable from the result screen and from
the `+` entry. One point per trial, timestamped, **split by hand and by test type**. Reuse
`TrendChart` and the scrolling detail-sheet work from `3530adc` — range is the window width, the
y-domain fits the whole series, and it already pans through the entire record.

### Storage

New SwiftData `@Model`, CloudKit-synced, additive Production schema deploy. No HealthKit type exists,
so it lives entirely in Kampa's store — always editable.

> ⚠️ **The new `@Model` joins `CSVBackupExporter`, `cleanupDuplicates` and `SupportDiagnostics` in the
> SAME commit.** `DyskinesiaReading` missed all three for a month (`73ee63a`).

---

## Closed Aug 4 2026

- ✅ **Trial length = 10 s**, from the PLOS validation protocol. See the protocol table.
- ✅ **Decrement statistic — moot.** Demoted; the study found no phone-measurable decrement parameter.
  Store it, show nothing.
- ✅ **Both hands per session.** The less-affected hand is the control arm.
- ✅ **Lever-audit matrix — NO, deliberately outside it.** The matrix inventories *levers*: things that
  plausibly move the symptoms and that a user could change. A movement check changes nothing — it is a
  **ruler, not a lever**. Adding it makes the matrix mean two things at once and blunts the capture-gap
  question it exists to answer. (Therapy logging is the opposite case and *does* belong: a therapy is
  something the user does to feel better.)

## Closed Aug 5 2026 (build)

- ✅ **Store raw taps, not just aggregates.** `MovementCheckTrial.taps: [MovementCheckTap]`
  (Codable struct, not a second `@Model` — no relationship, no cascade-delete risk this codebase
  has zero precedent for). Taps/travel/pause/decrement are all computed at read time in
  `MovementCheckMetrics`, so a future change to any of them applies retroactively. Matches the
  store-rich-reduce-at-read rule already governing `TremorReading`/`DyskinesiaReading`.
  ⚠️ **Amended Aug 5 2026: raw taps alone were NOT enough.** A tap is a point in the capture
  surface's space, and that space is sized per device — so without the geometry, a stored distance
  could not be converted back to millimetres by the app or by anything reading the export. The five
  geometry fields now on the trial are what make the claim above actually true. **Rule: storing a
  raw measurement means storing the frame it was measured in.**
- ✅ **Target layout is a per-device best-effort, not the literal protocol size.** Two 45mm
  targets + a 15mm gap is taller than an iPhone SE2's entire screen — physically cannot fit any
  iPhone in portrait at true scale. The layout scales down only as far as the screen forces,
  consistently per device, **and the scale used is stored on every trial**, so a reading is never
  orphaned from it. A single patient stays on one physical device, so this doesn't corrupt their own
  "usual range" comparison, but absolute travel/mm numbers still aren't comparable across models.
  ⚠️ `pointsPerMM` was a flat `163/25.4` for every iPhone, which drew the targets ~6% oversized on
  every @3x device (~153 points/inch, not 163). Now display-scale aware at draw time — and read time
  no longer uses it at all: a trial recovers its own scale from the drawn box, which is 45mm tall by
  protocol whatever the estimate was.
- ✅ **Taps and travel plot as two stacked panels on ONE shared x-axis; pause is never plotted.**
  ⛔ Pause is `(last - first) / (n - 1)` — the tap rate inverted. Measured on the Aug 5 export, every
  trial returns its own ~9 s span when pause is multiplied back by its gap count, at 19, 21, 31 and
  37 taps alike. Charting it beside taps draws one signal twice, mirrored. It stays a fact row.
  Taps and travel are NOT normalized onto a shared y-axis either — that axis reads in no unit anyone
  can name. Small multiples, locked to the same window.

## Open

- **Cold-start range.** How many trials per hand before a usual range is honest? Unmeasured, and there
  is no reason to guess — it is answerable from the first weeks of real trials. The `8`-trial gate
  shipped in v1 reuses the existing tremor/HRV usual-range convention (`e0ec548`) rather than
  answering this properly — revisit once real trial data exists.
- **What a re-test right after a bad trial does to the record.** A user who dislikes a result will tap
  again. That is the selection effect operating within a single minute.
