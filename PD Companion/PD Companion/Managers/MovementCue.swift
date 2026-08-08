import AVFoundation

/// Audible start/stop cues for the timed movement checks (Tapping and Rotation).
///
/// ⭐ **Why sound at all, when both screens already fire haptics.** Tester feedback (John S,
/// Aug 7 2026) on Rotation: the phone is held flat on your palm at arm's length, so you cannot
/// see the countdown, and a haptic delivered through an outstretched arm to a palm that is
/// itself turning over is easy to miss. Sound is the one channel that survives the posture.
/// Tapping gets the identical cues so a session sounds the same whichever instrument you open.
///
/// The grammar matches the haptics already in place: **one beep = GO, two beeps = STOP.** Count,
/// not pitch, carries the meaning — pitch is the first thing to go at arm's length and with
/// age-related hearing loss, and two events are unmistakable against one.
///
/// ⛔ No audio files. The tones are synthesised into an in-memory WAV at first use, so there is
/// no asset to ship, localise, or keep in sync with the app's build settings.
@MainActor
final class MovementCue {
    static let shared = MovementCue()

    private var startPlayer: AVAudioPlayer?
    private var stopPlayer: AVAudioPlayer?
    private var sessionActive = false

    private init() {}

    /// Call when a trial is about to begin (the pre-roll is the right moment). Builds the
    /// players once, then only re-primes them — `prepareToPlay()` does the buffer allocation and
    /// hardware warm-up up front so `play()` at the instant of GO isn't waiting on either.
    func prepare() {
        if startPlayer == nil {
            startPlayer = try? AVAudioPlayer(data: Self.startTone)
            stopPlayer = try? AVAudioPlayer(data: Self.stopTone)
            startPlayer?.volume = 1
            stopPlayer?.volume = 1
        }
        startPlayer?.prepareToPlay()
        stopPlayer?.prepareToPlay()

        guard !sessionActive else { return }
        // ⚠️ **`.playback` is deliberate: it means the cue is heard with the ring switch set to
        // silent.** Anything else and the fix fails silently for exactly the user who needs it —
        // a phone kept on silent is the normal case, not the edge case, and this cue is the only
        // thing telling them when the measured window opens and closes. `.duckOthers` so a
        // podcast dips rather than stops; the session is deactivated the moment the trial ends,
        // which resumes it.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
        sessionActive = true
    }

    func playStart() { fire(startPlayer) }
    func playStop() { fire(stopPlayer) }

    /// Hands the audio route back. ⚠️ Call only after the stop cue has had time to finish — both
    /// screens hold the "done" beat for 700-900 ms, which is longer than the ~0.4 s cue.
    func release() {
        guard sessionActive else { return }
        sessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fire(_ player: AVAudioPlayer?) {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}

// MARK: - Tone synthesis

private extension MovementCue {
    struct Beep {
        let frequency: Double
        let duration: TimeInterval
        /// Silence appended after this beep, which is what separates a two-beep cue.
        var gapAfter: TimeInterval = 0
    }

    /// 880 Hz (A5) — clear of speech and of most room noise, short enough not to overlap the
    /// first moment of the movement it is starting.
    static let startTone = render([Beep(frequency: 880, duration: 0.20)])

    /// Two beeps, a note lower, so STOP is distinguishable from GO even if the pitch is not.
    static let stopTone = render([
        Beep(frequency: 660, duration: 0.14, gapAfter: 0.09),
        Beep(frequency: 660, duration: 0.14)
    ])

    static let sampleRate = 44_100

    static func render(_ beeps: [Beep]) -> Data {
        var samples: [Int16] = []
        for beep in beeps {
            let count = max(0, Int(beep.duration * Double(sampleRate)))
            // Ramped in and out. A sine that starts and ends at full amplitude produces a step
            // discontinuity, which is audible as a click on top of the tone.
            let attack = max(1, Int(0.008 * Double(sampleRate)))
            let decay = max(1, Int(0.030 * Double(sampleRate)))
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                var envelope = 1.0
                if i < attack { envelope = Double(i) / Double(attack) }
                if i > count - decay { envelope = min(envelope, Double(count - i) / Double(decay)) }
                let value = sin(2 * .pi * beep.frequency * t) * envelope * 0.9
                samples.append(Int16(clamping: Int(value * 32_767)))
            }
            samples.append(contentsOf: repeatElement(0, count: Int(beep.gapAfter * Double(sampleRate))))
        }
        return wav(samples)
    }

    /// Minimal 16-bit mono PCM WAV container — `AVAudioPlayer(data:)` needs a real file format,
    /// not bare samples.
    static func wav(_ samples: [Int16]) -> Data {
        var data = Data()
        func ascii(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        let byteCount = UInt32(samples.count * 2)
        ascii("RIFF"); u32(36 + byteCount); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        ascii("data"); u32(byteCount)
        for sample in samples {
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}
