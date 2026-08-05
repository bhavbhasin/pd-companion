import Foundation
import SwiftData
import SwiftUI

/// A therapy the user does: ozone, PEMF, TPS, acupuncture, bodywork. This is the **type**,
/// managed from `+ → Therapy → Edit my therapies`; each time they actually do it, a `TherapySession`
/// points here. Originated with tester John S.
///
/// ⭐ **Why a catalog and not a name on each session.** With a free-text name per session, a
/// rename fixes one row and leaves the rest — ten PEMFs and one Pemf — and every log is a
/// fresh chance to spell it differently. Holding the name in one place makes a rename
/// propagate to the whole history for free, and turns logging into a pick rather than typing,
/// which is the difference that matters when a tremor makes typing the expensive part.
@Model
final class Therapy {
    // CloudKit (NSPersistentCloudKitContainer) requires every stored property to be optional
    // or carry a default, and relationships to be optional.
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    /// Archived therapies drop out of the picker but keep every session they own. See
    /// `canBeDeleted` for why this exists rather than a delete.
    var isArchived: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \TherapySession.therapy)
    var sessions: [TherapySession]? = []

    init(name: String, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.isArchived = false
        self.sessions = []
    }

    var sessionCount: Int { sessions?.count ?? 0 }

    /// ⛔ **A therapy that has been used is never deletable.** Deleting the type would take
    /// logged health events with it, and the tremor record around those events cannot be
    /// refetched. Archiving is the answer for "I stopped doing this": it leaves the picker,
    /// the history stays readable, and it can be restored.
    var canBeDeleted: Bool { sessionCount == 0 }
}

/// One session of a `Therapy` — a start and an end, nothing else.
///
/// ⛔ **Kampa never states whether a therapy worked.** Event frequency is 10-100× below
/// levodopa's, the confound is worse than caffeine's (people book treatment when they feel
/// worse, so the "before" window is selected for being bad), and these are unregulated
/// out-of-pocket treatments where a false positive is a purchase recommendation. The engine
/// stays silent here in v1. See `docs/design/therapy-logging.md`.
///
/// Logging still earns its place without a verdict: an untracked weekly acupuncture session
/// is **invisible variance** already shaping the readings around it, so recording it makes
/// every *other* insight more honest.
@Model
final class TherapySession {
    var id: UUID = UUID()
    var start: Date = Date.now
    /// Always stored, never nil. The *entry* is optional — the screen prefills
    /// `start + 30 min` and the user may never touch it — but a session with no end has no
    /// duration, and an optional here would push that emptiness into every reader.
    var end: Date = Date.now.addingTimeInterval(TherapyStyle.defaultDuration)
    var therapy: Therapy?
    /// ⚠️ **Fallback only, never the source of truth.** Written once at insert and never
    /// updated, so it must not be read while `therapy` resolves — a rename would not reach it.
    /// It exists solely for the window where CloudKit has delivered a session but not yet the
    /// `Therapy` it points at, so an unnamed marker never appears on the timeline. Anything
    /// that "fixes" this by keeping it in sync has reintroduced the defect the catalog removed.
    var nameSnapshot: String?
    var notes: String?

    init(therapy: Therapy, start: Date, end: Date? = nil, notes: String? = nil) {
        self.id = UUID()
        self.therapy = therapy
        self.nameSnapshot = therapy.name
        self.start = start
        self.end = end ?? start.addingTimeInterval(TherapyStyle.defaultDuration)
        self.notes = notes
    }

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// The live name, falling back only when the relationship has not arrived yet.
    var displayName: String {
        if let name = therapy?.name, !name.isEmpty { return name }
        if let snapshot = nameSnapshot, !snapshot.isEmpty { return snapshot }
        return "Therapy"
    }
}

/// One shared glyph and colour for **every** therapy — users do not pick per-therapy icons.
/// A single symbol keeps therapy a legible band on the timeline whatever the modality;
/// per-item glyphs would be noise and a maintenance surface. The name carries the
/// specificity, the glyph carries the category.
enum TherapyStyle {
    static let timelineSymbol = "hands.and.sparkles.fill"
    static let tint = Color.teal
    /// The prefilled session length. Bodywork and acupuncture have a clear start and end;
    /// "took an ozone sauna this morning" does not, and requiring an end time would block the
    /// log on a number the user is guessing at anyway.
    static let defaultDuration: TimeInterval = 30 * 60

    /// The existing therapy with this name, ignoring case and surrounding space — **including
    /// archived ones**. The catalog stops most duplicates by making logging a pick; this stops
    /// the rest at the one place a name can still be typed.
    ///
    /// ⚠️ Returning the therapy rather than a Bool is deliberate. An archived match is not a
    /// duplicate to refuse — it is the therapy the user is asking for, and the honest response is
    /// to offer it back. Refusing with "you already have this" while nothing of that name is
    /// visible anywhere is a dead end, which is exactly what the first version did.
    static func match(_ name: String, in existing: [Therapy]) -> Therapy? {
        let folded = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !folded.isEmpty else { return nil }
        return existing.first { $0.name.lowercased() == folded }
    }
}
