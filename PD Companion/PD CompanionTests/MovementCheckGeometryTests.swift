//
//  MovementCheckGeometryTests.swift
//  PD CompanionTests
//
//  The capture geometry a movement-check trial is measured against.
//  docs/design/movement-checks.md.
//
//  ⭐ These exist because the first build shipped with NO coverage of position at all, and two
//  defects hid in that gap for a full day of device testing — both measured out of his own
//  Aug 5 2026 export, neither visible on screen:
//
//    1. Taps were recorded in each target's OWN local coordinate space, so the distance
//       between the two boxes was absent from every stored tap. Travel summed only the
//       scatter inside a box: 37 taps reported 0.4 m where the geometry demands ~1.6 m, and
//       one trial implied 5.6 mm per crossing across a 15 mm gap — physically impossible.
//    2. The ~15 mm gap between the drawn boxes was dead space. 26.3% of intended bottom-box
//       taps registered nowhere (vs 2.9% for the top box) because his landings hug the facing
//       edges and any undershoot fell into the gap.
//
//  ⛔ Pins geometry and arithmetic, never copy.
//

import Foundation
import CoreGraphics
import Testing
@testable import PD_Companion

@Suite("Movement check geometry")
struct MovementCheckGeometryTests {

    /// A layout roughly matching what an iPhone renders: two ~238 pt targets, ~79 pt apart.
    private func layout() -> MovementCheckLayout {
        MovementCheckLayout(
            containerSize: CGSize(width: 160, height: 555),
            targetSize: CGSize(width: 140, height: 238),
            gap: 79
        )
    }

    // MARK: The dead zone

    @Test("A touch in the gap belongs to a target, never to nothing")
    func gapTouchesAreNeverDiscarded() {
        let l = layout()
        let top = l.rect(for: 0), bottom = l.rect(for: 1)
        // Dead centre of the gap, and one point either side of centre.
        let gapMidY = (top.maxY + bottom.minY) / 2
        #expect(l.nearestTarget(to: CGPoint(x: 80, y: gapMidY - 1)) == 0)
        #expect(l.nearestTarget(to: CGPoint(x: 80, y: gapMidY + 1)) == 1)
        // An undershoot short of the bottom box still counts as reaching for it once it is
        // past the midpoint — this is the exact touch that used to vanish.
        let undershoot = bottom.minY - 5
        #expect(l.nearestTarget(to: CGPoint(x: 80, y: undershoot)) == 1)
    }

    @Test("Every point on the surface resolves to one of the two targets")
    func wholeSurfaceIsLive() {
        let l = layout()
        for y in stride(from: 0.0, through: l.containerSize.height, by: 5) {
            let t = l.nearestTarget(to: CGPoint(x: 80, y: y))
            #expect(t == 0 || t == 1)
        }
    }

    // MARK: Travel

    @Test("Travel spans the distance between the boxes, not just scatter inside one")
    func travelCrossesTheGap() {
        let l = layout()
        // Two taps, one dead centre of each target. Their separation is target height + gap.
        let taps = [
            MovementCheckTap(offset: 0, x: l.center(for: 0).x, y: l.center(for: 0).y, target: 0),
            MovementCheckTap(offset: 0.25, x: l.center(for: 1).x, y: l.center(for: 1).y, target: 1)
        ]
        let s = MovementCheckMetrics.summary(for: taps, layout: l)
        #expect(abs(s.totalTravel - (238 + 79)) < 0.001)
        // ⛔ The regression that matters: under the old local-coordinate capture these two
        // centre taps had IDENTICAL coordinates and travel came out as 0.
        #expect(s.totalTravel > 300)
    }

    @Test("Points convert to millimetres via the drawn target, not a screen-density guess")
    func scaleIsRecoveredFromTheTarget() {
        let l = layout()
        // The box is `targetHeightMM` tall by protocol, so its height in points fixes the
        // scale whatever `pointsPerMM` estimated when it was drawn.
        #expect(abs(l.mmPerPoint * 238 - MovementCheckStyle.targetHeightMM) < 0.001)

        let taps = [
            MovementCheckTap(offset: 0, x: l.center(for: 0).x, y: l.center(for: 0).y, target: 0),
            MovementCheckTap(offset: 0.25, x: l.center(for: 1).x, y: l.center(for: 1).y, target: 1)
        ]
        let s = MovementCheckMetrics.summary(for: taps, layout: l)
        // One crossing centre-to-centre is 45mm of target + 15mm of gap = 60mm = 0.06 m.
        #expect(abs((s.travelMeters ?? 0) - 0.06) < 0.001)
    }

    @Test("Travel and accuracy are withheld, not guessed, when a trial has no geometry")
    func legacyTrialsReportNothingRatherThanNonsense() {
        let taps = [
            MovementCheckTap(offset: 0, x: 65, y: 125, target: 0),
            MovementCheckTap(offset: 0.25, x: 78, y: 89, target: 1)
        ]
        let s = MovementCheckMetrics.summary(for: taps, layout: nil)
        #expect(s.travelMeters == nil)
        #expect(s.offTargetMean == nil)
        // Tap count never depended on geometry, so it survives.
        #expect(s.tapCount == 2)
    }

    // MARK: Accuracy

    @Test("Off-target distance measures the miss, and is zero on a perfect centre hit")
    func offTargetMeasuresAccuracy() {
        let l = layout()
        let centred = [MovementCheckTap(offset: 0, x: l.center(for: 0).x,
                                        y: l.center(for: 0).y, target: 0)]
        #expect((MovementCheckMetrics.summary(for: centred, layout: l).offTargetMean ?? -1) == 0)

        let off = [MovementCheckTap(offset: 0, x: l.center(for: 0).x,
                                    y: l.center(for: 0).y - 30, target: 0)]
        let d = MovementCheckMetrics.summary(for: off, layout: l).offTargetMean ?? 0
        #expect(abs(d - 30) < 0.001)
    }

    // MARK: The missed-tap floor

    @Test("Two taps in a row on one target are the trace a missed tap leaves")
    func missedTapFloorCountsRepeats() {
        // The real 5:33 PM left-hand sequence from the Aug 5 2026 export.
        let seq = [0,1,0,1,0,0,0,0,1,0,0,0,1,0,0,0,1,0,0]
        let taps = seq.enumerated().map {
            MovementCheckTap(offset: Double($0.offset) * 0.4, x: 60, y: 100, target: $0.element)
        }
        // Eight adjacent same-target pairs, all of them on the TOP box, meaning eight
        // BOTTOM-box taps were made and never registered.
        #expect(MovementCheckMetrics.missedTapFloor(for: taps) == 8)

        // Perfect alternation has nothing to report.
        let clean = (0..<20).map {
            MovementCheckTap(offset: Double($0) * 0.25, x: 60, y: 100, target: $0 % 2)
        }
        #expect(MovementCheckMetrics.missedTapFloor(for: clean) == 0)
    }

    // MARK: Pause is the tap count inverted

    @Test("Pause carries no information the tap count doesn't already")
    func pauseIsTheReciprocalOfRate() {
        // Why pause is not plotted: it is defined as (last - first) / (n - 1), so for any
        // evenly spaced trial it is exactly the inverse of the rate. Two trials at very
        // different speeds both return their own span when multiplied back out.
        for n in [19, 37] {
            let spacing = 9.0 / Double(n - 1)
            let taps = (0..<n).map {
                MovementCheckTap(offset: Double($0) * spacing, x: 60, y: 100, target: $0 % 2)
            }
            let s = MovementCheckMetrics.summary(for: taps)
            #expect(abs(s.interTapDwellMean * Double(n - 1) - 9.0) < 0.0001)
        }
    }
}
