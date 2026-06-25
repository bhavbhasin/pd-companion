#!/usr/bin/env python3
"""
classify_food.py - reference food->attribute classifier + correctness diff.

The Python reference implementation of Kampa's runtime classifier (the model the
Swift FoodAttributeClassifier will mirror): a free-text description ->
FoodAttribute set, using FoodDB.sqlite + food-aliases.json, fully deterministic.

DESIGN (redesigned Jun 24 - food-NAME-level matching):
  The earlier model resolved each WORD to "the food where that word is primary"
  and unioned attributes. That was unreliable - ambiguous words grabbed
  unrepresentative foods ("black" -> black TEA -> phantom caffeine on black-eyed
  peas; "rice" -> a sweetened rice -> phantom sugar; "tea" -> herbal -> LOST
  caffeine on chai). The fix:

    1. Match each canonical food PHRASE against full food NAMES (token-subset,
       fuzzy per token for plurals/typos) - never substring (so "cola" can't hit
       "choCOLAte").
    2. Among the foods a phrase matches, pick the REPRESENTATIVE one: USDA's
       generic "NFS"/"NS as to..." entry, leading with the queried food, fewest
       qualifier tokens. That entry carries the coarse, typical attributes.
    3. A standalone unmapped QUALIFIER word (black/white/hot/raw/...) is dropped -
       it only ever modifies a food, it is not a food, so it must not pull one.
    4. food-aliases.json maps colloquial/regional terms (and a few ambiguous
       English words) to a specific representative phrase: chai -> "tea hot leaf
       black", rajma -> "kidney beans". Multi-word keys ("black eyed peas") are
       matched greedily before single tokens.

Run with no args: classifies every food in the CSV and DIFFS the result against
the `attributes` already stored by the old keyword matcher - showing exactly what
the new classifier would correct (and previewing the one-time backfill).

    python classify_food.py
"""
from __future__ import annotations

import importlib.util
import json
import sqlite3
from collections import Counter
from difflib import get_close_matches
from pathlib import Path

import pandas as pd

HERE = Path(__file__).parent
REPO = Path(__file__).resolve().parents[2]
RES = REPO / "PD Companion" / "PD Companion" / "Resources" / "Food"  # bundled (tracked)
DB = HERE / "FoodDB.sqlite"          # tooling-only sqlite (lives beside this script)
MAP = RES / "food-aliases.json"
CSV = REPO / "analysis" / "data" / "food_events_2026-05-12_to_2026-06-18.csv"  # gitignored
ATTRS = ("protein", "fat", "sugar", "fiber", "caffeine")

# reuse the validated normalization/tokenization from the spike
_spec = importlib.util.spec_from_file_location("spike", HERE / "spike_food_db.py")
spike = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(spike)

# Standalone words that only ever MODIFY a food - never a food themselves. Dropped
# when they appear as an unmapped lone token, so they can't drag in a wrong food
# ("black" must not resolve to black tea). They still ride along inside a mapped
# phrase ("tea hot leaf black" from chai) - this only affects bare user tokens.
QUALIFIERS = {
    "black", "white", "red", "green", "yellow", "brown", "purple",
    "hot", "cold", "iced", "warm", "raw", "fried", "roasted", "baked",
    "boiled", "steamed", "grilled", "fresh", "dried", "ground", "whole",
}

# Processed/derived FORM tokens in a food NAME. For a whole food, the raw/plain
# entry is more representative than a canned/juiced/dried/sweetened one (e.g.
# "Pear, raw" 3.1g fiber vs "Pear, canned" 1.5g), so foods carrying these are
# deprioritized in selection - even over USDA's generic NFS marker.
PROCESSED = {
    "canned", "juice", "dried", "frozen", "sweetened", "syrup", "candied",
    "jam", "jelly", "instant", "bottled", "powder", "concentrate", "honey",
}


def load_foods(db: Path) -> list[dict]:
    con = sqlite3.connect(db)
    rows = con.execute(f"SELECT name, {','.join(ATTRS)} FROM food").fetchall()
    con.close()
    foods = []
    for name, *flags in rows:
        toks = spike.tokens(name)
        if not toks:
            continue
        foods.append({
            "name": name,
            "toks": toks,
            "tokset": set(toks),
            "attrs": frozenset(a for a, f in zip(ATTRS, flags) if f),
            # USDA's generic representative marker
            "generic": ("nfs" in toks) or ("ns" in toks),
        })
    return foods


def best_food(query: str, foods: list[dict], cutoff: float = 0.84) -> dict | None:
    """The representative DB food for a canonical phrase. A food is a candidate if
    every query token is one of its name tokens (exact, or a close fuzzy match for
    plural/typo). Among candidates prefer: the food LED by the queried word, then
    the generic NFS/NS entry, then fewest qualifier tokens, then shorter name."""
    qtoks = spike.tokens(query)
    if not qtoks:
        return None
    qset = set(qtoks)
    cands = [
        f for f in foods
        if all(qt in f["tokset"] or get_close_matches(qt, f["toks"], n=1, cutoff=cutoff)
               for qt in qtoks)
    ]
    if not cands:
        return None
    cands.sort(key=lambda f: (
        f["toks"][0] not in qset,                    # food led by the queried word first
        bool(f["tokset"] & PROCESSED),               # then a raw/plain form over processed
        not f["generic"],                            # then the generic NFS/NS entry
        len(f["toks"]) - len(qset),                  # then fewest extra qualifier tokens
        len(f["name"]),                              # then the plainer (shorter) name
    ))
    return cands[0]


def expand_queries(desc: str, amap: dict[str, list[str]]) -> list[str]:
    """desc -> list of canonical food-PHRASE queries. Greedy multi-word alias keys
    match first, then single-token keys; unmapped qualifier words are dropped,
    other unmapped tokens pass through as their own single-word query."""
    toks = spike.tokens(desc)
    # longest alias keys first so "black eyed peas" wins over "peas"
    keys = sorted((k for k in amap), key=lambda k: -len(k.split()))
    out: list[str] = []
    i = 0
    while i < len(toks):
        matched = False
        for key in keys:
            kt = key.split()
            if toks[i:i + len(kt)] == kt:
                out.extend(amap[key])       # each value entry is a phrase query
                i += len(kt)
                matched = True
                break
        if matched:
            continue
        t = toks[i]
        if t not in QUALIFIERS:
            out.append(t)
        i += 1
    return out


def classify(desc: str, amap: dict, foods: list[dict]) -> frozenset:
    out: set[str] = set()
    for q in expand_queries(desc, amap):
        f = best_food(q, foods)
        if f:
            out |= f["attrs"]
    return frozenset(out)


def main() -> None:
    amap = {k.lower(): v for k, v in json.loads(MAP.read_text()).items()
            if not k.startswith("_")}
    foods = load_foods(DB)
    d = pd.read_csv(CSV)

    changed = added_only = removed_any = 0
    add_counter, rem_counter = Counter(), Counter()
    examples = []
    for _, r in d.iterrows():
        desc = str(r["userDescription"]).strip()
        if not desc or desc == "nan":
            continue
        old = frozenset(x for x in str(r.get("attributes", "") or "").split("|")
                        if x and x != "nan")
        new = classify(desc, amap, foods)
        if new == old:
            continue
        changed += 1
        adds, rems = new - old, old - new
        add_counter.update(adds); rem_counter.update(rems)
        if rems:
            removed_any += 1
        elif adds:
            added_only += 1
        examples.append((desc, old, new, adds, rems))

    total = len(d[d["userDescription"].notna()])
    print(f"Entries classified: {total}")
    print(f"  changed by new classifier: {changed}  ({changed/total:.0%})")
    print(f"    additions only (more complete):   {added_only}")
    print(f"    some attribute REMOVED (scrutinize): {removed_any}")
    print(f"  attributes ADDED across corpus:   {dict(add_counter)}")
    print(f"  attributes REMOVED across corpus: {dict(rem_counter)}")
    print("\n  sample changes (old -> new):")
    for desc, old, new, adds, rems in examples[:24]:
        tag = ("  +" + ",".join(sorted(adds))) + (("  -" + ",".join(sorted(rems))) if rems else "")
        print(f"    {desc[:38]:40s} {sorted(old)} -> {sorted(new)}{tag}")


if __name__ == "__main__":
    main()
