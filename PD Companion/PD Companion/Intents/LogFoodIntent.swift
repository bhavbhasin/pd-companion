import AppIntents
import SwiftData

/// Voice/Siri/Shortcuts entry point for logging a meal, snack, or drink without
/// typing — the accessibility path for tremor-affected hands. The spoken free-text
/// description is classified on-device by `FoodAttributeClassifier` (the same
/// classifier `LogFoodScreen` uses) and written as a `FoodEvent` into the shared
/// `AppContainer` store, so a voice-logged item is indistinguishable from a
/// hand-logged one and syncs via CloudKit like any other.
///
/// Confirm-then-commit: the parsed result is read back ("Log … at 9 AM?") and only
/// written on a yes. Nothing is saved if the user declines, so a mis-heard food term
/// or time can be re-recorded instead of corrected after the fact.
struct LogFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Food or Drink"
    static var description = IntentDescription(
        "Log a meal, snack, or drink in Kampa by describing it out loud."
    )

    // Stay in the background — the whole point is to log without opening the app.
    static var openAppWhenRun = false

    @Parameter(title: "Food or drink", requestValueDialog: "What did you eat or drink?")
    var foodDescription: String

    /// Power-path for the Shortcuts app: an explicit time wins over anything parsed
    /// from speech. Nil on the common voice path, where time is parsed or defaults to now.
    @Parameter(title: "Time")
    var explicitTime: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$foodDescription)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let raw = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw $foodDescription.needsValueError("What did you eat or drink?")
        }

        let (parsedDate, cleaned) = LogParsing.extractDate(from: raw)
        let foodText = cleaned.isEmpty ? raw : cleaned
        guard !foodText.isEmpty else {
            throw $foodDescription.needsValueError("What did you eat or drink?")
        }

        let hadTime = explicitTime != nil || parsedDate != nil
        var when = explicitTime ?? parsedDate ?? .now
        if when > .now { when = .now }          // never log into the future
        let phrase = hadTime ? LogParsing.timePhrase(when) : "now"

        // Read it back and wait for a yes before writing anything.
        try await requestConfirmation(
            dialog: IntentDialog(stringLiteral: "Log \(foodText) \(phrase)?")
        )

        let attributes = FoodAttributeClassifier.shared.classify(foodText)
        try await Self.commit(foodText: foodText, attributes: attributes, when: when)

        return .result(dialog: IntentDialog(stringLiteral: "Logged \(foodText) \(phrase)."))
    }

    // SwiftData's mainContext is main-actor isolated and `perform()` is not, so the
    // write hops here. The explicit save guards against the intent process being torn
    // down before autosave flushes.
    @MainActor
    private static func commit(foodText: String, attributes: [FoodAttribute], when: Date) throws {
        let context = AppContainer.shared.mainContext
        context.insert(FoodEvent(timestamp: when, userDescription: foodText, attributes: attributes))
        try context.save()
    }
}
