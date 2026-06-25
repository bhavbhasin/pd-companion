import Foundation
import SwiftData

/// One-time re-classification of existing `FoodEvent`s with the corrected
/// `FoodAttributeClassifier`.
///
/// The old `FoodAttribute.detect()` keyword list under-tagged history (e.g.
/// almonds came out `fat`-only, missing protein + fiber). This re-derives the
/// attribute set for every stored entry from its description using the validated
/// classifier, so the correlation engine sees correct tags on past data too.
///
/// Safe + idempotent: attributes are a pure function of the description and there
/// is no manual-correction UI to preserve, so re-running yields the same result.
/// Guarded by a version flag, so it runs once per bump. Writes only entries whose
/// attribute *set* actually changed, to avoid needless CloudKit churn.
enum FoodAttributeBackfill {
    private static let versionKey = "foodAttributeBackfillVersion"
    // Bump whenever the classifier or alias map changes in a way that should re-tag
    // existing history. v2: diet-soda aliases (Diet Coke / Coke Zero / Diet Pepsi)
    // now resolve to caffeine-only instead of picking up regular cola's sugar.
    private static let currentVersion = 2

    /// Runs once, entirely off the main thread on its own background `ModelContext`,
    /// so the bulk re-classification never blocks the UI. (An earlier main-thread
    /// version hung launch into a watchdog SIGKILL; with the indexed classifier each
    /// call is ~ms, and this keeps it off the UI thread regardless.) The flag is set
    /// only on success, so a failure simply retries next launch — harmless and idempotent.
    static func runIfNeeded(container: ModelContainer) {
        guard UserDefaults.standard.integer(forKey: versionKey) < currentVersion else { return }
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            do {
                let events = try context.fetch(FetchDescriptor<FoodEvent>())
                var changed = 0
                for event in events {
                    let newAttrs = FoodAttributeClassifier.shared.classify(event.userDescription)
                    if Set(newAttrs) != Set(event.attributes) {
                        event.attributes = newAttrs
                        changed += 1
                    }
                }
                if context.hasChanges { try context.save() }
                UserDefaults.standard.set(currentVersion, forKey: versionKey)
                print("[backfill] food attributes re-classified: \(changed)/\(events.count) entries updated")
            } catch {
                print("[backfill] food attribute backfill failed: \(error)")
            }
        }
    }
}
