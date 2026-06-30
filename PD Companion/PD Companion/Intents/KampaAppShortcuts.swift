import AppIntents

/// Registers the spoken phrases Siri recognizes for Kampa. The `\(.applicationName)`
/// token is required in every phrase; it resolves to the app's display name plus any
/// `INAlternativeAppNames` (we add plain "Kampa"/"Kumpa" in Info.plist so the macron
/// display name "Kāmpa" doesn't trip up recognition). Siri then elicits the food
/// description / session details via each intent's `requestValueDialog`.
struct KampaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log food in \(.applicationName)",
                "Log a meal in \(.applicationName)",
                "Log a snack in \(.applicationName)",
                "Log a drink in \(.applicationName)",
                "Log what I ate in \(.applicationName)",
            ],
            shortTitle: "Log Food",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogMindfulnessIntent(),
            phrases: [
                "Log meditation in \(.applicationName)",
                "Log a meditation in \(.applicationName)",
                "Log mindfulness in \(.applicationName)",
                "Log a meditation session in \(.applicationName)",
            ],
            shortTitle: "Log Meditation",
            systemImageName: "brain.head.profile"
        )
        // Distinct, phonetically-separated phrases ("meds"/"dose"/"Sinemet") so Siri
        // routes medication away from the close-sounding "meditation" intent.
        AppShortcut(
            intent: LogMedicationIntent(),
            phrases: [
                "Log medication in \(.applicationName)",
                "Log my medication in \(.applicationName)",
                "Log my meds in \(.applicationName)",
                "Log a dose in \(.applicationName)",
                "Log my dose in \(.applicationName)",
                "Log my Sinemet in \(.applicationName)",
                "Open my medications in \(.applicationName)",
            ],
            shortTitle: "Log Medication",
            systemImageName: "pills.fill"
        )
    }
}
