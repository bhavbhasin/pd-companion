import SwiftUI

@main
struct PD_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var movementManager = MovementDisorderManager.shared
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(movementManager)
                .environmentObject(connectivityManager)
                .task {
                    // Foreground-only refresh loop. Init lives in WatchAppDelegate so it
                    // runs on background launches too.
                    // Request workout share auth here (foreground = the prompt has UI) so a
                    // later phone-triggered startWatchApp can open a sync session.
                    await WorkoutSyncCoordinator.shared.requestAuthorizationIfNeeded()
                    queryAndSync()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(120))
                        queryAndSync()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        BackgroundRefreshCoordinator.shared.scheduleNextRefresh()
                        queryAndSync()
                    }
                }
        }
    }

    private func queryAndSync() {
        movementManager.queryRecentResults {
            Task { @MainActor in
                let cutoff = Date().addingTimeInterval(-48 * 3600)
                let tremor = MovementDisorderManager.shared.recentTremorSamples
                    .filter { $0.timestamp >= cutoff }
                let dyskinesia = MovementDisorderManager.shared.recentDyskinesiaSamples
                    .filter { $0.startDate >= cutoff }
                WatchConnectivityManager.shared.sendTremorSamples(tremor: tremor, dyskinesia: dyskinesia)
            }
        }
    }
}
