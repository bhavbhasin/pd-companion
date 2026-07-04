import WatchConnectivity
import SwiftData
import HealthKit
import Foundation
import Combine

@MainActor
class PhoneConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneConnectivityManager()

    @Published var latestTremorSamples: [TremorSample] = []
    @Published var isWatchPaired = false
    @Published var isWatchAppInstalled = false
    @Published var isWatchReachable = false
    // Drives the "Open Kampa on your Watch" banner when a paired watch that has synced before
    // has gone quiet past the stale threshold. See docs/design/watch-sync-payload-options.md (step 4).
    @Published var syncIsStale = false

    // Hold the container, not a context. A persistent ModelContext from the SwiftUI
    // environment is unreliable on background-launched WCSession callbacks
    // (Apple Developer Forums thread 736305). Construct a fresh ModelContext per
    // delegate invocation instead.
    var modelContainer: ModelContainer?

    // Used only to call startWatchApp(with:) — never to read/save health data here.
    private let healthStore = HKHealthStore()
    // Debounce so rapid foreground/background cycles don't re-launch the Watch app
    // (and light up the wrist) more than once a minute.
    private var lastWatchLaunch: Date?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Re-read live WCSession state. The session's isPaired/isWatchAppInstalled
    /// values are not reliably hydrated at the instant activation completes, and
    /// sessionWatchStateDidChange only fires on a transition — so the flags can
    /// get stuck at a stale `false` even while data flows via application context.
    /// Call this on every foreground to keep the status icon honest.
    func refreshWatchState() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        isWatchPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isWatchReachable = session.isReachable
    }

    /// Wake the Watch app so it can run a CoreMotion query and push tremor data,
    /// even if neither app was open. Uses HKHealthStore.startWatchApp(with:), which
    /// launches the Watch app into a short HKWorkoutSession (see WorkoutSyncCoordinator
    /// on the Watch). The session is never saved as a workout. Call on phone foreground.
    func launchWatchAppForSync() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled else {
            print("[sync] launchWatchAppForSync skipped — not activated / watch app not installed")
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if let last = lastWatchLaunch, Date().timeIntervalSince(last) < 60 {
            print("[sync] launchWatchAppForSync debounced (<60s since last)")
            return
        }
        lastWatchLaunch = Date()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown
        healthStore.startWatchApp(with: config) { success, error in
            if let error {
                print("[sync] startWatchApp failed: \(error.localizedDescription)")
            } else {
                print("[sync] startWatchApp launched Watch app for sync (success=\(success))")
            }
        }
    }

    func requestFreshTremorData() {
        guard WCSession.default.activationState == .activated else { return }

        var payload: [String: Any] = ["requestTremorSync": true]
        if let latest = latestStoredSampleTimestamp() {
            payload["since"] = latest.timeIntervalSince1970
        }

        print("[sync] requestFreshTremorData since=\(payload["since"] as? TimeInterval ?? -1) reachable=\(WCSession.default.isReachable)")

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { error in
                print("[sync] requestFreshTremorData sendMessage failed: \(error.localizedDescription) — falling back to transferUserInfo")
                WCSession.default.transferUserInfo(payload)
            }
        } else {
            WCSession.default.transferUserInfo(payload)
        }
    }

    // MARK: - Sync freshness (in-app banner only)

    // A paired watch that has produced data before but has gone silent this long reads as stale:
    // the Review screen shows a passive banner (no push — a late sync is delayed, not lost; the
    // 7-day gap-recovery backfills). 8h clears a normal overnight off-wrist charge.
    private let staleThresholdHours: Double = 8

    /// Recompute whether watch data has gone stale. Cheap; safe on every foreground and after each
    /// incoming batch. Only flags stale for a paired watch that has synced before — a brand-new
    /// user with no data yet is cold-start, not stale.
    func evaluateSyncFreshness() {
        guard isWatchPaired, let latest = latestStoredSampleTimestamp() else {
            syncIsStale = false
            return
        }
        let hours = Date().timeIntervalSince(latest) / 3600
        syncIsStale = hours > staleThresholdHours
        if syncIsStale {
            print("[sync] stale: \(String(format: "%.1f", hours))h since last watch data")
        }
    }

    private func makeContext() -> ModelContext? {
        guard let container = modelContainer else { return nil }
        return ModelContext(container)
    }

    private func latestStoredSampleTimestamp() -> Date? {
        guard let context = makeContext() else { return nil }
        var descriptor = FetchDescriptor<TremorReading>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.timestamp
    }

    /// Single entry point for an incoming WC payload — extracts both streams (either may be
    /// absent) so every delegate callback handles tremor + dyskinesia identically.
    @discardableResult
    private func processIncoming(_ payload: [String: Any]) -> Bool {
        var handled = false
        if let data = Self.streamData(payload, raw: "tremorSamples", lz: "tremorSamplesLZ") {
            processTremorData(data)
            handled = true
        }
        if let data = Self.streamData(payload, raw: "dyskinesiaSamples", lz: "dyskinesiaSamplesLZ") {
            processDyskinesiaData(data)
            handled = true
        }
        // Fresh data advances the watermark → clears any stale banner state.
        if handled { evaluateSyncFreshness() }
        return handled
    }

    // Extract a stream's JSON, preferring the compressed key (…LZ) and falling back to the
    // legacy raw key so a new phone build still reads an older watch build's payload during a
    // staggered TestFlight update. See docs/design/watch-sync-payload-options.md.
    private static func streamData(_ payload: [String: Any], raw: String, lz: String) -> Data? {
        if let compressed = payload[lz] as? Data { return WCPayload.decompress(compressed) }
        if let plain = payload[raw] as? Data { return plain }
        return nil
    }

    private func processTremorData(_ data: Data) {
        do {
            let samples = try JSONDecoder().decode([TremorSample].self, from: data)
            self.latestTremorSamples = samples
            let inserted = persistSamples(samples)
            print("[sync] processTremorData received=\(samples.count) inserted=\(inserted)")
        } catch {
            print("[sync] Failed to decode tremor data: \(error)")
        }
    }

    private func processDyskinesiaData(_ data: Data) {
        do {
            let samples = try JSONDecoder().decode([DyskinesiaSample].self, from: data)
            let inserted = persistDyskinesiaSamples(samples)
            print("[sync] processDyskinesiaData received=\(samples.count) inserted=\(inserted)")
        } catch {
            print("[sync] Failed to decode dyskinesia data: \(error)")
        }
    }

    @discardableResult
    private func persistSamples(_ samples: [TremorSample]) -> Int {
        guard let context = makeContext() else { return 0 }
        // Dedup only against existing rows within the incoming batch's time span: a
        // duplicate must share a timestamp, which is necessarily inside [lo, hi], so
        // rows outside that window can't collide. Avoids hydrating the whole table on
        // every sync (which grows with the database).
        let times = samples.map { $0.timestamp }
        guard let lo = times.min(), let hi = times.max() else { return 0 }
        let descriptor = FetchDescriptor<TremorReading>(
            predicate: #Predicate { $0.timestamp >= lo && $0.timestamp <= hi }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingTimestamps = Set(existing.map { $0.timestamp })
        var inserted = 0
        for sample in samples where !existingTimestamps.contains(sample.timestamp) {
            context.insert(TremorReading(from: sample))
            inserted += 1
        }
        // Loud save — never swallow a save error. A silent `try?` made a failed persist
        // indistinguishable from "never arrived", hiding the last step of the
        // receive→dedup→insert→save pipeline. See docs/design/watch-sync-payload-options.md (Step 1).
        do {
            try context.save()
            print("[sync] persistSamples saved inserted=\(inserted)")
        } catch {
            print("[sync] persistSamples SAVE FAILED inserted=\(inserted): \(error)")
        }
        return inserted
    }

    @discardableResult
    private func persistDyskinesiaSamples(_ samples: [DyskinesiaSample]) -> Int {
        guard let context = makeContext() else { return 0 }
        // Same targeted dedup as persistSamples: only fetch existing rows in the
        // batch's startDate span instead of the whole DyskinesiaReading table.
        let starts = samples.map { $0.startDate }
        guard let lo = starts.min(), let hi = starts.max() else { return 0 }
        let descriptor = FetchDescriptor<DyskinesiaReading>(
            predicate: #Predicate { $0.startDate >= lo && $0.startDate <= hi }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingStarts = Set(existing.map { $0.startDate })
        var inserted = 0
        for sample in samples where !existingStarts.contains(sample.startDate) {
            context.insert(DyskinesiaReading(from: sample))
            inserted += 1
        }
        // Loud save — see persistSamples above / docs/design/watch-sync-payload-options.md (Step 1).
        do {
            try context.save()
            print("[sync] persistDyskinesiaSamples saved inserted=\(inserted)")
        } catch {
            print("[sync] persistDyskinesiaSamples SAVE FAILED inserted=\(inserted): \(error)")
        }
        return inserted
    }

    func cleanupDuplicates() {
        guard let context = makeContext() else { return }
        guard let all = try? context.fetch(FetchDescriptor<TremorReading>()) else { return }
        var seen: Set<Date> = []
        for reading in all {
            if seen.contains(reading.timestamp) {
                context.delete(reading)
            } else {
                seen.insert(reading.timestamp)
            }
        }
        try? context.save()
    }
}

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let reachable = session.isReachable
        let didActivate = activationState == .activated
        Task { @MainActor in
            self.isWatchPaired = paired
            self.isWatchAppInstalled = installed
            self.isWatchReachable = reachable
            print("[sync] WCSession activated didActivate=\(didActivate) paired=\(paired) installed=\(installed)")
            if didActivate {
                self.requestFreshTremorData()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isWatchReachable = reachable
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            self.isWatchPaired = paired
            self.isWatchAppInstalled = installed
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.processIncoming(message)
        }
    }

    // Ack variant: the Watch's WorkoutSyncCoordinator sends with a reply handler and
    // ends its session the moment we confirm receipt. Persist, then reply.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            let handled = self.processIncoming(message)
            replyHandler(["ack": handled])
        }
    }

    // Ambient backbone receiver. Watch publishes its latest-known samples here;
    // iOS delivers them on the next activation regardless of whether either app
    // was open in between. Pairs with the on-demand message/userInfo handlers.
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            self.processIncoming(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.processIncoming(userInfo)
        }
    }
}
