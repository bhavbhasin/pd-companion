import Foundation
import HealthKit

struct SleepBreakdown: Equatable {
    var totalAsleepHours: Double
    var deepHours: Double
    var remHours: Double
    var coreHours: Double
    var awakeMinutes: Double
    var interruptions: Int
    var bedtime: Date?
    var wakeTime: Date?
    var stages: [SleepStageSegment]

    static let empty = SleepBreakdown(
        totalAsleepHours: 0, deepHours: 0, remHours: 0, coreHours: 0,
        awakeMinutes: 0, interruptions: 0, bedtime: nil, wakeTime: nil,
        stages: []
    )

    var hasData: Bool { totalAsleepHours > 0 || awakeMinutes > 0 }
}

enum SleepStage: String, Equatable, CaseIterable {
    case awake, rem, core, deep

    var displayName: String {
        switch self {
        case .awake: return "Awake"
        case .rem:   return "REM"
        case .core:  return "Core"
        case .deep:  return "Deep"
        }
    }

    var yBand: Int {
        switch self {
        case .awake: return 4
        case .rem:   return 3
        case .core:  return 2
        case .deep:  return 1
        }
    }
}

struct SleepStageSegment: Identifiable, Equatable {
    let id: UUID
    let stage: SleepStage
    let start: Date
    let end: Date

    init(stage: SleepStage, start: Date, end: Date) {
        self.id = UUID()
        self.stage = stage
        self.start = start
        self.end = end
    }
}

enum DayEvent: Identifiable {
    case medication(id: UUID, time: Date, name: String?)
    case workout(id: UUID, start: Date, duration: TimeInterval, type: HKWorkoutActivityType)
    case mindfulness(id: UUID, start: Date, duration: TimeInterval)
    case food(id: UUID, time: Date, type: FoodType, attributes: [FoodAttribute])

    var id: UUID {
        switch self {
        case .medication(let id, _, _):    return id
        case .workout(let id, _, _, _):    return id
        case .mindfulness(let id, _, _):   return id
        case .food(let id, _, _, _):       return id
        }
    }

    var time: Date {
        switch self {
        case .medication(_, let time, _):  return time
        case .workout(_, let start, _, _): return start
        case .mindfulness(_, let start, _): return start
        case .food(_, let time, _, _):     return time
        }
    }

    var iconName: String {
        switch self {
        case .medication:                  return "pill.fill"
        case .mindfulness:                 return "brain.head.profile"
        case .food(_, _, let type, _):     return type.symbolName
        case .workout(_, _, _, let type):
            switch type {
            case .taiChi, .yoga, .pilates, .mindAndBody, .flexibility:
                return "figure.mind.and.body"
            case .pickleball, .tennis, .tableTennis: return "figure.tennis"
            case .running:                 return "figure.run"
            case .walking, .hiking:        return "figure.walk"
            case .cycling:                 return "figure.outdoor.cycle"
            case .swimming:                return "figure.pool.swim"
            case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining:
                return "figure.strengthtraining.traditional"
            case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
            case .boxing, .martialArts:    return "figure.boxing"
            case .dance:                   return "figure.dance"
            default:                       return "figure.run"
            }
        }
    }

    var iconColor: String {
        switch self {
        case .medication:              return "pink"
        case .mindfulness:             return "cyan"
        case .workout:                 return "green"
        case .food(_, _, let type, _): return type.timelineColor
        }
    }

    var label: String {
        switch self {
        case .medication(_, _, let name):     return name ?? "Dose"
        case .workout(_, _, _, let type):     return type.displayName
        case .mindfulness:                    return "Mindfulness"
        case .food(_, _, let type, _):        return type.displayName
        }
    }
}
