import Foundation

struct TremorSample: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let timestamp: Date          // = CMTremorResult.startDate (kept name for engine continuity)
    let tremorScore: Double
    let dyskinesiaScore: Double  // legacy merged score — left untouched for existing consumers

    // Full per-minute tremor distribution from CMTremorResult (each a fraction 0...1;
    // all six — including percentUnknown — sum to 1.0). Captured raw because Apple's
    // Movement Disorder API retains only a rolling ~7 days: if we store only the collapsed
    // `tremorScore` the distribution is unrecoverable, and duration metrics (time-in-tremor,
    // time-at-moderate+, "hours monitored" from percentUnknown) can never be derived after
    // the fact. Reduce at read, not at capture. `tremorScore` stays the denormalized,
    // duration-weighted reduction the engine reads (computed below, unchanged).
    var bucketEnd: Date = .distantPast   // = CMTremorResult.endDate (buckets are ~1 minute)
    var percentUnknown: Double = 0
    var percentNone: Double = 0
    var percentSlight: Double = 0
    var percentMild: Double = 0
    var percentModerate: Double = 0
    var percentStrong: Double = 0

    static func weightedScore(
        none: Float, slight: Float, mild: Float, moderate: Float, strong: Float
    ) -> Double {
        let total = none + slight + mild + moderate + strong
        guard total > 0 else { return 0 }
        return Double(
            (0 * none + 1 * slight + 2 * mild + 3 * moderate + 4 * strong) / total
        )
    }
}

extension TremorSample {
    // Decode-tolerant init: the watch and phone apps update independently on TestFlight,
    // so during a staggered update an older watch build can send JSON without the new
    // distribution keys. Treat them as absent (→ defaults) rather than throwing and
    // dropping the entire batch in PhoneConnectivityManager's decode. Living in an
    // extension preserves the synthesized memberwise initializer and Encodable conformance.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        tremorScore = try c.decode(Double.self, forKey: .tremorScore)
        dyskinesiaScore = try c.decode(Double.self, forKey: .dyskinesiaScore)
        bucketEnd = try c.decodeIfPresent(Date.self, forKey: .bucketEnd) ?? .distantPast
        percentUnknown = try c.decodeIfPresent(Double.self, forKey: .percentUnknown) ?? 0
        percentNone = try c.decodeIfPresent(Double.self, forKey: .percentNone) ?? 0
        percentSlight = try c.decodeIfPresent(Double.self, forKey: .percentSlight) ?? 0
        percentMild = try c.decodeIfPresent(Double.self, forKey: .percentMild) ?? 0
        percentModerate = try c.decodeIfPresent(Double.self, forKey: .percentModerate) ?? 0
        percentStrong = try c.decodeIfPresent(Double.self, forKey: .percentStrong) ?? 0
    }
}

// Raw dyskinesia capture — an independent per-minute stream, NOT merged onto tremor
// buckets. CMDyskineticSymptomResult gives percentUnlikely + percentLikely = 1.0 (no
// "unknown" state). We store only percentLikely raw (percentUnlikely = 1 - percentLikely).
// Kept separate from TremorSample so a dyskinesia minute with no matching tremor bucket
// is never dropped (the reduce-at-capture mistake this whole change exists to avoid).
struct DyskinesiaSample: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let startDate: Date          // = CMDyskineticSymptomResult.startDate
    let endDate: Date            // = CMDyskineticSymptomResult.endDate
    let percentLikely: Double    // raw fraction 0...1
}

struct HealthSample: Codable, Identifiable {
    var id: UUID = UUID()
    let date: Date
    var sleepHours: Double?
    var hrvAverage: Double?
    var restingHeartRate: Double?
    var exerciseMinutes: Double?
    var mindfulnessMinutes: Double?
    var stepCount: Double?
}

/// LZFSE (de)compression for WatchConnectivity payloads. Tremor/dyskinesia JSON is dominated
/// by repeated key names, which compress ~5-10×, keeping `applicationContext` under its
/// ~256KB cap and shrinking `transferUserInfo` well below the ~1MB that was failing to
/// deliver. Lives here so both the phone and watch targets share one implementation.
/// See docs/design/watch-sync-payload-options.md (Recommendation, step 2).
enum WCPayload {
    static func compress(_ data: Data) -> Data? {
        try? (data as NSData).compressed(using: .lzfse) as Data
    }
    static func decompress(_ data: Data) -> Data? {
        try? (data as NSData).decompressed(using: .lzfse) as Data
    }
}
