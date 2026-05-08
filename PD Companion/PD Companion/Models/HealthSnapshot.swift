import Foundation
import SwiftData

@Model
final class HealthSnapshot {
    var date: Date
    var sleepHours: Double?
    var hrvAverage: Double?
    var restingHeartRate: Double?
    var exerciseMinutes: Double?
    var mindfulnessMinutes: Double?
    var stepCount: Double?

    init(date: Date) {
        self.date = date
    }

    convenience init(from sample: HealthSample) {
        self.init(date: sample.date)
        self.sleepHours = sample.sleepHours
        self.hrvAverage = sample.hrvAverage
        self.restingHeartRate = sample.restingHeartRate
        self.exerciseMinutes = sample.exerciseMinutes
        self.mindfulnessMinutes = sample.mindfulnessMinutes
        self.stepCount = sample.stepCount
    }
}
