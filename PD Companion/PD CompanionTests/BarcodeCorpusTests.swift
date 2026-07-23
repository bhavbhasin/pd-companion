//
//  BarcodeCorpusTests.swift
//  PD CompanionTests
//
//  Exercises the on-device barcode reader end-to-end against the REAL bundled
//  corpus (barcode-index.bin / barcode-names.bin, generated from FDC Branded
//  2026-04-30 by scripts/food/build_barcode_corpus.py). Fixtures are pinned to
//  that dataset version — regenerating the corpus from a newer FDC release may
//  shift a value and require re-pinning. Requires the two .bin resources + this
//  file to be in the app / test targets.
//

import Foundation
import Testing
@testable import PD_Companion

struct BarcodeCorpusTests {

    private let corpus = BarcodeCorpus.shared

    @Test func corpusLoads() {
        #expect(corpus.available, "corpus .bin resources not bundled — add Resources/Food/*.bin to the target")
    }

    // GTIN 5487 — "POTATO CHIPS, SEA SALT": protein 7, fat 32, sugar 0 (known),
    // fiber 4, caffeine UNKNOWN (flags 0b1111). The macro decode + known-vs-zero.
    @Test func resolvesKnownProduct() throws {
        let p = try #require(corpus.product(forGTIN: 5487))
        #expect(p.name == "POTATO CHIPS, SEA SALT")
        #expect(p.protein == 7)
        #expect(p.fat == 32)
        #expect(p.sugar == 0)        // known and zero
        #expect(p.fiber == 4)
        #expect(p.caffeine == nil)   // not reported — must NOT read as 0
    }

    // Attributes for the chips: protein(7≥5), fat(32≥3), fiber(4≥3) present;
    // sugar(0<5) and unknown caffeine absent. Order = FoodAttribute.allCases.
    @Test func reducesToAttributes() throws {
        let p = try #require(corpus.product(forGTIN: 5487))
        #expect(corpus.attributes(p) == [.protein, .fiber, .fat])
    }

    // Leading-zero normalization: the corpus key is int 73430446151; a scanned
    // EAN-13 string "073430446151" must resolve to the same record.
    @Test func normalizesLeadingZeroScan() throws {
        #expect(BarcodeCorpus.normalize("073430446151") == 73430446151)
        let p = try #require(corpus.product(forScanned: "073430446151"))
        #expect(p.name.contains("SIMPLY BUBBLES"))
        // Water: protein/fat known and 0, rest unknown → no attributes.
        #expect(p.protein == 0)
        #expect(p.sugar == nil)
        #expect(corpus.attributes(p).isEmpty)
    }

    // GTIN 12000042713 — a caffeinated iced tea: sugar 5 (known), caffeine 2 (known),
    // fiber UNKNOWN. Attributes = caffeine + sugar.
    @Test func resolvesCaffeine() throws {
        let p = try #require(corpus.product(forGTIN: 12000042713))
        #expect(p.caffeine == 2)
        #expect(p.fiber == nil)
        #expect(corpus.attributes(p) == [.caffeine, .sugar])
    }

    // A barcode not in the corpus → nil (caller falls through to manual entry).
    @Test func missReturnsNil() {
        #expect(corpus.product(forGTIN: 999_999_999_999) == nil)
        #expect(corpus.product(forScanned: "999999999999") == nil)
    }

    // Non-numeric / empty input never crashes and never matches.
    @Test func junkInputIsSafe() {
        #expect(BarcodeCorpus.normalize("") == nil)
        #expect(BarcodeCorpus.normalize("abc") == nil)
        #expect(corpus.product(forScanned: "no-barcode-here") == nil)
    }
}
