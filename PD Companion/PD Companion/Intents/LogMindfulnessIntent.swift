import AppIntents
import HealthKit

/// Voice/Siri/Shortcuts entry point for logging a meditation or mindfulness session.
/// Unlike medication (read-only in Apple's API), Mindful Minutes is app-writable, so
/// this writes the session straight to HealthKit via `HealthKitManager.writeMindfulSession`
/// — it then appears in both Kampa and Apple Health, exactly like the in-app sheet.
///
/// Duration is the actual measured quantity, so it is never defaulted: if the user
/// doesn't say it, the intent asks ("How long was your session?") rather than guess a
/// number that would silently corrupt the signal. The spoken anchor time is treated as
/// the session's *end* (you log when you finish), so it can never land in the future.
struct LogMindfulnessIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Meditation"
    static var description = IntentDescription(
        "Log a meditation or mindfulness session in Kampa."
    )

    static var openAppWhenRun = false

    @Parameter(title: "Session", requestValueDialog: "How long was your session?")
    var details: String

    /// Filled by the elicitation prompt when no duration was spoken. On the re-run,
    /// `details` is still present so the time parsed from it is preserved.
    @Parameter(title: "Duration (minutes)")
    var durationMinutes: Int?

    /// Power-path for the Shortcuts app; wins over anything parsed from speech.
    @Parameter(title: "Time")
    var explicitTime: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (parsedDate, afterDate) = LogParsing.extractDate(from: details)
        let parsedMinutes = LogParsing.extractDuration(from: afterDate).minutes

        guard let minutes = durationMinutes ?? parsedMinutes, minutes > 0 else {
            throw $durationMinutes.needsValueError("How long was your session?")
        }
        guard minutes <= 24 * 60 else {
            throw $durationMinutes.needsValueError("That seems too long — how many minutes?")
        }

        let hadTime = explicitTime != nil || parsedDate != nil
        let duration = Double(minutes) * 60
        // A spoken time is the session START ("a 30-min meditation at 6pm" began at 6).
        // With no time, you're logging one you just finished — so it ends now.
        var start = hadTime ? (explicitTime ?? parsedDate ?? .now)
                            : Date.now.addingTimeInterval(-duration)
        // Never let the session extend into the future.
        if start.addingTimeInterval(duration) > .now {
            start = Date.now.addingTimeInterval(-duration)
        }
        let whenSaid = hadTime ? "starting \(LogParsing.timePhrase(start))" : "now"

        try await requestConfirmation(
            dialog: IntentDialog(stringLiteral: "Log a \(minutes)-minute meditation \(whenSaid)?")
        )

        do {
            try await Self.writeSession(start: start, minutes: minutes)
        } catch {
            throw LogIntentError.healthKitWriteFailed
        }

        return .result(dialog: IntentDialog(
            stringLiteral: "Logged a \(minutes)-minute meditation \(whenSaid)."
        ))
    }

    // HealthKitManager is main-actor isolated; hop here since `perform()` isn't.
    @MainActor
    private static func writeSession(start: Date, minutes: Int) async throws {
        try await HealthKitManager().writeMindfulSession(
            start: start, duration: Double(minutes) * 60
        )
    }
}

enum LogIntentError: Error, CustomLocalizedStringResourceConvertible {
    case healthKitWriteFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .healthKitWriteFailed:
            return "Couldn't save to Apple Health. Open Kampa, allow Health access, then try again."
        }
    }
}
