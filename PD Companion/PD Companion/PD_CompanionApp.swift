import SwiftUI
import SwiftData

@main
struct PD_CompanionApp: App {
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var connectivity = PhoneConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(healthKit)
                .environmentObject(connectivity)
                .modelContainer(for: [TremorReading.self, HealthSnapshot.self])
                .task {
                    await healthKit.requestAuthorization()
                    await healthKit.fetchTodaySnapshot()
                    connectivity.activate()
                }
                .onAppear {
                    if let container = try? ModelContainer(for: TremorReading.self, HealthSnapshot.self) {
                        connectivity.modelContext = container.mainContext
                    }
                }
        }
    }
}
