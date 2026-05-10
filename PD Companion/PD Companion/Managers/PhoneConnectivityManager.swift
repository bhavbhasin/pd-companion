import WatchConnectivity
import SwiftData
import Foundation
import Combine

@MainActor
class PhoneConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneConnectivityManager()

    @Published var latestTremorSamples: [TremorSample] = []
    @Published var isWatchPaired = false
    @Published var isWatchAppInstalled = false
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
        let existing = (try? context.fetch(FetchDescriptor<TremorReading>())) ?? []
        let existingTimestamps = Set(existing.map { $0.timestamp })
        for sample in samples where !existingTimestamps.contains(sample.timestamp) {
            context.insert(TremorReading(from: sample))
        }
        try? context.save()
    }

    func cleanupDuplicates() {
        guard let context = modelContext else { return }
        guard let all = try? context.fetch(FetchDescriptor<TremorReading>()) else { return }
        var seen: Set<Date> = []
        for reading in all {
            if seen.contains(reading.timestamp) {
                context.delete(reading)
            } else {
                seen.insert(reading.timestamp)
            }
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
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let reachable = session.isReachable
        Task { @MainActor in
            self.isWatchPaired = paired
            self.isWatchAppInstalled = installed
            self.isWatchReachable = reachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isWatchReachable = reachable
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            self.isWatchPaired = paired
            self.isWatchAppInstalled = installed
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
