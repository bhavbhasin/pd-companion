# Kampa — Food Attribute Correction & Learning (Design)

> **Status:** Designed June 2026, not built. Forward-looking design for the
> human-in-the-loop layer on top of the food classifier
> ([`food-classification.md`](food-classification.md)).

---

## Problem

The classifier auto-tags each food entry with coarse attributes
(protein / fat / sugar / fiber / caffeine). It is good but not perfect — diet
sodas, brand names, regional dishes, and the inherent ceiling of a coarse
5-attribute model all produce occasional wrong or missing tags. We need a
human-in-the-loop correction path.

The naive version — let the user toggle the attribute chips on a single entry —
**fixes that one entry but does not learn.** Re-log the same food tomorrow and it
mis-tags again; the user re-corrects every time. That is patchwork, not learning.

**The right design makes a correction persist for the *food*, across all future
logs.** This document captures both levels and recommends building toward the
learning version from the start.

---

## Level 1 — Per-entry chip editing (patchwork, NOT learning)

The minimal version, documented here mainly to be explicit about why it is *not*
sufficient on its own.

- On the entry detail card, the read-only `Detected:` chips become toggleable:
  all five attributes shown, detected ones filled, the rest outlined; tap to flip.
  Removing a wrong tag and adding a missing one are the same gesture.
- A new `attributesEdited: Bool` flag on `FoodEvent` marks a hand-corrected entry,
  so the launch backfill and any auto-reclassify **skip it** (never silently
  overwrite a human correction). New field → **CloudKit schema change**.
- Edge rule: editing the food *text* re-classifies (fresh food → fresh tags);
  editing *chips* is a sticky override.

**Why it is not enough (the core limitation):** the correction lives on the
`FoodEvent`, not on the food. The same food, logged again, starts wrong again.

---

## Level 2 — Food-term-level learned corrections (the right design)

A correction associates an attribute set with the **food term**, so it persists
for every future log containing that term. This is the actual "learning."

### The granularity problem (the crux)

A free-text entry — "paneer bread diet coke" — merges several foods' attributes
into one chip set. If the user removes **sugar**, *which* food did they mean — the
bread or the diet coke? An entry-level correction cannot know. **Learning requires
correcting at the food level, not the entry level.**

The classifier already decomposes internally (each canonical query → one
representative food → its attributes); it just merges the results before
returning. Level 2 surfaces that decomposition:

```
We read this as:
   Diet Coke → caffeine
   Paneer    → protein, fat
   Bread     → sugar, protein
```

The user corrects a *specific recognized food*, and that correction is stored
keyed on **the user's normalized term** ("diet coke") — not the resolved USDA
food name — so it generalizes to how they actually type. Next time any entry
contains "diet coke," the learned override is applied.

### Where it sits architecturally

This is a **per-user, learned extension of the alias/attribute layer.** The global
alias map is shared vocabulary; learned corrections are a personal overlay on top
of the same DB + alias resolution. Same "config layer over a deterministic engine"
seam the rest of the system already uses — the classifier resolves a term, then
overlays any personal learned override for that term before returning.

### Data model

```
@Model LearnedFoodCorrection {
    var term: String          // normalized user term, unique key (e.g. "diet coke")
    var attributes: [FoodAttribute]   // or a delta — see open decisions
    var updatedAt: Date
}
```

On-device, **CloudKit-synced** (personal, private — never centralized; see the
cross-user data boundary below). Another schema addition → careful deploy.

### Classifier change required

The classifier currently returns a merged `Set<FoodAttribute>` for the whole
description. Level 2 needs it to also return the **per-food breakdown**:
`[(term, resolvedFoodName, attributes)]`. It already computes this internally
(`expandQueries` → `bestFood` per query) — this just exposes it so the correction
UI can show and correct each recognized food.

---

## Recommendation

**Do not ship Level 1 alone.** Per the core limitation, entry-only chips create a
UX we would have to redo. Design the correction UI around **food-level**
correction from the start (show the decomposition, correct per food), so the same
UI naturally supports learning once the override store is wired.

Minimum coherent slice:
1. Classifier exposes the per-food breakdown.
2. Correction UI shows recognized foods + their chips, editable.
3. `LearnedFoodCorrection` store, keyed on normalized term.
4. Classifier overlays learned overrides on every future classify.
5. (Carry over from L1) `attributesEdited` on `FoodEvent` so already-corrected
   entries are not re-derived.

---

## Open decisions

- **Absolute vs delta override.** Store the corrected attribute *set* for a term,
  or a *delta* ("remove sugar / add fiber")? Deltas compose better when a food
  co-occurs with others; absolute is simpler to reason about. Leaning delta.
- **Term key granularity.** The learned key must respect alias/multi-word
  granularity — "diet coke" vs "coke" must not collide.
- **Unrecognized text.** Decomposition can only surface foods the classifier
  recognized. Text it did not resolve to a food cannot be corrected at the food
  level (falls back to leaving the entry as-is, or an entry-level note).
- **Promotion to the global map.** A correction many users make ("diet coke → no
  sugar") is a signal to fix the *global* alias map — but that needs cross-user
  data, which crosses the privacy line (raw user data is never centralized; only
  federated / aggregate / opt-in, per the data-architecture decisions). Personal
  learning stays on-device; global learning is a separate, gated, privacy-careful
  feature. **Level 2 is personal-only.**

---

## Honest ceiling

Even food-level learning only corrects wrong/missing attribute *flags* for a known
food — it cannot add dimensions the coarse 5-attribute model never had (portion
size, papain-style enzymes, glycemic load). For those, the correlation engine
reading real logged data over time remains the deeper lever, not richer tagging.
