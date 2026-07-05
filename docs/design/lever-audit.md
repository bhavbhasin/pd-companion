# Lever Audit — capture & wiring state

**Purpose.** For every real-world factor that plausibly moves the symptoms (tremor,
dyskinesia, ON/OFF wearing-off, gait/mobility), record whether Kampa (a) captures the
data that represents it and (b) has a registry entry that reasons over it. The point is to
find **capture gaps** — signal being lost every day F&F testers are live, which cannot be
backfilled — separately from **wiring gaps**, where the data is already stored and the
question can be added any time.

**State legend**
- ✅ **Wired + captured** — data flows *and* a `RegistryEntry` tests it. Nothing to do.
- 🟡 **Captured, not wired** — data is stored; no registry question uses it yet. *Wiring gap — do whenever (data waits).*
- 🟠 **Partial / fidelity gap** — captured, but at the wrong grain or as a proxy (e.g. dose as an *event*, not mg).
- 🔴 **Capture gap** — no data recorded at all. *One-way door — every uncaptured day is lost.*

Grounding: `InsightRegistry.starter` (wired questions), `HealthKitManager` read set +
`DayEvent` (captured), `FoodAttribute = {caffeine, protein, sugar, fiber, fat}`.

---

## A. Medication (observe-only — never a nudge)

| Lever | Data representation | State | Note |
|---|---|---|---|
| Dose timing | logged med event / HK `userAnnotatedMedication` | ✅ | `levodopaDose→tremor` (×2), `→dyskinesia`; anchors the wearing-off model |
| Dose **type / formulation** (Sinemet / Rytary / Mucuna / agonist) | `Dose.name` (from HK medication) — **captured** | 🟡 | **Captured, not wired.** The name rides on every dose; primitives pool all doses into one survival curve and ignore it. On a *mixed* regimen this averages incompatible PK curves (IR vs ER vs plant-source; agonists have no discrete ON pulse) → median describes neither → forecast inherits the error. Fix = stratify primitives by `name`. ⚠ capture-quality caveat: only as good as the user's Health med setup (nil → "Dose"). Backlog: "Per-medication dose-response". |
| Dose amount (mg) | — (event only, no mg field) | 🟠 | exposure is `.levodopaDose` = binary event; dose *size* not modeled. Lower priority than type. |
| Missed / late doses | — (no prescribed schedule stored) | 🔴 | "late vs prior dose" is derivable; "**missed**" needs the regimen, which isn't captured |
| Protein–dose interval | food attr `protein` + dose event | ✅ | `protein-meal-dose-onset` (mealTimingCompetition) |
| Adherence pattern over time | — (needs schedule, as above) | 🔴 | blocked on regimen capture |

## B. Diet / nutrition (controllable)

| Lever | Data representation | State | Note |
|---|---|---|---|
| Protein timing & load | food attr `protein` | ✅ / 🟠 | timing wired; **load** (amount) not captured — presence only |
| Meal timing vs dose | `meal(.large)` proxy | ✅ | `meal-fullness-dose-onset` |
| Caffeine | food attr `caffeine` | ✅ | `caffeine-tremor` (windowedEffect) |
| Sugar | food attr `sugar` | ✅ | `sugar-tremor` |
| Fiber | food attr `fiber` | 🟡 | captured if logged; no entry (candidate: fiber→GI→dose-failure) |
| Fat | food attr `fat` | 🟡 | captured; no entry (fat delays gastric emptying → onset) |
| Alcohol | free-text only, **no attribute** | 🔴 | not extracted; no attribute, no entry |
| Hydration | — (HK `dietaryWater` not read, no log) | 🔴 | capture gap |

## C. Physical activity (controllable — strongest PD evidence)

| Lever | Data representation | State | Note |
|---|---|---|---|
| Aerobic / structured exercise | HK `HKWorkout` (type, duration) | ✅ | 10 workout types wired `workout→tremor` |
| Exercise timing vs dose | workout time captured | 🟡 | no workout×dose interaction entry |
| Sedentary / inactive time | HK `stepCount`, `appleExerciseTime` | 🟡 | captured; no "inactivity→symptom" entry |

## D. Sleep & circadian

| Lever | Data representation | State | Note |
|---|---|---|---|
| Total sleep | HK `sleepAnalysis` | ✅ | `sleep-duration-next-day-tremor` |
| Deep sleep | HK `sleepAnalysis` stages | ✅ | `sleep-deep-next-day-tremor` |
| Fragmentation (awakenings) | derivable from `sleepAnalysis` | 🟡 | raw stages captured; not computed as an exposure |
| Daytime napping | `sleepAnalysis` (daytime) | 🟡 | captured; not distinguished/wired |
| Time-of-day baseline | timestamps | ✅ | `circadian-tremor-baseline` (timeOfDay→tremor) |
| REM behavior disorder | — | 🔴 | no signal (⚪ low priority) |

## E. Autonomic / stress / mood

| Lever | Data representation | State | Note |
|---|---|---|---|
| HRV / autonomic tone | HK `heartRateVariabilitySDNN` | ✅ | `hrv-tremor-within-day` |
| Acute stress / anxiety | — (HRV is the only proxy) | 🔴 | no direct stress signal; no in-the-moment marker |
| Mood (depression/apathy) | — | 🔴 | not captured |
| Fatigue / cognitive load | — | 🔴 | not captured (⚪) |

## F. GI function — ⚠️ KNOWN GAP CLUSTER

| Lever | Data representation | State | Note |
|---|---|---|---|
| Constipation / bowel regularity | — | 🔴 | **flagship capture gap**; precedes & predicts dose failures |
| Gastroparesis signs (nausea, bloat, early satiety) | — | 🔴 | delayed emptying blunts levodopa; no capture |

## G. Physiological / illness / environment (mostly context, not nudge)

| Lever | Data representation | State | Note |
|---|---|---|---|
| Blood glucose | HK `bloodGlucose` (CGM) | 🟡 | captured; **intentionally** not wired (step-1 = observe by eye) |
| Acute illness / infection | — (restingHR/respRate/O₂ as weak proxies) | 🔴 | no illness marker; large transient worsening goes unlabeled |
| Body temp / heat / dehydration | — (no wrist-temp read) | 🔴 | mostly uncaptured |
| Ambient weather | — | 🔴 | no integration (⚪) |
| Weight / BMI drift | — (`bodyMass` not read) | 🔴 | dosing-relevant over months (⚪) |
| Menstrual / hormonal | — | — | N/A for this user — dropped |

---

## Gap list (the output that matters)

### 🔴 Capture gaps — TIME-SENSITIVE (one-way door, F&F live now)
Every day these go uncaptured, the lived signal is lost and cannot be reconstructed.

1. **GI: constipation / bowel regularity** — highest value; mechanistically upstream of dose failures. *The flagship.*
2. **GI: gastroparesis signs** (nausea/bloating/early satiety).
3. **Medication regimen / schedule** — unlocks *missed-dose* and *adherence* detection (two levers at once).
4. **Acute illness / infection marker** — a single "sick today" flag would rescue otherwise-confounded days.
5. **Alcohol** — cheap: add as a `FoodAttribute` so existing food logging captures it going forward.
6. **Hydration** — lower value; only if capture is near-free.
7. *(⚪ low priority: mood, weight, wrist-temp, weather — note but don't build.)*

### 🟡 Wiring gaps — NOT time-sensitive (data already stored, add the question whenever)
- **Dose type / formulation → stratify the wearing-off + onset primitives by `Dose.name`.** ⚠ Higher urgency than a typical wiring gap: on a *mixed* regimen the pooled curve is *wrong today*, so the forecast is currently misleading for anyone mixing formulations — a correctness/trust issue, not just a missing insight. Data-loss clock: none (name accrues per dose).
- Fiber / fat → onset or GI (food attrs already captured)
- Exercise timing × dose interaction
- Sedentary time → symptom
- Sleep fragmentation / napping as exposures
- Blood glucose → symptom (deliberately held at step-1)

---

## Recommended sequence
1. **Design the GI capture surface first** (gaps 1–2) — lowest-effort, highest-value, and the clock is running. A once-daily, ambient, low-burden bowel/GI check.
2. **Alcohol attribute** (gap 5) — a one-line `FoodAttribute` add; stops the loss immediately.
3. **Medication regimen capture** (gap 3) — bigger design (schedule model + missed-dose logic); scope after GI.
4. **Illness flag** (gap 4) — a single daily toggle; cheap confound-rescue.
5. Wiring gaps: batch later; they wait for free.

> All new capture obeys the ambient / zero-cognitive-load rule — passive or one-tap, never a form. GI especially: a daily yes/no, not a diary.
