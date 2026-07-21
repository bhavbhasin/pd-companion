# Cold-Start Prior Table — Plan (drafted Jul 16 2026, ~3am; Bhav to review)

**Status: PLAN ONLY — not approved, no code.** Gate B blocker. Chosen over newsletter-first (Jul 16).
Strategy + licensing context: memory `project_kampa_cold_start_priors` + the Jul 16 cold-start artifact.

## Contract
Day 1, a new IR-levodopa user gets a running forecast seeded from published population
parameters — explicitly labeled as population-tier, citations attached. Personal data shrinks
the estimate toward *their* number continuously. **No silent blending**: every claim is either
"people like you, per literature" or "you, per your data" — visibly distinct tiers.

## Phases (~1 week)
1. **Parameter inventory (0.5d)** — enumerate what the Phase A forward model actually consumes
   (onset latency, time-to-peak, duration-of-benefit, decay shape, per-formulation). Code defines
   the schema, then literature fills it. Output: empty JSON schema.
2. **Literature extraction (2-3d, long pole)** — per slot: published value, uncertainty, cohort,
   citation. Peer-reviewed / OA only; published summary stats = facts (no DUA/copyright). Anchors
   held: IR duration-of-benefit ~2.69h, peak 28-53min, onset-to-ON ~46 min (SD 21,
   patient-reported; delayed-ON literature, e-jmd.org/journal/view.php?number=579).
   Unsourceable ⇒ excluded, never guessed.
   Cohorts skew long-duration ⇒ widen priors, don't narrow.
3. **Artifact (0.5d)** — versioned, cited `priors.json` in the app bundle (offline, auditable).
4. **Blending (1-2d)** — continuous shrinkage: prior = fixed pseudo-sample, personal n dominates
   naturally. NO day-N switch cliff (no arbitrary thresholds). Plugs into wearing-off estimator +
   day-ahead forward run.
5. **Surface + copy (1d)** — DayAheadPanel / morning briefing first. Copy: "Most people on IR
   levodopa get ~2.7h per dose — as your data comes in, Kampa finds your number." Distinct visual
   tier + tappable citation. Silence discipline: labeled prior, engine-judged personal, or nothing.
6. **Validation (0.5-1d)** — truncate Bhav's 69d to simulate day-1/7/21 user. Accept: day-1
   prior-seeded forecast useful (his 3.2h vs 2.69h published ⇒ conservative, right direction) +
   monotone convergence. Adversarial 5: Mucuna-only (PRN), CR/Rytary, mixed regimen, no levodopa
   (table stays silent), uncovered regimen.

## Phase 1 findings — parameter inventory ✅ DONE (Jul 17 2026)
Read the real forward model (`CorrelationEngine.dayForecast` + `PulseModel`, `CorrelationEngine.swift:1911–2094`).

**The forward model is a rectangular ON pulse, not a PK rise-peak-decay curve.** Per dose:
`ON = [dose+onset, dose+onDuration]`, OFF = complement, merged across overlapping doses.
It consumes exactly, per formulation (`PulseModel`):
- **onsetLatencyMin** — dose → clinical ON (measured as tremor t½; per-time-of-day bucket + pooled fallback)
- **onDurationMin** — duration of benefit (KM median, clamped [90,360], hard fallback `doseOnWindowFallback = 190`)
- **onDurationIqrMin** — spread of ON-durations → the ± band on next-OFF
- `offThreshold` (0–4 tremor ON/OFF line) — an app-wide constant, NOT a per-formulation literature value → **stays out of `priors.json`**

**⇒ Schema is 3 numbers + uncertainty for IR levodopa. DROP time-to-peak and decay shape from Phase 2** — the box model doesn't read them; extracting them would be literature we never consume.

**Day-1 gap confirmed (the thing the prior fixes):** `estimableFormulations` floor = ≥20 doses + finite KM median + finite onset. Below it → empty set → `dayForecast` returns `nil` → panel hidden. A true day-1 user gets no forecast. The prior seeds a `PulseModel` (onset/onDuration/iqr) so the forward run works before personal data clears the floor.

**Implicit priors already in the code to formalize + cite (or delete):** `doseOnWindowFallback = 190`, clamp rails `[90,360]`. The blending seam `WindowAdjustment` (onsetDelta/durationDelta/confidence) exists but is post-hoc; the prior is cleaner as the seed `PulseModel`, shrunk per Phase 4.

**Empty schema (Phase 3 target):**
```json
{ "version": "", "formulations": { "ir-levodopa": {
  "onsetLatencyMin":  { "value": null, "sd": null, "cohort": "", "citation": "" },
  "onDurationMin":    { "value": null, "sd": null, "cohort": "", "citation": "" },
  "onDurationIqrMin": { "value": null, "cohort": "", "citation": "" } } } }
```

## Scope decisions — ⬜ PENDING BHAV (recommendations)
1. **v1 = IR levodopa only**; honest "no baseline for your regimen yet" path for others.
2. **Single adult stratum, wide uncertainty** — no years-on-levodopa stratification in v1.
3. **Forecast surface first**, wearing-off card later (card still carries the open
   median-vs-median estimator question — orthogonal to this work, collides only in copy).

## Non-goals
No PPMI/Fox Insight data (closed by IP clauses — see memory). No row-level data of any kind.
Doesn't touch the wearing-off margin decision (`docs/design/wearing-off-margin.md`).
