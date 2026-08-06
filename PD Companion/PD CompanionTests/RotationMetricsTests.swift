//
//  RotationMetricsTests.swift
//  PD CompanionTests
//
//  The hand-rotation (pronation-supination) algorithm. docs/design/movement-checks.md.
//
//  ⭐ Written BEFORE the capture UI exists, against synthetic signals where the right answer is
//  known by construction. The tapping test taught this the expensive way: its capture defects
//  were invisible on screen and only fell out of counting an export, after a full day of device
//  testing. A synthetic signal has no such ambiguity - if 20 half-turns go in, 20 must come out.
//

import Foundation
import Testing
@testable import PD_Companion

@Suite("Rotation metrics")
struct RotationMetricsTests {

    /// A clean pronation-supination trial: sinusoidal angular velocity about one axis.
    /// A full sine cycle is TWO half-turns (palm up, then palm down), so `cycles` cycles is
    /// `2 * cycles` reversals.
    private func sine(cycles: Double, seconds: Double, sampleRate: Double,
                      amplitude: Double) -> [Double] {
        let n = Int(seconds * sampleRate)
        let f = cycles / seconds
        return (0..<n).map { i in
            amplitude * sin(2 * .pi * f * Double(i) / sampleRate)
        }
    }

    // MARK: Turn counting

    @Test("A known number of flips comes back out")
    func countsHalfTurns() {
        // 10 s at 100 Hz, 15 full cycles = 1.5 Hz, which is a realistic rotation rhythm.
        let signal = sine(cycles: 15, seconds: 10, sampleRate: 100, amplitude: 6)
        let s = RotationMetrics.summary(angularVelocity: signal, sampleRate: 100)
        #expect(s != nil)
        // 15 cycles crosses zero 30 times; the final partial segment may or may not close.
        #expect(abs((s?.turns ?? 0) - 30) <= 1)
    }

    @Test("Rotating twice as fast reports twice the turns")
    func turnsScaleWithRate() {
        let slow = RotationMetrics.summary(
            angularVelocity: sine(cycles: 10, seconds: 10, sampleRate: 100, amplitude: 6),
            sampleRate: 100)
        let fast = RotationMetrics.summary(
            angularVelocity: sine(cycles: 20, seconds: 10, sampleRate: 100, amplitude: 6),
            sampleRate: 100)
        let ratio = Double(fast?.turns ?? 0) / Double(slow?.turns ?? 1)
        #expect(abs(ratio - 2) < 0.15)
    }

    @Test("Superimposed tremor does not invent extra turns")
    func tremorDoesNotInflateTurns() {
        // 1.5 Hz rotation with a 5 Hz tremor riding on it at 15% amplitude - the band overlap
        // that makes this measurement hard. The filter must not let the tremor create reversals.
        let rotation = sine(cycles: 15, seconds: 10, sampleRate: 100, amplitude: 6)
        let tremor = sine(cycles: 50, seconds: 10, sampleRate: 100, amplitude: 0.9)
        let combined = zip(rotation, tremor).map(+)
        let s = RotationMetrics.summary(angularVelocity: combined, sampleRate: 100)
        #expect(abs((s?.turns ?? 0) - 30) <= 2)
    }

    // MARK: Amplitude is independent of count

    @Test("Fast-and-shallow versus slow-and-full separate on amplitude, not turns")
    func amplitudeIsIndependentOfTurns() {
        // Same number of cycles, one sweeping twice as far per flip.
        let shallow = RotationMetrics.summary(
            angularVelocity: sine(cycles: 15, seconds: 10, sampleRate: 100, amplitude: 3),
            sampleRate: 100)
        let full = RotationMetrics.summary(
            angularVelocity: sine(cycles: 15, seconds: 10, sampleRate: 100, amplitude: 6),
            sampleRate: 100)
        // Turns match...
        #expect(abs((shallow?.turns ?? 0) - (full?.turns ?? 0)) <= 1)
        // ...while amplitude does not. This is exactly why both earn a row and neither is a
        // restatement of the other.
        let ratio = (full?.meanAmplitudeDegrees ?? 0) / (shallow?.meanAmplitudeDegrees ?? 1)
        #expect(abs(ratio - 2) < 0.2)
    }

    @Test("Peak velocity tracks the fastest rotation reached")
    func peakVelocity() {
        let s = RotationMetrics.summary(
            angularVelocity: sine(cycles: 15, seconds: 10, sampleRate: 100, amplitude: 6),
            sampleRate: 100)
        // 6 rad/s is ~344 deg/s; the filter takes a little off the peak.
        let peak = s?.peakVelocityDegreesPerSecond ?? 0
        #expect(peak > 250 && peak < 350)
    }

    // MARK: The PCA axis

    @Test("The rotation axis is found wherever the user actually held their arm")
    func principalAxisFollowsTheMovement() {
        // Rotation entirely about a tilted axis - what happens when someone doesn't hold the
        // phone square. A fixed assumption (say, roll about the device's long edge) would
        // measure only a projection of this and under-report every turn.
        let axis = (x: 0.6, y: 0.8, z: 0.0)
        let rate = sine(cycles: 15, seconds: 10, sampleRate: 100, amplitude: 6)
        let samples = rate.map { (x: $0 * axis.x, y: $0 * axis.y, z: $0 * axis.z) }

        let found = RotationMetrics.principalAxis(samples)
        // Sign is arbitrary for an eigenvector, so compare the absolute alignment.
        let dot = abs(found.x * axis.x + found.y * axis.y + found.z * axis.z)
        #expect(abs(dot - 1) < 0.001)

        // And projecting onto it recovers the full movement, not a fraction of it.
        let projected = RotationMetrics.project(samples, onto: found)
        let recovered = RotationMetrics.summary(angularVelocity: projected, sampleRate: 100)
        #expect(abs((recovered?.turns ?? 0) - 30) <= 1)
    }

    @Test("An off-axis assumption would have under-reported - the axis step earns its place")
    func projectingOntoTheWrongAxisLosesSignal() {
        let axis = (x: 0.6, y: 0.8, z: 0.0)
        let rate = sine(cycles: 15, seconds: 10, sampleRate: 100, amplitude: 6)
        let samples = rate.map { (x: $0 * axis.x, y: $0 * axis.y, z: $0 * axis.z) }

        let onTrue = RotationMetrics.project(samples, onto: RotationMetrics.principalAxis(samples))
        let onAssumed = RotationMetrics.project(samples, onto: (x: 1, y: 0, z: 0))
        let truePeak = onTrue.map(abs).max() ?? 0
        let assumedPeak = onAssumed.map(abs).max() ?? 0
        // Assuming the x axis captures only 60% of a movement made at this angle.
        #expect(assumedPeak < truePeak * 0.7)
    }

    // MARK: Degenerate input

    @Test("A still phone reports no turns rather than noise")
    func stillPhoneReportsNothing() {
        let s = RotationMetrics.summary(angularVelocity: [Double](repeating: 0, count: 1000),
                                        sampleRate: 100)
        #expect(s?.turns == 0)
        #expect(s?.meanAmplitudeDegrees == 0)
    }

    @Test("An unreadable trial returns nil instead of dividing by a zero sample rate")
    func unreadableTrialIsNil() {
        #expect(RotationMetrics.summary(angularVelocity: [1, 2, 3], sampleRate: 0) == nil)
        #expect(RotationMetrics.summary(angularVelocity: [], sampleRate: 100) == nil)
    }
}
