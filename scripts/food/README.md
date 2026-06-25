# Food classification toolchain

Build-time + maintenance tooling for Kampa's food → `FoodAttribute`
(protein / fat / sugar / fiber / caffeine) classifier. Design rationale lives in
[`docs/food-classification.md`](../../docs/food-classification.md); this README is
the operational how-to.

The running app never touches USDA or any network — it bundles a static SQLite +
a small alias map. These scripts produce and validate those two files.

## Files & layout

| Path | Tracked? | Role |
|---|---|---|
| `scripts/food/build_food_db.py` | yes | USDA CSVs → `FoodDB.sqlite` |
| `scripts/food/classify_food.py` | yes | reference classifier + correctness diff vs the old tags |
| `scripts/food/spike_food_db.py` | yes | coverage gap-finder (the maintenance instrument) |
| `PD Companion/PD Companion/Resources/Food/FoodDB.sqlite` | yes | the bundled DB (build output; app reads this) |
| `PD Companion/PD Companion/Resources/Food/food-aliases.json` | yes | hand-maintained vocabulary map (app reads this) |
| `analysis/data/FoodData_Central_*` | **no** (gitignored, ~56 MB) | USDA bulk CSV inputs to `build_food_db.py` |
| `analysis/data/food_events_*.csv` | **no** (gitignored, personal) | real logged-food export used by the diff |

`FoodDB.sqlite` is committed even though it's generated, because the USDA source
CSVs are not in the repo — so the app builds without a 56 MB download. Rebuild it
only when changing tracked attributes or thresholds (not for USDA refreshes —
nutrient facts don't move).

## USDA inputs (if you need to rebuild the DB)

Download FoodData Central "Foundation Foods" and "FNDDS / Survey" CSV bundles from
<https://fdc.nal.usda.gov/download-datasets.html> and unzip into `analysis/data/`
so the two `FoodData_Central_*_csv_*` folders sit there. Then:

```bash
python scripts/food/build_food_db.py     # writes Resources/Food/FoodDB.sqlite
```

## The maintenance loop (growing the alias map)

The classifier covers global cuisines via `food-aliases.json` — a small,
hand-grown map from colloquial/regional terms to representative USDA food phrases.
Grow it from real gaps, not guesses:

1. **Gather** — export a tester's `food_events.csv` into `analysis/data/`.
2. **Diagnose** — `python scripts/food/spike_food_db.py …` prints the missing
   food-words (the update queue). You never run a script to *edit* the map.
3. **Find the DB target** for each gap (e.g. `rajma` → `kidney beans`).
4. **Edit `food-aliases.json`** by hand — values are representative *phrase*
   queries (`"chai": ["tea hot leaf black"]`), not bare words.
5. **Confirm** — re-run `classify_food.py`; the diff should show the lift and no
   new phantom tags.
6. **Commit** — the map + (if rebuilt) the SQLite ride the next app build.

## Note on the Python venv

These use the prototype venv at `analysis/.venv` (pandas for CSV reads). It stays
in the gitignored lab; recreate with `python3 -m venv analysis/.venv && analysis/.venv/bin/pip install pandas` if missing.
