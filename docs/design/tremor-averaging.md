# Tremor Averaging — Design Note

**Status: BUILT Jul 6 2026 (late), verified on-device + unit tests.** The as-built summary below supersedes the exploration that follows (kept for the reasoning trail). Root insight held; the *statistic* evolved once real data was in hand.

## As built

**Chart (`DayInReviewView`, tremor + dyskinesia):** **10-min buckets** (was 30) + **MEAN**, plotted at slot **center**, **monotone** (dropped Catmull-Rom overshoot). Path we walked: 30-min P90 → too high at rising edges (back-dates a later peak); 10-min median → artifact-robust but steppier; **10-min mean** → the short window does the peak-localization, and the mean keeps brief-but-real breakthroughs visible (Bhav's call: show spikes, don't hide them; accepts a lone artifact nudging a slot ~0.3). Callout reads the same slot mean, so callout = curve.

**Live-edge headline (`liveEdgeState` → `DayForecast.nowState`):** **median** of the last 15 min + a trend guard (OFF only if level ≥ threshold and not clearly falling). Median *here* on purpose — a state flip is a decision, and a single walk/eating artifact minute must not flash "you're OFF." Deliberately a different statistic from the chart (severity display vs state decision).

**Forecast band (`observedTimeline`/`despeckle`, 30-min bins):**
- **Despeckle confidence-gate** — a short OFF/ON run whose measured severity is ≥ half a band past the threshold (`confidentMargin` 0.5) is a real episode and survives; only *ambiguous* near-threshold flips get absorbed. Fixes real ~30-min OFF episodes being erased (Jul 6 4-5 PM was painted solid ON before).
- **Live-edge overlay (`applyLiveEdge`)** — the band's trailing 15-min sliver uses the *same* `liveEdgeState` read as the headline (carrying the live median as its OFF severity), so bar and headline agree at "now" instead of the bar lagging ~30 min.

**Untouched by design:** the glance-card daily average (separate daily mean; unaffected by buckets — but note it reads low vs a bimodal signal). Insights/correlation engine (chart buckets are display-only, private).

**OPEN / NEXT:**
- **10-min forecast bins** (Bhav wants band binning to match the chart). Needs `minRun` 2→3 to keep a ~30-min stability floor, then re-verify the parity suite. Robustness caveat: fine for Bhav's bimodal data, may strobe on noisier users. Scoped as its own change, not folded into this commit.
- **Felt-vs-measured calibration** (upstream): Bhav feels "slight-mild" at a measured ~2.0. Confirmed real Jul 6 (4:23 slot was genuinely sustained ~1.8). Not a statistic bug — needs a debug readout to calibrate, or is left as honest measurement. [[project_kampa_engine_xray]]

**Tests:** despeckle gate (`despeckleSparesDecisiveShortEpisode`, `despeckleAbsorbsAmbiguousShortFlip`), live-edge overlay (`liveEdgeOverlaysBandTail`, `liveEdgeNoOpWhenNil`); parity green.

---

## Root defect (original exploration)

*"The app averages tremor over windows long relative to how fast the tremor moves."*

*"The app averages tremor over windows long relative to how fast the tremor moves."*
Short, strong spikes — exactly what a PD patient feels — get smoothed below what's shown. **One defect, three surfaces.** All three share the same mistake: a 30-min **mean** stands in for a fast-moving signal, so the number understates the felt peak and lags the felt transition.

**Unifying principle for the fix:** at the live edge, prefer a **robust peak** and a **faster read** over a smooth mean. Keep smoothing only where it's honest — the *historical* band, read after the fact. Never show a single mean as if it were the moment.

---

## Symptom 1 — chart callout & curve understate the peak

**Where:** `DayInReviewView.swift`
- `hourlyBuckets` (L926) buckets readings into 30-min slots, value = `sum/count` (**mean**), keyed at slot **start** (L933).
- Curve interpolates `.catmullRom` (L607/621) — overshoots toward the next point.
- `tremorReadout` (L790) → `bucketForSlot` (L815) reads the containing slot's mean.
- Observed: callout read **0.5** while the drawn line sat at **~1.5** at 3:56 PM. The 3:30 slot mean is dragged down by its calm first minutes; the spline rides up toward the higher 4:00 slot. The *curve* was closer to felt tremor than the *callout*.

**Fix (decided):**
1. Bucket value = **robust P90** of the slot's raw tremor samples, **not mean, not raw max**. P90 over ~30 samples/slot means the top ~3 samples clear it — one jitter sample can't set it, but a real 5-minute spike does. Same statistic for **curve and callout** (they must never disagree again).
2. Plot at slot **center** (+15 min), not start — kills the ~15-min left-skew that made the spline chase the next slot.
3. **Drop Catmull-Rom** → monotone/linear. With a peak curve the spline overshoot double-counts. *(Bhav decision — see below.)*

**Implementation note:** `HourBucket` currently overloads `hour` for x-plot, containment, gap-break, and sort. Splitting peak + center means: collect **raw values per slot** (not `sum/count`), keep `slotStart` for containment/gap/sort, add a separate **plotted x = center**. The dayEnd anchor bucket (L944) plots at `dayEnd` exactly, no +15.

**⛔ Rejected:** peak + avg both in the callout. Too crowded — dyskinesia shares the box. **One value = the peak.**

**Reframe:** the panel is no longer "average tremor" — it's "how strong tremor got each half-hour." Needs one honest label so it isn't misread. *(Bhav decision — see below.)*

---

## Symptom 2 — forecast "now" ON/OFF lags ~30 min

**Where:** `CorrelationEngine.swift`
- `observedTimeline` (L1794) bins into 30-min (`forecastObservedBinMin`=30, L1655), OFF when **bin mean ≥ offThreshold (1.0)** (L1809).
- `despeckle` (L1835, `forecastMinRunBins`=2 → ~60-min floor) absorbs short runs into neighbors.
- A short strong OFF is (a) averaged below threshold **and** (b) de-noised away until it's ~1h old. A/B screenshots confirmed: same 0.5 reading, band said ON at 4:08 → OFF at 4:38 as the OFF aged past the floor. **Model is right, just late — it self-corrects.**

**Fix (decided): split the two jobs.**
- **Historical band** (everything older than the live edge): keep binned + despeckled. After the fact, smoothing is honest.
- **"Right now" state** (last bin only): compute from a **faster, less-smoothed read** — last **~15 min raw** tremor + trend (rising/falling), bypassing the despeckle floor. This feeds `phaseAtNow` / the headline, not the historical shading.

**Trade-off:** responsiveness vs. an occasional brief false-OFF flicker at the edge. Bhav leans **responsive**. Default: last 15 min, OFF if that window's P90 ≥ threshold (peak, consistent with Symptom 1) AND trend not falling. Flagged below.

**Not caused by Phase A** — observed reconstruction was untouched by the formulation change.

---

## Symptom 3 — headline says "ON steady" inside its own wear-off window

**Where:** `DayAheadPanel.swift`, `headline` (L81).
- `.on` case prints "You're likely ON (steady) right now — wearing off expected [whenText]" where `whenText` is `nextOffRange` (L63), e.g. 3:45–4:45.
- `phaseAtNow` (L51) stays `.on` until `nextOffStart` (band center, ~4:15), so at 4:08 — already **past the band's lower bound (3:45)** — it still says "steady."

**Fix (decided):** when `now ≥ nextOffRange.lowerBound`, stop saying "(steady)" → **"you may be starting to wear off now."** Small, localized to `headline`, needs no data. Cause-independent — ship even if 1 & 2 slip.

---

## Decisions (locked Jul 6)

1. **No chart label.** Don't clutter the panel; a "peak tremor" label is also incomplete since the chart carries dyskinesia too. The P90 reframe is explained in the **FAQ** instead — and that FAQ entry is **part of this change's definition-of-done**, riding the pending website batch (blocked on the 3-panel video). Ship the code and the FAQ together.
2. **Dyskinesia switches to P90 too.** `dyskinesiaBuckets` (L953/966) is currently the same 30-min mean. Leaving it as mean while tremor becomes peak would put two *different statistics* on one 0–4 axis — silently dishonest. Both lines become "how strong it got per half-hour"; one FAQ entry covers both.
3. **Drop Catmull-Rom** → monotone/linear.
4. **Live-edge window** (Symptom 2) = last 15 min + P90 + trend. Bhav confirmed responsive.

## Upstream — felt-vs-measured calibration (OUT of scope for this build)

Deeper than all three: Bhav *feels* real tremor at a measured **0.5**, below the OFF line (**1.0**). Either the Watch under-reads or 1.0 is too high for him. Every ON/OFF label sits on this. **Dependency, not a decision** — needs his real readings (DEBUG readout / engine X-ray). Can't fetch HealthKit from the dev box. Revisit after the 3 fixes. Tie: [[feedback_no_arbitrary_thresholds]], [[feedback_preserve_raw_sensor_data]].

## Build order

1. Symptom 3 (headline) — trivial, no data, ship-safe.
2. Symptom 1 (P90 + center + raw-per-slot) — the visible win; carries the P90 helper Symptom 2 reuses.
3. Symptom 2 (live-edge state) — reuses the P90 helper.
4. Then commit Phase A (5 files). Then revisit calibration.
