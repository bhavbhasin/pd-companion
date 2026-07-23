#!/usr/bin/env python3
"""
Build the on-device barcode corpus from USDA FoodData Central "Branded Foods".

Reduces the raw dataset (~2M products, ~40 nutrients each) to the minimum the
Kampa engine + UI need: GTIN -> {product name, 5 quantized macros}. Reports the
shippable size under several filter policies so the bundle-vs-ODR-vs-prune call
is made on measured numbers, not guesses.

Reference: docs/design/barcode-capture.md. Run offline; output is gitignored.

Usage:
    python3 build_barcode_corpus.py <dataset_dir> [--emit out.sqlite --policy us_active]
"""
import argparse
import csv
import os
import struct
import sys
import time

# FDC nutrient.csv `id` values for the 5 macros the engine consumes.
# Two sugar variants exist; prefer 2000 (Total Sugars, newer label data),
# fall back to 1063 (Sugars, Total).
NUT = {
    "protein": {1003},
    "fat": {1004},
    "sugar_primary": {2000},
    "sugar_fallback": {1063},
    "fiber": {1079},
    "caffeine": {1057},   # unit MG, not G
}
WANTED_NUTRIENT_IDS = {1003, 1004, 2000, 1063, 1079, 1057}

# Grams quantized to one byte (0..255g covers any realistic per-100g/serving
# value). Caffeine is mg -> cap at 255mg (a strong coffee is ~100-200mg).
def q(x):
    if x is None:
        return None
    v = int(round(x))
    return max(0, min(255, v))


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dataset_dir")
    ap.add_argument("--emit", metavar="PREFIX",
                    help="write the binary corpus: PREFIX-index.bin + PREFIX-names.bin")
    ap.add_argument("--policy", default="us_active_macros",
                    help="filter policy for --emit: all | us | active | us_active | us_active_macros")
    ap.add_argument("--compress-test", metavar="POLICY",
                    help="measure compressed names-blob + index size for POLICY")
    args = ap.parse_args()

    d = args.dataset_dir
    branded_csv = os.path.join(d, "branded_food.csv")
    food_csv = os.path.join(d, "food.csv")
    nutrient_csv = os.path.join(d, "food_nutrient.csv")
    for p in (branded_csv, food_csv, nutrient_csv):
        if not os.path.exists(p):
            sys.exit(f"missing {p}")

    csv.field_size_limit(1 << 24)  # ingredients fields can be long

    # --- Pass 1: names from food.csv (fdc_id -> description) ------------------
    log("Pass 1/3: reading food.csv (product names)")
    names = {}
    with open(food_csv, newline="", encoding="utf-8", errors="replace") as f:
        r = csv.DictReader(f)
        for row in r:
            names[row["fdc_id"]] = row["description"].strip()
    log(f"  names: {len(names):,}")

    # --- Pass 2: macros from food_nutrient.csv (the 1.4GB file) ---------------
    # Keep only our 5 nutrient ids. macros[fdc_id] = dict(nutrient_id -> amount)
    log("Pass 2/3: streaming food_nutrient.csv (macros only) - this is the slow one")
    macros = {}
    seen = 0
    with open(nutrient_csv, newline="", encoding="utf-8", errors="replace") as f:
        r = csv.reader(f)
        header = next(r)
        i_fdc = header.index("fdc_id")
        i_nut = header.index("nutrient_id")
        i_amt = header.index("amount")
        for row in r:
            seen += 1
            if seen % 20_000_000 == 0:
                log(f"    scanned {seen:,} nutrient rows")
            try:
                nid = int(row[i_nut])
            except (ValueError, IndexError):
                continue
            if nid not in WANTED_NUTRIENT_IDS:
                continue
            fdc = row[i_fdc]
            try:
                amt = float(row[i_amt])
            except (ValueError, IndexError):
                continue
            macros.setdefault(fdc, {})[nid] = amt
    log(f"  products with >=1 target macro: {len(macros):,} (scanned {seen:,} rows)")

    # --- Pass 3: join branded_food -> records, tally policies -----------------
    log("Pass 3/3: joining branded_food.csv")
    policies = {
        "all": 0, "us": 0, "active": 0, "us_active": 0, "us_active_macros": 0,
    }
    name_bytes = {k: 0 for k in policies}
    records = []  # kept only if --emit; else we just tally
    test_names = []  # kept only if --compress-test
    total = 0
    with open(branded_csv, newline="", encoding="utf-8", errors="replace") as f:
        r = csv.DictReader(f)
        for row in r:
            total += 1
            gtin = (row.get("gtin_upc") or "").strip()
            if not gtin:
                continue
            fdc = row["fdc_id"]
            m = macros.get(fdc, {})
            name = names.get(fdc, "").strip()
            if not name:
                # brand fields are a usable fallback name
                name = (row.get("brand_name") or row.get("brand_owner") or "").strip()
            is_us = (row.get("market_country") or "").strip() == "United States"
            is_active = not (row.get("discontinued_date") or "").strip()
            sugar = m.get(2000, m.get(1063))
            has_core = all(m.get(n) is not None for n in (1003, 1004)) or sugar is not None

            in_policy = {
                "all": True,
                "us": is_us,
                "active": is_active,
                "us_active": is_us and is_active,
                "us_active_macros": is_us and is_active and has_core,
            }
            for k, ok in in_policy.items():
                if ok:
                    policies[k] += 1
                    name_bytes[k] += len(name.encode("utf-8"))

            if args.compress_test and in_policy.get(args.compress_test):
                test_names.append(name)

            if args.emit and in_policy.get(args.policy):
                records.append((
                    gtin, name,
                    q(m.get(1003)), q(m.get(1004)), q(sugar),
                    q(m.get(1079)), q(m.get(1057)),
                ))
    log(f"  branded rows: {total:,} (with GTIN)")

    # --- Size projection per policy ------------------------------------------
    # Fixed per-record bytes: 8 (gtin int) + 5 (macros) = 13; name is measured.
    # SQLite overhead ~1.6x the packed payload in practice (page + index + row hdr).
    print("\n=== corpus size by policy ===")
    print(f"{'policy':<20}{'records':>12}{'avg name B':>12}{'packed MB':>12}{'~sqlite MB':>12}")
    for k in ("all", "us", "active", "us_active", "us_active_macros"):
        n = policies[k]
        avg = (name_bytes[k] / n) if n else 0
        packed = n * (13 + avg) / 1e6
        print(f"{k:<20}{n:>12,}{avg:>12.1f}{packed:>12.1f}{packed*1.6:>12.1f}")
    print()

    if args.compress_test:
        compress_test(args.compress_test, test_names)

    if args.emit:
        emit_binary(args.emit, records)


def compress_test(policy, names):
    import zlib
    import lzma
    n = len(names)
    blob = ("\n".join(names)).encode("utf-8")
    raw = len(blob)
    zl = len(zlib.compress(blob, 9))          # ~ conservative, near Apple LZFSE
    xz = len(lzma.compress(blob, preset=6))    # ~ high-ratio (zstd-high class)
    # Index: 8B gtin + 5B macros + 4B name offset = 17B/record, mmap'd binary.
    index_mb = n * 17 / 1e6
    print(f"\n=== compression test — policy '{policy}' ({n:,} records) ===")
    print(f"names raw:            {raw/1e6:8.1f} MB  (avg {raw/n:.1f} B)")
    print(f"names zlib(9):        {zl/1e6:8.1f} MB  ({raw/zl:.2f}x)   <- ~LZFSE floor")
    print(f"names lzma(6):        {xz/1e6:8.1f} MB  ({raw/xz:.2f}x)   <- best case")
    print(f"index (17B/rec):      {index_mb:8.1f} MB")
    print(f"TOTAL zlib+index:     {(zl/1e6 + index_mb):8.1f} MB")
    print(f"TOTAL lzma+index:     {(xz/1e6 + index_mb):8.1f} MB")
    print()


# --- Binary corpus format (see docs/design/barcode-capture.md) ---------------
# index.bin : "KBIX" | u16 ver | u16 chunk | u32 count | count × record
#             record = u64 gtin (LE, sorted asc) | u8 flags | 5× u8 macro
#             flags bit i set => macro i (protein,fat,sugar,fiber,caffeine) known.
#             "known" is distinct from a 0 value (sugar-free != sugar-unknown).
# names.bin : "KBNM" | u16 ver | u16 chunk | u32 nchunks | (nchunks+1)× u32 dir
#             | zlib chunks. chunk c holds names for records [c*chunk:(c+1)*chunk],
#             each name = u16 len + utf8. Record i's name = chunk i//chunk, item i%chunk.
CHUNK = 256

def emit_binary(prefix, records):
    import zlib
    # dedup by GTIN (keep last), parse to int, drop unusable keys
    by_gtin = {}
    for (gtin, name, p, fat, sug, fib, caf) in records:
        try:
            g = int(gtin)
        except (ValueError, TypeError):
            continue
        if g <= 0 or g.bit_length() > 64:
            continue
        by_gtin[g] = (name or "", p, fat, sug, fib, caf)
    gtins = sorted(by_gtin)
    n = len(gtins)
    log(f"Emitting {n:,} records (after GTIN dedup) -> {prefix}-index.bin / -names.bin")

    # index.bin
    idx = bytearray(b"KBIX" + struct.pack("<HHI", 1, CHUNK, n))
    for g in gtins:
        _, p, fat, sug, fib, caf = by_gtin[g]
        vals = [p, fat, sug, fib, caf]
        flags = 0
        packed = []
        for bit, v in enumerate(vals):
            if v is not None:
                flags |= (1 << bit)
                packed.append(v)
            else:
                packed.append(0)
        idx += struct.pack("<QB5B", g, flags, *packed)
    idx_path = f"{prefix}-index.bin"
    with open(idx_path, "wb") as f:
        f.write(idx)

    # names.bin
    nchunks = (n + CHUNK - 1) // CHUNK
    blobs = []
    for c in range(nchunks):
        buf = bytearray()
        for g in gtins[c * CHUNK:(c + 1) * CHUNK]:
            nm = by_gtin[g][0].encode("utf-8")[:65535]
            buf += struct.pack("<H", len(nm)) + nm
        blobs.append(zlib.compress(bytes(buf), 9))
    directory, off = [], 0
    for b in blobs:
        directory.append(off)
        off += len(b)
    directory.append(off)  # end sentinel
    names = bytearray(b"KBNM" + struct.pack("<HHI", 1, CHUNK, nchunks))
    names += b"".join(struct.pack("<I", o) for o in directory)
    names += b"".join(blobs)
    names_path = f"{prefix}-names.bin"
    with open(names_path, "wb") as f:
        f.write(names)

    im, nm_ = os.path.getsize(idx_path) / 1e6, os.path.getsize(names_path) / 1e6
    log(f"  index.bin {im:.1f} MB + names.bin {nm_:.1f} MB = {im + nm_:.1f} MB total")


if __name__ == "__main__":
    main()
