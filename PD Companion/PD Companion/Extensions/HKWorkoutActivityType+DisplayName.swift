import HealthKit

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .taiChi: return "Tai Chi"
        case .pickleball: return "Pickleball"
        case .tennis: return "Tennis"
        case .tableTennis: return "Table Tennis"
        case .running: return "Running"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .functionalStrengthTraining: return "Strength"
        case .traditionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining: return "Core"
        case .flexibility: return "Flexibility"
        case .mindAndBody: return "Mind & Body"
        case .dance: return "Dance"
        case .boxing: return "Boxing"
        case .martialArts: return "Martial Arts"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairs: return "Stairs"
        case .stepTraining: return "Step Training"
        case .crossTraining: return "Cross Training"
        case .other: return "Workout"
        default: return "Workout"
        }
    }
}
