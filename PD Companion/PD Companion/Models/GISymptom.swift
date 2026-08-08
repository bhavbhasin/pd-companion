import HealthKit
import SwiftUI

/// The curated non-motor symptom set Kampa logs, surfaced as "Symptoms" on the "+" screen.
/// The bowel members (constipation, and the retained gastroparesis markers) are the
/// gut-motility levers that gate levodopa absorption — that's the core thesis. `urinary`
/// (bladder/autonomic), `mood` and `fatigue` are off that thesis; they ride here because they
/// share the exact same log shape and are bundled under one "+" entry for the user. Each case
/// maps to a HealthKit category, so a log is an `HKCategorySample` that Apple Health *and* the
/// correlation engine both read (the close-loop pattern, like mindfulness).
///
/// `fatigue` and `mood` overlap in what a person feels (low energy vs flat motivation) but not
/// in what they ask, and they are the two that move within a day. If a user's logs show them
/// always moving together, that is a signal to drop one, not to keep both.
///
/// For the graded symptoms we log the *problem* only; a normal day is the silent baseline.
/// `mood` is the exception, and deliberately so: it is a recurring within-day state rather
/// than a discrete event, so "fine at 9am, off at 3pm" is the shape worth capturing, and an
/// absence is half of it. That is why absence is offered (and kept) for `mood` alone — see
/// `isSeverityGraded` and the read filter in `fetchGISymptomsInRange`.
///
/// The type name is now a misnomer (`mood` is not GI). Renaming it touches ~40 call sites,
/// so it stays until there's a reason to churn them.
///
/// `allCases` retains the full historical set (bloating/nausea/diarrhea/cramps/heartburn) so
/// already-logged samples still read back; `loggable` is the trimmed set the pickers OFFER.
nonisolated enum GISymptom: String, CaseIterable, Identifiable, Sendable {
    case constipation, bloating, nausea, diarrhea, cramps, heartburn, urinary, mood, fatigue

    var id: String { rawValue }

    /// The subset the `+` chips and the voice-correction picker OFFER. The others stay in
    /// `allCases` purely to DECODE existing Apple Health samples on read (non-destructive trim).
    static let loggable: [GISymptom] = [.constipation, .fatigue, .mood, .urinary]

    var categoryIdentifier: HKCategoryTypeIdentifier {
        switch self {
        case .constipation: .constipation
        case .bloating:     .bloating
        case .nausea:       .nausea
        case .diarrhea:     .diarrhea
        case .cramps:       .abdominalCramps
        case .heartburn:    .heartburn
        // Apple Health has no "urinary urgency" type; `.bladderIncontinence` is the closest
        // severity-scaled bladder category. Note the semantic gap: it reads as *leakage* in
        // Apple Health, not urgency. Same `HKCategoryValueSeverity` scale (SDK-verified).
        case .urinary:      .bladderIncontinence
        // `.moodChanges` is the only mood-adjacent category Apple Health has; there is no
        // depression, anxiety or apathy type (SDK-verified against HKTypeIdentifiers.h).
        // Naming the chip "Mood" rather than a specific symptom keeps the question we ask
        // aligned with what the sample can actually say. Presence-only, not graded; see
        // `isSeverityGraded`.
        case .mood:         .moodChanges
        // The one addition with no semantic gap at all: Apple Health's `.fatigue` means
        // exactly what the chip says, on the same severity scale as the bowel symptoms.
        case .fatigue:      .fatigue
        }
    }

    /// Most Apple Health symptoms are graded on `HKCategoryValueSeverity`. A few, including
    /// `.moodChanges`, are `HKCategoryValuePresence` instead: present or not present, no
    /// grades. Writing a severity raw value (mild == 2) into one of those stores a number the
    /// type does not define, so presence-only symptoms hide the severity picker and always
    /// record "present".
    var isSeverityGraded: Bool {
        switch self {
        case .mood: false
        default:      true
        }
    }

    /// The raw `HKCategorySample` value for a log at `severity`. A presence-only symptom keeps
    /// only the present/absent distinction and drops any grade. Decoding needs no equivalent
    /// branch: the two scales agree on the values a presence type can hold
    /// (present == unspecified == 0, notPresent == 1).
    func hkValue(for severity: GISeverity) -> Int {
        guard !isSeverityGraded else { return severity.hkSeverity.rawValue }
        return severity == .notPresent ? HKCategoryValuePresence.notPresent.rawValue
                                       : HKCategoryValuePresence.present.rawValue
    }

    /// The values this symptom's picker offers: three grades, or the two thumbs.
    var valueOptions: [GISeverity] {
        isSeverityGraded ? GISeverity.loggable : GISeverity.presenceOptions
    }

    /// The large symbol above the picker. Graded symptoms show their own glyph, growing and
    /// deepening in colour with the grade; presence-only symptoms show the thumb itself.
    func heroSymbol(for severity: GISeverity) -> String {
        isSeverityGraded ? iconName : severity.thumbSymbol
    }

    /// Coerce a value carried over from another symptom (or parsed from speech) into one this
    /// symptom can actually take, leaving valid selections alone.
    func validValue(_ severity: GISeverity) -> GISeverity {
        valueOptions.contains(severity) ? severity : (isSeverityGraded ? .mild : .present)
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
        case .urinary:      "Urinary"
        case .mood:         "Mood"
        case .fatigue:      "Fatigue"
        }
    }

    /// Per-symptom SF Symbol for the `+` chips (differentiates the picker). The dense
    /// tremor-chart marker uses the *shared* `timelineSymbol` instead — see below.
    var iconName: String {
        switch self {
        // Slow transit is what the symptom actually is, and the tortoise reads as "slow"
        // instantly. The plain hourglass read as a loading spinner.
        case .constipation: "tortoise.fill"
        case .bloating:     "wind"
        case .nausea:       "face.dashed"
        case .diarrhea:     "drop.fill"
        case .cramps:       "bolt.fill"
        case .heartburn:    "flame.fill"
        case .urinary:      "drop.circle.fill"
        case .mood:         "face.smiling"
        case .fatigue:      "battery.25percent"
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
        case "urinary", "urgency", "bladder":          .urinary
        // No bare "motivation" or "mood" — the parser matches single words, so "good mood"
        // would log a mood problem. Each word here carries its own negative sense.
        case "apathy", "apathetic", "unmotivated":     .mood
        case "fatigue", "fatigued", "exhausted", "tired", "wiped": .fatigue
        default:                                       nil
        }
    }

    // The tremor-chart marker is one restrained, unified glyph (the chart is already busy;
    // GI is a mixed cluster) in Apple Health's symptom hue — not per-symptom, not an emoji.
    static let timelineSymbol = "cross.case.fill"
    static let tint = Color.purple

    /// Every category type this feature can READ — the full historical set, so samples logged
    /// before a symptom was retired still decode. ⛔ Not the write set: asking to share a type
    /// no picker can produce puts a dead row in the Health permission sheet.
    static var sampleTypes: Set<HKSampleType> { Set(allCases.map(\.categoryType)) }

    /// The types this feature can actually WRITE — exactly what `loggable` offers. Derived from
    /// `loggable` rather than listed again, so retiring a chip removes its permission row too.
    static var writableSampleTypes: Set<HKSampleType> { Set(loggable.map(\.categoryType)) }
}

/// The value a symptom is logged at. Graded symptoms use mild/moderate/severe; presence-only
/// symptoms use present/notPresent. Maps onto `HKCategoryValueSeverity`, whose first two cases
/// coincide with `HKCategoryValuePresence` (0 == present, 1 == not present).
nonisolated enum GISeverity: String, CaseIterable, Identifiable, Sendable {
    case notPresent, present, mild, moderate, severe

    var id: String { rawValue }

    /// What the GRADED symptoms offer. "Present" is intentionally excluded — if a symptom is
    /// there it's mild, moderate, or severe; "present" adds no information. It stays in the
    /// enum only to DECODE Apple Health's ungraded ("Present"/`.unspecified`) samples on read.
    static let loggable: [GISeverity] = [.mild, .moderate, .severe]

    /// What a PRESENCE-ONLY symptom offers: two faces instead of three grades. Ordered better
    /// to worse, matching the graded picker's mild → severe direction.
    static let presenceOptions: [GISeverity] = [.notPresent, .present]

    var displayName: String {
        switch self {
        case .notPresent: "Not present"
        case .present:  "Present"
        case .mild:     "Mild"
        case .moderate: "Moderate"
        case .severe:   "Severe"
        }
    }

    /// The thumb shown for a presence-only symptom. A thumb rather than a face because the
    /// question is "was it there", not "how bad was it" — the graded symptoms own that scale.
    var thumbSymbol: String {
        self == .notPresent ? "hand.thumbsup.fill" : "hand.thumbsdown.fill"
    }

    /// Emoji twin of `thumbSymbol`, for the timeline label (a plain String, so it can't carry
    /// a tinted SF Symbol). Renders in the emoji palette, not the app's green/amber.
    var thumbLabel: String { self == .notPresent ? "👍" : "👎" }

    /// Word beside the thumb. The picture alone would leave "thumbs down for mood" ambiguous
    /// about which direction is which, and it's what VoiceOver reads.
    var thumbCaption: String { self == .notPresent ? "Fine" : "Off" }

    /// Valence colour, following the app's language (see `SeverityValence`): green is good and
    /// amber is a soft caution rather than an alarm. Red appears only at the top of a
    /// self-reported severity scale, where the user has explicitly said "severe" — that's a
    /// statement, not a comparison against a baseline, so the no-alarm rule doesn't apply.
    var valueColor: Color {
        switch self {
        case .notPresent: .green
        case .present:    .orange
        case .mild:       Color.secondary
        case .moderate:   .orange
        case .severe:     .red
        }
    }

    /// The hero symbol grows with intensity, so the screen responds as you move through the
    /// scale. The words below stay the precise part; this is the felt part.
    var symbolSize: CGFloat {
        switch self {
        case .notPresent, .present: 54
        case .mild:     42
        case .moderate: 50
        case .severe:   58
        }
    }

    /// "Present" = symptom present, severity unspecified — matches what Apple Health writes
    /// when you tap "Present" without grading it.
    var hkSeverity: HKCategoryValueSeverity {
        switch self {
        case .notPresent: .notPresent
        case .present:  .unspecified
        case .mild:     .mild
        case .moderate: .moderate
        case .severe:   .severe
        }
    }

    /// Map a stored `HKCategorySample.value` back to a value. `notPresent` decodes rather than
    /// being dropped here, because whether a confirmed-absent record is an event depends on the
    /// symptom, not the value — `fetchGISymptomsInRange` makes that call.
    init?(hkValue: Int) {
        switch HKCategoryValueSeverity(rawValue: hkValue) {
        case .notPresent:  self = .notPresent
        case .unspecified: self = .present
        case .mild:        self = .mild
        case .moderate:    self = .moderate
        case .severe:      self = .severe
        default:           return nil   // unknown
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
