import Foundation

/// What a spoken phrase resolved to. The same three categories the "+" sheet offers.
enum VoiceLogType {
    case food
    case medication
    case mindfulness
}

/// Decides which kind of entry a transcript is, by keyword. This runs *inside* Kampa,
/// so — unlike Siri's App Shortcut matcher — there is no cross-intent arbitration and
/// "meditation" can map straight to mindfulness without colliding with "medication".
/// Order matters: medication is checked first so "took my meds before meditating"
/// resolves to the dose, which is the safety-relevant event.
///
/// Matching is **word-aware, not substring**: medication words match a whole spoken word
/// (so "med" no longer fires on "**med**itated", nor "pill" on "**pill**ow"), while
/// mindfulness matches a word *stem* ("meditat" → meditate/meditated/meditation).
enum VoiceLogClassifier {
    // Category words only — NOT drug names. On-device dictation mangles uncommon pharma
    // names ("Sinemet"/"Rytary" → garbage → defaults to food), and the name is redundant
    // regardless: medication is a handoff to Apple Health, where the actual drug is
    // selected. Matched as whole words.
    private static let medicationWords: Set<String> = [
        "medication", "medications", "meds", "med", "dose", "doses", "dosage",
        "pill", "pills", "tablet", "tablets", "capsule", "capsules",
        "supplement", "supplements",
    ]
    // Stems, matched as a word prefix. "meditat" covers meditate/meditated/meditation;
    // "breath" covers breathe/breathing. "relax"/"calm" are deliberately excluded — they
    // collide with food ("a calming tea") and would misroute a meal to mindfulness.
    private static let mindfulnessStems = [
        "mindful", "meditat", "breath",
    ]

    static func classify(_ transcript: String) -> VoiceLogType {
        let words = transcript.lowercased().split { !$0.isLetter }.map(String.init)
        if words.contains(where: medicationWords.contains) { return .medication }
        if words.contains(where: { word in mindfulnessStems.contains(where: word.hasPrefix) }) {
            return .mindfulness
        }
        return .food            // the default — most spoken logs are meals/snacks/drinks
    }
}

/// A transcript turned into a ready-to-commit entry: the type, a cleaned description,
/// the anchored time, and (for mindfulness) a duration. Building this is pure and
/// synchronous so the UI can show a live preview as the user speaks, then commit the
/// exact thing it previewed. Reuses `LogParsing` so spoken time/duration handling is
/// identical to the Siri intents.
struct VoiceLogDraft {
    let type: VoiceLogType
    /// The spoken content with any time/duration phrase stripped out.
    let description: String
    let when: Date
    /// Present only for mindfulness, and only when the user actually said a length —
    /// never guessed, since it's a measured quantity.
    let durationMinutes: Int?
    /// True when a time was spoken (vs. defaulted to now) — drives the preview wording.
    let hadSpokenTime: Bool

    init?(transcript: String, defaultDate: Date) {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let type = VoiceLogClassifier.classify(raw)
        let (spokenDate, afterDate) = LogParsing.extractDate(from: raw)

        // For mindfulness, pull a duration out of what's left after the time.
        var minutes: Int? = nil
        var content = afterDate
        if type == .mindfulness {
            let (parsedMinutes, afterDuration) = LogParsing.extractDuration(from: afterDate)
            minutes = parsedMinutes
            content = afterDuration
        }

        // Classification already ran on `raw` (cues intact); now strip the spoken command
        // preamble ("log food …", "took my …") so the stored entry is just the content.
        let cleaned = LogParsing.stripLeadingCommand(from: content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type
        self.description = cleaned.isEmpty ? raw : cleaned
        self.durationMinutes = minutes
        self.hadSpokenTime = spokenDate != nil

        // Anchor: a spoken time wins; otherwise the viewed day at the current clock time,
        // never the future (matches LogFoodScreen / LogMindfulnessScreen behavior).
        if let spokenDate {
            self.when = min(spokenDate, .now)
        } else {
            let now = Date.now
            let cal = Calendar.current
            let t = cal.dateComponents([.hour, .minute], from: now)
            let onViewedDay = cal.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0,
                                       second: 0, of: defaultDate) ?? defaultDate
            self.when = min(onViewedDay, now)
        }
    }

    /// Human-readable time fragment for the preview ("now" or "at 9:00 AM").
    var whenPhrase: String {
        hadSpokenTime ? LogParsing.timePhrase(when) : "now"
    }
}
