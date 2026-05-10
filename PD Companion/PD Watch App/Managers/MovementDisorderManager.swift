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
    @Published var error: String?

    init() {}

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
#endif
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

                        var dyskinesiaScore: Double = 0
                        if let matching = dyskinesias.first(where: {
                            abs($0.startDate.timeIntervalSince(tremorResult.startDate)) < 60
                        }) {
                            dyskinesiaScore = Double(matching.percentLikely) / 25.0
                        }

                        samples.append(TremorSample(
                            timestamp: tremorResult.startDate,
                            tremorScore: tremorScore,
                            dyskinesiaScore: dyskinesiaScore
                        ))
                    }

                    self.recentTremorSamples = samples
                    self.lastQueryDate = now
                    completion?()
                }
            }
        }
    }
}
