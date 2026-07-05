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
                "Log food with \(.applicationName)",
                "Log a meal in \(.applicationName)",
                "Log a meal with \(.applicationName)",
                "Log a snack in \(.applicationName)",
                "Log a drink in \(.applicationName)",
                "Log what I ate in \(.applicationName)",
            ],
            shortTitle: "Log Food",
            systemImageName: "fork.knife"
        )
        // Only Food and Mindfulness are hands-free auto-shortcuts: their trigger words
        // ("food/meal/snack/drink" vs "mindfulness") share nothing, so Siri separates
        // them cleanly. Medication is deliberately NOT here — "medication" is a homophone
        // of "meditation", and Siri's auto-matcher cannot reliably tell two close "Log
        // [noun]" phrases apart (it falls back to declaration order, hijacking whichever
        // is declared second). Medication logging lives on the in-app "+" voice path
        // instead, where Kampa owns the context and there is no Siri arbitration; a user
        // who wants it hands-free can record a custom phrase against `LogMedicationIntent`.
        AppShortcut(
            intent: LogMindfulnessIntent(),
            phrases: [
                "Log mindfulness in \(.applicationName)",
                "Log mindfulness with \(.applicationName)",
                "Log my mindfulness in \(.applicationName)",
                "Log a mindfulness session in \(.applicationName)",
                "Start a mindfulness session in \(.applicationName)",
            ],
            shortTitle: "Log Mindfulness",
            systemImageName: "brain.head.profile"
        )
        // GI symptoms are deliberately NOT auto-shortcuts. Siri's voice matcher hijacks
        // "Log [X] in Kampa" to the Food/Mindfulness intents (their open free-text
        // parameters make them greedy for any such phrase), so GI phrases mis-route no
        // matter how they're structured — concrete or parameterized. Verified on device.
        // GI voice logging lives on the in-app "+" mic instead (Kampa owns classification,
        // no Siri arbitration). If hands-free Siri is ever revisited, it needs an explicit
        // "add to Siri" setup flow that binds the phrase (as StrivePD does), not zero-config
        // auto-registration.
    }
}
