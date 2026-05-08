import Foundation

struct TremorSample: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let timestamp: Date
    let tremorScore: Double
    let dyskinesiaScore: Double

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
