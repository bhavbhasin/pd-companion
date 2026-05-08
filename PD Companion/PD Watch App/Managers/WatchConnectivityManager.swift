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
        guard WCSession.default.activationState == .activated else { return }

        do {
            let data = try JSONEncoder().encode(samples)
            let message: [String: Any] = ["tremorSamples": data]

            if WCSession.default.isReachable {
                WCSession.default.sendMessage(message, replyHandler: nil)
            } else {
                try WCSession.default.updateApplicationContext(message)
            }
        } catch {
            print("Failed to send tremor data: \(error)")
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
