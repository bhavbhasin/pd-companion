import WatchKit
import Foundation

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            // Initialize on every launch path (foreground OR background-launched by WCSession).
            // SwiftUI .task only runs when a scene activates, which is not guaranteed on
            // background launches — so all delegate-callback prerequisites must live here.
            let movement = MovementDisorderManager.shared
            if !movement.isAvailable {
                movement.checkAvailability()
                movement.startMonitoring()
            }
            WatchConnectivityManager.shared.activate()
            BackgroundRefreshCoordinator.shared.scheduleNextRefresh()
            print("[sync] WatchAppDelegate launched — movement.isAvailable=\(movement.isAvailable)")
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
                    BackgroundRefreshCoordinator.shared.handleRefreshTask(refreshTask)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
