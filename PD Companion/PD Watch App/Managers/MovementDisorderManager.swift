import CoreMotion
import Foundation
import Combine

@MainActor
final class MovementDisorderManager: ObservableObject {
    static let shared = MovementDisorderManager()

    private var manager: CMMovementDisorderManager?

    @Published var isAvailable = false
    @Published var isMonitoring = false
    @Published var lastQueryDate: Date?
    @Published var recentTremorSamples: [TremorSample] = []
    @Published var recentDyskinesiaSamples: [DyskinesiaSample] = []
    @Published var error: String?
    // Motion & Fitness authorization for the Movement Disorder API. Without it, every
    // query silently returns zero samples — the failure mode Jon hit. We surface this so
    // the UI can say "Motion access needed" instead of a false "Monitoring active".
    @Published var authorizationStatus: CMAuthorizationStatus = .notDetermined

    init() {}

    /// True once we know Motion access is granted. `.notDetermined` is treated as "not yet
    /// blocking" — the first query triggers the system prompt.
    var isAuthorized: Bool { authorizationStatus == .authorized }
    var isMotionDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func checkAvailability() {
#if targetEnvironment(simulator)
        isAvailable = false
        error = "Movement Disorder API requires a real Apple Watch (Series 4 or later). The simulator cannot run this API."
        return
#else
        guard CMMovementDisorderManager.isAvailable() else {
            isAvailable = false
            error = "Movement Disorder API not available on this device. Requires Apple Watch Series 4 or later."
            return
        }
        manager = CMMovementDisorderManager()
        isAvailable = true
        refreshAuthorizationStatus()
#endif
    }

    /// Read the current Motion & Fitness authorization. There is no explicit "request" call
    /// for this API — the prompt is triggered the first time we start monitoring / query, so
    /// we just read status here and re-read after each query to catch the user's response.
    func refreshAuthorizationStatus() {
        authorizationStatus = CMMovementDisorderManager.authorizationStatus()
    }

    func startMonitoring() {
        guard isAvailable, let manager else { return }
        manager.monitorKinesias(forDuration: 7 * 24 * 60 * 60)
        isMonitoring = true
    }

    func queryRecentResults(completion: (@Sendable () -> Void)? = nil) {
        guard isAvailable, let manager else {
            completion?()
            return
        }

        let now = Date()
        let queryStart = Calendar.current.date(byAdding: .day, value: -7, to: now)!

        manager.queryTremor(from: queryStart, to: now) { [weak self] tremorResults, tremorError in
            guard let self, let manager = self.manager else {
                completion?()
                return
            }

            manager.queryDyskineticSymptom(from: queryStart, to: now) { dyskinesiaResults, dyskinesiaError in
                Task { @MainActor in
                    // Re-read auth: the first query is what triggers the system prompt, so
                    // the user's grant/deny lands right after this returns.
                    self.refreshAuthorizationStatus()

                    if let tremorError {
                        self.error = tremorError.localizedDescription
                        completion?()
                        return
                    }

                    let tremors = tremorResults
                    let dyskinesias = dyskinesiaResults

                    var samples: [TremorSample] = []

                    for tremorResult in tremors {
                        let tremorScore = TremorSample.weightedScore(
                            none: tremorResult.percentNone,
                            slight: tremorResult.percentSlight,
                            mild: tremorResult.percentMild,
                            moderate: tremorResult.percentModerate,
                            strong: tremorResult.percentStrong
                        )

                        // Legacy merged dyskinesia score — kept byte-for-byte (incl. the /25
                        // scaling) for engine/UI continuity. The CORRECT raw dyskinesia signal
                        // is captured independently in `dyskinesiaSamples` below; the display
                        // fix that replaces this lives in a separate task.
                        var dyskinesiaScore: Double = 0
                        if let matching = dyskinesias.first(where: {
                            abs($0.startDate.timeIntervalSince(tremorResult.startDate)) < 60
                        }) {
                            dyskinesiaScore = Double(matching.percentLikely) / 25.0
                        }

                        samples.append(TremorSample(
                            timestamp: tremorResult.startDate,
                            tremorScore: tremorScore,
                            dyskinesiaScore: dyskinesiaScore,
                            bucketEnd: tremorResult.endDate,
                            percentUnknown: Double(tremorResult.percentUnknown),
                            percentNone: Double(tremorResult.percentNone),
                            percentSlight: Double(tremorResult.percentSlight),
                            percentMild: Double(tremorResult.percentMild),
                            percentModerate: Double(tremorResult.percentModerate),
                            percentStrong: Double(tremorResult.percentStrong)
                        ))
                    }

                    // Independent raw dyskinesia stream — every bucket, not merged onto tremor.
                    let dyskinesiaSamples: [DyskinesiaSample] = dyskinesias.map { result in
                        DyskinesiaSample(
                            startDate: result.startDate,
                            endDate: result.endDate,
                            percentLikely: Double(result.percentLikely)
                        )
                    }

                    self.error = nil
                    self.recentTremorSamples = samples
                    self.recentDyskinesiaSamples = dyskinesiaSamples
                    self.lastQueryDate = now
                    WatchConnectivityManager.shared.pushLatestContext(
                        tremor: samples, dyskinesia: dyskinesiaSamples
                    )
                    completion?()
                }
            }
        }
    }
}
