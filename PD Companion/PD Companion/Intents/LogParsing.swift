import Foundation

/// Shared parsing for the voice-logging intents. Lets a single spoken sentence
/// carry both *what* and *when* (and, for meditation, *how long*) so Siri only has
/// to transcribe — we do the splitting here, which is far more reliable than asking
/// Siri to map free text onto separate typed parameters.
///
/// `nonisolated` because the target defaults to `@MainActor` isolation and these are
/// pure functions that the intents may call off the main actor.
nonisolated enum LogParsing {

    /// Pulls the first *real* time mentioned in `text` (e.g. "at 9am today",
    /// "yesterday at 2pm") and returns it with that phrase removed. `date == nil`
    /// when no time is mentioned — the caller then defaults to now. Future times are
    /// left for the caller to clamp.
    static func extractDate(from text: String) -> (date: Date?, cleanedText: String) {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else {
            return (nil, text)
        }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, options: [], range: full) {
            guard let date = match.date, let r = Range(match.range, in: text) else { continue }
            // Guard against bare-number false positives ("5 almonds"): a real time
            // always carries a letter (am/pm/today/morning) or a colon. A lone digit
            // that NSDataDetector guesses at is rejected so quantities stay in the text.
            let matched = text[r].lowercased()
            let looksLikeTime = matched.rangeOfCharacter(from: .letters) != nil || matched.contains(":")
            guard looksLikeTime else { continue }

            var cleaned = text
            cleaned.removeSubrange(r)
            return (date, stripDanglingConnectors(cleaned))
        }
        return (nil, text)
    }

    /// Pulls a duration in minutes from `text` ("45 minutes", "an hour",
    /// "half an hour", "1.5 hours"). `minutes == nil` when none is found — the
    /// meditation intent then asks the user, rather than guessing a measurement.
    static func extractDuration(from text: String) -> (minutes: Int?, cleanedText: String) {
        func find(_ pattern: String) -> Range<String.Index>? {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
        }
        if let r = find(#"half an hour|half hour"#) {
            return (30, stripDanglingConnectors(removing(text, r)))
        }
        if let r = find(#"quarter (of an |of a |an |a )?hour"#) {
            return (15, stripDanglingConnectors(removing(text, r)))
        }
        if let r = find(#"\b(an|one|a) hour\b"#) {
            return (60, stripDanglingConnectors(removing(text, r)))
        }
        if let r = find(#"\d+(\.\d+)?\s*(hours?|hrs?)"#) {
            let n = Double(text[r].prefix { $0.isNumber || $0 == "." }) ?? 0
            return (Int((n * 60).rounded()), stripDanglingConnectors(removing(text, r)))
        }
        if let r = find(#"\d+\s*(minutes?|mins?)"#) {
            let n = Int(text[r].prefix { $0.isNumber }) ?? 0
            return (n, stripDanglingConnectors(removing(text, r)))
        }
        return (nil, text)
    }

    /// Human-readable time for the confirmation/echo dialogs: "at 9:00 AM" today,
    /// "yesterday at 2:00 PM", otherwise "on Jun 27 at 2:00 PM".
    static func timePhrase(_ date: Date) -> String {
        let cal = Calendar.current
        let clock = DateFormatter()
        clock.dateFormat = "h:mm a"
        let t = clock.string(from: date)
        if cal.isDateInToday(date) { return "at \(t)" }
        if cal.isDateInYesterday(date) { return "yesterday at \(t)" }
        let day = DateFormatter()
        day.dateFormat = "MMM d"
        return "on \(day.string(from: date)) at \(t)"
    }

    // MARK: - Helpers

    private static func removing(_ text: String, _ r: Range<String.Index>) -> String {
        var s = text
        s.removeSubrange(r)
        return s
    }

    /// After a time/duration phrase is cut out, a connector word is often left
    /// dangling ("5 almonds and chai at " → "...at"; "for 30 minutes" → "for ").
    /// Collapse whitespace and peel any leading/trailing connectors.
    private static func stripDanglingConnectors(_ text: String) -> String {
        var s = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let connectors = ["at", "for", "around", "about", "on", "of", "@"]
        var changed = true
        while changed {
            changed = false
            let lower = s.lowercased()
            for c in connectors {
                if lower == c {
                    s = ""; changed = true
                } else if lower.hasSuffix(" \(c)") {
                    s = String(s.dropLast(c.count + 1)).trimmingCharacters(in: .whitespaces); changed = true
                } else if lower.hasPrefix("\(c) ") {
                    s = String(s.dropFirst(c.count + 1)).trimmingCharacters(in: .whitespaces); changed = true
                }
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
