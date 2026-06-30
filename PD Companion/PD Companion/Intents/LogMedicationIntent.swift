import AppIntents
import UIKit

/// Voice fast-path for medication. Apple's Medications API is **read-only** to third
/// parties (you can read dose events but not write them), so unlike food/mindfulness
/// this can't log the dose itself — it hands off to Apple Health's Medications screen,
/// the same deep-link `LogEntrySheet` uses. This is a navigation shortcut, not a write,
/// and deliberately does not make Kampa the system-of-record for meds.
///
/// It also disambiguates the Siri phrase: without an explicit "medication" shortcut,
/// "log medication" was matching the phonetically-close "log meditation" intent and
/// mis-logging a mindfulness session.
struct LogMedicationIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Medication"
    static var description = IntentDescription(
        "Open Apple Health's Medications screen to log a dose. Apple doesn't allow apps to record doses directly, so Kampa hands off to Health."
    )

    // Must foreground to hand off to another app's URL scheme.
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await Self.openMedications()
        return .result(dialog: "Opening Medications in Apple Health.")
    }

    // Deep-links to Health's Medications screen; falls back to Health's home if that
    // undocumented path ever stops resolving, so the shortcut never dead-ends.
    @MainActor
    private static func openMedications() async {
        let medications = URL(string: "x-apple-health://Medications")!
        let opened = await UIApplication.shared.open(medications)
        if !opened, let health = URL(string: "x-apple-health://") {
            _ = await UIApplication.shared.open(health)
        }
    }
}
