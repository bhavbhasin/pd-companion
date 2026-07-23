# Packaged-food capture — barcode + label OCR

**Status:** Design (not started). Logged Jul 22 2026.
**Purpose:** Turn a packaged product (protein bar, snack) into the engine's coarse attributes without typing - the daily annoyance the free-text classifier can't fix, since packaged/branded items aren't in the USDA whole-food table.

## The reframe (load-bearing)

Barcode and label-photo are NOT two features. They are a **fallback chain** for one job - "package → attributes":

1. **Barcode** → on-device product corpus lookup. Deterministic, fast, covers the majority. Primary path.
2. **Nutrition-panel photo (OCR)** → fallback when the barcode isn't in the corpus (imported/bulk/no-barcode).
3. **Manual / voice** → final fallback (already exists).

OCR earns its complexity only for the misses - not as a co-equal path. Building both as parallel features doubles the work for a case barcode already mostly covers.

**Photograph the Nutrition Facts panel, not the ingredients list.** The panel is a standardized FDA format carrying the exact macros the engine wants (protein/fat/sugar/fiber, grams); reliably parseable. The ingredients list is free text, messier, and mostly redundant. The one thing the panel misses that the engine cares about is **caffeine** (only in the ingredients list) → a Phase-3 keyword scan, not the main OCR target.

## Architecture

**Single reduction seam.** Both the corpus (grams) and OCR (grams) feed one shared rule: grams → the engine's presence flags (protein/fat/sugar/fiber/caffeine) via thresholds. The engine consumes presence, so v1 reduces to presence - no engine refactor. (Quantitative attributes = a future, separate engine change.)

### Phase 1 — Barcode → on-device corpus (self-contained; the real win)
- **Capture:** `VisionKit` `DataScannerViewController` - live scan, on-device, auto-captures when the code is in frame (no precise shutter tap → tremor-friendly).
- **Corpus:** bundle USDA Branded (~400-500k products - VERIFY count) as an indexed on-disk store (SQLite / indexed binary), keyed by barcode GTIN. Exact-match, sub-ms, ~0 memory if mmap'd. ~40 MB; On-Demand Resources removes it from the initial download. Kept SEPARATE from the in-memory 5,901-food fuzzy-match table (name/voice path) - only the camera path touches the corpus.
- **Fall-through:** unknown barcode → existing manual/voice entry. Never a dead end.
- **Wire-in:** create a `FoodEvent` through the existing pipeline (reuse, don't fork).

### Phase 2 — Nutrition-panel OCR (fallback for barcode misses)
- **OCR:** `Vision` `VNRecognizeTextRequest` - on-device, free.
- **Parse:** standardized panel → macros → same reduction seam.
- **"AI" parsing, done right:** for robust parsing of messy OCR, **Apple Foundation Models** (iOS 26 on-device LLM) - NOT a cloud API. Hardware-gated (A17 Pro+; floor is iPhone 11) → pair with a **deterministic regex parser as the universal fallback**. Same FM-with-fallback pattern chosen for voice narration.

### Phase 3 — ingredients keyword scan (optional, lowest priority)
Only to catch caffeine and similar things the macro panel misses.

## Privacy (non-negotiable)
All on-device: Vision/VisionKit + bundled corpus + FM. **No per-scan network call** - a live lookup would leak what you ate and when, and would spend the "no networking code in the app target, enforced by absence" property the DesignReview calls the strongest privacy claim. A bulk corpus download leaks nothing about diet. **Do not reach for Haiku / any API here** - it breaks enforcement-by-absence for a convenience feature. This is a one-way door; don't spend it on barcode.

## Gates before shipping
- **Verify** the USDA Branded product count + record size (sizing must be measured, not guessed - a `FoodDB.json` record is ~79 B).
- **License:** USDA Branded = US-gov public domain, clean to embed. Open Food Facts = ODbL (attribution + share-alike) - needs a real read before use as any fallback source; not an assumption.
- **Coverage:** US-centric; the NorthAfrican-6% lesson repeats for imported packaged goods. OCR is the escape hatch for those - expect it, don't rediscover it.

## Corpus generation — `scripts/food/build_barcode_corpus.py`

**Storage boundary (load-bearing):** the corpus is reference data - bundle / On-Demand Resources only, **never** in the CloudKit sync path. Same class as `FoodDB.json` (rides in the app bundle, not iCloud). Only the resulting FoodEvent syncs. A 40 MB corpus multiplied across every user's iCloud would be a storage/sync disaster.

**Size strategy = build-time reduction.** Ship only what the engine + UI need, not raw USDA Branded. Per record:
- **GTIN** - 8 B integer key.
- **5 macros** (protein/fat/sugar/fiber/caffeine) quantized to 1 B grams each = 5 B. Drop the other ~40 USDA nutrients. (Grams, not presence flags - keeps quantitative attributes open later, still tiny.)
- **Product name** - the size driver, ~30-35 B.

~53 B/record (name = ~41 B of it). Name dominates → the only lever that matters is **compressing the names blob**; filters and brand-dedup are duds (see MEASURED below).

**MEASURED (FDC Branded 2026-04-30, `build_barcode_corpus.py`):**
- **Count: 1,999,950 products** (~4× the old 400-500k guess). ~1.87M have usable macros.
- **Filters are duds:** the set is essentially all-US, all-active - US filter drops 13k, discontinued drops 4k. Dropping no-macro records is the only real cut (2.0M → 1.87M).
- **Naive SQLite = ~160 MB** (uncompressed names + page overhead) - NOT shippable.
- **Names compress hard** (repetitive brands/units): 76.8 MB raw → **19.7 MB zlib** (3.9×) / 10.1 MB lzma (7.6×).
- **Realistic on-device: ~42-52 MB** = 32 MB binary index (8 B gtin + 5 B macros + 4 B name offset) + 10-20 MB compressed names.

**Format consequence:** can't be naive SQLite. Use a **binary gtin index + chunk-compressed names blob** (mmap, binary-search, decompress one chunk per scan) → keeps BOTH download and on-disk ~50 MB. Alternative (ship-compressed → inflate to SQLite on first launch) is simpler but balloons on-disk back to ~160 MB. Prefer the binary index since on-phone footprint matters, not just download.

**Verdict: viable.** ~50 MB via ODR = zero bytes for non-scanning users, one-time ~50 MB pull for scanners. Barcode-with-corpus stays Phase 1; OCR stays Phase 2.

**Script steps:**
1. **Acquire + measure** - FDC "Branded Foods" bulk dataset; report real count + raw size (closes the verify-count gate).
2. **Extract** - per product: `gtinUpc`, brand + description, the 5 target nutrients only.
3. **Reduce** - nutrients → quantized grams (1 B each).
4. **Clean** - dedup GTINs (keep latest revision), drop no-GTIN / no-usable-macro records, normalize names, strip serving noise.
5. **Emit** - indexed SQLite keyed on GTIN + optional brand-string table.
6. **Report go/no-go** - final store size, per-record byte breakdown (name vs nutrition vs key), % records with complete macros.
7. **Verify** - scan a handful of real products (protein bars), confirm each resolves.

**Routing:** deliberate/verified session (not Fable) - output feeds a launch-affecting size decision, numbers must be trustworthy.

## Effort read
Phase 1 is bounded but real: camera permission + VisionKit UI, a corpus-generation script (USDA Branded → indexed store, the load-bearing piece), the reduction rule, `LogEntrySheet` wiring. Phase 1 alone removes the protein-bar annoyance and is worth doing standalone. Phase 2 is additive - defer until barcode coverage proves insufficient in practice.

## Related
Supersedes the barcode bullet in BACKLOG.md. Coverage/alias work (the "sushi" gap) is a separate track - see `analysis/food-coverage-audit/` and the food-classification entry. Marketing angle tracked in `marketing/linkedin/README.md`.
