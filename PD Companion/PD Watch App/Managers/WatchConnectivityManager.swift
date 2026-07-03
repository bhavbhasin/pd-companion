import WatchConnectivity
import Foundation
import Combine

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    @Published var isReachable = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // Ambient backbone: publish latest-known samples as application context.
    // iOS retains the last value and delivers it on the next iPhone-side
    // activation, even if neither app was open in between. Pairs with the
    // on-demand sendMessage/transferUserInfo path — never trust a single chain.
    /// Build the WC payload carrying both streams. Tremor and dyskinesia ride together
    /// under separate keys so existing transport/size/ack logic is unchanged; an empty
    /// stream simply omits its key (the phone tolerates a missing key).
    // applicationContext is hard-capped (~256KB) and latest-wins, so it carries only a small
    // recent slice as an always-fits ambient heartbeat; bulk/backfill rides transferUserInfo.
    // See docs/design/watch-sync-payload-options.md (Recommendation).
    private let applicationContextWindowHours: Double = 6

    private func makePayload(
        tremor: [TremorSample], dyskinesia: [DyskinesiaSample]
    ) -> [String: Any]? {
        var message: [String: Any] = [:]
        do {
            try Self.addStream(tremor, raw: "tremorSamples", lz: "tremorSamplesLZ", to: &message)
            try Self.addStream(dyskinesia, raw: "dyskinesiaSamples", lz: "dyskinesiaSamplesLZ", to: &message)
        } catch {
            print("[sync] Failed to encode symptom data (t=\(tremor.count) d=\(dyskinesia.count)): \(error)")
            return nil
        }
        return message.isEmpty ? nil : message
    }

    // Encode a stream to JSON, then attach it compressed under the …LZ key when compression
    // succeeds, else raw under the legacy key. Compression is what keeps the payload under
    // WC's size limits; the phone reads either key. See docs/design/watch-sync-payload-options.md.
    private static func addStream<T: Encodable>(
        _ samples: [T], raw: String, lz: String, to message: inout [String: Any]
    ) throws {
        guard !samples.isEmpty else { return }
        let json = try JSONEncoder().encode(samples)
        if let compressed = WCPayload.compress(json) {
            message[lz] = compressed
        } else {
            message[raw] = json
        }
    }

    func pushLatestContext(tremor: [TremorSample], dyskinesia: [DyskinesiaSample]) {
        guard WCSession.default.activationState == .activated else { return }
        let cutoff = Date().addingTimeInterval(-applicationContextWindowHours * 3600)
        let recentTremor = tremor.filter { $0.timestamp > cutoff }
        let recentDyskinesia = dyskinesia.filter { $0.startDate > cutoff }
        guard let message = makePayload(tremor: recentTremor, dyskinesia: recentDyskinesia) else { return }
        do {
            try WCSession.default.updateApplicationContext(message)
            print("[sync] applicationContext updated: \(recentTremor.count) tremor, \(recentDyskinesia.count) dyskinesia (≤\(Int(applicationContextWindowHours))h slice)")
        } catch {
            print("[sync] updateApplicationContext failed (t=\(recentTremor.count) d=\(recentDyskinesia.count)): \(error.localizedDescription)")
        }
    }

    func sendTremorSamples(tremor: [TremorSample], dyskinesia: [DyskinesiaSample]) {
        guard WCSession.default.activationState == .activated else {
            print("[sync] WCSession not activated — skipping symptom sync (t=\(tremor.count) d=\(dyskinesia.count))")
            return
        }

        guard let message = makePayload(tremor: tremor, dyskinesia: dyskinesia) else {
            print("[sync] No new symptom samples to send")
            return
        }

        // Sum every Data value (compressed …LZ or legacy raw keys) so the size gate is
        // key-name agnostic.
        let payloadKB = message.values.compactMap { ($0 as? Data)?.count }.reduce(0, +) / 1024
        let sendMessageLimitKB = 60

        if WCSession.default.isReachable && payloadKB < sendMessageLimitKB {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("[sync] sendMessage failed (\(payloadKB)KB): \(error.localizedDescription) — falling back to transferUserInfo")
                WCSession.default.transferUserInfo(message)
            }
            print("[sync] sendMessage dispatched: \(payloadKB)KB, t=\(tremor.count) d=\(dyskinesia.count)")
        } else {
            WCSession.default.transferUserInfo(message)
            print("[sync] transferUserInfo queued: \(payloadKB)KB, t=\(tremor.count) d=\(dyskinesia.count)")
        }
    }

    /// Send samples and call `completion` once the phone acks (or we fall back).
    /// Used by WorkoutSyncCoordinator to end its session the moment delivery is confirmed.
    /// When the phone is reachable we use sendMessage's reply handler as the ack; when it
    /// isn't, we queue transferUserInfo (guaranteed eventual delivery) and complete now —
    /// keeping the session open wouldn't help an unreachable phone.
    func sendTremorSamplesAwaitingAck(
        tremor: [TremorSample], dyskinesia: [DyskinesiaSample],
        completion: @escaping @Sendable () -> Void
    ) {
        guard WCSession.default.activationState == .activated else {
            print("[sync] ack-send skipped — WCSession not activated")
            completion()
            return
        }
        guard let message = makePayload(tremor: tremor, dyskinesia: dyskinesia) else {
            print("[sync] ack-send: no samples to send")
            completion()
            return
        }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: { _ in
                print("[sync] ack received from phone")
                completion()
            }, errorHandler: { error in
                print("[sync] ack-send failed: \(error.localizedDescription) — transferUserInfo fallback")
                WCSession.default.transferUserInfo(message)
                completion()
            })
        } else {
            print("[sync] phone not reachable — transferUserInfo queued, completing")
            WCSession.default.transferUserInfo(message)
            completion()
        }
    }

    private func handleIncoming(_ payload: [String: Any]) {
        guard payload["requestTremorSync"] as? Bool == true else { return }
        let since = (payload["since"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        Task { @MainActor in
            BackgroundRefreshCoordinator.shared.scheduleNextRefresh()
            // Background-launched delegate callbacks may arrive before the SwiftUI scene
            // has ever activated. Re-init MovementDisorderManager defensively — without
            // this, queryRecentResults bails on a nil internal manager and returns no data.
            let movement = MovementDisorderManager.shared
            if !movement.isAvailable {
                movement.checkAvailability()
                movement.startMonitoring()
            }
            print("[sync] handleIncoming requestTremorSync since=\(since?.description ?? "nil") available=\(movement.isAvailable)")
            movement.queryRecentResults {
                Task { @MainActor in
                    let baselineCutoff = Date().addingTimeInterval(-48 * 3600)
                    let cutoff = max(since ?? baselineCutoff, baselineCutoff)
                    let tremor = MovementDisorderManager.shared.recentTremorSamples
                        .filter { $0.timestamp > cutoff }
                    let dyskinesia = MovementDisorderManager.shared.recentDyskinesiaSamples
                        .filter { $0.startDate > cutoff }
                    print("[sync] handleIncoming sending \(tremor.count) tremor, \(dyskinesia.count) dyskinesia")
                    WatchConnectivityManager.shared.sendTremorSamples(tremor: tremor, dyskinesia: dyskinesia)
                }
            }
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncoming(userInfo)
    }
}
