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
    func pushLatestContext(_ samples: [TremorSample]) {
        guard WCSession.default.activationState == .activated else { return }
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        let recent = samples.filter { $0.timestamp > cutoff }
        guard !recent.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(recent)
            try WCSession.default.updateApplicationContext(["tremorSamples": data])
            print("[sync] applicationContext updated: \(recent.count) samples")
        } catch {
            print("[sync] updateApplicationContext failed (\(recent.count) samples): \(error.localizedDescription)")
        }
    }

    func sendTremorSamples(_ samples: [TremorSample]) {
        guard WCSession.default.activationState == .activated else {
            print("[sync] WCSession not activated — skipping tremor sync (\(samples.count) samples)")
            return
        }

        guard !samples.isEmpty else {
            print("[sync] No new tremor samples to send")
            return
        }

        do {
            let data = try JSONEncoder().encode(samples)
            let payloadKB = data.count / 1024
            let message: [String: Any] = ["tremorSamples": data]
            let sendMessageLimitKB = 60

            if WCSession.default.isReachable && payloadKB < sendMessageLimitKB {
                WCSession.default.sendMessage(message, replyHandler: nil) { error in
                    print("[sync] sendMessage failed (\(payloadKB)KB, \(samples.count) samples): \(error.localizedDescription) — falling back to transferUserInfo")
                    WCSession.default.transferUserInfo(message)
                }
                print("[sync] sendMessage dispatched: \(payloadKB)KB, \(samples.count) samples")
            } else {
                WCSession.default.transferUserInfo(message)
                print("[sync] transferUserInfo queued: \(payloadKB)KB, \(samples.count) samples")
            }
        } catch {
            print("[sync] Failed to encode tremor data (\(samples.count) samples): \(error)")
        }
    }

    /// Send samples and call `completion` once the phone acks (or we fall back).
    /// Used by WorkoutSyncCoordinator to end its session the moment delivery is confirmed.
    /// When the phone is reachable we use sendMessage's reply handler as the ack; when it
    /// isn't, we queue transferUserInfo (guaranteed eventual delivery) and complete now —
    /// keeping the session open wouldn't help an unreachable phone.
    func sendTremorSamplesAwaitingAck(_ samples: [TremorSample], completion: @escaping @Sendable () -> Void) {
        guard WCSession.default.activationState == .activated else {
            print("[sync] ack-send skipped — WCSession not activated")
            completion()
            return
        }
        guard !samples.isEmpty else {
            print("[sync] ack-send: no samples to send")
            completion()
            return
        }
        do {
            let data = try JSONEncoder().encode(samples)
            let message: [String: Any] = ["tremorSamples": data]
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
        } catch {
            print("[sync] ack-send encode failed: \(error.localizedDescription)")
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
                    let samples = MovementDisorderManager.shared.recentTremorSamples
                        .filter { $0.timestamp > cutoff }
                    print("[sync] handleIncoming sending \(samples.count) samples")
                    WatchConnectivityManager.shared.sendTremorSamples(samples)
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
