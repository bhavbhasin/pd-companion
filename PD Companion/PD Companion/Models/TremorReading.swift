import Foundation
import SwiftData

@Model
final class TremorReading {
    var timestamp: Date
    var tremorScore: Double
    var dyskinesiaScore: Double

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
