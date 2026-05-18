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

    func sendTremorSamples(_ samples: [TremorSample]) {
        guard WCSession.default.activationState == .activated else {
            print("WCSession not activated — skipping tremor sync (\(samples.count) samples)")
            return
        }

        guard !samples.isEmpty else {
            print("No new tremor samples to sync")
            return
        }

        do {
            let data = try JSONEncoder().encode(samples)
            let payloadKB = data.count / 1024
            let message: [String: Any] = ["tremorSamples": data]
            let sendMessageLimitKB = 60

            if WCSession.default.isReachable && payloadKB < sendMessageLimitKB {
                WCSession.default.sendMessage(message, replyHandler: nil) { error in
                    print("sendMessage failed (\(payloadKB)KB, \(samples.count) samples): \(error) — falling back to transferUserInfo")
                    WCSession.default.transferUserInfo(message)
                }
            } else {
                WCSession.default.transferUserInfo(message)
                print("transferUserInfo queued: \(payloadKB)KB, \(samples.count) samples")
            }
        } catch {
            print("Failed to send tremor data (\(samples.count) samples): \(error)")
        }
    }

    private func handleIncoming(_ payload: [String: Any]) {
        guard payload["requestTremorSync"] as? Bool == true else { return }
        let since = (payload["since"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        Task { @MainActor in
            MovementDisorderManager.shared.queryRecentResults {
                Task { @MainActor in
                    let baselineCutoff = Date().addingTimeInterval(-48 * 3600)
                    let cutoff = max(since ?? baselineCutoff, baselineCutoff)
                    let samples = MovementDisorderManager.shared.recentTremorSamples
                        .filter { $0.timestamp > cutoff }
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
