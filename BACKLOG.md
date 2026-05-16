# PD Companion — Feature Backlog

Tactical queue of features. Strategic context for each phase lives in [ParkinsonsProject.md](ParkinsonsProject.md).

Updated as features move through Backlog → In Progress → Done (or Blocked / Conditional / Speculative).

---

## Status legend

| Status | Meaning |
|---|---|
| **Backlog** | Queued, not started |
| **In Progress** | Actively being built |
| **Done** | Shipped |
| **Blocked** | Waiting on prerequisite (data, decision, external) |
| **Conditional** | Only build if specific signal triggers the need |
| **Speculative** | Might never build; depends on external factors (Apple API additions, etc.) |

---

## Phase 1 — Foundation & Telemetry

Strategic context: [ParkinsonsProject.md → Phase 1](ParkinsonsProject.md#phase-1---foundation--telemetry-current-focus)

### Workout type breakdown — Done (commit 0c07443, May 10)

Replaced generic `appleExerciseTime` "Exercise: X min" with workout-type-aware tile. Distinguishes Tai Chi, Pickleball, HIIT, etc. via `HKWorkout` samples grouped by `workoutActivityType`. Foundation for Phase 2 type-aware correlation.

**Why this mattered:** For PD correlation, the *type* of exercise matters more than total minutes. Tai Chi consistently reduces PD tremor (well-documented in literature); HIIT may increase it temporarily. Without type granularity, the correlation engine can't answer the questions a PD patient actually wants answered.

### Watch app display name fix — Backlog

Watch app currently displays "PD" in the home screen / app list. Should be "PD Watch" or similar. Cosmetic, in target General tab in Xcode. Loose end from Session 4 (May 8).

### CloudKit sync for SwiftData — Backlog (HIGH PRIORITY)

`ModelContainer` in `PD_CompanionApp.swift:13` is local-only. `TremorReading` and `FoodEvent` rows live exclusively on this iPhone — phone replacement, app deletion, or restore-from-old-backup permanently destroys the longitudinal dataset. HealthKit-backed data (sleep, HRV, workouts, medications, mindfulness, daylight, steps) is safe; SwiftData is not.

**Why this matters:** The whole Phase 2/3 correlation thesis depends on accumulating months/years of intersected tremor + event data. Every day without iCloud sync compounds the risk. As of May 14 we have ~7,500 tremor readings across 7 days that are one device-loss away from being gone forever.

**Implementation:**
1. Switch `ModelContainer` init to use `ModelConfiguration` with `cloudKitDatabase: .private(...)` for the app's iCloud container
2. Audit `TremorReading`, `FoodEvent`, `HealthSnapshot` for CloudKit constraints — all stored properties must be optional or have defaults; relationships (none currently) need inverses
3. Add CloudKit container ID to entitlements; verify Apple Developer portal has the container provisioned
4. Test: delete app on iPhone, reinstall → verify history restores from iCloud
5. Test: install on a second device → verify sync

**Discussed Session 8 (May 14)** — pending implementation, picked back up for evening session.

### Tremor chart — Done (May 15)

Full history: shipped as `LineMark` (May 11) → switched to `BarMark` (May 14) to eliminate an apparent midnight gap (rightmost hourly bucket had no successor to draw a line segment to) → switched back to `LineMark` + `AreaMark` (May 15) because bar chart felt less clinical than a smooth curve.

**May 15 final state:**
- `AreaMark` (blue gradient fill, 35% → 5% opacity) + `LineMark` (solid blue, 2pt stroke), both using `.catmullRom` interpolation for smooth curves between hourly buckets
- Midnight gap fixed via a synthetic `HourBucket` appended at `dayEnd` carrying the last known value, so the line always runs to the chart's right edge
- Horizontal scroll fixed: removed `chartOverlay` blanket view (which intercepted all touch events). Replaced with a split layout — top 36pt of plot area is hit-testable via `simultaneousGesture(SpatialTapGesture())` (where event icons live); remaining area has `allowsHitTesting(false)` so scroll passes through untouched
- Event icons (`PointMark` at y=4.3 + `RuleMark` dashed verticals) remain as visual decoration inside the chart; tapping near them in the top strip opens the event detail sheet
- Legend below chart (Medication / Workout / Meditation / Food) filtered to only show categories with events on that day

### Layer 4 workout session — Conditional

Fallback for guaranteed continuous background runtime via `HKWorkoutSession`, if Apple's discretionary `WKApplicationRefreshBackgroundTask` (Layer 1) proves too unreliable in real-world wear.

**Why:** `HKWorkoutSession` configured for a low-impact activity type (`.other` or `.preparationAndRecovery`) gives near-guaranteed continuous runtime — the Watch keeps the app alive 24/7 like a fitness tracker, bypassing Apple's discretionary refresh scheduling. Real cost: ~15–20% extra battery drain per day, plus a workout indicator stays visible on the Watch.

**Trigger:** Only build if Bhav reports real-world data gaps that don't resolve via CoreMotion's ~24h processing lag. Decision deferred in Session 5 — wear what we have for a few days first.

**Implementation when triggered:**
1. Add an "always-on" toggle in settings (off by default)
2. When on, start a long-running `HKWorkoutSession` with low-impact activity type
3. Inside the session, query CoreMotion every ~5 min and sync to iPhone
4. Display a status indicator that always-on mode is active so user knows about the battery cost
5. Honor the session through Watch reboots if possible

---

## Phase 2 — Correlation Engine

Strategic context: [ParkinsonsProject.md → Phase 2](ParkinsonsProject.md#phase-2---correlation-engine)

### Review tab — In Progress

Originally scoped as "Insights tab," reframed as "Day in Review" on May 11, then shortened to "Review" the same day for tab-bar fit. Will rename to "Insights" once Phase 2 correlation logic delivers computed observations.

**Shipped (May 11):** daily-primary view (default to yesterday), date chevrons, glance card (sleep/tremor/HRV/daylight — 4 tiles), tremor chart with event overlays, sleep stages chart (Awake/REM/Core/Deep horizontal bars), Observations placeholder. App is now single-screen — Today tab killed May 11.

**Shipped (May 14–15):**
- `+` button moved to top-left toolbar; Watch icon stays top-right
- Log Entry sheet: menu (Food / Meditation) → individual sub-screens
- Food logging: free-text description + native `DatePicker(.compact)` — design simplification, ML extracts attributes later (see food logging entry below)
- Meditation logging: date/time + duration stepper + quick picks; writes `HKCategorySample(mindfulSession)` to HealthKit; appears on tremor timeline
- All event types (medication, workout, meditation, food) show on tremor timeline with icons
- Tapping event icons (top strip of chart) opens `EventDetailSheet`
- `EventDetailSheet`: icon + category label + title + detail line; food entries show description + detected attribute chips
- Edit/delete from detail sheet: food → full edit (pre-populated `EditFoodScreen`) + SwiftData delete; meditation → HealthKit sample delete; medication/workout → "Manage in Health app" note
- Observations panel shipped (see separate entry below)

**Backlog (next):** Apple Sleep Score reproduction (Duration 50 + Bedtime 30 + Interruptions 20 = 100) as a header above the sleep panel.

**Step 2 onward:** Scatter plots with lag, lag analysis, correlation matrix / heatmap. Wearing-off and on-off patterns are fundamentally about lag — must be a first-class chart type.

**Phase 3 only:** Predictive forecast UI based on Core ML model.

### Day-scoped Observations panel — Done (May 15)

Rule-based engine that generates plain-language observations from a single day's data — no historical baseline required. Lives in `ObservationsPanel.swift` (`ObservationEngine` + `ObservationsPanel` + `ObservationCard`). Feeds the "Observations" section of the Review tab.

**Rules shipped:**
1. **Post-dose tremor effect** — compares avg tremor 30 min before a dose vs. 30–90 min after (levodopa absorption window). Reports % change; positive if ≥15% reduction, negative if ≥15% rise.
2. **Post-workout effect** — same window logic (30 min pre → 60–90 min post-workout end). Flags workout types by name.
3. **Tremor trajectory** — splits day into morning/afternoon/evening; reports which period had lowest avg tremor if the spread is ≥0.3. Requires ≥3 readings per period.
4. **Caffeine effect** — keyword match on food descriptions (coffee, espresso, matcha, cola, etc.) + `FoodAttribute.caffeine`. If tremor rises ≥20% in the 30–60 min window after, flags it.
5. **Protein-dose proximity** — flags meals containing protein (keyword match + `FoodAttribute.protein`) that fall within 1 hour of a dose. Levodopa competes with dietary protein for absorption.
6. **Sleep context** — flags short sleep (<6h) and low deep sleep (<30 min) with PD-relevant context.

**Design decision:** Named `DayObservation` (not `Observation`) to avoid shadowing Apple's `Observation` framework, which `@Model` macro expansion depends on.

**Next:** This engine is day-scoped and rule-based. The Continuous time-windowed correlation engine (below) is the longer-horizon successor that uses statistical validation across weeks/months of data.

### Continuous time-windowed correlation engine — Backlog

**Core architectural feature.** The engine that powers all per-day Observations and aggregate Insights surfaces.

**Three properties (locked May 11):**

1. **Continuous, not one-shot.** Engine runs on a cadence (nightly background task + on-demand refresh), incorporating all data accumulated to that point. Mandatory for a progressive condition — "normal" drifts as the disease progresses and as the user adapts behaviors.
2. **Time-windowed.** Engine API takes a `DateInterval` window. Same data + different windows = different insights. Cache common windows (7d, 30d, all-time) in SwiftData; recompute uncached windows on demand. Surface a "based on N days" badge on any insight derived from a short window so users can judge reliability.
3. **Window-comparison is its own insight type.** Comparing one window against another surfaces *change* — clinically meaningful for PD specifically. Examples:
   - "Morning tremor is 25% higher this month than your 6-month baseline" (possible progression / medication wearing off)
   - "Sinemet effect window shortened by 12 min in the last 30 days vs. all-time baseline" (classic wearing-off signal)
   - "Tai Chi tremor reduction was 35% three months ago, only 12% in the last month" (intervention losing potency or baseline rising)
   These are observations that StrivePD doesn't do, the neurologist sees too rarely to catch, and the patient can't reliably notice subjectively.

**Trade-off to surface in UI:** responsiveness vs. reliability. Short windows react fast but have weak statistical power; long windows are reliable but slow to detect recent changes. Don't let a 7-day blip masquerade as a stable truth.

**Cadence:** nightly recompute, plus explicit "refresh now" override. Real-time recompute is wasteful; reserve real-time for Phase 3 predictive inference.

**Engine outputs (consumed by other surfaces):**
- Personal baselines: rolling profiles of "normal for you" (tremor by hour-of-day, dose-effect window, sleep-tremor correlation, etc.)
- Conditional rules: validated patterns of the form "when X, then Y on average"

**Dependencies:** None — current data model already supports this (per-sample TremorReading + native HealthKit retention).

**Trigger:** ~3–4 weeks of consistent wear data accumulated. Engine is useless before then due to insufficient sample size.

### Aggregate Insights tab — Backlog

A separate tab from Review. **Review = "what's notable about THIS day."** Aggregate Insights = **"what have we learned about ME in general."** Different surfaces, same engine. This is where the "Insights" name we shelved earlier finally gets earned.

**Surface design:**
- Window picker at top: 7d / 30d / 3mo / all-time / *custom range*
- Sections: personal baselines (tremor curves by hour-of-day, dose-effect window, etc.); conditional rules ("when X, then Y for you"); window-comparison observations (the change-detection insights from the engine entry above)
- Each insight shows the underlying sample size and time range so the user can audit reliability

**Dependencies:** Continuous time-windowed correlation engine (above). Cannot ship until engine ships.

**Naming note:** when this tab launches with real engine output, rename the current "Review" tab? No — they're different surfaces serving different jobs. Review stays Review (per-day); this new tab is "Insights" (aggregate).

### Multi-medication & supplement tracking — Backlog

**Triggered when:** Bhav logs a non-Sinemet substance (currently only Sinemet is logged).

Dynamic per-substance UI in events lane and glance card. Treat supplements (Vitamin D, B12, creatine, ashwagandha, magnesium — all things Bhav has historically taken) as first-class correlation candidates. **Never pre-filter to "PD-relevant" medications** — the whole point of the correlation engine is to *discover* what affects symptoms, including things current PD literature hasn't connected.

**Implementation:**
- **Mechanical UI fix (~30–45 min):** dynamic legend in `TremorTimelinePanel` driven by actual substances taken (not hardcoded "Sinemet"); per-substance breakdown in glance card label ("3 Sinemet · 1 Vitamin D" instead of generic "4 Doses"); distinct icon tints per substance; all in `Views/DayInReviewView.swift`, no data layer changes — `DayEvent.medication` already carries the name string.
- **Larger surface (own scope, defer until needed):** "Manage medications & supplements" settings screen for grouping ("PD prescription", "Supplement", "Other"). Critically, categorization is for grouping/display only, **never for filtering data out of correlation analysis.**

### Per-tile detail modals (consolidation casualties) — Backlog

When the Today tab was killed (May 11), three Health Today tiles were dropped from the surface: Mindfulness minutes, Steps, and Resting Heart Rate. They didn't make the glance-card cut (4 tiles: Sleep / Tremor / HRV / Daylight). They're still queryable from HealthKit; no data is lost.

If/when these become correlation-relevant or user-requested, the right home is **per-tile detail modals** (already a separate backlog entry) rather than re-expanding the glance card. The detail modal pattern was designed to surface deeper context per metric without crowding the dashboard.

### Food & beverage logging — Done (May 15)

Captures food and beverage as event data for correlation with tremor.

**Real-world motivation (May 12):** Bhav observed Sinemet at 11:30 AM → lunch → tremor subsided → coffee at ~2 PM → tremor returned within ~30 min. Caffeine and protein-levodopa interaction are the two highest-signal food correlations for PD.

**Shipped design (differs from original locked spec):** Original design had Drink/Meal type chips + Caffeine/Protein/Sugar/Fiber/Fat attribute chips for manual tagging. Shipped instead with free-text description only — reasoning: manual attribute tagging added cognitive load with false precision, and ML can extract attributes from natural language later. The two-tier `FoodType` + `FoodAttribute` schema is preserved in the data model for ML output; it's just not user-facing on entry.

*Entry:* `+` button (top-left) → Log Entry sheet → **Food** → free-text `TextEditor` + `DatePicker(.compact)` → Save.

*Data model (SwiftData):*
```swift
FoodEvent {
  id: UUID
  timestamp: Date
  userDescription: String?   // free-text, ML extracts attributes later
  attributes: [FoodAttribute]  // written by ML; empty until analysis runs
  type: FoodType               // schema compat; always .mealSnack on new entries
  notes: String?
}
```

*Timeline:* `fork.knife` icon (brown) on tremor chart. Tapping opens detail sheet showing description + any detected attributes.

*Edit/delete:* Edit opens pre-populated form (`EditFoodScreen`); delete removes SwiftData record. Both accessible from event detail sheet.

**What v1 does not capture:** portion sizes, photo input, per-item identification. Camera path (photo → multimodal model → food + portion estimate) deferred to Phase 4 — requires either on-device capable vision or a deliberate cloud + consent architecture.

**App Intent shell:** `LogFoodIntent` stubbed; extends to "Hey Siri, log coffee" with marginal extra work when voice input is prioritised.

### Mindfulness session logging — Done (May 15, retroactive entry)

Meditation is now loggable from `+` → **Meditation** → date/time picker + duration stepper + quick picks (5/10/15/20/30/45/60 min) → Save. Writes `HKCategorySample(type: .mindfulSession)` to HealthKit. Appears on tremor timeline (cyan `figure.mind.and.body` icon). Delete available from event detail sheet (removes HealthKit sample).

**Design shipped vs. original spec:** Original design was a live start/stop timer (tap Start → session runs in background → tap Stop, duration captured from elapsed time). Shipped instead as retroactive entry (log it after the fact with a duration picker). Trade-off: simpler to build and less likely to be accidentally left running; downside is slightly higher friction to remember to log. Live timer remains a Backlog item for v2 of this feature.

**Live timer — Backlog:**
Tap "Start" → background session runs → status indicator in toolbar → "Stop" writes the actual elapsed duration. Better UX for users who want to start logging before meditating. Build when the retroactive path has been used long enough to validate that the category is worth the extra engineering.

**Why this exists:** Apple's built-in Mindfulness app caps at ~5 min. Insight Timer is a third-party dependency (violates self-contained product principle). No native Apple path covers free-form 45–60 min sessions of this length. Workout type would corrupt the correlation engine's ability to distinguish physical exertion from mental stillness.

### Voice input for medication logging via App Intents — Backlog (deprioritized May 12)

**Status update (May 12):** Deprioritized behind manual food logging. Today's coffee→tremor observation made food/beverage data capture the higher-value next step — voice polish matters less than getting any food data flowing. Design below remains fully locked and ready. Build after food logging ships; the `LogFoodIntent` App Intent shell from that entry sets the pattern this work extends.

Voice-driven Sinemet logging to bypass typing for tremor-affected hands. **Design locked May 11; ready to build (~2–3 hours).**

**Real-world motivation:** Bhav tried Apple's native Siri medication logging on May 11 and hit two failures: (1) Siri heard "Sinemet" as "cinema," (2) when it finally got the right medication, Apple's built-in flow logged all three scheduled doses for the day at once — Bhav had to manually mark two as skipped. Building our own intent fixes both.

**Why Apple wake words are out:** Custom wake words ("Hey PD Companion") are not available to third-party iOS apps — only Apple and partner-bundled devices can register them. We use "Hey Siri" + our registered phrases.

**Locked design:**

*Two App Intents:*
- `LogSinemetDoseIntent` — writes a single `HKMedicationDoseEvent` with `status: .taken`, `startDate: now` (or user-specified time). Does NOT iterate the day's schedule (which is what Apple's flow did wrong).
- `UndoLastDoseIntent` — queries the most recent dose event and deletes it. Safety valve for mishears or accidental triggers.

*Phrase aliases registered via `AppShortcutsProvider`* (multiple phrases pre-trained into Siri's recognition for our app's context):
- `"log Sinemet"`, `"log my Sinemet"`, `"took Sinemet"`
- `"log my dose"`, `"log my pill"`, `"log my morning pill"`
- `"log my PD med"`, `"log Parkinson's medication"`
- `"log carbidopa"`, `"log levodopa"` — phonetically distinct from "cinema"
- `"undo my last dose"` (separate intent)

The non-Sinemet phrases give a fallback when Siri mishears the medication name.

*Confirmation flow:* Silent log + audio confirmation (*"Logged Sinemet at 12:42 PM"*) — no yes/no question. Faster, fits ambient-first. Undo intent is the safety net.

*Time handling:* Default to `now`. Parse explicit time from natural language ("log Sinemet 30 minutes ago", "log Sinemet at 8 AM") via Foundation's date parsing.

*Watch experience:* Works automatically on Watch via Siri raise-to-speak — no extra Watch code needed for v1.

**File structure to build:**
- `Intents/LogDoseIntent.swift` — both intent definitions
- `Intents/PDCompanionShortcuts.swift` — `AppShortcutsProvider` with phrase variants
- Possibly small Info.plist additions for App Intents support

**What this does NOT solve:**
- Siri still misrecognizes things sometimes. We're improving the odds significantly via phrase registration, not eliminating recognition errors.
- If Apple's built-in medication shortcut is also registered for similar phrases, Siri picks one — may be ours, may be Apple's. Test which wins; user can disable Apple's medication shortcut in Settings if needed.

**Dependencies:** None blocking on its own; sequenced behind food logging so the App Intent shell pattern lands there first.

### Food → tremor correlation — Backlog (Blocked)

Once food events are captured, the engine includes them as correlation candidates. Validates known PD pharmacology (protein-levodopa interaction is documented — protein competes with levodopa absorption at the gut wall and blood-brain barrier) and surfaces personal patterns (chicken vs. fish, time-of-day food sensitivity, etc.).

**Why this is genuinely high-value:** Food-tremor correlation is a near-virgin data space. No existing PD app captures food well enough to correlate it. The protein-levodopa interaction is one of the most clinically actionable signals in PD management ("take Sinemet 30 min before meals, not with them") — but no app currently *measures* whether a given patient's effect window shrinks after high-protein meals. Bhav's setup could be the first.

**Blocker:** Food & beverage logging entry above must ship first.

### Per-tile detail modals (glance card drill-down) — Backlog

Tap any glance card stat → modal slides up with a deeper view of that metric framed through a PD-correlation lens. Trigger surface changed May 11 from the (now-deleted) Health Today tiles to glance card stats; design language and rationale unchanged.

**Why:** A single number on the glance card is glanceable but lossy. The modal answers "what does this metric look like in detail, how does today compare to my baseline, and what pattern does it have?" Apple Health shows the raw data; the modal shows the *PD-relevant interpretation*.

**Three-section template (consistent across all six tiles):**

1. **Today** — detail beyond the headline number (timestamps, distribution, peak/valley, breakdown)
2. **How today compares** — vs. your own baselines across time windows (last 7 days / 30 days / all-time). This is where the time-windowed correlation engine surfaces, including window-comparison observations ("tremor up 12% this month vs. 6-month baseline" — the wearing-off / progression signal)
3. **Pattern** — the engine-surfaced insight specific to this metric

**Section 3 differs by tile type:**

- **Five "input" tiles (Sleep, Sinemet, Workout, HRV, Daylight)** — pattern section answers *"how does this metric correlate with my tremor?"* Examples: avg dose-effect window, sleep-quality vs. next-day-tremor correlation, post-workout tremor delta.
- **Tremor tile (the dependent variable)** — pattern section runs the engine *inverse*: *"what conditions tend to produce days like today vs. your better days?"* Engine identifies days at/below some tremor threshold and surfaces what those days had in common; compares today against that profile. Example: *"On days when avg ≤ 0.4 (n=24), you typically had 6.5h+ sleep, walk before 10 AM, first dose by 8 AM. Today missed: sleep duration, early morning movement."* Stays in pattern-surface stance, never prescriptive.

**Bottom-of-modal actions:** "Open in Apple Health" button preserves the previous tap-to-Health behavior (useful for adding meds, setting schedules). Possibly "View week trend" or similar for cross-modal navigation.

**Dependencies:**
- Trigger is the 4 glance card stat cells in `DayInReviewView.swift` (`GlanceCard`). Wiring is mechanical (~30 min) — replace the implicit non-action with a sheet presenter per stat.
- Section 3 substance requires the continuous time-windowed correlation engine. Modals can ship with sections 1+2 first, add section 3 as engine output becomes available.

**Estimate:** ~2–3 hours per modal for sections 1+2 (today + comparison). Section 3 substance comes free once engine is producing output — modals just consume engine API.

### Dyskinesia trend toggle — Blocked

**Blocker:** Waiting on dyskinesia signal to emerge from `CMMovementDisorderManager`. Apple's API requires levodopa logging to disambiguate dyskinesia from intentional movement. Bhav started logging Sinemet 2026-05-08; processing lag means signal may take a few more days.

When unblocked: add dyskinesia overlay to the tremor chart in the Review tab with a toggle ("Show dyskinesia"). Don't auto-show — give Bhav control over visual density. Note: dyskinesia uses a different value scale than tremor (`percentLikely / 25.0` in `MovementDisorderManager`) — may need a secondary y-axis or a separate stacked chart rather than overlaying on the 0–4 tremor scale.

---

## Phase 3 — Predictive / Preemptive

Strategic context: [ParkinsonsProject.md → Phase 3](ParkinsonsProject.md#phase-3---predictive--preemptive)

### Predictive nudges and interventions — Backlog

The real product vision. Once Phase 2 has been running long enough to produce reliable conditional rules, surface forward-looking interventions as smart, low-noise wrist haptics or notifications.

**Examples of nudges the engine could produce:**
- *"Your last dose was 3h 50m ago — your typical wear-off is at 4h. Consider taking your next dose now."* (uses personal dose-effect window from engine)
- *"Days like this (poor sleep + no morning movement) have averaged elevated afternoon tremor. A 20-min walk before noon has helped on similar days."* (uses conditional rules + window comparison)
- *"Your Tai Chi session yesterday produced a 35% tremor reduction. You haven't done one in 4 days."* (intervention reminder driven by what works for this user)

**Critical constraint:** nudge quality is bounded by Phase 2 reliability. Premature or overconfident nudges destroy trust faster than no nudges at all. Suppression rules:

- Only fire when underlying rule has high statistical confidence (e.g., n ≥ 20 events, p < 0.05, effect size > some threshold)
- Maximum N nudges per day (cognitive load matters even for helpful prompts)
- Snooze / "don't show this again" per nudge type
- Honest provenance — each nudge taps to reveal "this is based on your last 30 days, n=X events"

**Implementation:** Core ML model trained on personal longitudinal data, on-device, no data leaves phone. Same architectural commitment as Phase 2 — local inference only, no cloud round-trip.

**Dependencies:** Continuous time-windowed correlation engine (Phase 2). Needs ~6+ months of data for model to be meaningfully personal.

---

## Phase 4 — Scaled Patient App

Strategic context: [ParkinsonsProject.md → Phase 4](ParkinsonsProject.md#phase-4---scaled-patient-app-future)

*(No entries yet — Phase 4 work hasn't started. The repo public-vs-private decision is tracked as a watch trigger in auto-memory rather than a backlog entry.)*

---

## Cross-cutting

### Health tile section deep links — Speculative

**Trigger:** Only buildable if/when Apple documents URL scheme paths to specific Health sections (Medications, Sleep, Workouts, etc.).

Apple does NOT publicly document deep-link paths to specific Health app sections. Some unofficial / reverse-engineered paths exist but break with iOS updates and aren't safe to ship.

**Why it would matter:** Tapping a glance card stat or event detail "Open in Health" button ideally lands directly on the relevant Health app section, not its home — saves a navigation step. For a PD patient with tremor, every removed tap matters.

**Implementation when unblocked:** Event detail sheets already have an "Open in Health app" note for medication/workout events. The `x-apple-health://` URL scheme can be extended with section-specific paths once Apple documents them. Worth checking Apple's HealthKit documentation and WWDC release notes annually.
