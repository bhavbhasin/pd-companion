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

Originally scoped as "Insights tab," reframed as "Day in Review" on May 11, then shortened to "Review" the same day for tab-bar fit and to avoid overpromising interpretation. Will rename back to "Insights" once Phase 2 correlation logic actually delivers computed observations. Step 1 shipped May 11: daily-primary view (default to yesterday), date chevrons, glance card (sleep/tremor/doses/workouts/HRV/daylight), tremor line with event overlays (medication/workout/mindfulness icons + dotted RuleMarks, scrollable horizontally with 12-hour visible window, 3-hour major gridlines, 1-hour minor ticks), sleep stages chart (Apple-pattern: Awake/REM/Core/Deep horizontal bars over time), empty Observations placeholder for future correlation logic. App is now single-screen — Today tab killed May 11 because Review serves both "now" and retrospective use cases via date chevrons.

**Step 1.5 — Backlog (next):** Reproduce Apple Sleep Score (Duration 50 + Bedtime 30 + Interruptions 20 = 100) as a header above the sleep panel. Calibrate against Apple's own number on the same night. Defer the question of whether this score or raw fragmentation/stages better predicts tremor until we have a few days of correlated data.

**Step 2 onward:** Scatter plots with lag, lag analysis (e.g., "Tremor 0–30 min after Tai Chi vs 1–2 hours after"), correlation matrix / heatmap. Wearing-off and on-off patterns are fundamentally about lag — must be a first-class chart type.

**Phase 3 only:** Predictive forecast UI based on Core ML model.

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
- **Mechanical UI fix (~30–45 min):** dynamic legend in `EventsLanePanel` driven by actual substances taken (not hardcoded "Sinemet"); per-substance breakdown in glance card label ("3 Sinemet · 1 Vitamin D" instead of generic "4 Doses"); distinct icon tints per substance; all in `Views/DayInReviewView.swift`, no data layer changes — `DayEvent.medication` already carries the name string.
- **Larger surface (own scope, defer until needed):** "Manage medications & supplements" settings screen for grouping ("PD prescription", "Supplement", "Other"). Critically, categorization is for grouping/display only, **never for filtering data out of correlation analysis.**

### Per-tile detail modals (consolidation casualties) — Backlog

When the Today tab was killed (May 11), three Health Today tiles were dropped from the surface: Mindfulness minutes, Steps, and Resting Heart Rate. They didn't make the glance-card cut because we capped at 6 high-PD-signal cells. They're still queryable from HealthKit; no data is lost.

If/when these become correlation-relevant or user-requested, the right home is **per-tile detail modals** (already a separate backlog entry) rather than re-expanding the glance card. The detail modal pattern was designed to surface deeper context per metric without crowding the dashboard.

### Voice input for medication logging via App Intents — Next up

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

**Dependencies:** None blocking. Independent of engine + data accumulation. Foundation for voice-driven food logging (next backlog entry).

### Food logging (voice and/or camera) — Backlog

Capture meals as a new event type for correlation with tremor. Two input paths, each with real trade-offs:

**Voice path (privacy-aligned, low-friction):**
- "Logged lunch: chicken sandwich and salad" via Speech framework on-device
- Parse into structured tags (protein type, carb type, etc.) using on-device NLP or simple keyword matching
- No portion-size data, but categorical data is enough for most correlations
- All on-device, zero API calls, private

**Camera path (Cal AI–style, accuracy magic, real privacy/cost trade-off):**
- Photo of meal → multimodal model identifies food + estimates portions
- **Reality check:** general food identification at Cal AI's accuracy requires hosted multimodal models (GPT-4V, Claude, Gemini Vision). Apple's on-device vision models are not capable enough for arbitrary meal recognition.
- Sending food photos to a hosted API **violates the privacy-first principle** as currently stated. Possible reframings:
  - Get explicit per-photo opt-in consent
  - Strip metadata, route through a privacy-preserving proxy
  - Defer until Apple ships a capable on-device food-recognition model (may never)
- Cost: ~$0.01–0.05 per photo if using a hosted API. At even modest usage, costs become real for a free/affordable patient app.

**My recommendation for v1:** voice-only food logging. Cal AI–style camera logging is a separable Phase 4-ish discussion that requires either an architecture change (consent + cloud round-trip) or waiting on Apple's stack to mature.

**Dependencies:** Voice input infrastructure (above). Builds cleanly on top.

### Food → tremor correlation — Backlog (Blocked)

Once food events are captured, the engine includes them as correlation candidates. Validates known PD pharmacology (protein-levodopa interaction is documented — protein competes with levodopa absorption at the gut wall and blood-brain barrier) and surfaces personal patterns (chicken vs. fish, time-of-day food sensitivity, etc.).

**Why this is genuinely high-value:** Food-tremor correlation is a near-virgin data space. No existing PD app captures food well enough to correlate it. The protein-levodopa interaction is one of the most clinically actionable signals in PD management ("take Sinemet 30 min before meals, not with them") — but no app currently *measures* whether a given patient's effect window shrinks after high-protein meals. Bhav's setup could be the first.

**Blocker:** Food logging entry above must ship first.

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
- The `HealthMetricTile` referenced in earlier session notes no longer exists (deleted in single-screen consolidation, May 11). New trigger is glance card `stat()` cells in `DayInReviewView.swift`. Wiring is mechanical (~30 min) — replace the implicit non-action with a sheet presenter per stat.
- Section 3 substance requires the continuous time-windowed correlation engine. Modals can ship with sections 1+2 first, add section 3 as engine output becomes available.

**Estimate:** ~2–3 hours per modal for sections 1+2 (today + comparison). Section 3 substance comes free once engine is producing output — modals just consume engine API.

### Dyskinesia trend toggle — Blocked

**Blocker:** Waiting on dyskinesia signal to emerge from `CMMovementDisorderManager`. Apple's API requires levodopa logging to disambiguate dyskinesia from intentional movement. Bhav started logging Sinemet 2026-05-08; processing lag means signal may take a few more days.

When unblocked: re-add dyskinesia line to the Today dashboard's Tremor Trend chart with a toggle ("Show dyskinesia"). Don't auto-show — give Bhav control over visual density. Note: dyskinesia uses a different value scale than tremor (`percentLikely / 25.0` in `MovementDisorderManager`) — may need a secondary y-axis or a separate stacked chart rather than overlaying on the tremor scale.

The Day in Review tab already includes dyskinesia in its top panel from day 1 regardless, so emerging signal will surface there first.

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

Today all six Health Today tiles open Apple Health to its home via `x-apple-health://`. Apple does NOT publicly document deep-link paths to specific sections. Some unofficial / reverse-engineered paths exist but break with iOS updates and aren't safe to ship.

**Why it would matter:** Tapping "Last Sinemet" should ideally land directly on the Health app's medication detail page, not its home — saves a navigation step. For a PD patient with tremor, every removed tap matters.

**Implementation when unblocked:** `HealthMetricTile.action` parameter and the per-tile call sites in `HealthSummaryView` already isolate this change — each tile's `action` closure swaps in the section-specific URL. Worth periodically checking Apple's HealthKit documentation and WWDC release notes for new URL scheme additions.
