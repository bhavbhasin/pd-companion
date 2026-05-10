import WatchKit
import Foundation
import Combine

@MainActor
final class FocusSessionManager: NSObject, ObservableObject {
    static let shared = FocusSessionManager()

    @Published var isActive = false
    @Published var startedAt: Date?
    @Published var willExpireSoon = false

    private var session: WKExtendedRuntimeSession?
    private var queryLoop: Task<Void, Never>?

    private let queryInterval: TimeInterval = 30

    override init() {
        super.init()
    }

    func start() {
        guard !isActive else { return }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        session = s
    }

    func stop() {
        session?.invalidate()
    }

    private func cleanup() {
        queryLoop?.cancel()
        queryLoop = nil
        session = nil
        isActive = false
        startedAt = nil
        willExpireSoon = false
        BackgroundRefreshCoordinator.shared.scheduleNextRefresh()
    }

    private func startQueryLoop() {
        queryLoop?.cancel()
        queryLoop = Task { @MainActor in
            performQuery()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(queryInterval))
                guard !Task.isCancelled else { break }
                performQuery()
            }
        }
    }

    private func performQuery() {
        MovementDisorderManager.shared.queryRecentResults {
            Task { @MainActor in
                let samples = MovementDisorderManager.shared.recentTremorSamples
                WatchConnectivityManager.shared.sendTremorSamples(samples)
            }
        }
    }
}

extension FocusSessionManager: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        Task { @MainActor in
            isActive = true
            startedAt = Date()
            willExpireSoon = false
            startQueryLoop()
            WKInterfaceDevice.current().play(.start)
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {
        Task { @MainActor in
            willExpireSoon = true
            WKInterfaceDevice.current().play(.notification)
        }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        Task { @MainActor in
            cleanup()
            WKInterfaceDevice.current().play(.stop)
        }
    }
}
