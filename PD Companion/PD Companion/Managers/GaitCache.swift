import Foundation

// Local, NON-synced disk cache for gait samples. The Insights load reduces ~12 years of
// raw HealthKit gait samples to monthly medians; querying all of that from HealthKit on
// every open cost ~2.2s. Past samples never change, so we persist what we've fetched and
// query HealthKit only for the delta since the last fetch.
//
// Deliberately NOT CloudKit: gait medians are re-derivable, device-specific data — a cache,
// not a system of record — so syncing them buys nothing and would add schema/migration risk.
// A plain JSON file in Caches (the OS may evict it; a miss just triggers one full refetch).
//
// Correctness note on source exclusion: `fetchGaitSeries` filters foreign HealthKit sources
// at fetch time, and `GaitSample` doesn't retain the source name. So the cache is KEYED on
// the excluded-sources signature — if it changes, the cache is ignored and rebuilt, keeping
// exclusions correct without per-sample source tracking. (Exclusions change rarely, from
// Settings, so the occasional full refetch is cheap.)
//
// Known limitation: a backfilled HISTORICAL sample (old startDate, synced late — e.g. a new
// device importing years of data) sits before the watermark and won't be picked up until a
// full rebuild (exclusion change or cache eviction). Harmless for a monthly-median trend.
nonisolated enum GaitCache {

    struct MetricCache: Codable, Sendable {
        var watermark: Date          // fetch instant of the last query; the next delta starts here
        var samples: [GaitSample]    // already source-filtered for `excludedSignature`
    }

    struct Payload: Codable, Sendable {
        var excludedSignature: String
        var metrics: [String: MetricCache]   // keyed by GaitMetric.rawValue
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("gait-cache.json")
    }

    static func signature(_ excluded: Set<String>) -> String {
        excluded.sorted().joined(separator: "\u{1}")
    }

    static func load() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func save(_ payload: Payload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
