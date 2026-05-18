import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct PD_CompanionApp: App {
    static let tremorSyncTaskID = "com.bhavbhasin.pdcompanion.tremor-sync"

    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var connectivity = PhoneConnectivityManager.shared
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: TremorReading.self, FoodEvent.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.tremorSyncTaskID,
            using: nil
        ) { task in
            Self.handleTremorSyncTask(task as! BGAppRefreshTask)
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
                    Self.scheduleTremorSync()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        connectivity.requestFreshTremorData()
                    case .background:
                        Self.scheduleTremorSync()
                    default:
                        break
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    static func scheduleTremorSync() {
        let request = BGAppRefreshTaskRequest(identifier: tremorSyncTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("scheduleTremorSync submit failed: \(error)")
        }
    }

    static func handleTremorSyncTask(_ task: BGAppRefreshTask) {
        scheduleTremorSync()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task { @MainActor in
            PhoneConnectivityManager.shared.requestFreshTremorData()
            task.setTaskCompleted(success: true)
        }
    }
}
