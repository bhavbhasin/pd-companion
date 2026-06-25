#!/usr/bin/env python3
"""
Spike: can a CLEAN, no-alias-table match against an on-device food DB cover
Bhav's real logged foods?

The question this answers (and ONLY this): for each food description he has
actually typed, does a deterministic fuzzy match find a plausible entry in a
candidate database WITHOUT any hand-maintained alias/synonym table? If yes for
some DB, that DB + this matcher is the whole classifier design. If USDA-clean
is too low, we try a broader USDA set, then Open Food Facts.

This phase tests NAME COVERAGE only (does the food exist in the DB), not the
nutrient->attribute mapping. Coverage is the gate; if a food isn't in the DB,
nothing downstream matters. Nutrient mapping is phase 2.

No new deps: stdlib difflib only (pandas just for the CSV read). rapidfuzz is
faster/better if we decide to keep going, but difflib keeps the spike portable.

Usage:
    python spike_food_db.py \
        --food data/food_events_18-06-2026.csv \
        --db usda_foundation=data/usda_foundation_names.txt \
        --db usda_fndds=data/usda_fndds_names.txt \
        --db off=data/off_names.txt \
        --threshold 0.72

Each --db is LABEL=PATH. PATH is either a .txt (one food name per line) or a
.csv (food name column auto-detected: 'description' / 'product_name' / 'name').
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
from difflib import get_close_matches
from pathlib import Path

import pandas as pd

# Words that carry no food identity - dropped before token matching so
# "rajma chawal with coffee" -> ["rajma", "chawal", "coffee"].
STOPWORDS = {
    "with", "and", "a", "an", "of", "the", "plus", "some", "my", "in", "on",
    "for", "to", "had", "ate", "drank", "cup", "cups", "glass", "bowl", "plate",
    "piece", "pieces", "slice", "slices", "small", "medium", "large", "half",
    # spelled-out quantities ("Five almonds, three walnuts") - not foods
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
}
_PUNCT = re.compile(r"[^a-z0-9\s]")
_WS = re.compile(r"\s+")


def norm(text: str) -> str:
    text = _PUNCT.sub(" ", text.lower())
    return _WS.sub(" ", text).strip()


def tokens(text: str) -> list[str]:
    # drop stopwords AND pure-number tokens (quantities like "5", "2" aren't foods)
    return [t for t in norm(text).split() if t and t not in STOPWORDS and not t.isdigit()]


def db_vocabulary(path: Path) -> set[str]:
    """The DB's WORD vocabulary: every food-word that appears across all entry
    names. We match food words against this set, NOT whole strings against
    whole strings - so USDA's verbose descriptors ('apple raw', 'bread
    chappatti or roti') don't penalize a clean term like 'apple' or 'roti'."""
    if path.suffix.lower() == ".csv":
        df = pd.read_csv(path)
        for col in ("description", "product_name", "name", "food_name"):
            if col in df.columns:
                names = df[col].dropna().astype(str)
                break
        else:
            sys.exit(f"{path}: no recognizable name column in {list(df.columns)}")
    else:
        names = pd.Series([l.strip() for l in path.read_text().splitlines() if l.strip()])
    vocab: set[str] = set()
    for n in names:
        vocab.update(tokens(n))  # same norm/stopword/digit filtering as queries
    return vocab


def token_matches(tok: str, vocab: set[str], cutoff: float) -> bool:
    """A food word is present if it's in the DB vocabulary outright, or a close
    fuzzy match exists (handles plurals 'oranges'->'orange', typos
    'chicpeas'->'chickpeas'). Still no alias table - pure string similarity."""
    if tok in vocab:
        return True
    return bool(get_close_matches(tok, vocab, n=1, cutoff=cutoff))


def canonicalize(toks: list[str], amap: dict[str, list[str]] | None) -> list[str]:
    """Apply food-aliases.json: replace a colloquial token with its canonical
    DB word(s); [] drops a non-food token; unmapped tokens pass through."""
    if not amap:
        return toks
    out: list[str] = []
    for t in toks:
        out.extend(amap[t]) if t in amap else out.append(t)
    return out


def match_food(desc: str, vocab: set[str], cutoff: float,
               amap: dict[str, list[str]] | None = None) -> dict:
    """A food 'covers' if EVERY meaningful word in it (after canonicalization) is
    present in the DB vocabulary. Token-level handles compound meals with no
    decomposition table."""
    toks = canonicalize(tokens(desc), amap)
    missing = [t for t in toks if not token_matches(t, vocab, cutoff)]
    return {
        "desc": desc,
        "covered": bool(toks) and not missing,
        "weak_tokens": missing,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--food", required=True, help="Kampa food_events CSV (userDescription col)")
    ap.add_argument("--db", action="append", required=True, metavar="LABEL=PATH",
                    help="repeatable; candidate DB name list")
    ap.add_argument("--cutoff", type=float, default=0.84,
                    help="fuzzy cutoff for a single food word (plural/typo tolerance)")
    ap.add_argument("--map", dest="mapfile", default=None,
                    help="food-aliases.json to apply before matching (shows the lift)")
    args = ap.parse_args()

    amap = None
    if args.mapfile:
        import json
        amap = {k: v for k, v in json.loads(Path(args.mapfile).read_text()).items()
                if not k.startswith("_")}
        print(f"Applying alias map: {len(amap)} entries from {args.mapfile}\n")

    food = pd.read_csv(args.food)
    if "userDescription" not in food.columns:
        sys.exit(f"--food CSV missing userDescription; has {list(food.columns)}")
    descs = sorted({d.strip() for d in food["userDescription"].dropna().astype(str) if d.strip()})
    print(f"Loaded {len(descs)} distinct food descriptions from {len(food)} events.\n")

    # union mode: combine vocabularies of all --db sources into one
    vocabs = {}
    for spec in args.db:
        label, _, path = spec.partition("=")
        vocabs[label] = db_vocabulary(Path(path))
    if len(vocabs) > 1:
        vocabs["UNION(all)"] = set().union(*vocabs.values())

    from collections import Counter
    for label, vocab in vocabs.items():
        rows = [match_food(d, vocab, args.cutoff, amap) for d in descs]
        covered = [r for r in rows if r["covered"]]
        rate = len(covered) / len(rows) if rows else 0.0
        print(f"=== {label}  ({len(vocab):,} food-words, fuzzy cutoff {args.cutoff}) ===")
        print(f"  COVERAGE: {len(covered)}/{len(rows)}  = {rate:.0%}")
        # which individual WORDS are the gap, ranked by how often they appear
        gap = Counter()
        for r in rows:
            gap.update(r["weak_tokens"])
        if gap:
            print(f"  missing food-words (count = # of your descriptions blocked by it):")
            for word, c in gap.most_common():
                print(f"      {c:>2}x  {word}")
        print()


if __name__ == "__main__":
    main()
