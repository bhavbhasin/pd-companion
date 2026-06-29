import Foundation

/// On-device food → `[FoodAttribute]` classifier. Deterministic and fully offline:
/// it loads a bundled USDA-derived food table (`FoodDB.json`) plus a small
/// hand-maintained vocabulary map (`food-aliases.json`) and resolves a free-text
/// food description ("rajma rice with chai") into the coarse attribute set the
/// correlation engine consumes (protein / fat / sugar / fiber / caffeine).
///
/// This replaces `FoodAttribute.detect(in:)`, the old hardcoded keyword list.
///
/// It is a faithful port of the validated Python reference in
/// `scripts/food/classify_food.py`. **Keep the two in lockstep** — the design
/// (food-NAME-level matching, representative-food selection, qualifier dropping,
/// multi-word alias keys) and the rationale live in `docs/food-classification.md`.
/// Changes here should be mirrored there and re-validated with the parity check.
///
/// Resources are loaded once, lazily, and matched in memory (the matching is a
/// token-subset scan over every food, not a database query — so JSON + an array
/// is all we need; no SQLite at runtime).
nonisolated final class FoodAttributeClassifier: Sendable {

    static let shared = FoodAttributeClassifier()

    // MARK: - Loaded data

    private struct FoodRecord {
        let name: String
        let tokens: [String]
        let tokenSet: Set<String>
        let attrs: [FoodAttribute]
        let generic: Bool          // USDA's generic "NFS" / "NS as to…" representative entry
    }

    /// Alias entries, each a tokenized key → its replacement phrase queries.
    /// Sorted longest-key-first so a multi-word key ("black eyed peas") wins over
    /// a single token ("peas") during the greedy scan.
    private struct Alias { let key: [String]; let values: [String] }

    private let foods: [FoodRecord]
    private let aliases: [Alias]
    /// Inverted index: food-name token → indices of foods whose name contains it.
    /// Turns matching from an O(all foods) scan into posting-list lookups + a small
    /// intersection, so a classify is sub-millisecond instead of ~0.6s.
    private let postings: [String: [Int]]
    /// Unique food tokens bucketed by character length, for the fuzzy (plural/typo)
    /// fallback — only tokens within ±2 length can clear the similarity cutoff, so
    /// we never Levenshtein against the whole vocabulary.
    private let vocabByLength: [Int: [String]]

    // MARK: - Vocabulary (mirrors scripts/food/spike_food_db.py + classify_food.py)

    /// Words that carry no food identity — dropped before matching.
    private static let stopwords: Set<String> = [
        "with", "and", "a", "an", "of", "the", "plus", "some", "my", "in", "on",
        "for", "to", "had", "ate", "drank", "cup", "cups", "glass", "bowl", "plate",
        "piece", "pieces", "slice", "slices", "small", "medium", "large", "half",
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    ]

    /// Words that only ever MODIFY a food, never name one. Dropped when they appear
    /// as a standalone unmapped token, so "black" can't pull in black tea (caffeine)
    /// from "black-eyed peas". They still ride along inside a mapped phrase.
    private static let qualifiers: Set<String> = [
        "black", "white", "red", "green", "yellow", "brown", "purple",
        "hot", "cold", "iced", "warm", "raw", "fried", "roasted", "baked",
        "boiled", "steamed", "grilled", "fresh", "dried", "ground", "whole",
    ]

    /// Processed/derived FORM tokens in a food NAME. For a whole food the raw/plain
    /// entry is more representative than a canned/juiced/honeyed one, so foods
    /// carrying these are deprioritized in selection.
    private static let processed: Set<String> = [
        "canned", "juice", "dried", "frozen", "sweetened", "syrup", "candied",
        "jam", "jelly", "instant", "bottled", "powder", "concentrate", "honey",
    ]

    /// A query token matches a food token if it's within this similarity (handles
    /// plurals "oranges"→"orange" and typos). Mirrors the Python difflib cutoff.
    private static let fuzzyCutoff = 0.84

    // MARK: - Init / loading

    private init() {
        let loaded = Self.loadFoods()
        self.foods = loaded
        self.aliases = Self.loadAliases()
        var postings: [String: [Int]] = [:]
        for (i, f) in loaded.enumerated() {
            for t in f.tokenSet { postings[t, default: []].append(i) }
        }
        self.postings = postings
        self.vocabByLength = Dictionary(grouping: postings.keys, by: { $0.count })
        if loaded.isEmpty {
            // The Resources/Food files aren't in the app bundle yet (Xcode target
            // membership). classify() degrades to [] until they are.
            assertionFailure("FoodDB.json not found in bundle — add Resources/Food to the target.")
        }
    }

    private static func bundleURL(_ name: String, _ ext: String) -> URL? {
        // Works whether the folder was added as a reference ("Food/…") or a group (flat).
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Food")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    private static func loadFoods() -> [FoodRecord] {
        struct RawFood: Decodable { let name: String; let attrs: [FoodAttribute] }
        struct RawDB: Decodable { let foods: [RawFood] }
        guard let url = bundleURL("FoodDB", "json"),
              let data = try? Data(contentsOf: url),
              let db = try? JSONDecoder().decode(RawDB.self, from: data) else { return [] }
        return db.foods.compactMap { raw in
            let toks = tokens(raw.name)
            guard !toks.isEmpty else { return nil }
            return FoodRecord(
                name: raw.name,
                tokens: toks,
                tokenSet: Set(toks),
                attrs: raw.attrs,
                generic: toks.contains("nfs") || toks.contains("ns")
            )
        }
    }

    private static func loadAliases() -> [Alias] {
        guard let url = bundleURL("food-aliases", "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var out: [Alias] = []
        for (key, value) in obj {
            if key.hasPrefix("_") { continue }            // _comment etc.
            guard let values = value as? [String] else { continue }
            let keyTokens = tokens(key)
            guard !keyTokens.isEmpty else { continue }
            out.append(Alias(key: keyTokens, values: values))
        }
        // longest key first so "black eyed peas" beats "peas"
        return out.sorted { $0.key.count > $1.key.count }
    }

    // MARK: - Text processing

    private static func norm(_ text: String) -> String {
        let lowered = text.lowercased()
        let scalars = lowered.unicodeScalars.map { s -> Character in
            (CharacterSet.alphanumerics.contains(s) || s == " ") ? Character(s) : " "
        }
        return String(scalars)
    }

    /// Lowercase → strip punctuation → drop stopwords and pure-number tokens.
    private static func tokens(_ text: String) -> [String] {
        norm(text).split(separator: " ").map(String.init).filter { tok in
            !tok.isEmpty && !stopwords.contains(tok) && Int(tok) == nil
        }
    }

    // MARK: - Matching

    /// A free-text description → its list of canonical food-PHRASE queries. Greedy
    /// multi-word alias keys match first, then single-token keys; unmapped qualifier
    /// words are dropped, other unmapped tokens pass through as their own query.
    private func expandQueries(_ description: String) -> [String] {
        let toks = Self.tokens(description)
        var out: [String] = []
        var i = 0
        while i < toks.count {
            var matched = false
            for alias in aliases {     // already longest-first
                let n = alias.key.count
                if i + n <= toks.count && Array(toks[i..<i + n]) == alias.key {
                    out.append(contentsOf: alias.values)
                    i += n
                    matched = true
                    break
                }
            }
            if matched { continue }
            let t = toks[i]
            if !Self.qualifiers.contains(t) { out.append(t) }
            i += 1
        }
        return out
    }

    /// Food indices whose name contains a token matching `qt` — exactly (posting
    /// lookup) or fuzzily (plural/typo, only against same-length-ish vocabulary).
    /// Equivalent to the old per-food `tokenSet.contains || fuzzyContains`, but via
    /// the index instead of a full scan.
    private func candidateIndices(for qt: String) -> Set<Int> {
        var result = Set(postings[qt] ?? [])
        let len = qt.count
        for l in max(1, len - 2)...(len + 2) {
            guard let bucket = vocabByLength[l] else { continue }
            for vt in bucket where vt != qt && Self.similarity(qt, vt) >= Self.fuzzyCutoff {
                if let idx = postings[vt] { result.formUnion(idx) }
            }
        }
        return result
    }

    /// The representative DB food for a canonical phrase. A food is a candidate if
    /// every query token matches one of its name tokens (exact or fuzzy) — computed
    /// as the intersection of the per-token candidate sets. Among candidates prefer:
    /// the food LED by the queried word, then a raw/plain form over a processed one,
    /// then the generic NFS/NS entry, then fewest extra tokens, then the shorter name.
    private func bestFood(_ query: String) -> FoodRecord? {
        let qtoks = Self.tokens(query)
        guard !qtoks.isEmpty else { return nil }
        let qset = Set(qtoks)

        var candidates: Set<Int>?
        for qt in qtoks {
            let s = candidateIndices(for: qt)
            candidates = candidates.map { $0.intersection(s) } ?? s
            if candidates!.isEmpty { return nil }
        }
        guard let idx = candidates, !idx.isEmpty else { return nil }

        return idx.map { foods[$0] }.min { a, b in
            Self.rank(a, qset).lexicographicallyPrecedes(Self.rank(b, qset))
        }
    }

    /// Lower is better. Lexicographic over the five selection criteria.
    private static func rank(_ f: FoodRecord, _ qset: Set<String>) -> [Int] {
        [
            (f.tokens.first.map { qset.contains($0) } ?? false) ? 0 : 1,  // led by queried word
            f.tokenSet.isDisjoint(with: processed) ? 0 : 1,               // raw/plain over processed
            f.generic ? 0 : 1,                                            // generic NFS/NS entry
            f.tokens.count - qset.count,                                  // fewest extra tokens
            f.name.count,                                                 // plainer (shorter) name
        ]
    }

    /// Similarity in [0, 1]. Cheap plural shortcut first, then a Levenshtein-based
    /// ratio. (Approximates Python's difflib for the plural/typo cases that arise
    /// here; the parity check against classify_food.py is the source of truth.)
    private static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if a.count >= 4 && b.count >= 4 {
            if a.hasPrefix(b) || b.hasPrefix(a) {  // orange / oranges, tomato / tomatoes
                let shorter = Double(min(a.count, b.count))
                let longer = Double(max(a.count, b.count))
                if longer - shorter <= 2 { return shorter / longer >= fuzzyCutoff ? 1 : shorter / longer }
            }
        }
        let dist = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        return maxLen == 0 ? 1 : 1 - Double(dist) / Double(maxLen)
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var curr = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            curr[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[t.count]
    }

    // MARK: - Public API

    /// Classify a free-text food description into its coarse attribute set.
    /// Returns attributes in `FoodAttribute.allCases` order for stability. Empty
    /// input — or missing bundled data — yields `[]` (save is never blocked on this).
    func classify(_ description: String?) -> [FoodAttribute] {
        guard let description, !description.isEmpty, !foods.isEmpty else { return [] }
        var found = Set<FoodAttribute>()
        for query in expandQueries(description) {
            if let food = bestFood(query) { found.formUnion(food.attrs) }
        }
        return FoodAttribute.allCases.filter { found.contains($0) }
    }
}
