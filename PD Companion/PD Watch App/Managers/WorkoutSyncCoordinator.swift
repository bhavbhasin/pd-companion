import HealthKit
import Foundation

/// Drives the "open the iPhone app → Watch syncs without being opened" path.
///
/// The iPhone calls `HKHealthStore.startWatchApp(with:)`, which launches this app
/// and hands `WatchAppDelegate.handle(_:)` an `HKWorkoutConfiguration`. We start a
/// short `HKWorkoutSession` purely to borrow its background-runtime privilege, run a
/// CoreMotion query, push the samples to the phone, and end the session as soon as the
/// phone acks (or a hard timeout fires).
///
/// We deliberately never create an `HKWorkoutBuilder` or call `finishWorkout()`, so
/// **nothing is saved** — no Activity-ring contribution and no phantom workout on the
/// tremor timeline.
@MainActor
final class WorkoutSyncCoordinator: NSObject {
    static let shared = WorkoutSyncCoordinator()

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var timeoutTask: Task<Void, Never>?

    /// Backstop: if the ack never arrives (e.g. phone unreachable), end anyway so the
    /// session can never orphan and drain the battery.
    private let safetyTimeout: TimeInterval = 90

    override init() { super.init() }

    /// Request workout share authorization so we're allowed to start sessions.
    /// Call from a foreground context (the prompt needs UI) — see PDApp `.task`.
    func requestAuthorizationIfNeeded() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        } catch {
            print("[sync] watch workout auth request failed: \(error.localizedDescription)")
        }
    }

    /// Entry point from `WatchAppDelegate.handle(_ workoutConfiguration:)`.
    func startSyncSession(with configuration: HKWorkoutConfiguration) {
        guard session == nil else {
            print("[sync] workout sync already running — ignoring duplicate launch")
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[sync] health data unavailable — cannot start workout sync session")
            return
        }
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.delegate = self
            self.session = session
            session.startActivity(with: Date())
            startTimeout()
            print("[sync] workout sync session startActivity")
        } catch {
            print("[sync] failed to create workout session: \(error.localizedDescription)")
            session = nil
            // Existing WCSession paths still operate; we simply lose the wake benefit.
        }
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [safetyTimeout] in
            try? await Task.sleep(for: .seconds(safetyTimeout))
            guard !Task.isCancelled else { return }
            print("[sync] workout sync safety timeout — ending session")
            WorkoutSyncCoordinator.shared.endSession()
        }
    }

    /// Runs once the session is actually `.running` — query CoreMotion, push, await ack.
    private func runSyncAndAwaitAck() {
        let movement = MovementDisorderManager.shared
        if !movement.isAvailable {
            movement.checkAvailability()
            movement.startMonitoring()
        }
        movement.queryRecentResults {
            Task { @MainActor in
                let cutoff = Date().addingTimeInterval(-48 * 3600)
                let tremor = MovementDisorderManager.shared.recentTremorSamples
                    .filter { $0.timestamp >= cutoff }
                let dyskinesia = MovementDisorderManager.shared.recentDyskinesiaSamples
                    .filter { $0.startDate >= cutoff }
                print("[sync] workout sync sending \(tremor.count) tremor, \(dyskinesia.count) dyskinesia, awaiting ack")
                WatchConnectivityManager.shared.sendTremorSamplesAwaitingAck(
                    tremor: tremor, dyskinesia: dyskinesia
                ) {
                    Task { @MainActor in
                        WorkoutSyncCoordinator.shared.endSession()
                    }
                }
            }
        }
    }

    /// End the session. Idempotent — clearing `session` immediately prevents a double end
    /// from the ack and the timeout racing. Never saves a workout.
    func endSession() {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let session else { return }
        self.session = nil
        session.end()
        print("[sync] workout sync session end requested")
    }
}

extension WorkoutSyncCoordinator: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                WorkoutSyncCoordinator.shared.runSyncAndAwaitAck()
            case .ended, .stopped:
                WorkoutSyncCoordinator.shared.session = nil
                print("[sync] workout sync session reached \(toState == .ended ? "ended" : "stopped")")
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            print("[sync] workout sync session failed: \(error.localizedDescription)")
            WorkoutSyncCoordinator.shared.timeoutTask?.cancel()
            WorkoutSyncCoordinator.shared.timeoutTask = nil
            WorkoutSyncCoordinator.shared.session = nil
        }
    }
}
