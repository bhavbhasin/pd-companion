import SwiftUI
import SwiftData

@main
struct PD_CompanionApp: App {
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var connectivity = PhoneConnectivityManager.shared
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: TremorReading.self, HealthSnapshot.self, FoodEvent.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            DayInReviewView()
                .environmentObject(healthKit)
                .environmentObject(connectivity)
                .task {
                    connectivity.modelContext = modelContainer.mainContext
                    connectivity.cleanupDuplicates()
                    await healthKit.requestAuthorization()
                    await healthKit.fetchTodaySnapshot()
                    connectivity.activate()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        connectivity.requestFreshTremorData()
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
