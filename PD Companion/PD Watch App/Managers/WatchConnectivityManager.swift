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

        do {
            let data = try JSONEncoder().encode(samples)
            let payloadKB = data.count / 1024
            let message: [String: Any] = ["tremorSamples": data]

            if WCSession.default.isReachable {
                WCSession.default.sendMessage(message, replyHandler: nil) { error in
                    print("sendMessage failed (\(payloadKB)KB, \(samples.count) samples): \(error)")
                }
            } else {
                try WCSession.default.updateApplicationContext(message)
                print("updateApplicationContext queued: \(payloadKB)KB, \(samples.count) samples")
            }
        } catch {
            print("Failed to send tremor data (\(samples.count) samples): \(error)")
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
}
