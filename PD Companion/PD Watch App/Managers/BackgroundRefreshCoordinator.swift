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

        manager.queryRecentResults {
            Task { @MainActor in
                let samples = MovementDisorderManager.shared.recentTremorSamples
                WatchConnectivityManager.shared.sendTremorSamples(samples)
                BackgroundRefreshCoordinator.shared.scheduleNextRefresh()
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
