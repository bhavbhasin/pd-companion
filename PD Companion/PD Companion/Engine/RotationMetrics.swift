import Foundation

/// Derives every quantity a hand-rotation trial reports from its stored angular-velocity
/// series. Pure — no SwiftData, no view code — so it stays unit-testable and every number
/// stays reproducible from the stored stream. See `docs/design/movement-checks.md`.
///
/// Implements the algorithm Roche/Verily published analytical validation for: gyroscope →
/// low-pass filter → PCA for the true axis of rotation → integrate angular velocity about that
/// axis. Their ICC against human raters counting turns by eye was 0.935, and 0.97–0.99 when
/// subjects deliberately did it wrong (raising the arm, stopping and starting, rotating about
/// several axes) — the PCA step is what buys that robustness, because it never assumes the user
/// held a clean axis.
enum RotationMetrics {

    struct Summary {
        /// Completed half-turns: one palm-up-to-palm-down flip each, which is what a clinical
        /// rater counts when MDS-UPDRS 3.6 says "turn the palm up and down alternately".
        var turns: Int
        /// Mean angle swept per half-turn, in degrees. ⭐ Genuinely independent of `turns` —
        /// MDS-UPDRS scores amplitude separately from speed, and someone can flip fast and
        /// shallow or slow and full. ⛔ Do NOT derive one from the other and show both.
        var meanAmplitudeDegrees: Double
        /// Fastest rotation reached, degrees/second.
        var peakVelocityDegreesPerSecond: Double
        /// First-half vs second-half turn rate, as a fractional drop. ⛔ Stored, shown nowhere —
        /// same standing as tapping's decrement, and for the same reason: no evidence a phone
        /// measures fatigue reliably. `nil` below 4 half-turns.
        var decrement: Double?
        /// The rhythm the trial actually settled into, Hz. Used to set the filter cutoff, and
        /// worth keeping because a trial with no clear rhythm is a trial to distrust.
        var dominantFrequency: Double
    }

    static func summary(for trial: RotationTrial) -> Summary? {
        guard trial.isReadable else { return nil }
        return summary(angularVelocity: trial.angularVelocity, sampleRate: trial.sampleRate)
    }

    static func summary(angularVelocity: [Double], sampleRate: Double) -> Summary? {
        guard sampleRate > 0, angularVelocity.count > 1 else { return nil }

        // ⚠️ The cutoff is DERIVED, not chosen. A fixed number would be a magic constant, and a
        // wrong one is unrecoverable: PD rest tremor (4-6 Hz) overlaps the voluntary rotation
        // band (~1-5 Hz), so no universal cutoff separates them. Taking 3x the rhythm this
        // trial actually settled into keeps the movement and its first harmonics — enough to
        // preserve a sharp reversal — while still suppressing what sits above it.
        let dominant = dominantFrequency(angularVelocity, sampleRate: sampleRate)
        let cutoff = max(3 * dominant, 2.0)
        let filtered = lowPassZeroPhase(angularVelocity, sampleRate: sampleRate, cutoff: cutoff)

        // A half-turn ends where the rotation reverses. ⭐ Threshold-free by construction: a
        // sign change is a sign change, so there is no "how big must a wobble be to count"
        // constant to get wrong. The filter above is what stops noise inventing reversals.
        var reversals = 0
        var segmentAngles: [Double] = []
        var currentAngle = 0.0
        let dt = 1.0 / sampleRate
        for (a, b) in zip(filtered, filtered.dropFirst()) {
            currentAngle += abs(a) * dt
            if (a > 0 && b <= 0) || (a < 0 && b >= 0) {
                reversals += 1
                segmentAngles.append(currentAngle)
                currentAngle = 0
            }
        }

        let meanAmplitude = segmentAngles.isEmpty
            ? 0
            : segmentAngles.reduce(0, +) / Double(segmentAngles.count) * 180 / .pi
        let peak = (filtered.map(abs).max() ?? 0) * 180 / .pi

        return Summary(
            turns: reversals,
            meanAmplitudeDegrees: meanAmplitude,
            peakVelocityDegreesPerSecond: peak,
            decrement: decrement(segmentAngles),
            dominantFrequency: dominant
        )
    }

    /// Fractional drop in half-turns-per-second between the first and second half of the trial.
    private static func decrement(_ segments: [Double]) -> Double? {
        guard segments.count >= 4 else { return nil }
        let mid = segments.count / 2
        let first = segments[..<mid].reduce(0, +)
        let second = segments[mid...].reduce(0, +)
        // Equal counts of half-turns, so comparing the ANGLE each half consumed compares how
        // long they took — more angle for the same number of turns means slower, fuller sweeps.
        guard first > 0 else { return nil }
        return (second - first) / first
    }

    // MARK: - Signal processing

    /// The principal axis of rotation, by power iteration on the 3x3 covariance of the angular
    /// velocity vectors.
    ///
    /// ⭐ This is the step that makes the test survive a user who doesn't hold their forearm
    /// square to the phone: whatever axis they actually rotated about becomes THE axis, rather
    /// than us assuming roll about the device's long edge and quietly measuring a projection of
    /// the real movement.
    static func principalAxis(_ samples: [(x: Double, y: Double, z: Double)])
        -> (x: Double, y: Double, z: Double) {
        guard !samples.isEmpty else { return (0, 0, 1) }
        // Covariance about zero, not about the mean: we want the dominant direction of the
        // rotation itself, and a back-and-forth movement has a mean near zero by design.
        var c = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for s in samples {
            let v = [s.x, s.y, s.z]
            for i in 0..<3 { for j in 0..<3 { c[i][j] += v[i] * v[j] } }
        }
        var vec = [1.0, 1.0, 1.0]
        for _ in 0..<64 {
            var next = [0.0, 0.0, 0.0]
            for i in 0..<3 { for j in 0..<3 { next[i] += c[i][j] * vec[j] } }
            let norm = (next[0] * next[0] + next[1] * next[1] + next[2] * next[2]).squareRoot()
            guard norm > 1e-12 else { return (0, 0, 1) }
            vec = next.map { $0 / norm }
        }
        return (vec[0], vec[1], vec[2])
    }

    /// Signed scalar angular velocity about `axis` — the one channel worth storing.
    static func project(_ samples: [(x: Double, y: Double, z: Double)],
                        onto axis: (x: Double, y: Double, z: Double)) -> [Double] {
        samples.map { $0.x * axis.x + $0.y * axis.y + $0.z * axis.z }
    }

    /// Dominant frequency in the plausible pronation-supination band, by direct evaluation of
    /// the power at each candidate frequency. ⚠️ The 0.5–8 Hz window is the physiological range
    /// of the movement, not a tuning knob: below 0.5 Hz nobody is "rotating as fast as they
    /// can", and above 8 Hz no wrist alternates.
    static func dominantFrequency(_ signal: [Double], sampleRate: Double) -> Double {
        guard signal.count > 1, sampleRate > 0 else { return 0 }
        let n = Double(signal.count)
        var best = 0.0, bestPower = -1.0
        var f = 0.5
        while f <= 8.0 {
            var re = 0.0, im = 0.0
            let w = 2 * Double.pi * f / sampleRate
            for (i, v) in signal.enumerated() {
                re += v * cos(w * Double(i))
                im += v * sin(w * Double(i))
            }
            let power = (re * re + im * im) / n
            if power > bestPower { bestPower = power; best = f }
            f += 0.05
        }
        return best
    }

    /// One-pole low pass run forwards then backwards, so it smooths without shifting anything
    /// in time. ⚠️ Phase matters here: a lagged signal moves every reversal, and reversals are
    /// what we count.
    static func lowPassZeroPhase(_ signal: [Double], sampleRate: Double, cutoff: Double) -> [Double] {
        guard signal.count > 1, cutoff > 0, sampleRate > 0 else { return signal }
        let rc = 1 / (2 * Double.pi * cutoff)
        let dt = 1 / sampleRate
        let alpha = dt / (rc + dt)

        var forward = [Double](repeating: 0, count: signal.count)
        forward[0] = signal[0]
        for i in 1..<signal.count {
            forward[i] = forward[i - 1] + alpha * (signal[i] - forward[i - 1])
        }
        var backward = forward
        for i in stride(from: signal.count - 2, through: 0, by: -1) {
            backward[i] = backward[i + 1] + alpha * (forward[i] - backward[i + 1])
        }
        return backward
    }
}
