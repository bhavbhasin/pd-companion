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
                    movementManager.checkAvailability()
                    movementManager.startMonitoring()
                    connectivityManager.activate()
                    BackgroundRefreshCoordinator.shared.scheduleNextRefresh()
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
                let samples = MovementDisorderManager.shared.recentTremorSamples
                WatchConnectivityManager.shared.sendTremorSamples(samples)
            }
        }
    }
}
