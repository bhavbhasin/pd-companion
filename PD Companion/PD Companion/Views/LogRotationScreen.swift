import SwiftUI
import SwiftData
import CoreMotion

// MARK: - Rotation (pronation-supination) flow
//
// The second instrument in the Movement check category. Both hands every session, for the same
// reason as Tapping: the less-affected hand is the only internal control this design has.
// No streak, no schedule, no score.

enum RotationStyle {
    static let timelineSymbol = "arrow.trianglehead.2.clockwise.rotate.90"
    static let tint = Color.teal
    /// Roche's shipped PD Mobile Application v2 uses 10 s per hand. ⚠️ A 20 s variant exists in
    /// the analytical-validation paper; 10 s is the duration that shipped to 316 patients at
    /// ICC 0.92-0.95, and it matches Tapping's 10 s so a session stays a consistent length.
    static let trialDuration: TimeInterval = 10
    /// 100 Hz is CoreMotion's practical ceiling for device motion and ~20x the fastest
    /// plausible rotation rhythm, so reversals are located to within a sample or two.
    static let sampleRate: Double = 100
}

struct LogRotationScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let onSaved: (Date) -> Void

    private enum Phase: Equatable {
        case instructions
        case capturing(MovementCheckHand)
        case results
    }

    @State private var phase: Phase = .instructions
    @State private var leftTrial: RotationTrial?
    @State private var rightTrial: RotationTrial?
    @State private var showHistory = false

    var body: some View {
        Group {
            switch phase {
            case .instructions:
                instructions
            case .capturing(let hand):
                // ⚠️ `.id(hand)` is load-bearing — a `switch` in a ViewBuilder gives each CASE
                // one identity slot, not one per associated value, so without this the second
                // hand reuses the first hand's `@State` and opens mid-flow already "finished".
                // That exact bug cost a device-testing round on the tapping screen.
                RotationCaptureView(hand: hand) { trial in
                    complete(hand: hand, trial: trial)
                }
                .id(hand)
            case .results:
                if let leftTrial, let rightTrial {
                    RotationResultScreen(left: leftTrial, right: rightTrial) {
                        onSaved(leftTrial.timestamp)
                    }
                }
            }
        }
        .navigationTitle(phase == .instructions ? "" : "Rotation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if phase != .results {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .navigationDestination(isPresented: $showHistory) {
            RotationHistoryScreen()
        }
    }

    private func complete(hand: MovementCheckHand, trial: RotationTrial) {
        modelContext.insert(trial)
        switch hand {
        case .left:
            leftTrial = trial
            phase = .capturing(.right)
        case .right:
            rightTrial = trial
            try? modelContext.save()
            phase = .results
        }
    }

    private var instructions: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: RotationStyle.timelineSymbol)
                .font(.system(size: 44))
                .foregroundStyle(RotationStyle.tint)
            Text("Rotation")
                .font(.title2.weight(.semibold))
            // ⚠️ Part of the measurement, not UI copy: the outstretched arm IS the validated
            // posture, and a trial taken with the elbow tucked in isn't comparable to one
            // taken properly. Stated every session.
            Text("Hold your phone flat in one hand, palm up, with your arm stretched out in front of you. Turn your hand palm up and palm down, as fast and as fully as you can, for 10 seconds each hand.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            // ⚠️ Safety, and it is a real risk rather than boilerplate — this is the one test
            // in the app that has you waving an unsecured phone around at arm's length.
            Text("Sit down first, over your lap or a sofa, in case the phone slips.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 32)
            Text("You'll likely get faster over the first few weeks just from practice - that's expected, not a change in your symptoms.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                phase = .capturing(.left)
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RotationStyle.tint, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)

            Button {
                showHistory = true
            } label: {
                Label("History & trend", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Capture

/// Ten seconds of pronation-supination for one hand, recorded from the gyroscope.
private struct RotationCaptureView: View {
    let hand: MovementCheckHand
    let onComplete: (RotationTrial) -> Void

    @State private var started = false
    @State private var countdown: Int?
    @State private var remaining: TimeInterval = RotationStyle.trialDuration
    @State private var startDate: Date = .now
    @State private var captureTask: Task<Void, Never>?
    /// Holds the live device roll, purely so the screen visibly responds while you rotate.
    /// ⚠️ Feedback is not decoration here: the tapping screen's worst device-test round was
    /// "nothing seems to be happening", and this test gives even less inherent feedback because
    /// there is nothing to touch.
    @State private var recorder = MotionRecorder()

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("\(hand.displayName) hand")
                    .font(.headline)
                Text(headline)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: remaining)
                    .animation(.snappy, value: countdown)
                Text(started
                     ? "Keep turning."
                     : "Hold the phone flat on your \(hand.displayName.lowercased()) palm, arm out in front. Turn it palm up and palm down as fast as you can.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top)

            Spacer()

            // The dial turns with the phone. It reports nothing and scores nothing — it exists
            // so a user can see the sensor is live, which is the only confirmation available
            // when there's no target to hit.
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 96))
                .foregroundStyle(isBusy ? RotationStyle.tint : RotationStyle.tint.opacity(0.3))
                .rotation3DEffect(.radians(recorder.currentRoll), axis: (x: 0, y: 1, z: 0))
                .animation(.linear(duration: 0.05), value: recorder.currentRoll)
                .accessibilityHidden(true)

            Spacer()
        }
        .safeAreaInset(edge: .bottom) {
            Button(actionLabel) { begin() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isBusy ? Color.secondary.opacity(0.2) : RotationStyle.tint,
                            in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(isBusy ? Color.secondary : Color.white)
                .disabled(isBusy)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .sensoryFeedback(.selection, trigger: countdown)
        .onDisappear {
            captureTask?.cancel()
            recorder.stop()
        }
    }

    private var headline: String {
        if let countdown { return "\(countdown)" }
        if started { return String(format: "%.0f", remaining.rounded(.up)) }
        return "Ready"
    }

    private var actionLabel: String {
        if started { return "Turning…" }
        if countdown != nil { return "Get ready…" }
        return "Start"
    }

    private var isBusy: Bool { started || countdown != nil }

    private func begin() {
        guard !isBusy else { return }
        // ⭐ The pre-roll matters more here than on the tapping screen: you need both hands
        // free to get the phone flat on your palm and your arm out before the clock starts.
        // Recording begins now so the dial is live during the count and the user can see it
        // working before anything is being measured.
        recorder.start()
        captureTask = Task {
            for n in stride(from: 3, through: 1, by: -1) {
                countdown = n
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            countdown = nil
            await runTrial()
        }
    }

    private func runTrial() async {
        started = true
        startDate = .now
        // ⚠️ Samples collected BEFORE this point (during the pre-roll) are discarded — the
        // trial is the 10 s, not the fumbling beforehand.
        recorder.beginTrial()
        while !Task.isCancelled {
            let elapsed = Date.now.timeIntervalSince(startDate)
            remaining = max(0, RotationStyle.trialDuration - elapsed)
            if elapsed >= RotationStyle.trialDuration { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard !Task.isCancelled else { return }
        let elapsed = Date.now.timeIntervalSince(startDate)
        let samples = recorder.finishTrial()
        recorder.stop()

        // ⚠️ **MEASURED, never the nominal 100 Hz.** CoreMotion treats the update interval as a
        // request, not a contract — it can deliver slower under load or thermal pressure. Every
        // quantity downstream is a rate, so storing a rate the device didn't actually achieve
        // would scale turns and amplitude wrong while nothing on screen looked broken.
        let measuredRate = elapsed > 0 ? Double(samples.count) / elapsed : RotationStyle.sampleRate

        // PCA finds the axis the user actually rotated about, then everything downstream is
        // one channel. See RotationMetrics for why this is what makes the test survive an
        // arm held at whatever angle is comfortable.
        let axis = RotationMetrics.principalAxis(samples)
        let series = RotationMetrics.project(samples, onto: axis)
        onComplete(RotationTrial(timestamp: startDate, hand: hand,
                                 angularVelocity: series,
                                 sampleRate: measuredRate,
                                 axis: axis))
    }
}

/// Wraps `CMMotionManager` for the duration of one trial.
///
/// ⛔ Uses `startDeviceMotionUpdates`, NOT `startGyroUpdates` — device motion is the supported
/// path and hands back a bias-corrected `rotationRate`, where raw gyro output drifts. (The same
/// note in the watch design applies: `isGyroAvailable` has been reported false on hardware that
/// demonstrably has a gyroscope, so never gate on it.)
@Observable
@MainActor
private final class MotionRecorder {
    /// Observed purely to drive the on-screen dial.
    var currentRoll: Double = 0

    private let manager = CMMotionManager()
    private var samples: [(x: Double, y: Double, z: Double)] = []
    private var recording = false

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / RotationStyle.sampleRate
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.currentRoll = motion.attitude.roll
            if self.recording {
                let r = motion.rotationRate
                self.samples.append((x: r.x, y: r.y, z: r.z))
            }
        }
    }

    func beginTrial() {
        samples.removeAll()
        recording = true
    }

    func finishTrial() -> [(x: Double, y: Double, z: Double)] {
        recording = false
        return samples
    }

    func stop() {
        recording = false
        manager.stopDeviceMotionUpdates()
    }
}
