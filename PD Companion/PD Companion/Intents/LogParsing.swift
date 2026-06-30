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
    /// "yesterday at 2pm", "last night at 10:30") and returns it with that phrase
    /// removed. `date == nil` when no time is mentioned — the caller then defaults to
    /// now. Future times are left for the caller to clamp.
    static func extractDate(from text: String) -> (date: Date?, cleanedText: String) {
        // Relative time-of-day phrases NSDataDetector can't resolve ("last night",
        // "this morning"…). Each carries a day offset and a default hour, used only when
        // no explicit clock time is *also* spoken. Tried first so "last night at 10:30"
        // lands on yesterday, not today.
        if let relative = extractRelativePhrase(from: text) {
            return (relative.date, relative.cleanedText)
        }
        return extractClockTime(from: text)
    }

    /// The NSDataDetector pass: handles absolute dates, "yesterday at 2pm", bare "9am".
    /// Bare-number false positives ("5 almonds") are rejected — a real time carries a
    /// letter (am/pm/today) or a colon — so quantities stay in the text.
    static func extractClockTime(from text: String) -> (date: Date?, cleanedText: String) {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else {
            return (nil, text)
        }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, options: [], range: full) {
            guard let date = match.date, let r = Range(match.range, in: text) else { continue }
            let matched = text[r].lowercased()
            let looksLikeTime = matched.rangeOfCharacter(from: .letters) != nil || matched.contains(":")
            guard looksLikeTime else { continue }

            var cleaned = text
            cleaned.removeSubrange(r)
            return (date, stripDanglingConnectors(cleaned))
        }
        return (nil, text)
    }

    /// Resolves the time-of-day phrases NSDataDetector misses. Returns the composed date
    /// (day offset + explicit-or-default hour, clamped to ≤ now) and the text with both
    /// the phrase and any explicit time removed. `nil` when no such phrase is present.
    private static func extractRelativePhrase(from text: String) -> (date: Date, cleanedText: String)? {
        let lower = text.lowercased()
        guard let match = relativePhrases
            .sorted(by: { $0.phrase.count > $1.phrase.count })          // longest wins
            .first(where: { lower.contains($0.phrase) })
        else { return nil }

        var remaining = text
        if let r = remaining.range(of: match.phrase, options: .caseInsensitive) {
            remaining.removeSubrange(r)
        }

        // An explicit clock time, if spoken, overrides the phrase's default hour.
        var hour = match.defaultHour
        var minute = 0
        let clock = extractClockTime(from: remaining)
        if let spoken = clock.date {
            let c = Calendar.current.dateComponents([.hour, .minute], from: spoken)
            hour = c.hour ?? hour
            minute = c.minute ?? 0
            remaining = clock.cleanedText
        }

        let cal = Calendar.current
        let baseDay = cal.date(byAdding: .day, value: match.dayOffset, to: cal.startOfDay(for: .now)) ?? .now
        var composed = cal.date(bySettingHour: hour, minute: minute, second: 0, of: baseDay) ?? baseDay
        if composed > .now { composed = .now }                          // never the future
        return (composed, stripDanglingConnectors(remaining))
    }

    /// Time-of-day phrases and their (day offset, default hour when no clock time spoken).
    private static let relativePhrases: [(phrase: String, dayOffset: Int, defaultHour: Int)] = [
        ("yesterday morning", -1, 8),
        ("yesterday afternoon", -1, 14),
        ("yesterday evening", -1, 19),
        ("last night", -1, 20),
        ("last evening", -1, 20),
        ("this morning", 0, 8),
        ("this afternoon", 0, 14),
        ("this evening", 0, 19),
        ("tonight", 0, 20),
    ]

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

    /// Peels the spoken command preamble off the front of a description so the stored
    /// text is the content, not "log food …". Only a *leading* run of command words is
    /// removed (verb → article/possessive → category noun → connector); the moment a real
    /// content word appears, stripping stops — so a food that happens to contain one of
    /// these words later ("almond butter on toast") is left intact. Never returns empty:
    /// if the phrase was *all* command words, the original text is kept.
    static func stripLeadingCommand(from text: String) -> String {
        let fillers: Set<String> = [
            "log", "logged", "record", "recorded", "track", "tracked", "add", "note",
            "took", "take", "taking", "taken", "had", "have", "having",
            "ate", "eat", "eating", "drank", "drink", "drinking",
            "did", "do", "start", "started", "begin", "began", "i",
            "a", "an", "my", "some", "the", "of", "for",
            "food", "meal", "snack", "bite",
            "medication", "medications", "med", "meds", "dose", "dosage",
            "pill", "pills", "tablet", "capsule", "supplement",
            "mindfulness", "meditation", "session",
        ]
        var tokens = text.split(separator: " ").map(String.init)
        while let first = tokens.first {
            let bare = first.lowercased().trimmingCharacters(in: .punctuationCharacters)
            guard fillers.contains(bare) else { break }
            tokens.removeFirst()
        }
        let result = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? text : result
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
