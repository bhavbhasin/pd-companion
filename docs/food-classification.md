# Kampa — Food Classification Design

> **Status:** Decided June 2026.
>
> How Kampa turns a free-text food description ("rajma rice with chai") into the
> `FoodAttribute` set (protein / fat / sugar / fiber / caffeine) the correlation
> engine consumes — privately, offline, for free, across global cuisines.

---

## The problem

Food logging is free text (voice/typed). The engine needs structured attributes
from it. The original classifier was `FoodAttribute.detect()` — a **hardcoded
keyword list** in `FoodEvent.swift`, English/Indian-centric, hand-grown one word
at a time. It doesn't scale to global cuisines and it's a maintenance treadmill
that also requires *nutrition* knowledge to extend (you'd have to know each food's
nutrients to add it).

Goal: replace it with something that (a) covers global cuisines, (b) stays
**fully on-device** (the privacy moat — "we can't see your data"), (c) is free,
(d) is **deterministic and auditable** (consistent with the engine's "no LLM as
judge" philosophy), and (e) is low-burden to grow.

---

## The decision

A **two-file, on-device design**:

| | **`FoodDB.sqlite`** | **`food-aliases.json`** |
|---|---|---|
| What | USDA FoodData Central (FNDDS + Foundation): food names + nutrients → coarse attributes | colloquial/regional term → canonical DB word(s) |
| Carries | **nutrition (the only place)** | **vocabulary only — no nutrition** |
| Owner | `build_food_db.py` (generated, never hand-edited) | **Bhav, by hand** |
| Format | binary SQLite, read-only, bundled in app | small human-editable JSON, in git, bundled |
| Changes | almost never | often early, then asymptotes |

**The principle that keeps it clean:** the map carries *vocabulary*, the DB
carries *nutrition*. Nutrition lives in exactly one place, so the two files can't
drift. You only ever hand-edit *names*, never nutrient facts.

---

## Why on-device database, NOT a live API

This is the load-bearing architecture choice. It is **not** an API at runtime —
it's a static SQLite file shipped inside the app.

- **Privacy** — nothing leaves the device. A live food API (USDA's or Open Food
  Facts') would send the user's food text to a third party, the same trust-boundary
  crossing as the Claude API: it would make the live privacy policy ("no Kampa
  servers, no sharing") false and require an opt-in + App Store disclosure.
- **Stability** — there is no API to be unstable, rate-limited, deprecated, or down.
  The only external touch is a **build-time** data export we run on our own schedule;
  the running app depends on a file we control, not someone else's server.
- **Offline + zero latency + $0.**

USDA bulk data is public domain, versioned, and free — perfect for bundling.

---

## Why DB + a small alias map (the evidence)

A clean **DB-only** design (no alias list) was tested against Bhav's real 86
logged food descriptions via `analysis/spike_food_db.py` (token-containment match
against USDA FNDDS+Foundation, normalized):

- **Clean DB-only coverage = 50%.**
- The failure is **chai-shaped**: `chai` is the *sole* missing word in 26 of 43
  misses — it's the most frequent item and USDA files it under "tea." Resolving
  chai alone → **80%**. The rest is a thin single-occurrence regional tail
  (uttapam, pinni, rajma, kadi, besan, idli, medu vada).
- A US food database structurally under-serves a chai-and-dal-heavy diet. No
  matching algorithm fixes it — the *words* aren't in USDA.

So DB-only is not shippable for this audience. Closing the gap needs the small
alias map. With ~10 entries, coverage goes 50% → ~90%.

### Rejected alternatives

| Considered | Verdict |
|---|---|
| **DB-only, no list** | ❌ 50% on real data; half the gap is one word (chai). |
| **Live food API** | ❌ privacy crossing + external dependency/instability. |
| **Open Food Facts instead of USDA** | ⚠️ covers regional names natively (no map) but ODbL license obligations + variable crowd-sourced quality + bigger bundle. Fallback only if the USDA+map path proves insufficient. |
| **On-device LLM (Apple Foundation Models)** | ⚠️ knows chai/dal/rajma semantically with no map, but iPhone-15-Pro+ only (app floor is iPhone 11) → forces a second fallback path, and reintroduces a hallucination surface in the attribute layer. The regional gap is what it's best at, but at costs we declined. |
| **On-device open LLM (Llama/Gemma via MLX/llama.cpp)** | ❌ 700MB–2GB payload, RAM-tight on iPhone 11, slow — wildly overkill for coarse attribute tagging. |
| **DB (USDA) + ~10-entry alias map** | ✅ **Chosen.** ~90% coverage, on-device, private, free, deterministic, clean license. |

---

## Runtime flow (save time)

```
"Rajma rice with chai"
  ① normalize → lowercase, strip punctuation, drop stopwords + number-words
       → tokens: ["rajma", "rice", "chai"]
  ② canonicalize each token through food-aliases.json:
       "rajma" → ["kidney beans"]   (map hit)
       "rice"  → ["rice"]           (no entry → passes through unchanged)
       "chai"  → ["tea"]            (map hit)
  ③ DB lookup on canonical terms (fuzzy match handles plurals/typos):
       kidney beans → protein, fiber
       rice         → (no flagged attribute)
       tea          → caffeine
  ④ union → { protein, fiber, caffeine }  → written to FoodEvent.attributes
```

- **Save is never blocked on classification** — the `FoodEvent` persists
  instantly (tremor/cognitive-load principle); attributes fill in right after.
- The map **never states nutrition** — it says "chai means tea"; the **DB** says
  tea has caffeine. End to end it's one auditable chain: `chai → tea → caffeine`.
- **Unmapped terms pass straight through** (most Western foods need no map entry —
  USDA already has them), so the map only fills USDA's *gaps* and stays small.
  A missing entry degrades gracefully — never breaks.
- **One-to-many** map values handle compound dishes with no separate decompose
  logic: `"uttapam" → ["rice", "lentil"]`, `"pinni" → ["ghee", "flour", "sugar"]`.
- The in-app **correction UI** (editable attribute chips) is the safety net: a
  wrong/empty tag is visible and fixable, so a deterministic matcher is acceptable.

---

## Operations — cadence, trigger, mechanism

**Mental model: the DB is the stable file; the map is the living file.**

### `FoodDB.sqlite`
- **Cadence:** essentially never. Nutrient facts ("kidney beans have protein")
  don't change.
- **Trigger to rebuild:** NOT "USDA released an update" — rather "**I changed what
  the app tracks**" (added a new attribute like sodium → needs a new nutrient
  column; or changed nutrient→attribute thresholds).
- **How to push:** it's bundled in the binary → a regenerated DB ships with a normal
  app build (TestFlight → App Store). It's **read-only reference data**, so **no
  CloudKit, no schema migration** — none of the `@Model` production-deploy drama.

### `food-aliases.json`
- **Cadence:** frequent early (onboarding testers with diverse diets), then
  asymptotes to a rare long tail.
- **Trigger to update:** a real logged food returns missing/wrong attributes —
  surfaced **reactively** (correction UI shows empty/wrong chips, or a tester
  reports it) or **proactively** (run the spike over recent tester food CSVs; it
  prints the exact missing-word list = the update queue).
- **Mechanical sequence to add mappings:**
  1. **Gather** — export the tester's `food_events.csv`, drop in `analysis/data/`.
  2. **Diagnose** — run `spike_food_db.py` over it; read the "missing food-words"
     list. (Diagnosis script — you never run a script to *edit* the map.)
  3. **Find the DB target word** for each gap (`rajma` → USDA "Beans, kidney…" →
     `kidney beans`). [Harness `--suggest` mode does this for you — see below.]
  4. **Edit `food-aliases.json`** by hand — add `"rajma": ["kidney beans"]`, etc.
  5. **Confirm the lift** — re-run the spike *with the map applied* and watch
     coverage move (e.g. 50% → 88%). [Harness `--map` mode — see below.]
  6. **Ship** — commit; the map rides the next app build (later: remote-config push).

### Maintenance loop — the spike is the permanent gap-finder
The same `spike_food_db.py` that made this decision is the ongoing instrument:
> collect tester food CSV → run spike → it names the gaps (and `--suggest`s
> targets) → edit `food-aliases.json` → re-run spike (`--map` confirms the lift)
> → commit.

Two harness enhancements make the loop turnkey (to build):
- **`--map food-aliases.json`** — applies the map before matching, so step 5 works.
- **`--suggest`** — for each missing word, prints the closest DB entries as
  candidate targets, so step 3 stops being a manual grep.

---

## Deployment — same config-vs-code split as the engine

This file joins the lane the registry already lives in
([`intelligence-architecture.md`](intelligence-architecture.md)):

| Artifact | Nature | Deployment |
|---|---|---|
| **`food-aliases.json`** | *config* (vocabulary) | **remote-config push** (eventual) — no App Store resubmit, human-approves-the-change seam intact |
| Registry entries | *config* | remote-config push |
| `FoodDB.sqlite`, primitives, adapters, `build_food_db.py` | *code* | app update |

One deployment model, one governance seam, at every scale. The map's "an app
build per edit" wrinkle has a designed exit (remote config) — gated/later, not
built now.

---

## Build status (Jun 24, 2026)

**Python slice built; COVERAGE *and* ATTRIBUTE CORRECTNESS both solved.**

- ✅ `analysis/build_food_db.py` → `FoodDB.sqlite` (5,901 foods, 0.6 MB). Caught+fixed
  a real bug: FNDDS uses legacy SR nutrient numbers, Foundation uses FDC ids, so the
  first build silently zeroed all FNDDS attributes incl. caffeine. Now resolved
  per-dataset from `nutrient.csv` (keyed on both id schemes).
- ✅ `analysis/food-aliases.json` + `spike_food_db.py --map`.
  **Coverage on the real 86 foods: 50% (DB-only) → 100% (with map).**
- ✅ **`analysis/classify_food.py` — attribute resolution redesigned to FOOD-NAME-level
  matching.** The earlier word→attribute index was unreliable (ambiguous words grabbed
  unrepresentative foods: "black" → black *tea* → phantom caffeine on black-eyed peas;
  "rice" → phantom sugar; "tea" → herbal → `chai` LOST caffeine). The new model:
  1. **Token-subset match** the canonical phrase against full food **names** (fuzzy per
     token for plurals/typos) — never substring, so `cola` can't hit "cho**cola**te".
  2. **Pick the representative food**: prefer USDA's generic `NFS`/`NS as to…` entry, led
     by the queried word, with fewest qualifier tokens — and **penalize processed forms**
     (`canned`/`juice`/`dried`/`honey`/…) so `Pear, raw` (3.1g fiber) beats `Pear, canned`
     (1.5g).
  3. **Drop standalone qualifier words** (`black`/`white`/`hot`/`raw`/…) — they modify a
     food, they are not one, so they can't pull a wrong food on their own.
  4. **Greedy multi-word alias keys** (`black eyed peas` → `blackeyed peas`) before single
     tokens. `food-aliases.json` values are now representative *phrase* queries, not bare
     words (`chai → "tea hot leaf black"`, `rajma → "kidney beans"`, `coffee → "coffee ns
     type"`, `walnut(s) → "walnuts english halves"`).
- ✅ **Validated against the real 86 foods (diff vs the old keyword matcher):** 97
  additions-only (real under-tagging fixed — e.g. almonds now `protein+fat+fiber`, not
  `fat`-only), **1 removal** (uttapam phantom sugar — a correction), and **zero phantom
  caffeine** anywhere. Every change is a justified add or a correct removal.
- **Threshold calibration (coarse-presence decisions):**
  - **Caffeine `0.0001` → `5 mg/100g`.** The old "any trace" bar flagged dessert caffeine
    (ice cream ~1, choc milk ~1, cocoa ~3) as equal to coffee. 5mg keeps every real source
    (coffee ~40, black tea ~20, cola ~9, dark chocolate ~47) and drops the trace noise
    (403 → 247 flagged foods). This is the one clinically-validated attribute (PD
    pharmacology), so it's worth getting right.
  - **Whole fruit always counts as fiber** (overrides the 3g bar). Per-100g, fruit is
    modest (apple 2.1, orange 2.0, banana 1.7) and misses the generic threshold — but it's
    eaten in large portions and is the canonical motility/constipation lever (strong
    personal n-of-1: an apple after dinner reliably moves the next morning). Keyed off
    USDA's fruit *categories*, not names — FNDDS WWEIA whole-fruit block 6002–6024 — and
    **juice/drinks are excluded** (juice strips the fiber out): `Apple, raw` → fiber,
    `Apple juice` → not. The base fiber bar stays 3.0g for everything else (lowering it
    globally to catch fruit balloons fiber-flagged foods 18% → 31%, diluting the signal).
- ▶ **NEXT:** Swift `FoodAttributeClassifier` (mirror the validated Python, replace
  `FoodAttribute.detect()`, Opus + on-phone); spike `--suggest` for the maintenance loop.
- ⚠️ **Historical backfill — needed but GATED on the Swift port.** Existing history is
  under-tagged (almonds = `fat`-only). When the corrected classifier ships, run a one-time
  re-classification over all existing `FoodEvent`s (SwiftData → CloudKit, no schema
  change) — **preserving any manual chip corrections.**
- **LinkedIn:** post candidate logged in `marketing/linkedin/README.md` idea bank.
- ⚠️ **Repo hygiene — the code is NOT in git yet.** The whole `analysis/` lab is
  gitignored (`.gitignore:30`), so `build_food_db.py`, `classify_food.py`,
  `spike_food_db.py`, and `food-aliases.json` live only on local disk — invisible to
  git/backup. Fine while it's throwaway prototype, but when the classifier ships these
  must move to **tracked** locations: `build_food_db.py` → `scripts/`;
  **`food-aliases.json` → a tracked path / the app bundle** (it's the hand-maintained
  *living* file — must not live only in a gitignored lab long-term). The two-file table
  above already assumes `food-aliases.json` is "in git, bundled" — this is the open
  action to make that true.
