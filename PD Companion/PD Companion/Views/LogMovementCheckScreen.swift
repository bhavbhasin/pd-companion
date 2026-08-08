import SwiftUI
import SwiftData
import UIKit

// MARK: - Log movement check flow
//
// Both hands, every session — the less-affected hand is the only internal control this
// design has (see docs/design/movement-checks.md). Which hand goes FIRST alternates between
// sessions so the warm-up advantage does not always land on the same side; then the
// result screen shows both. No streak, no schedule, no score: a user who never opens this
// from "+" never sees it, and nothing here nags them back.

/// One shared glyph/tint/protocol-constant set for the "Movement check" category, mirroring
/// TherapyStyle.
enum MovementCheckStyle {
    static let timelineSymbol = "hand.tap.fill"
    static let tint = Color.indigo
    /// Lee et al., PLOS One 2016 — validated against UPDRS bradykinesia subscores. mPower
    /// uses 20 s; 10 s is the one validated against bradykinesia specifically.
    static let trialDuration: TimeInterval = 10
    /// Points-per-millimetre for DRAWING the targets at their protocol size.
    ///
    /// ⚠️ iOS exposes no true physical PPI, so this is an estimate — but not a constant one:
    /// @2x iPhones are 326 ppi (163 points/inch) and @3x iPhones are ~460 ppi (~153
    /// points/inch), so a single 163 drew the targets ~6% oversized on every Pro/Max. Read
    /// time never uses this: a trial's own `layout` recovers its scale from the drawn box,
    /// which is `targetHeightMM` tall by protocol whatever this estimated.
    static func pointsPerMM(displayScale: CGFloat) -> Double {
        let pointsPerInch: Double = displayScale >= 2.5 ? 153.3 : 163.0
        return pointsPerInch / 25.4
    }
    /// Fallback scale for trials captured before geometry was stored. ⛔ Not for new work —
    /// use the trial's `layout`.
    static let legacyPointsPerMM: Double = 163.0 / 25.4
    static let targetWidthMM: Double = 30
    static let targetHeightMM: Double = 45
    static let targetGapMM: Double = 15
}

struct LogMovementCheckScreen: View {
    @Environment(\.modelContext) private var modelContext
    // ⚠️ Only meaningful now that this screen is presented via `.fullScreenCover` (see
    // LogEntrySheet) rather than pushed into an ancestor's NavigationStack — as the root of
    // its own fresh stack there is no ambient "back" destination to fall back on, so Cancel
    // has to be explicit. See the toolbar below.
    @Environment(\.dismiss) private var dismiss
    let onSaved: (Date) -> Void

    private enum Phase: Equatable {
        case instructions
        case capturing(MovementCheckHand)
        case results
    }

    @State private var phase: Phase = .instructions
    @State private var leftTrial: MovementCheckTrial?
    @State private var rightTrial: MovementCheckTrial?
    /// ⚠️ Device feedback (Aug 5 2026): history/trend was reachable ONLY after finishing a
    /// fresh test, so a returning user checking past results had to run a whole new trial
    /// first just to get there. Now on the landing screen itself, alongside Start.
    @State private var showHistory = false
    /// Which hand this session starts with — see `firstHandForThisSession`.
    @State private var firstHand: MovementCheckHand = .left

    var body: some View {
        Group {
            switch phase {
            case .instructions:
                instructions
            case .capturing(let hand):
                // A partial trial's taps are simply discarded on Cancel below; nothing is
                // inserted into the store until `finish()` runs.
                //
                // ⚠️ `.id(hand)` is load-bearing, not decoration. A `switch` inside a
                // ViewBuilder gives each CASE LABEL one persistent identity slot — it does
                // NOT re-key on the associated value. Without this, `.capturing(.left)` →
                // `.capturing(.right)` reuses the same `TapCaptureView` instance, and its
                // `@State` (taps, started, justFinished) leaks across the hand switch: the
                // right-hand screen opened already `justFinished == true` from the left
                // hand's completion, instantly showed a stale "done" overlay with the
                // wrong tap count, and had no live task left to advance past it — a
                // genuine dead end, only escapable via the back button. `.id(hand)` forces
                // SwiftUI to tear down and rebuild fresh state on every hand change.
                TapCaptureView(hand: hand) { trial in
                    complete(hand: hand, trial: trial)
                }
                .id(hand)
            case .results:
                if let leftTrial, let rightTrial {
                    MovementCheckResultScreen(left: leftTrial, right: rightTrial) {
                        onSaved(leftTrial.timestamp)
                    }
                }
            }
        }
        // ⛔ Blank on the instructions screen, deliberately: that screen already names itself
        // in the middle at title size, and carrying "Tapping" in the nav bar too said the same
        // word twice on one screen. The capture and result screens have no such heading, so
        // they keep it.
        .navigationTitle(phase == .instructions ? "" : "Tapping")
        .navigationBarTitleDisplayMode(.inline)
        // Not shown on `.results` — that screen already has its own single, clean "Done"
        // exit (`MovementCheckResultScreen`'s confirmationAction), and a second Cancel
        // beside it would just be two exits fighting for meaning.
        .toolbar {
            if phase != .results {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .navigationDestination(isPresented: $showHistory) {
            MovementCheckHistoryScreen()
        }
    }

    /// ⭐ **Which hand goes first ALTERNATES between sessions, and that is a measurement fix.**
    /// The second hand always benefits from having just warmed up, so a fixed order biases
    /// exactly the number this feature exists for — the between-hands gap. Alternating puts
    /// that advantage on each hand half the time instead of accumulating on one side.
    ///
    /// ⚠️ Nothing new is stored to record the order: both trials carry timestamps, so whichever
    /// is earlier went first. Derived, not duplicated.
    private func firstHandForThisSession() -> MovementCheckHand {
        // `fetchCount`, not a `@Query` — a Query for a count hydrates every row and re-runs
        // on any save.
        let count = (try? modelContext.fetchCount(FetchDescriptor<MovementCheckTrial>())) ?? 0
        return (count / 2) % 2 == 0 ? .left : .right
    }

    private func complete(hand: MovementCheckHand, trial: MovementCheckTrial) {
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

    private var instructions: some View {
        VStack(spacing: 20) {
            Spacer()
            // ⭐ Replaced the static `hand.tap.fill` glyph. A symbol named the category; it did
            // not show that there are TWO targets, that they are stacked, or that the movement is
            // an alternation between them — which is the whole shape of this test. Rotation's
            // instructions screen earns its picture the same way.
            // ⚠️ Full-bleed, no horizontal padding, matching Rotation: the clip carries its own
            // background in both appearances, so at screen width there is no visible video edge.
            // Constraining it would only shrink the targets — the part that has to be legible.
            TapDemoVideo()
                .frame(maxWidth: .infinity)
            Text("Tapping")
                .font(.title2.weight(.semibold))
            // ⚠️ The instruction line is part of the measurement, not UI copy — a trial
            // taken off-table isn't comparable to one taken on it, and the app can't tell
            // the difference. Stated every session, not just the first.
            Text("Set your phone flat on a table. You'll tap two targets with your index finger, one hand at a time, for 10 seconds each.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            // ⛔ The practice-effect disclosure MOVED to the result screen. It is still
            // required by the design doc and still non-negotiable — it exists to stop an
            // improving number reading as a symptom change, so it belongs where the numbers
            // are, not before a test where there is nothing yet to misread.
            Spacer()
            Button {
                firstHand = firstHandForThisSession()
                phase = .capturing(firstHand)
            } label: {
                // ⛔ NOT "Start". The capture screen has its own Start, and that is the one
                // that begins the 10 seconds — you press it with your finger already poised.
                // Two buttons reading "Start" one screen apart made the first one look like it
                // was already timing something. This one only moves you forward.
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(MovementCheckStyle.tint, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)

            // Same entry point the result screen offers, surfaced here too so checking
            // past trials never requires running a new one first.
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

/// Ten seconds of alternating taps for one hand. Two fixed targets sized from the
/// validated protocol's physical dimensions, clamped to whatever the device screen can
/// actually hold — see `TargetLayout`.
private struct TapCaptureView: View {
    let hand: MovementCheckHand
    let onComplete: (MovementCheckTrial) -> Void

    @State private var started = false
    @State private var taps: [MovementCheckTap] = []
    @State private var remaining: TimeInterval = MovementCheckStyle.trialDuration
    @State private var startDate: Date = .now
    @State private var captureTask: Task<Void, Never>?
    /// Which target just registered a tap, for the flash below. Cleared on a short timer —
    /// this is the ONLY per-tap feedback the trial gives, so it has to fire on every tap.
    @State private var flashTarget: Int?
    /// 3, 2, 1 before the clock starts. ⭐ **Not just comfort — it protects the measurement.**
    /// Starting the 10 s on the button press means the finger is still travelling to the first
    /// target while the clock runs, so the opening gap measures reaction time, not tapping
    /// speed, and it rewards whoever felt least rushed. The countdown gives everyone the same
    /// standing start. Taps are ignored until it finishes (`started` is still false).
    @State private var countdown: Int?
    /// The geometry the taps are being captured against, held so `finish()` can store it on
    /// the trial — without it the stored points can't be turned back into distances.
    @State private var capturedLayout: MovementCheckLayout?
    @Environment(\.displayScale) private var displayScale
    /// True for a beat after the 10 s ends, before `onComplete` fires and the screen
    /// changes. Without this the countdown just silently hits 0 and the next screen
    /// silently appears — no visible event marks "that trial is over."
    @State private var justFinished = false

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                // Fixed-height header, measured naturally — NOT a guessed reservation. The
                // targets below get a GeometryReader over the space actually left after
                // this, so the two can never fight over a hand-tuned pixel count again
                // (that's what clipped the second target: the guess undercounted the
                // header's real height).
                VStack(spacing: 6) {
                    Text("\(hand.displayName) hand")
                        .font(.headline)
                    Text(headline)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: remaining)
                        .animation(.snappy, value: countdown)
                    // ⚠️ Fixed after device testing: this used to say "left, then right,
                    // then left", which collided with "Left hand"/"Right hand" meaning a
                    // completely different thing (which physical hand you're using) — the
                    // two boxes are stacked TOP/BOTTOM on screen, never side by side, so
                    // that copy contradicted what was in front of the reader. Now names
                    // the finger AND the actual on-screen order in one sentence.
                    Text(started
                         ? "\(taps.count) tap\(taps.count == 1 ? "" : "s")"
                         : "Using your \(hand.displayName.lowercased()) index finger, tap the boxes alternately - top, then bottom - as fast as you can.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: taps.count)
                }
                .padding(.top)

                GeometryReader { geo in
                    let layout = Self.layout(for: geo.size, displayScale: displayScale)
                    ZStack {
                        targetView(index: 0, layout: layout)
                        targetView(index: 1, layout: layout)
                        // ⚠️ **The live area is the WHOLE surface, not the two rectangles.**
                        // Measured from his own export (Aug 5 2026): the drawn boxes sat ~79
                        // pt apart and 26% of intended BOTTOM-box taps registered nowhere at
                        // all, against 2.9% for the top box — his landings hug the facing
                        // edges, so any undershoot fell in the gap and was silently dropped.
                        // The drawn boxes still carry the validated protocol's dimensions;
                        // this surface just makes sure a touch is never thrown away, and
                        // records where it actually landed so accuracy is measurable instead
                        // of invisible.
                        TapSurface { point in register(at: point, layout: layout) }
                            .allowsHitTesting(started)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { capturedLayout = layout }
                    .onChange(of: geo.size) { capturedLayout = layout }
                }
            }

            if justFinished {
                doneOverlay
            }
        }
        // Pinned OUTSIDE the layout, same pattern as LogEntrySheet's voice button —
        // `.safeAreaInset` carves its own room out of the space the GeometryReader above
        // measures, so the button always sits clear of the home indicator's gesture zone
        // instead of racing it. The earlier bug: Start rendered flush against the bottom
        // edge and taps there were getting eaten by the system swipe-up gesture.
        .safeAreaInset(edge: .bottom) {
            Button(actionLabel) { begin() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isBusy ? Color.secondary.opacity(0.2) : MovementCheckStyle.tint,
                            in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(isBusy ? Color.secondary : Color.white)
                .disabled(isBusy)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.thinMaterial)
        }
        // A tap changes `taps.count`, so this fires the SAME instant the target flashes —
        // sight and touch confirm the same event. iOS 17+ native haptic API, no UIKit needed.
        .sensoryFeedback(.impact(weight: .light), trigger: taps.count)
        // A tick per count, because during the pre-roll your eyes belong on the boxes and your
        // finger on the glass — not on a number at the top of the screen.
        .sensoryFeedback(.selection, trigger: countdown)
        // Same grammar as rotation: firm impact = GO, success pattern = STOP. Your eyes are on
        // the targets, not on the countdown, so the trial's start and end are announced by
        // touch rather than only by a number changing at the top of the screen.
        .sensoryFeedback(.impact(weight: .heavy), trigger: started)
        .sensoryFeedback(.success, trigger: justFinished)
        // ⚠️ **The dead-taps bug, device-found.** `+` opens as a `.sheet`, and a sheet's own
        // interactive drag-to-dismiss is a second, SYSTEM-level gesture recognizer sitting
        // on top of everything in it. A tap made with a tremor carries a little unintended
        // drag — that drag was partially winning the arbitration against `SpatialTapGesture`
        // on some taps, especially reachable ones lower on screen, so the touch fed the
        // sheet's dismiss recognizer instead of the target and the tap was silently lost.
        // Locked only while a trial is actually running (`started`): the instructions and
        // results screens keep the normal swipe-to-dismiss a "+" entry is expected to have.
        .interactiveDismissDisabled(started)
        .onDisappear { captureTask?.cancel() }
    }

    /// Shown for ~0.9s between the countdown hitting 0 and `onComplete` actually firing —
    /// the explicit "yes, that happened" moment the silent auto-advance was missing.
    private var doneOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("\(hand.displayName) hand done")
                .font(.title3.weight(.semibold))
            Text("\(taps.count) taps")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    /// Drawn at the protocol's physical size and positioned from the same `layout` the taps
    /// are measured against, so what the user aims at and what the data says are one thing.
    /// ⛔ Carries no gesture of its own — `TapSurface` above owns every touch. Two recognizers
    /// over the same pixels is what produced the arbitration bugs this screen already ate.
    private func targetView(index: Int, layout: MovementCheckLayout) -> some View {
        let flashing = flashTarget == index
        let rect = layout.rect(for: index)
        // Keyed to `isBusy`, not `started`: the targets brighten as the countdown runs, which
        // is when the user is looking for somewhere to put their finger.
        return RoundedRectangle(cornerRadius: 16)
            .fill(MovementCheckStyle.tint.opacity(flashing ? 0.5 : (isBusy ? 0.18 : 0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(MovementCheckStyle.tint.opacity(isBusy ? 1 : 0.4), lineWidth: 2)
            )
            .scaleEffect(flashing ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: flashing)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityLabel("Target \(index + 1)")
    }

    /// What the big slot shows: the pre-roll count, then the trial clock, then "Ready" again.
    private var headline: String {
        if let countdown { return "\(countdown)" }
        if started { return String(format: "%.0f", remaining.rounded(.up)) }
        return "Ready"
    }

    private var actionLabel: String {
        if started { return "Tapping…" }
        if countdown != nil { return "Get ready…" }
        return "Start"
    }

    /// Pre-roll counts as busy: pressing Start again mid-countdown would restart it.
    private var isBusy: Bool { started || countdown != nil }

    private func begin() {
        guard !started, countdown == nil else { return }
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

    /// ⚠️ `startDate` is set HERE, after the pre-roll, not when the button was pressed — the
    /// 10 s has to start when the user does.
    private func runTrial() async {
        started = true
        taps = []
        startDate = .now
        while !Task.isCancelled {
            let elapsed = Date.now.timeIntervalSince(startDate)
            remaining = max(0, MovementCheckStyle.trialDuration - elapsed)
            if elapsed >= MovementCheckStyle.trialDuration { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) { justFinished = true }
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        finish()
    }

    private func register(at location: CGPoint, layout: MovementCheckLayout) {
        let offset = Date.now.timeIntervalSince(startDate)
        guard offset <= MovementCheckStyle.trialDuration else { return }
        let target = layout.nearestTarget(to: location)
        taps.append(MovementCheckTap(offset: offset, x: location.x, y: location.y, target: target))
        flashTarget = target
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            if flashTarget == target { flashTarget = nil }
        }
    }

    private func finish() {
        onComplete(MovementCheckTrial(timestamp: startDate, hand: hand, taps: taps,
                                      layout: capturedLayout))
    }
}

extension TapCaptureView {
    /// Fits the protocol's 30x45mm targets / 15mm gap into whatever space the device actually
    /// has, shrinking only as far as the screen forces.
    ///
    /// ⚠️ **Full physical fidelity does not fit portrait on the smallest supported device.**
    /// Two 45mm targets plus a 15mm gap is ~105mm of pure target height — taller than an
    /// iPhone SE2's entire 667pt screen before any chrome. This is a per-device best-effort
    /// scale-down, not a silent substitution of a different protocol: a single patient stays
    /// on one physical device for their trial history, so the scale is consistent within their
    /// own "usual range" comparison even though it isn't identical across every iPhone model.
    /// The scale used is stored on the trial, so a reading is never orphaned from it.
    ///
    /// No chrome to subtract here, deliberately: the header sits OUTSIDE this
    /// GeometryReader, sized to its own natural height, and Start lives in a
    /// `.safeAreaInset`. `available` is already exactly what's left for the targets.
    static func layout(for available: CGSize, displayScale: CGFloat) -> MovementCheckLayout {
        let ppmm = MovementCheckStyle.pointsPerMM(displayScale: displayScale)
        let idealWidth = MovementCheckStyle.targetWidthMM * ppmm
        let idealHeight = MovementCheckStyle.targetHeightMM * ppmm
        let idealGap = MovementCheckStyle.targetGapMM * ppmm
        let neededHeight = idealHeight * 2 + idealGap
        let vScale = neededHeight > 0 ? min(1, max(0, available.height) / neededHeight) : 1
        let hScale = idealWidth > 0 ? min(1, max(0, available.width) / idealWidth) : 1
        let scale = min(vScale, hScale)
        return MovementCheckLayout(
            containerSize: available,
            targetSize: CGSize(width: idealWidth * scale, height: idealHeight * scale),
            gap: idealGap * scale
        )
    }
}

/// A bare touch surface: reports the location of every touch-DOWN, and nothing else.
///
/// ⚠️ **Deliberately UIKit, not a SwiftUI gesture.** Every gesture recognizer available here
/// can decline a touch — `SpatialTapGesture` requires a press-and-release that stays roughly
/// still, and a fast or tremor-affected tap that slides is simply discarded. This screen has
/// already lost two rounds of device testing to recognizers dropping or losing arbitration
/// over taps. `touchesBegan` cannot decline: if the finger touched the glass, the tap is in
/// the record.
///
/// Touch-DOWN is also the better timestamp for a speed test than touch-up — release adds a
/// variable dwell that has nothing to do with how fast someone can tap.
private struct TapSurface: UIViewRepresentable {
    let onTouchDown: (CGPoint) -> Void

    func makeUIView(context: Context) -> TouchReportingView {
        let view = TouchReportingView()
        view.backgroundColor = .clear
        // One index finger, one target at a time — a second simultaneous touch would be a
        // palm or a second finger, neither of which is the thing being measured.
        view.isMultipleTouchEnabled = false
        view.onTouchDown = onTouchDown
        return view
    }

    func updateUIView(_ uiView: TouchReportingView, context: Context) {
        uiView.onTouchDown = onTouchDown
    }

    final class TouchReportingView: UIView {
        var onTouchDown: ((CGPoint) -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            onTouchDown?(touch.location(in: self))
        }
    }
}
