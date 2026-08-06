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
    /// Drives the looping demo on the instructions screen.
    @State private var demoFlipped = false
    /// Which hand this session starts with — see `firstHandForThisSession`.
    @State private var firstHand: MovementCheckHand = .left

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

    /// ⭐ **Which hand goes first ALTERNATES between sessions, and that is a measurement fix.**
    /// The second hand always has the advantage of having just warmed up, so a fixed order
    /// biases exactly the number this feature exists for — the between-hands gap. With the
    /// order alternating, that advantage lands on each hand half the time and averages out
    /// instead of accumulating on one side.
    ///
    /// ⚠️ Nothing new is stored to record the order: both trials carry timestamps, so whichever
    /// is earlier went first. Derived, not duplicated.
    private func firstHandForThisSession() -> MovementCheckHand {
        // `fetchCount` rather than a `@Query` — see reference note: a Query for a count
        // hydrates every row and re-runs on any save.
        let count = (try? modelContext.fetchCount(FetchDescriptor<RotationTrial>())) ?? 0
        return (count / 2) % 2 == 0 ? .left : .right
    }

    private func complete(hand: MovementCheckHand, trial: RotationTrial) {
        modelContext.insert(trial)
        switch hand {
        case .left:  leftTrial = trial
        case .right: rightTrial = trial
        }
        if hand == firstHand {
            phase = .capturing(firstHand == .left ? .right : .left)
        } else {
            try? modelContext.save()
            phase = .results
        }
    }

    /// ⭐ The instruction is DEMONSTRATED, not just described. "Flat on your palm, arm out,
    /// turn it over" is three things to get right at once, and this is the one test where doing
    /// it wrong yields a plausible-looking wrong number rather than an obvious failure.
    ///
    /// ⛔ **Rotates about z (in the plane of the screen), NOT about y.** The first attempt spun
    /// an `iphone` glyph about its vertical axis, which reads as a phone turning like a
    /// revolving door — the wrong movement, with no hand and no context. With the arm pointing
    /// away from you, the forearm's rotation axis points INTO the screen, so an in-plane
    /// rotation is the honest depiction: the phone starts above the palm and ends below it.
    /// Drawn here rather than shipped as a video — no asset to host, works offline, follows
    /// light and dark for free, and it keeps the "no video inside the app" decision intact.
    private var demoIllustration: some View {
        ZStack {
            Capsule()
                .fill(RotationStyle.tint.opacity(0.22))
                .frame(width: 96, height: 46)
            RoundedRectangle(cornerRadius: 6)
                .fill(RotationStyle.tint)
                .frame(width: 36, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemBackground).opacity(0.9))
                        .frame(width: 26, height: 50)
                )
                .offset(y: -16)
        }
        .rotationEffect(.degrees(demoFlipped ? 180 : 0))
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: demoFlipped)
        .frame(height: 110)
        .accessibilityHidden(true)
        .onAppear { demoFlipped = true }
    }

    private var instructions: some View {
        VStack(spacing: 20) {
            Spacer()
            demoIllustration
            Text("Rotation")
                .font(.title2.weight(.semibold))
            // ⚠️ Part of the measurement, not UI copy: the outstretched arm IS the validated
            // posture, and a trial taken with the elbow tucked in isn't comparable to one
            // taken properly. Stated every session — but tightened, because the animation
            // above now carries the shape of the movement and the words don't have to.
            Text("Rest the phone flat on your open palm, arm out in front. Turn it over and back, as fast and as fully as you can - 10 seconds each hand.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            // ⚠️ Safety, and a real risk rather than boilerplate — this is the one test in the
            // app that has you waving an unsecured phone around at arm's length. ⛔ The
            // practice-effect disclosure that used to sit here has MOVED to the result screen:
            // it exists to stop an improving number reading as a symptom change, so it belongs
            // where the numbers are, and two blocks of grey text before a test is one too many.
            Text("Sit down first, over your lap or a sofa, in case the phone slips.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                firstHand = firstHandForThisSession()
                phase = .capturing(firstHand)
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
