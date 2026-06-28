import SwiftUI
import SwiftData
import BackgroundTasks
import UIKit

/// Shared container reference so both the SwiftUI App and the AppDelegate
/// resolve to the same SwiftData store. Background-launched WCSession callbacks
/// arrive before any SwiftUI scene activates, so the container must be accessible
/// from the AppDelegate path — not only from a view's `.task` modifier.
enum AppContainer {
    static let shared: ModelContainer = {
        do {
            // .automatic resolves the app's CloudKit container from the iCloud
            // entitlement, syncing TremorReading + FoodEvent to the user's private
            // database for backup + cross-device restore. Requires the iCloud
            // (CloudKit) capability on the iPhone target; the store fails to init
            // without it, so add the capability before running on device.
            let config = ModelConfiguration(cloudKitDatabase: .automatic)
            return try ModelContainer(for: TremorReading.self, FoodEvent.self, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}

final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Wire ModelContainer and activate WCSession *before* any delegate callback
        // can fire. SwiftUI's `.task` modifier is not guaranteed to run on
        // background launches, so connectivity setup cannot live there.
        PhoneConnectivityManager.shared.modelContainer = AppContainer.shared
        PhoneConnectivityManager.shared.activate()
        print("[sync] PhoneAppDelegate launched — WCSession activated, container attached")
        return true
    }
}

@main
struct PD_CompanionApp: App {
    static let tremorSyncTaskID = "com.bhavbhasin.pdcompanion.tremor-sync"

    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var appDelegate
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var connectivity = PhoneConnectivityManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
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
                    // Warm the food classifier off the main thread so the first food
                    // save doesn't pay the one-time index-build cost on the UI.
                    Task.detached(priority: .utility) { _ = FoodAttributeClassifier.shared }
                    // One-time re-classification of existing food entries with the
                    // corrected classifier — runs off the main thread on its own context.
                    FoodAttributeBackfill.runIfNeeded(container: AppContainer.shared)
                    connectivity.cleanupDuplicates()
                    await healthKit.requestAuthorization()
                    await healthKit.fetchTodaySnapshot()
                    Self.scheduleTremorSync()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        connectivity.refreshWatchState()
                        connectivity.requestFreshTremorData()
                        // Wake the Watch app so it can sync without the user opening it.
                        connectivity.launchWatchAppForSync()
                    case .background:
                        Self.scheduleTremorSync()
                    default:
                        break
                    }
                }
        }
        .modelContainer(AppContainer.shared)
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
