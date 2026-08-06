import Foundation

/// Derives every quantity a movement-check trial reports from its raw `taps`. Pure — no
/// SwiftData, no view code — so it stays unit-testable and every number stays reproducible
/// from the stored stream, per `docs/design/movement-checks.md`.
enum MovementCheckMetrics {
    struct Summary {
        var tapCount: Int
        /// Sum of point-to-point distance between consecutive taps, in the capture view's
        /// own coordinate space (points). AUC 0.92 in the validation study — the strongest
        /// discriminator after tap count.
        var totalTravel: Double
        /// Mean gap between consecutive taps. "Dwelling time" in the study's own terms —
        /// the pause, not the movement.
        var interTapDwellMean: TimeInterval
        /// First-half vs second-half tapping rate, as a fractional drop (0.1 = 10% slower
        /// by the second half). ⛔ Stored only, shown nowhere — the validation study found
        /// no phone-measurable decrement parameter. `nil` below 4 taps (needs 2 taps per
        /// half to define a rate).
        var decrement: Double?
        /// Mean distance from a tap to the centre of the target it was assigned to, in points.
        /// `nil` when the trial stored no capture geometry, since there is then no target
        /// position to measure against. ⭐ This is the part of a trial's positional data that
        /// isn't already implied by the tap count: the targets are fixed, so total travel is
        /// close to (crossings x a constant), while accuracy varies on its own.
        var offTargetMean: Double?
        /// Points-to-millimetres for this trial, recovered from its own drawn target.
        var mmPerPoint: Double?

        /// Total travel in metres, or `nil` when the trial has no geometry to scale by.
        var travelMeters: Double? {
            guard let mmPerPoint else { return nil }
            return totalTravel * mmPerPoint / 1000
        }
        /// Mean off-target distance in millimetres.
        var offTargetMM: Double? {
            guard let offTargetMean, let mmPerPoint else { return nil }
            return offTargetMean * mmPerPoint
        }
    }

    static func summary(for trial: MovementCheckTrial) -> Summary {
        summary(for: trial.taps, layout: trial.layout)
    }

    static func summary(for taps: [MovementCheckTap], layout: MovementCheckLayout? = nil) -> Summary {
        let ordered = taps.sorted { $0.offset < $1.offset }
        var travel = 0.0
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            travel += (dx * dx + dy * dy).squareRoot()
        }
        let dwells = zip(ordered, ordered.dropFirst()).map { $1.offset - $0.offset }
        let dwellMean = dwells.isEmpty ? 0 : dwells.reduce(0, +) / Double(dwells.count)
        var offTarget: Double?
        if let layout, !ordered.isEmpty {
            let sum = ordered.reduce(0.0) { $0 + layout.offTarget($1.point, target: $1.target) }
            offTarget = sum / Double(ordered.count)
        }
        return Summary(
            tapCount: ordered.count,
            totalTravel: travel,
            interTapDwellMean: dwellMean,
            decrement: decrement(ordered),
            offTargetMean: offTarget,
            mmPerPoint: layout?.mmPerPoint
        )
    }

    /// Taps the trial almost certainly recorded a touch for but never registered, inferred
    /// from the one trace a miss leaves: two taps in a row assigned to the SAME target, when
    /// the protocol is strictly alternating.
    ///
    /// ⚠️ A **floor**, not a count. A miss on one target immediately followed by a miss on the
    /// other preserves alternation and is invisible here. Kept out of `Summary` and off every
    /// user-facing surface on purpose — it's a diagnostic for whether the capture surface is
    /// working, not a fact about the person tapping.
    static func missedTapFloor(for taps: [MovementCheckTap]) -> Int {
        let ordered = taps.sorted { $0.offset < $1.offset }
        return zip(ordered, ordered.dropFirst()).reduce(0) { $0 + ($1.0.target == $1.1.target ? 1 : 0) }
    }

    private static func decrement(_ ordered: [MovementCheckTap]) -> Double? {
        guard ordered.count >= 4 else { return nil }
        let mid = ordered.count / 2
        guard let firstRate = tapRate(Array(ordered[..<mid])),
              let secondRate = tapRate(Array(ordered[mid...])),
              firstRate > 0 else { return nil }
        return (firstRate - secondRate) / firstRate
    }

    /// Taps per second within one half: (taps - 1) over the span the half actually covers.
    private static func tapRate(_ half: [MovementCheckTap]) -> Double? {
        guard half.count >= 2, let first = half.first?.offset, let last = half.last?.offset,
              last > first else { return nil }
        return Double(half.count - 1) / (last - first)
    }

    struct UsualRange { var lo: Double; var hi: Double }

    /// 10th/90th percentiles over recent trial values for one hand and one metric.
    ///
    /// ⚠️ **Cold-start gate is open, not decided.** `docs/design/movement-checks.md` leaves
    /// "how many trials before a range is honest" unmeasured on purpose. The `8` here isn't
    /// a new number — it reuses the recent-sample-count gate already shipped for the
    /// tremor/dyskinesia/HRV "usual range" bands (`e0ec548`), applied per TRIAL instead of
    /// per DAY since a movement check is already one data point per occasion, not a
    /// dense-within-a-day stream needing daily averaging first. Revisit once real trial
    /// data exists to answer the question properly.
    static func usualRange(_ values: [Double]) -> UsualRange? {
        guard values.count >= 8 else { return nil }
        let lo = CorrelationEngine.percentile(values, 0.10)
        let hi = CorrelationEngine.percentile(values, 0.90)
        return UsualRange(lo: lo, hi: hi)
    }
}
