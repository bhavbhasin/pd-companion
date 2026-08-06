import Foundation
import SwiftData

/// One hand-rotation (pronation-supination) trial — the second instrument in the Movement
/// check category, alongside Tapping. See `docs/design/movement-checks.md`.
///
/// ⭐ **Better validated than the tapping test we shipped first.** CloudUPDRS ran 16 smartphone
/// subtests against the same blinded raters and pronation/supination predicted its MDS-UPDRS
/// subitem at 74.6% / 73.0% (left/right) against finger tapping's 53.2% / 62.9%. Protocol from
/// Roche's shipped PD Mobile Application v2: phone HELD in the hand, arm outstretched, screen
/// palm up, rotate palm up/palm down as fast as possible, 10 s per hand.
///
/// ⚠️ **The type is `RotationTrial`, not `MovementCheckRotationTrial`** — and Tapping's type is
/// still `MovementCheckTrial` even though "Movement check" is now the CATEGORY rather than the
/// instrument. Renaming a `@Model` changes its CloudKit record type and orphans every synced
/// record, so the tapping model keeps the name it was born with. Don't tidy this.
@Model
final class RotationTrial {
    #Index<RotationTrial>([\.timestamp])

    // Defaults required for CloudKit: every stored property optional or defaulted.
    var id: UUID = UUID()
    var timestamp: Date = Date.distantPast
    var hand: MovementCheckHand = MovementCheckHand.left

    /// Angular velocity about the trial's own principal rotation axis, in radians/second, in
    /// sample order.
    ///
    /// ⭐ **One channel, not six, and deliberately the RAW projected signal.** Storing the axis
    /// beside it (below) means turns, amplitude, peak velocity and decrement are all
    /// re-derivable at read time without a retest — the same store-rich rule that let the
    /// tapping capture defects be diagnosed from an export rather than guessed at. Storing all
    /// six raw channels would be ~6x the bytes for information the projection has already used.
    var angularVelocity: [Double] = []
    /// Samples per second the series was captured at. Stored rather than assumed: every
    /// quantity below is a rate, so a series without its sample rate is unreadable.
    var sampleRate: Double = 0

    // The principal axis PCA found, in device coordinates. Stored so the projection can be
    // sanity-checked later (a wildly off-axis trial means the user rotated about something
    // other than their forearm) and so a future algorithm can re-project if it wants to.
    var axisX: Double = 0
    var axisY: Double = 0
    var axisZ: Double = 0

    /// `nil` for a trial with no usable series — read-time consumers must handle it explicitly
    /// rather than dividing by a zero sample rate.
    var isReadable: Bool { sampleRate > 0 && angularVelocity.count > 1 }

    init(timestamp: Date, hand: MovementCheckHand, angularVelocity: [Double],
         sampleRate: Double, axis: (x: Double, y: Double, z: Double)) {
        self.id = UUID()
        self.timestamp = timestamp
        self.hand = hand
        self.angularVelocity = angularVelocity
        self.sampleRate = sampleRate
        self.axisX = axis.x
        self.axisY = axis.y
        self.axisZ = axis.z
    }
}
