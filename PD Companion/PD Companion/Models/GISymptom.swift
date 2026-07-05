import HealthKit
import SwiftUI

/// The curated GI / gastroparesis symptom set Kampa logs — the gut-motility levers that
/// gate levodopa absorption. Each maps to a HealthKit symptom category (severity-scaled),
/// so a log is an `HKCategorySample` that Apple Health *and* the correlation engine both
/// read (the close-loop pattern, like mindfulness). We log the *problem*; a normal bowel
/// movement is the silent baseline — HealthKit has no type for it and it adds nothing to
/// the absorption correlation.
nonisolated enum GISymptom: String, CaseIterable, Identifiable, Sendable {
    case constipation, bloating, nausea, diarrhea, cramps, heartburn

    var id: String { rawValue }

    var categoryIdentifier: HKCategoryTypeIdentifier {
        switch self {
        case .constipation: .constipation
        case .bloating:     .bloating
        case .nausea:       .nausea
        case .diarrhea:     .diarrhea
        case .cramps:       .abdominalCramps
        case .heartburn:    .heartburn
        }
    }

    var categoryType: HKCategoryType {
        HKObjectType.categoryType(forIdentifier: categoryIdentifier)!
    }

    var displayName: String {
        switch self {
        case .constipation: "Constipation"
        case .bloating:     "Bloating"
        case .nausea:       "Nausea"
        case .diarrhea:     "Diarrhea"
        case .cramps:       "Abdominal Cramps"
        case .heartburn:    "Heartburn"
        }
    }

    /// Per-symptom SF Symbol for the `+` chips (differentiates the picker). The dense
    /// tremor-chart marker uses the *shared* `timelineSymbol` instead — see below.
    var iconName: String {
        switch self {
        case .constipation: "hourglass"
        case .bloating:     "wind"
        case .nausea:       "face.dashed"
        case .diarrhea:     "drop.fill"
        case .cramps:       "bolt.fill"
        case .heartburn:    "flame.fill"
        }
    }

    /// Resolve from a single spoken/typed word (caller splits into words). Homophone-safe:
    /// these are plain English, so on-device dictation transcribes them intact — unlike
    /// pharma names, which is why voice suits GI better than medication.
    static func match(word: String) -> GISymptom? {
        switch word {
        // Deliberately conservative — no "sick" (too generic) or "runs" (collides with the
        // running workout). The confirm screen's symptom picker catches any miss.
        case "constipation", "constipated":            .constipation
        case "bloating", "bloated", "bloat":           .bloating
        case "nausea", "nauseous", "nauseated":        .nausea
        case "diarrhea", "diarrhoea":                  .diarrhea
        case "cramps", "cramp", "cramping":            .cramps
        case "heartburn", "reflux":                    .heartburn
        default:                                       nil
        }
    }

    // The tremor-chart marker is one restrained, unified glyph (the chart is already busy;
    // GI is a mixed cluster) in Apple Health's symptom hue — not per-symptom, not an emoji.
    static let timelineSymbol = "cross.case.fill"
    static let tint = Color.purple

    /// All HealthKit category types this feature reads + writes.
    static var sampleTypes: Set<HKSampleType> { Set(allCases.map(\.categoryType)) }
}

/// The severity a GI symptom is logged at. We never offer "Not Present" as a log — we
/// record problems, not confirmations of normality. Maps onto `HKCategoryValueSeverity`.
nonisolated enum GISeverity: String, CaseIterable, Identifiable, Sendable {
    case present, mild, moderate, severe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .present:  "Present"
        case .mild:     "Mild"
        case .moderate: "Moderate"
        case .severe:   "Severe"
        }
    }

    /// "Present" = symptom present, severity unspecified — matches what Apple Health writes
    /// when you tap "Present" without grading it.
    var hkSeverity: HKCategoryValueSeverity {
        switch self {
        case .present:  .unspecified
        case .mild:     .mild
        case .moderate: .moderate
        case .severe:   .severe
        }
    }

    /// Map a stored `HKCategorySample.value` back to a loggable severity. Returns nil for
    /// `notPresent` — a "confirmed absent" marker is not a symptom event and never appears
    /// on the timeline.
    init?(hkValue: Int) {
        switch HKCategoryValueSeverity(rawValue: hkValue) {
        case .unspecified: self = .present
        case .mild:        self = .mild
        case .moderate:    self = .moderate
        case .severe:      self = .severe
        default:           return nil   // .notPresent or unknown
        }
    }

    /// Parse a spoken severity adjective; nil → default to `.present`.
    static func match(word: String) -> GISeverity? {
        switch word {
        case "mild", "slight":       .mild
        case "moderate":             .moderate
        case "severe", "bad", "terrible": .severe
        default:                     nil
        }
    }
}
