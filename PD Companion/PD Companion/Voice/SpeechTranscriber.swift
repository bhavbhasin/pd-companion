import Foundation
import Combine
import Speech
import AVFoundation

/// Live, on-device speech-to-text for the in-app "+" voice logger. This is the
/// reliable voice path: unlike Siri App Shortcuts, nothing arbitrates between intents
/// here — Kampa captures the raw transcript and routes it itself (see `VoiceLogDraft`),
/// so there is no medication/meditation homophone collision.
///
/// On-device recognition is forced when the device supports it, both for the privacy
/// moat (speech never leaves the phone) and so logging works offline. The class is
/// `@MainActor` because it drives `@Published` UI state; the recognition callback hops
/// back onto the main actor before touching anything.
@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published private(set) var transcript: String = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Begin a fresh capture. Requests permission on first use; surfaces a friendly
    /// message (rather than silently failing) if mic/speech access is denied.
    func start() async {
        errorMessage = nil
        transcript = ""

        guard await requestPermissions() else {
            errorMessage = "Kampa needs microphone and speech access. Turn them on in Settings → Kampa."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now. Try again in a moment."
            return
        }

        do {
            try beginAudioCapture(with: recognizer)
            isRecording = true
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            teardown()
        }
    }

    /// Stop capturing but keep the latest transcript so the UI can show the draft.
    func stop() {
        guard isRecording else { return }
        teardown()
    }

    // MARK: - Internals

    private func beginAudioCapture(with recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep speech on-device when possible — privacy moat + offline logging.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // The callback is non-isolated; hop to the main actor before touching state.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.teardown()
                }
            }
        }
    }

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
