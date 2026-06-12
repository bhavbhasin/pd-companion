import Foundation
import SwiftData

@Model
final class TremorReading {
    // Defaults are required for CloudKit (NSPersistentCloudKitContainer):
    // every stored property must be optional or have a default value.
    var timestamp: Date = Date.distantPast
    var tremorScore: Double = 0
    var dyskinesiaScore: Double = 0

    init(timestamp: Date, tremorScore: Double, dyskinesiaScore: Double) {
        self.timestamp = timestamp
        self.tremorScore = tremorScore
        self.dyskinesiaScore = dyskinesiaScore
    }

    convenience init(from sample: TremorSample) {
        self.init(
            timestamp: sample.timestamp,
            tremorScore: sample.tremorScore,
            dyskinesiaScore: sample.dyskinesiaScore
        )
    }
}
