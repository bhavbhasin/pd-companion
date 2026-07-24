import Foundation

// MARK: - On-disk cache of reduced sleep nights
//
// Rebuilding the sleep history from HealthKit is expensive and gets more so every night: measured
// at 615ms of query + 666ms of reduction over 55,367 samples / 2,188 nights, paid on every cold
// launch because the in-memory cache dies with the process. But a night that has passed never
// changes, so almost all of that work is re-derivation of a settled answer.
//
// This stores the reduced nights — a few tiny fields each, not the raw samples — so a launch reads
// them back and queries HealthKit only for the tail. See `HealthKitManager.loadSleepHistory`.
//
// The cache records the source-exclusion set it was built under. Change which sources count and
// the stored nights are wrong, so the payload is discarded and rebuilt rather than silently reused.

enum SleepHistoryStore {

    /// Bump when a change makes previously-stored nights untrustworthy — the cache is then thrown
    /// away and rebuilt from HealthKit rather than carried forward. v2: v1 wrote clipped nights at
    /// the incremental window's boundary, so any v1 file may hold a corrupted settled night.
    private static let version = 2

    private struct Payload: Codable {
        var version: Int = 1
        let excludedSources: [String]
        let nights: [NightSleep]
    }

    private static var url: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
        else { return nil }
        return dir.appendingPathComponent("sleep-history.json")
    }

    /// Cached nights, ascending — or nil when there's no usable cache (absent, unreadable, or built
    /// under a different source filter), which the caller treats as "rebuild from scratch".
    static func load(excluded: Set<String>) -> [NightSleep]? {
        guard let url, let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == version,
              Set(payload.excludedSources) == excluded
        else { return nil }
        return payload.nights
    }

    static func save(_ nights: [NightSleep], excluded: Set<String>) {
        guard let url else { return }
        let payload = Payload(version: version, excludedSources: Array(excluded), nights: nights)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
