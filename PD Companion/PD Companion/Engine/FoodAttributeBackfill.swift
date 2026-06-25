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
    private static let currentVersion = 1

    @MainActor
    static func runIfNeeded(_ context: ModelContext) {
        guard UserDefaults.standard.integer(forKey: versionKey) < currentVersion else { return }
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
