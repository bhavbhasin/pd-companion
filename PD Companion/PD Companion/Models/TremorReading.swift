import Foundation
import SwiftData

@Model
final class TremorReading {
    // Defaults are required for CloudKit (NSPersistentCloudKitContainer):
    // every stored property must be optional or have a default value.
    var timestamp: Date = Date.distantPast
    var tremorScore: Double = 0
    var dyskinesiaScore: Double = 0

    // Raw per-minute tremor distribution (additive CloudKit fields; see TremorSample for
    // rationale). Defaulted so existing rows and old payloads remain valid. Old rows keep
    // bucketEnd == .distantPast (treat as "end unknown ≈ start + 60s" when reducing).
    var bucketEnd: Date = Date.distantPast
    var percentUnknown: Double = 0
    var percentNone: Double = 0
    var percentSlight: Double = 0
    var percentMild: Double = 0
    var percentModerate: Double = 0
    var percentStrong: Double = 0

    init(
        timestamp: Date,
        tremorScore: Double,
        dyskinesiaScore: Double,
        bucketEnd: Date = .distantPast,
        percentUnknown: Double = 0,
        percentNone: Double = 0,
        percentSlight: Double = 0,
        percentMild: Double = 0,
        percentModerate: Double = 0,
        percentStrong: Double = 0
    ) {
        self.timestamp = timestamp
        self.tremorScore = tremorScore
        self.dyskinesiaScore = dyskinesiaScore
        self.bucketEnd = bucketEnd
        self.percentUnknown = percentUnknown
        self.percentNone = percentNone
        self.percentSlight = percentSlight
        self.percentMild = percentMild
        self.percentModerate = percentModerate
        self.percentStrong = percentStrong
    }

    convenience init(from sample: TremorSample) {
        self.init(
            timestamp: sample.timestamp,
            tremorScore: sample.tremorScore,
            dyskinesiaScore: sample.dyskinesiaScore,
            bucketEnd: sample.bucketEnd,
            percentUnknown: sample.percentUnknown,
            percentNone: sample.percentNone,
            percentSlight: sample.percentSlight,
            percentMild: sample.percentMild,
            percentModerate: sample.percentModerate,
            percentStrong: sample.percentStrong
        )
    }
}
