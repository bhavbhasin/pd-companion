# Insights Card — Confidence & Gating Redesign

**Status: DESIGN ONLY (Jul 17 2026, revised Jul 19) — not built.** Refines the Judge's gating + card
presentation. Parent: `intelligence-architecture.md` (architecture unchanged). Sibling:
`confidence-presence-vs-absence.md` (gait absence fix, shipped — this generalizes it).

**Jul 19 revision:** folded in the design-review findings (`DesignReview-2026-07-19.md`, local/untracked)
- this doc is now the **single build spec** for the "make the gate honest" package: gating redesign +
registry template entries + dead-config removal + doc-overclaim fixes + constants ledger. Three
decisions taken Jul 19 are marked ✅ below.

## The problem
The Judge's gate was a stack of picked constants — show/hide at n≥5, effect floors (15 min
onset, 0.5/1.0 tremor), significance cutoffs — each arbitrary. Chasing them one at a time
(0.5 SD, 1.0 band, n=5, a "tighter than swing" ratio) showed the gate *itself* was the
problem: every meaningfulness threshold hides a magic number, and for tremor there is no
clinical anchor to pin one to.

## The rule (one line, all cards)
**A card shows once every quantity its statement depends on is stably computable** — not a
picked n.
- windowedEffect (walking / food / exercise / mindfulness) → the **swing** (SD of the daily
  signal), which needs a few days of passive data.
- dose-window → **both** morning AND afternoon onset (a comparison needs both arms stable;
  show each bucket's n). *A slip to "morning only" was caught — a solid baseline vs a 2-dose
  afternoon estimate is still a fluke.*
- wearing-off → the ON-duration.  gait → the multi-month slope.
- Honest caveat: "stably computable" still needs one operational definition (min days /
  convergence check) — less-arbitrary, **not** zero-knob.

## Facts over verdicts (observational cards)
Don't declare "meaningful." Show: **before → after in native units + the user's own natural
variability (swing) + a factual comparison line** ("that 0.2 sits inside your 0.8 swing").
The user judges. This dissolves the MID problem — no threshold is needed if you don't declare
meaning. Guardrails, or it becomes StrivePD's noise machine:
1. **Non-causal wording:** "your tremor averaged 0.2 lower after," never "walking reduced it."
2. **Dose-cleaned numbers** (already active, `doseCleanEvents`): a walk near a dose is dropped,
   else the pill's drop is miscredited to the walk.
3. **The reference-stability floor** above (not a raw n).

## Meaningfulness (effect) gate — ONLY where a *sourced* MCID exists
| Card | Sourced MCID? | Effect gate? |
|---|---|---|
| wearing-off | 60 min/day (pramipexole trials) | ✅ keep |
| gait | 0.06 m/s (Hass 2014) | ✅ keep |
| tremor / windowedEffect | ❌ none exists (searched Jul 17) | ❌ drop → facts approach |
| dose-window (afternoon onset) | ❌ none exists (searched Jul 17) | ❌ drop → facts + onset-variability yardstick |

**No tremor MID, no onset MID — both confirmed by literature search (Jul 17).** Tremor scales
(TETRAS / Fahn-Tolosa-Marin) have no validated MCID; wearable tremor-*amplitude* MID is
explicitly unestablished; onset latency is a used trial endpoint but has no MCID ("varies by
formulation"). So there is nothing to source — the facts approach is not a shortcut, it is the
only honest option. (Bonus from the onset search, saved for cold-start: population onset-to-ON
~46 min, SD 21 — `cold-start-priors.md`.)

**Jul 19 extension - the no-MCID logic applies to ALL tiers, not just the floor.** Dropping the
dose-window 15-min *floor* while keeping `doseResponseGate`'s 20/25-min Strong/Moderate floors
keeps the same unsourced constant one shelf higher. All three onset-minute floors go; the badge
tiers re-base on onset-variability + per-bucket n (the same basis the card body moves to).
Likewise the raw n-tiers across specs (5/10/20 etc.) are replaced by the stably-computable rule
where they were doing "is the estimate real yet" duty; n stays visible as a *fact* on the card
(per-bucket counts), never as a hidden verdict knob.

## Confidence badge — keep as-is, on ALL cards
Strong / Moderate / Emerging computed exactly as today (per-card `GateSpec`). Badge = coarse
"how sure," top-right; body = the facts. They **coexist** (not either/or), which keeps the
surface consistent. Dropping the dose-window 15-min gate shifts its badge basis from "gap ≥15
min" to "gap beyond your onset variability" — a significance-like basis that makes it *more*
consistent with the tremor cards, not less. **"Strong" already means different things per card**
(significance for exercise, effect-size vs MCID for wearing-off/gait) — a deeper consistency
cleanup, noted, not now.

## Error bar — considered, dropped
It arose only to make "show from n=1" safe (a single before/after is a seductive anecdote; a
numeric range is the honest caveat). Once we floor on reference-stability and keep the badge
(itself a coarse error bar), it is redundant. Not needed. If ever wanted: the range as a
detail-on-tap, never the primary mechanism.

## Rejected alternatives
- **Fixed 1.0-band MID (one severity step):** too coarse on a 0-4 scale — a real ~0.5
  improvement gets stamped "no effect." Quick to reassure, slow to celebrate.
- **0.5 × SD (Norman 2003):** an *observed average* across QoL questionnaires, contested (0.3
  vs 0.5; 2022 JCE review: no universal value), and doubly-transplanted onto a wearable tremor
  scale. Arbitrary.
- **Raw delta, no reference:** a false-positive machine — two noisy averages are never equal,
  so every factor shows a "change." StrivePD's failure mode; violates the engine-judges moat.

## Card changes (concrete, numbers illustrative)
**Walking (windowedEffect):** badge stays; body → "after your walks, tremor averaged 0.2 lower
(1.8 → 1.6); that sits inside your 0.8 swing." Floor ~3 walks (mathematical minimum), not 5.
**Dose-window:** title verdict → observation ("takes longer to kick in"); add onset-variability
yardstick ("onset varies ±12 min, so a 26-min gap is outside your range"); **per-bucket counts**
(morning n / afternoon n) replace the lumped "232 scored doses"; drop the 15-min gate. Keep the
badge, the 3-curve chart, the "for your neurologist" framing.

## ✅ Registry template entries (decided Jul 19)

The registry gets **two kinds of entry**:
- **Singular hypothesis** - a genuinely distinct question with its own mechanism + statistical
  treatment (`protein-meal-dose-onset`, `caffeine-tremor` with its confound note). Hand-authored
  line, as today. This is what the registry concept is actually for.
- **Question template, quantified over a domain** - one entry, instantiated by the engine per
  value **observed in the user's own data**. First target: the exercise cluster - the 13
  hand-listed workout entries are one hypothesis stamped 13 times (identical primitive, gate,
  windows; only the rationale differs), and any activity type not listed (swimming, hiking,
  rowing, Zumba…) is fetched by the adapter and silently dropped. They collapse to ONE template
  ("does ⟨observed activity⟩ shift tremor in the 2h after?") + a per-type **override table**
  keeping the curated touches (Tai Chi literature note, boxing/Rock Steady rationale); unlisted
  types get honest generic copy. New Apple activity types arrive for free; nobody hand-wires a
  workout type again.

Schema impact: an `instantiation: singular | perObservedType` marker on the entry (or a separate
template list); dispatch + gate + renderer unchanged - instantiated entries flow through the
existing windowed-effect path. Later applications of the same pattern: food attributes (5
detected, only 2 questioned - fat/fiber classified on every log and never consumed) and sleep
facets (rem/interruptions defined but unreachable). Human-approval seam intact: the *template*
is the approved question; stamping it per type was never curation.

## ✅ Multiplicity (decided Jul 19)

**Facts-over-verdict IS the multiplicity mitigation - stated as a decision, not an omission.**
Instantiating over the observed domain makes the test count explicit and per-user-variable; a
formal family-wise correction is NOT added, because observational cards no longer declare a
per-type verdict (no verdict, no family-wise error to control - the user reads before→after
against their own swing). The few cards that DO declare verdicts (wearing-off, gait) are
MCID-gated and few in number, which is the real protection. Revisit only if a verdict-declaring
card family ever instantiates over a domain. This replaces the architecture doc's unbuilt
"multiple-comparison correction" claim with what is actually true (see build package below).

## ✅ Build package - "make the gate honest" (scoped Jul 19)

One coherent work package; items 2-5 are small and ride along with 1:
1. **Build this redesign** (stably-computable floors, facts-over-verdict bodies, MCID-only
   effect gates, per-bucket counts, template entries above).
2. **Delete `RegistryEntry.minN`** - dead config: documented as "the sufficiency floor the gate
   enforces" but never read (the gate reads only the hard-coded per-renderer `GateSpec`s). With
   stably-computable floors it has no future either - delete rather than wire.
3. **Honest dormancy for `dose-dyskinesia-peak`** - it carries `renderer: .windowedEffect` but
   can never render (`windowedEffectInsight` guards `outcome.isTremor`; `windowedExposure` has
   no dose branch). Set `renderer: nil` + comment until a dyskinesia signal resolver + dose
   exposure branch exist; fix the `confidence-presence-vs-absence.md:44` row that lists it live.
4. **Doc-overclaim fixes** - `intelligence-architecture.md:132` claims multiple-comparison
   correction + replication across time windows (neither exists; `GateBar.minStability` is never
   set, `perEvent` deltas never consumed): rewrite to match the multiplicity decision above, and
   either delete the unused stability axis or leave it with an "unwired" comment.
5. **Constants ledger** - every engine constant gets a classification in a doc comment at the
   constant itself: **sourced** (citation: 60 min/day OFF MCID, 0.06 m/s gait MCID) /
   **structural** (derived from data or a mathematical minimum: per-user ON-window, n≥3 for a
   mean) / **provisional** (needs data: dyskinesia 0.5 floor) / **arbitrary** (named tech debt:
   `bucketOf` cliffs, `days: 120` fetch defaults). Index = a short table in
   `intelligence-architecture.md`, NOT a separate file (separate files rot). New rule: a
   constant may not ship unclassified.

## Open / parked
- **Dyskinesia noise floor (0.5):** a **data** block, not design — needs a dyskinetic user's
  stream (Bhav ~0 can't calibrate). Method when data lands: off-dose-window baseline or
  felt-state anchor. See `confidence-presence-vs-absence.md` + BACKLOG.
- **Time-of-day dose buckets too coarse:** logged in BACKLOG (Jul 17) — 1pm & 4pm both land in
  "afternoon" → blended. Direction: move off fixed clock buckets to time-since-dose / meal
  proximity.
- **"Stably computable" operational definition** — the one residual knob; define per card.
  Jul 19 rec: define as a **convergence criterion** (the estimate stops moving more than X% as
  days accrue), not a min-days count — a min-days count quietly becomes n≥5 wearing a new name.
- **Cold-start prior table** paused (Phase 1 inventory done — `cold-start-priors.md`).

## Not changed
The intelligence architecture stands: 3 layers (LLM proposes → engine judges → LLM narrates),
the walled-off Judge, registry / primitive / renderer, the dose-confound guard, the privacy
boundary, human-approves-questions, scaling. This is a refinement *inside* the Judge. (The Jul 19
template-entry decision touches the registry *schema* — one marker field — but not the seam:
questions are still human-approved, at the template level.)
