//
//  WindowedEffectTests.swift
//  PD CompanionTests
//
//  Unit tests for the generic windowed-effect primitive — the workhorse behind the
//  exercise/diet registry cluster. Synthetic data only (no backup dependency), so
//  these run anywhere and are fully deterministic.
//

import Foundation
import HealthKit
import Testing
@testable import PD_Companion

struct WindowedEffectTests {

    private static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private static let hour = 3600.0

    /// Build six daily 1-hour events with a fixed pre-window value and post-window
    /// value, so the expected delta is exact.
    private static func scenario(before: Double, after: @escaping (Int) -> Double)
        -> (events: [(start: Date, end: Date)], signal: [(time: Date, value: Double)]) {
        var events: [(start: Date, end: Date)] = []
        var signal: [(time: Date, value: Double)] = []
        for i in 0..<6 {
            let start = t0.addingTimeInterval(Double(i) * 24 * hour + 12 * hour)
            let end = start.addingTimeInterval(hour)
            events.append((start, end))
            for m in stride(from: 60.0, through: 10.0, by: -10.0) {       // pre-window
                signal.append((start.addingTimeInterval(-m * 60), before))
            }
            for m in stride(from: 10.0, through: 90.0, by: 10.0) {        // post-window
                signal.append((end.addingTimeInterval(m * 60), after(i)))
            }
        }
        return (events, signal)
    }

    /// Tremor ~2.0 before each session, dropping to ~1.0 after → clear, significant
    /// negative effect.
    @Test func detectsPostEventDrop() throws {
        let s = Self.scenario(before: 2.0, after: { _ in 1.0 })
        let r = try #require(CorrelationEngine.windowedEffect(
            events: s.events, signal: s.signal, preMin: 90, postMin: 120))
        #expect(r.n == 6)
        #expect(abs(r.meanBefore - 2.0) < 1e-9)
        #expect(abs(r.meanAfter - 1.0) < 1e-9)
        #expect(abs(r.delta - (-1.0)) < 1e-9)
        #expect(abs(r.pctChange - (-50.0)) < 1e-9)
        #expect((r.pValue ?? 1) < 0.001)
    }

    /// No real effect (tiny symmetric noise around baseline) → mean delta ~0 and the
    /// t-test is not significant. The primitive must not manufacture a pattern.
    @Test func nullEffectIsNotSignificant() throws {
        let s = Self.scenario(before: 2.0, after: { i in i % 2 == 0 ? 2.05 : 1.95 })
        let r = try #require(CorrelationEngine.windowedEffect(
            events: s.events, signal: s.signal, preMin: 90, postMin: 120))
        #expect(r.n == 6)
        #expect(abs(r.delta) < 1e-9)
        #expect((r.pValue ?? 0) > 0.05)
    }

    /// Events without signal coverage on a side are skipped; nil when nothing usable.
    @Test func skipsEventsLackingCoverage() {
        let lonelyEvent = [(start: Self.t0, end: Self.t0.addingTimeInterval(Self.hour))]
        let farSignal = [(time: Self.t0.addingTimeInterval(100 * Self.hour), value: 1.0)]
        #expect(CorrelationEngine.windowedEffect(
            events: lonelyEvent, signal: farSignal, preMin: 30, postMin: 60) == nil)
    }

    /// End-to-end dispatch: 8 boxing sessions with a real post-session tremor drop,
    /// fed through `generateInsights`, should surface the boxing card from its
    /// registry line alone — and an activity the user never did stays silent.
    @Test func registrySurfacesExerciseCard() throws {
        let boxingRaw = HKWorkoutActivityType.boxing.rawValue
        var workouts: [WorkoutEvent] = []
        var samples: [TremorPoint] = []
        for i in 0..<8 {
            let start = Self.t0.addingTimeInterval(Double(i) * 24 * Self.hour + 12 * Self.hour)
            let end = start.addingTimeInterval(Self.hour)
            workouts.append(WorkoutEvent(start: start, duration: Self.hour, activityRawValue: boxingRaw))
            for m in stride(from: 60.0, through: 10.0, by: -10.0) {
                samples.append(TremorPoint(timestamp: start.addingTimeInterval(-m * 60), tremorScore: 2.0))
            }
            // Slight per-session variation so the t-test runs on real variance.
            for m in stride(from: 10.0, through: 90.0, by: 10.0) {
                samples.append(TremorPoint(timestamp: end.addingTimeInterval(m * 60),
                                           tremorScore: i % 2 == 0 ? 1.0 : 1.1))
            }
        }
        let insights = CorrelationEngine.generateInsights(
            samples: samples, doses: [], gait: [:], workouts: workouts)

        let boxing = try #require(insights.first { $0.title.localizedCaseInsensitiveContains("Boxing") })
        #expect(boxing.title.localizedCaseInsensitiveContains("ease"))   // tremor dropped
        #expect(boxing.confidence == .moderate)                          // n=8 ≥ 5, p ≤ 0.05
        // An activity with no sessions never produces a card.
        #expect(!insights.contains { $0.title.localizedCaseInsensitiveContains("Tango") })
    }
}
