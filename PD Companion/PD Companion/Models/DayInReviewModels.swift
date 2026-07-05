import Foundation
import HealthKit
import SwiftUI

extension Color {
    /// App-wide dyskinesia accent. Orange — the colorblind-safe complement to tremor blue (its
    /// chart-mate on the timeline); teal read too close to blue and the two lines blurred
    /// together. Clear of glucose (pink), HRV (purple), and the event glyphs (med red, workout
    /// green, food brown). Change here to restyle dyskinesia everywhere.
    static let dyskinesia = Color.orange
}

struct HRVSample: Equatable {
    let timestamp: Date
    let value: Double   // SDNN, milliseconds
}

/// One blood-glucose reading (mg/dL at a time) from HealthKit — brand-agnostic: any CGM
/// (Lingo/Stelo/Libre…) OR a finger-prick/manual entry the user adds to Apple Health.
/// Display-only for now — step 1 of the CGM slice is "confirm data lands, observe by eye";
/// no engine correlation yet. `Sendable` so the fetch can run off the main thread. `source`
/// is the HealthKit source name, kept for the panel caption and future dedup.
struct GlucoseSample: Sendable, Equatable {
    let date: Date
    let value: Double   // mg/dL
    let source: String
}

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

nonisolated enum SleepStage: String, Equatable, CaseIterable {
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

nonisolated struct SleepStageSegment: Identifiable, Equatable {
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
    // isEditable: true only when Kampa itself saved this mindful session. HealthKit
    // only lets an app delete samples it authored, so sessions from Apple's
    // Mindfulness app (or any other source) are read-only here and must be deleted
    // in the Health app.
    case mindfulness(id: UUID, start: Date, duration: TimeInterval, isEditable: Bool)
    case food(id: UUID, time: Date, userDescription: String, attributes: [FoodAttribute])
    // A logged GI symptom (constipation/nausea/…) at a point in time. isEditable is true
    // only when Kampa authored the HealthKit sample (same delete rule as mindfulness).
    case giSymptom(id: UUID, time: Date, symptom: GISymptom, severity: GISeverity, isEditable: Bool)

    var id: UUID {
        switch self {
        case .medication(let id, _, _):     return id
        case .workout(let id, _, _, _):     return id
        case .mindfulness(let id, _, _, _): return id
        case .food(let id, _, _, _):        return id
        case .giSymptom(let id, _, _, _, _): return id
        }
    }

    var time: Date {
        switch self {
        case .medication(_, let time, _):      return time
        case .workout(_, let start, _, _):     return start
        case .mindfulness(_, let start, _, _): return start
        case .food(_, let time, _, _):         return time
        case .giSymptom(_, let time, _, _, _): return time
        }
    }

    var iconName: String {
        switch self {
        case .medication:                  return "pill.fill"
        case .mindfulness:                 return "figure.mind.and.body"
        case .food:                        return "fork.knife"
        case .giSymptom:                   return GISymptom.timelineSymbol
        case .workout(_, _, _, let type):
            switch type {
            case .yoga:                    return "figure.yoga"
            case .taiChi, .mindAndBody:    return "figure.mind.and.body"
            case .pilates:                 return "figure.pilates"
            case .flexibility:             return "figure.flexibility"
            case .pickleball, .tennis, .tableTennis: return "figure.tennis"
            case .running:                 return "figure.run"
            case .walking, .hiking:        return "figure.walk"
            case .cycling:                 return "figure.outdoor.cycle"
            case .swimming:                return "figure.pool.swim"
            case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining:
                return "figure.strengthtraining.traditional"
            case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
            case .boxing, .martialArts:    return "figure.boxing"
            case .dance, .socialDance, .cardioDance: return "figure.dance"
            default:                       return "figure.run"
            }
        }
    }

    var iconColor: Color {
        switch self {
        case .medication:  return .red
        case .mindfulness: return .cyan
        case .workout:     return .green
        case .food:        return .brown
        case .giSymptom:   return GISymptom.tint
        }
    }

    var label: String {
        switch self {
        case .medication(_, _, let name):      return name ?? "Dose"
        case .workout(_, _, _, let type):      return type.displayName
        case .mindfulness:                     return "Mindfulness"
        case .food(_, _, let desc, _):
            return desc.isEmpty ? "Food" : String(desc.prefix(40))
        case .giSymptom(_, _, let symptom, let severity, _):
            return severity == .present ? symptom.displayName
                                        : "\(symptom.displayName) · \(severity.displayName)"
        }
    }
}

// Needed for .sheet(item:)
extension DayEvent: Equatable {
    static func == (lhs: DayEvent, rhs: DayEvent) -> Bool {
        lhs.id == rhs.id
    }
}
