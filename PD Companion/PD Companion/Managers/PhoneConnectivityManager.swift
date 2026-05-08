import WatchConnectivity
import SwiftData
import Foundation
import Combine

@MainActor
class PhoneConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneConnectivityManager()

    @Published var latestTremorSamples: [TremorSample] = []
    @Published var isWatchReachable = false

    var modelContext: ModelContext?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func processTremorData(_ data: Data) {
        do {
            let samples = try JSONDecoder().decode([TremorSample].self, from: data)
            self.latestTremorSamples = samples
            persistSamples(samples)
        } catch {
            print("Failed to decode tremor data: \(error)")
        }
    }

    private func persistSamples(_ samples: [TremorSample]) {
        guard let context = modelContext else { return }
        for sample in samples {
            let reading = TremorReading(from: sample)
            context.insert(reading)
        }
        try? context.save()
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message["tremorSamples"] as? Data {
            Task { @MainActor in
                self.processTremorData(data)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        if let data = applicationContext["tremorSamples"] as? Data {
            Task { @MainActor in
                self.processTremorData(data)
            }
        }
    }
}
