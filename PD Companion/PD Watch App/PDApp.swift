import SwiftUI

@main
struct PD_Watch_AppApp: App {
    @StateObject private var movementManager = MovementDisorderManager()
    @StateObject private var connectivityManager = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(movementManager)
                .environmentObject(connectivityManager)
                .task {
                    movementManager.checkAvailability()
                    movementManager.startMonitoring()
                    movementManager.queryRecentResults()
                    connectivityManager.activate()
                }
                .onChange(of: movementManager.recentTremorSamples) {
                    connectivityManager.sendTremorSamples(movementManager.recentTremorSamples)
                }
        }
    }
}
