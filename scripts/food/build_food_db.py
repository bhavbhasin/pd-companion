#!/usr/bin/env python3
"""
build_food_db.py - USDA FoodData Central CSVs -> bundled FoodDB.sqlite

Generates the on-device food database for Kampa's classifier (see
docs/food-classification.md). One row per real USDA food: its name plus the five
coarse FoodAttribute booleans (protein/fat/sugar/fiber/caffeine), derived from
per-100g nutrient amounts via the thresholds below.

This is a BUILD-TIME tool. The running app never touches USDA or any API - it
ships the SQLite this produces. Re-run only when changing the tracked
attributes or thresholds (not for USDA refreshes - nutrient facts don't move).

    python build_food_db.py            # writes data/FoodDB.sqlite + prints summary

Inputs (already staged, gitignored): data/FoodData_Central_*_csv_*/{food,food_nutrient}.csv
"""
from __future__ import annotations

import csv
import json
import sqlite3
import sys
from pathlib import Path

# Layout after graduating out of the analysis/ lab:
#   scripts/food/                 - this tool (tracked)
#   analysis/data/                - USDA bulk CSVs (gitignored, build-time input only)
#   PD Companion/.../Resources/Food/FoodDB.sqlite - the bundled output (tracked)
REPO = Path(__file__).resolve().parents[2]
DATA = REPO / "analysis" / "data"
RES = REPO / "PD Companion" / "PD Companion" / "Resources" / "Food"
OUT = RES / "FoodDB.sqlite"          # queried by the Python tooling (spike/classify)
JSON_OUT = RES / "FoodDB.json"       # bundled by the iOS app (Codable, no SQLite dep)

# Datasets to ingest: (label, dir, set of food.csv data_types that are real foods)
DATASETS = [
    ("foundation", "FoodData_Central_foundation_food_csv_2026-04-30", {"foundation_food"}),
    ("fndds",      "FoodData_Central_survey_food_csv_2024-10-31",      {"survey_fndds_food"}),
]

# Map our FoodAttribute from the nutrient NAME (prefix-matched in nutrient.csv).
# We resolve the actual numeric ids per-dataset because food_nutrient.csv uses
# DIFFERENT schemes: Foundation uses FDC ids (1003), FNDDS uses legacy SR numbers
# (203). Deriving from names handles both + the "269.3"->269 sugar quirk.
NUTRIENT_NAMES = {
    "protein": "protein", "total lipid": "fat", "sugars, total": "sugar",
    "fiber, total dietary": "fiber", "caffeine": "caffeine",
}


def nutrient_map(base: Path) -> dict[int, str]:
    """int-keyed {nutrient code -> attribute} covering BOTH the FDC `id` and the
    legacy `nutrient_nbr` for our 5 nutrients (ranges don't collide: 203 vs 1003),
    so the same map resolves whichever scheme a dataset's food_nutrient uses."""
    m: dict[int, str] = {}
    with open(base / "nutrient.csv", newline="") as fh:
        for r in csv.DictReader(fh):
            name = r["name"].lower()
            attr = next((a for k, a in NUTRIENT_NAMES.items() if name.startswith(k)), None)
            if not attr:
                continue
            m[int(r["id"])] = attr
            if r.get("nutrient_nbr"):
                m[int(float(r["nutrient_nbr"]))] = attr  # 269.3 -> 269
    return m

# Coarse presence thresholds, per 100g (USDA amounts are per 100g). Tunable.
# Protein is the clinically important one (levodopa competition) - 5g/100g flags
# real protein sources (beans ~9, paneer ~18, tofu ~8, dal ~5-9) but not rice (~2.7).
# Caffeine 5mg/100g keeps the real sources (coffee ~40, black tea ~20, cola ~9,
# dark chocolate ~47) but drops trace dessert caffeine (ice cream ~1, choc milk ~1,
# cocoa ~3) that would otherwise read as equivalent to a cup of coffee.
THRESHOLD = {"protein": 5.0, "fat": 5.0, "sugar": 5.0, "fiber": 3.0, "caffeine": 5.0}
ATTRS = ("protein", "fat", "sugar", "fiber", "caffeine")

# Whole fruit ALWAYS counts as fiber, below the 3g bar. Per-100g, fruit is modest
# (apple 2.1, orange 2.0, banana 1.7) so it misses the generic threshold - but it's
# eaten in large portions and is a canonical motility/constipation lever for people
# with Parkinson's, so whole fruit earns the flag despite the modest number. Keyed off
# USDA's fruit categories, NOT names, and JUICE/drinks are excluded (juice strips the
# fiber out). FNDDS WWEIA whole-fruit block = 6002..6024 (apples, bananas, grapes,
# berries, citrus, melons, dried, pears, pineapple, mango...), which sits cleanly below
# the juice/drink categories (7006, 7204). Foundation food_category 9 is "Fruits and
# Fruit Juices" combined, so there we drop juice by name.
FOUNDATION_FRUIT_CATS = {"9"}
JUICE_WORDS = ("juice", "drink", "nectar", "cocktail", "ade", "smoothie", "punch")


def is_fruit_category(label: str, cat: str) -> bool:
    if label == "foundation":
        return cat in FOUNDATION_FRUIT_CATS
    return cat.isdigit() and 6002 <= int(cat) <= 6024  # FNDDS WWEIA whole-fruit block


csv.field_size_limit(min(sys.maxsize, 2**31 - 1))


def ingest(label: str, folder: str, food_types: set[str]) -> list[tuple]:
    base = DATA / folder
    if not base.exists():
        sys.exit(f"missing dataset dir: {base}")

    # 1. wanted foods: fdc_id -> (name, category) filtered to real food data_types
    foods: dict[str, str] = {}
    category: dict[str, str] = {}
    with open(base / "food.csv", newline="") as fh:
        for r in csv.DictReader(fh):
            if r["data_type"] in food_types:
                foods[r["fdc_id"]] = r["description"].strip()
                category[r["fdc_id"]] = r.get("food_category_id", "")


    # 2. nutrient amounts for those foods (stream the big file once)
    nmap = nutrient_map(base)
    amounts: dict[str, dict[str, float]] = {fid: {} for fid in foods}
    with open(base / "food_nutrient.csv", newline="") as fh:
        for r in csv.DictReader(fh):
            fid = r["fdc_id"]
            if fid in amounts and r["nutrient_id"] and r["amount"]:
                attr = nmap.get(int(float(r["nutrient_id"])))
                if attr:
                    amounts[fid][attr] = float(r["amount"])

    # 3. derive boolean attributes per food
    rows = []
    for fid, name in foods.items():
        a = amounts[fid]
        flags = {at: int(a.get(at, 0.0) >= THRESHOLD[at]) for at in ATTRS}
        # whole fruit always counts as fiber (not juice/drinks)
        if is_fruit_category(label, category[fid]) and not any(w in name.lower() for w in JUICE_WORDS):
            flags["fiber"] = 1
        rows.append((fid, label, name, *(flags[at] for at in ATTRS)))
    return rows


def main() -> None:
    all_rows = []
    for label, folder, types in DATASETS:
        rows = ingest(label, folder, types)
        print(f"  {label:11s}: {len(rows):>5} foods")
        all_rows.extend(rows)

    OUT.unlink(missing_ok=True)
    con = sqlite3.connect(OUT)
    con.execute(
        "CREATE TABLE food (fdc_id TEXT, source TEXT, name TEXT, "
        + ", ".join(f"{a} INTEGER" for a in ATTRS) + ")"
    )
    con.executemany(
        f"INSERT INTO food VALUES (?,?,?,{','.join('?'*len(ATTRS))})", all_rows
    )
    con.execute("CREATE INDEX idx_name ON food(name)")
    con.commit()

    # summary
    print(f"\nWrote {OUT}  ({len(all_rows):,} foods, {OUT.stat().st_size/1e6:.1f} MB)")
    print("  foods flagged per attribute:")
    for a in ATTRS:
        n = con.execute(f"SELECT COUNT(*) FROM food WHERE {a}=1").fetchone()[0]
        print(f"    {a:9s} {n:>5}  (>= {THRESHOLD[a]} per 100g)")
    con.close()

    # JSON twin for the iOS app: {name, attrs[]} per food, sorted for clean diffs.
    # The app loads this with Codable and matches in-memory (the SQLite is only for
    # the Python tooling, which queries it). Same data, two consumers.
    foods_json = sorted(
        ({"name": name, "attrs": [a for a, f in zip(ATTRS, flags) if f]}
         for (_fid, _src, name, *flags) in all_rows),
        key=lambda d: d["name"],
    )
    JSON_OUT.write_text(json.dumps({"foods": foods_json}, ensure_ascii=False, indent=0))
    print(f"Wrote {JSON_OUT}  ({JSON_OUT.stat().st_size/1e6:.1f} MB, {len(foods_json):,} foods)")


if __name__ == "__main__":
    main()
