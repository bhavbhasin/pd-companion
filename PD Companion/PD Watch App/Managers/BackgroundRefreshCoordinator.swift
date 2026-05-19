import WatchKit
import Foundation

@MainActor
final class BackgroundRefreshCoordinator {
    static let shared = BackgroundRefreshCoordinator()

    private let preferredInterval: TimeInterval = 30 * 60

    init() {}

    func scheduleNextRefresh() {
        let nextDate = Date().addingTimeInterval(preferredInterval)
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: nextDate,
            userInfo: nil
        ) { error in
            if let error {
                print("scheduleBackgroundRefresh error: \(error.localizedDescription)")
            }
        }
    }

    func handleRefreshTask(_ task: WKApplicationRefreshBackgroundTask) {
        let manager = MovementDisorderManager.shared
        if !manager.isAvailable {
            manager.checkAvailability()
            manager.startMonitoring()
        }
        print("[sync] BG refresh task fired available=\(manager.isAvailable)")

        manager.queryRecentResults {
            Task { @MainActor in
                let cutoff = Date().addingTimeInterval(-48 * 3600)
                let samples = MovementDisorderManager.shared.recentTremorSamples
                    .filter { $0.timestamp >= cutoff }
                print("[sync] BG refresh sending \(samples.count) samples")
                WatchConnectivityManager.shared.sendTremorSamples(samples)
                BackgroundRefreshCoordinator.shared.scheduleNextRefresh()
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
