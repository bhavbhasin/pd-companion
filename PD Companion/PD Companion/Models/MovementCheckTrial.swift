import Foundation
import CoreGraphics
import SwiftData

/// One 10-second alternating-tap trial for a single hand — a user-initiated bradykinesia
/// reading behind the `+` sheet. There is no passive stream for bradykinesia (Apple's
/// Movement Disorder API doesn't provide it), which is the one thing that earns this an
/// exception to the no-active-tests rule. See `docs/design/movement-checks.md`.
///
/// Stores the raw tap stream, not just the derived numbers — taps/travel/pause/decrement are
/// all computed at read time (`MovementCheckMetrics`) from `taps`, so a future change to how
/// any of them is measured applies retroactively instead of needing a retest. Same
/// store-rich-reduce-at-read rule as `TremorReading`/`DyskinesiaReading`.
@Model
final class MovementCheckTrial {
    // Indexed for the same reason as TremorReading.timestamp — history/trend reads filter
    // and sort by it. Non-unique → CloudKit-compatible.
    #Index<MovementCheckTrial>([\.timestamp])

    // Defaults required for CloudKit (NSPersistentCloudKitContainer): every stored
    // property must be optional or carry a default.
    var id: UUID = UUID()
    var timestamp: Date = Date.distantPast
    var hand: MovementCheckHand = MovementCheckHand.left
    /// Raw touch stream for the trial's 10 seconds, in tap order. `MovementCheckTap` is a
    /// plain Codable struct, not a second `@Model` — SwiftData stores an array of Codable
    /// value types as one attribute, so this needs no relationship and none of the
    /// CloudKit cascade-delete uncertainty a child `@Model` would carry (this codebase has
    /// no `.cascade` precedent; only `.nullify`, on `Therapy` → `TherapySession`).
    var taps: [MovementCheckTap] = []

    // MARK: Capture geometry
    //
    // ⚠️ **Stored because raw taps alone are NOT self-describing.** `taps` are points in the
    // capture surface's coordinate space, and that space is sized per device by
    // `TargetLayout` — so without the geometry that produced them, a distance in points
    // can't be turned back into millimetres and a landing point can't be placed relative to
    // its target. The original build stored taps without it and travel became unrecoverable
    // in principle, not just unconverted. Anything derived from position now reads its scale
    // from the trial itself.
    //
    // `0` means "captured before this was recorded" — see `layout`, which returns nil then
    // so every read-time consumer has to handle the unknown case explicitly.
    var containerWidthPt: Double = 0
    var containerHeightPt: Double = 0
    var targetWidthPt: Double = 0
    var targetHeightPt: Double = 0
    var targetGapPt: Double = 0

    /// The geometry these taps were captured against, or `nil` for a trial recorded before
    /// geometry was stored (whose `x`/`y` are in a per-target local space and are not
    /// comparable with anything measured since).
    var layout: MovementCheckLayout? {
        guard targetHeightPt > 0, targetWidthPt > 0, containerHeightPt > 0 else { return nil }
        return MovementCheckLayout(
            containerSize: CGSize(width: containerWidthPt, height: containerHeightPt),
            targetSize: CGSize(width: targetWidthPt, height: targetHeightPt),
            gap: targetGapPt
        )
    }

    init(timestamp: Date, hand: MovementCheckHand, taps: [MovementCheckTap],
         layout: MovementCheckLayout?) {
        self.id = UUID()
        self.timestamp = timestamp
        self.hand = hand
        self.taps = taps
        self.containerWidthPt = Double(layout?.containerSize.width ?? 0)
        self.containerHeightPt = Double(layout?.containerSize.height ?? 0)
        self.targetWidthPt = Double(layout?.targetSize.width ?? 0)
        self.targetHeightPt = Double(layout?.targetSize.height ?? 0)
        self.targetGapPt = layout?.gap ?? 0
    }
}

/// Where the two targets sat inside the capture surface, in that surface's own points.
///
/// The two rectangles are centred as a vertical stack, which is exactly how `TapCaptureView`
/// lays them out — so the five stored scalars reconstruct both rects without storing eight.
struct MovementCheckLayout: Equatable, Sendable {
    var containerSize: CGSize
    var targetSize: CGSize
    var gap: Double

    private var stackHeight: Double { targetSize.height * 2 + gap }
    private var originY: Double { max(0, (containerSize.height - stackHeight) / 2) }
    private var originX: Double { max(0, (containerSize.width - targetSize.width) / 2) }

    /// Target 0 is the TOP box, target 1 the BOTTOM one — the order they're drawn in.
    func rect(for target: Int) -> CGRect {
        CGRect(x: originX,
               y: originY + Double(target) * (targetSize.height + gap),
               width: targetSize.width,
               height: targetSize.height)
    }

    func center(for target: Int) -> CGPoint {
        let r = rect(for: target)
        return CGPoint(x: r.midX, y: r.midY)
    }

    /// Which target a touch belongs to: the nearer centre, always. ⚠️ There is deliberately
    /// no "neither" answer — the ~15mm gap between the drawn boxes used to be dead space that
    /// swallowed 26% of bottom-box taps (measured, Aug 5 2026 export), and a tapping test that
    /// silently discards a quarter of the taps isn't measuring tapping speed. The DRAWN boxes
    /// keep the validated protocol's size; the LIVE area is the whole surface.
    func nearestTarget(to point: CGPoint) -> Int {
        let d0 = abs(point.y - center(for: 0).y)
        let d1 = abs(point.y - center(for: 1).y)
        return d0 <= d1 ? 0 : 1
    }

    /// How far a touch landed from the centre of the target it was assigned to. This is the
    /// part of "travel" that carries information the tap count doesn't already: with fixed
    /// targets, total travel is mostly (crossings x a constant), but accuracy is free to vary.
    func offTarget(_ point: CGPoint, target: Int) -> Double {
        let c = center(for: target)
        return ((point.x - c.x) * (point.x - c.x) + (point.y - c.y) * (point.y - c.y)).squareRoot()
    }

    /// Recovered from the drawn target rather than assumed from screen density: the box is
    /// `targetHeightMM` tall by protocol, so its height in points fixes the scale for this
    /// trial on this device, whatever `pointsPerMM` estimated at draw time.
    var mmPerPoint: Double { MovementCheckStyle.targetHeightMM / targetSize.height }
}

enum MovementCheckHand: String, Codable, CaseIterable, Sendable {
    case left, right

    var displayName: String {
        switch self {
        case .left:  return "Left"
        case .right: return "Right"
        }
    }
}

/// One touch during a trial.
///
/// `offset` is seconds since the trial's `timestamp`, not a wall-clock `Date` — trials are
/// 10 s, so a `Double` offset is exact and far smaller than a full `Date` per tap.
///
/// ⚠️ `x`/`y` are points in the WHOLE capture surface's coordinate space (origin top-left),
/// shared by both targets — read them against the trial's `layout`. They used to be captured
/// in each target's OWN local space, which meant the vertical distance between the two boxes
/// was absent from every stored tap and travel measured only the scatter inside a box. A
/// trial with no stored `layout` still holds the old, non-comparable local coordinates.
struct MovementCheckTap: Codable, Sendable {
    var offset: TimeInterval
    var x: Double
    var y: Double
    /// Which of the two targets this tap was assigned to: 0 (top) or 1 (bottom). Needed to
    /// tell a tap that alternated targets from one that hit the same target twice — the
    /// protocol's "alternating" requirement is a property of the sequence, not of any single
    /// tap, and a repeat is the only trace a MISSED tap leaves.
    var target: Int

    var point: CGPoint { CGPoint(x: x, y: y) }
}
