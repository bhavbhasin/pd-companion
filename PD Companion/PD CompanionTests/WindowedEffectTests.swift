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
        #expect(boxing.title.localizedCaseInsensitiveContains("tremor"))  // outcome-framed title
        #expect(boxing.summary.localizedCaseInsensitiveContains("lower")) // tremor dropped (in the body now)
        #expect(boxing.confidence == .moderate)                          // n=8 ≥ 5, p ≤ 0.05
        // An activity with no sessions never produces a card.
        #expect(!insights.contains { $0.title.localizedCaseInsensitiveContains("Tango") })
    }

    /// Template instantiation (item 1e): an UNLISTED activity — rowing was never a
    /// hand-wired registry line — now fires a card once it clears the gate, proving the
    /// exercise template stamps a question per observed type. The old 13-entry design
    /// silently dropped rowing no matter how much you rowed. A never-performed activity
    /// still stays silent (only observed types instantiate).
    @Test func templateSurfacesUnlistedActivity() throws {
        let rowingRaw = HKWorkoutActivityType.rowing.rawValue
        var workouts: [WorkoutEvent] = []
        var samples: [TremorPoint] = []
        for i in 0..<8 {
            let start = Self.t0.addingTimeInterval(Double(i) * 24 * Self.hour + 12 * Self.hour)
            workouts.append(WorkoutEvent(start: start, duration: Self.hour, activityRawValue: rowingRaw))
            for m in stride(from: 60.0, through: 10.0, by: -10.0) {
                samples.append(TremorPoint(timestamp: start.addingTimeInterval(-m * 60), tremorScore: 2.0))
            }
            for m in stride(from: 10.0, through: 90.0, by: 10.0) {
                samples.append(TremorPoint(timestamp: start.addingTimeInterval(Self.hour + m * 60),
                                           tremorScore: i % 2 == 0 ? 1.0 : 1.1))
            }
        }
        let insights = CorrelationEngine.generateInsights(
            samples: samples, doses: [], gait: [:], workouts: workouts)
        let rowing = try #require(insights.first { $0.title.localizedCaseInsensitiveContains("Rowing") },
                                  "rowing should card via the template even though it was never hand-wired")
        #expect(rowing.title.localizedCaseInsensitiveContains("tremor"))
        #expect(rowing.summary.localizedCaseInsensitiveContains("lower"))
        // Swimming never performed → no swimming card (only observed types instantiate).
        #expect(!insights.contains { $0.title.localizedCaseInsensitiveContains("Swimming") })
    }

    /// The food cluster's RENDERER path: 8 caffeine intakes with a real post-intake
    /// tremor rise, fed through the caffeine registry entry's windowed-effect renderer,
    /// produce a card — proving the renderer serves food through the generic exposure
    /// resolver, not just workouts (one adapter + one registry line, zero new stats).
    /// Calls `windowedEffectInsight` directly rather than `generateInsights`, so the
    /// test stays valid independent of governance `status`: caffeine is `.candidate`
    /// (dormant) until the dose-confound guard lands, and `status` gates *execution*,
    /// not *renderer capability* — which is what this test is actually about.
    @Test func foodRendererProducesCard() throws {
        let entry = try #require(
            InsightRegistry.starter.first { $0.id == "caffeine-tremor" },
            "caffeine entry should exist in the registry")
        var food: [FoodIntakeEvent] = []
        var samples: [TremorPoint] = []
        for i in 0..<8 {
            let t = Self.t0.addingTimeInterval(Double(i) * 24 * Self.hour + 12 * Self.hour)
            food.append(FoodIntakeEvent(timestamp: t, attributes: [.caffeine]))
            // Pre-window (within the 15-min lead-in): low tremor.
            for m in stride(from: 12.0, through: 2.0, by: -2.0) {
                samples.append(TremorPoint(timestamp: t.addingTimeInterval(-m * 60), tremorScore: 1.0))
            }
            // Post-window (within 120 min after): elevated, slight per-event variance
            // so the t-test runs on real variance.
            for m in stride(from: 10.0, through: 90.0, by: 10.0) {
                samples.append(TremorPoint(timestamp: t.addingTimeInterval(m * 60),
                                           tremorScore: i % 2 == 0 ? 2.0 : 2.1))
            }
        }
        let card = try #require(CorrelationEngine.windowedEffectInsight(
            entry: entry, samples: samples, workouts: [], food: food,
            preMin: 15, postMin: 120))
        #expect(card.title.localizedCaseInsensitiveContains("Caffeine"))
        #expect(card.summary.localizedCaseInsensitiveContains("higher"))  // tremor rose (in the body now)
        #expect(card.confidence == .moderate)                          // n=8 ≥ 5, p ≤ 0.05
        // No food events for the attribute → the renderer yields nil (no card).
        #expect(CorrelationEngine.windowedEffectInsight(
            entry: entry, samples: samples, workouts: [], food: [],
            preMin: 15, postMin: 120) == nil)
    }

    /// The daily-variation yardstick: the median of each day's WITHIN-day spread (SD), not
    /// the spread of daily averages. Two days that each hold {1.0, 3.0} have a within-day SD
    /// of √2; the median is √2. A single qualifying day has no median to speak of → nil.
    /// (This pins the fix for the "0.2 swing" bug — averaging within a day first would
    /// have collapsed this to ~0.)
    @Test func dailyTremorVariationIsMedianWithinDaySpread() throws {
        var samples: [TremorPoint] = []
        for d in 0..<2 {
            let day = Self.t0.addingTimeInterval(Double(d) * 24 * Self.hour)
            samples.append(TremorPoint(timestamp: day, tremorScore: 1.0))
            samples.append(TremorPoint(timestamp: day.addingTimeInterval(600), tremorScore: 3.0))
        }
        let variation = try #require(CorrelationEngine.dailyTremorVariation(samples))
        #expect(abs(variation - 2.0.squareRoot()) < 1e-9)
        // Only one qualifying day → nil.
        #expect(CorrelationEngine.dailyTremorVariation([
            TremorPoint(timestamp: Self.t0, tremorScore: 1.0),
            TremorPoint(timestamp: Self.t0.addingTimeInterval(600), tremorScore: 3.0)]) == nil)
    }

    /// The per-user ON-window wrapper: with no doses there's nothing to estimate from,
    /// so it returns the conservative fallback. (The KM-median path itself is covered by
    /// the wearing-off parity test; its end-to-end effect is verified on device.)
    @Test func doseOnWindowFallsBackWithoutDoses() {
        #expect(CorrelationEngine.doseOnWindowMinutes(samples: [], doses: [])
                == CorrelationEngine.doseOnWindowFallback)
    }

    /// The guard primitive in isolation: an event is dropped iff a dose falls in its
    /// shadow window [start − onWindowMin, end + postMin].
    @Test func doseCleanEventsDropsShadowedEvents() {
        let t = Self.t0
        let events = [(start: t, end: t)]
        // Dose 30 min before → inside the ~190-min lead shadow → dropped.
        #expect(CorrelationEngine.doseCleanEvents(
            events, doses: [Dose(timestamp: t.addingTimeInterval(-30 * 60), name: "Sinemet")],
            postMin: 120).isEmpty)
        // Dose 10 h before → outside the shadow → kept.
        #expect(CorrelationEngine.doseCleanEvents(
            events, doses: [Dose(timestamp: t.addingTimeInterval(-10 * 3600), name: "Sinemet")],
            postMin: 120).count == 1)
        // No doses logged → nothing to control for → kept.
        #expect(CorrelationEngine.doseCleanEvents(events, doses: [], postMin: 120).count == 1)
    }

    /// THE dose-confound guard, end-to-end: the same caffeine "rise," but now every
    /// serving is taken shortly after a levodopa dose (as Bhav's real coffee is). The
    /// guard drops all dose-shadowed servings → nothing clean survives → no card,
    /// instead of a confounded claim. This is the fix for the real "Caffeine eases
    /// your tremor / Strong" card that was actually the medication. With no doses
    /// logged (control), the same data does produce a card.
    @Test func doseConfoundGuardSuppressesDoseAdjacentFood() throws {
        let entry = try #require(InsightRegistry.starter.first { $0.id == "caffeine-tremor" })
        var food: [FoodIntakeEvent] = []
        var samples: [TremorPoint] = []
        var doses: [Dose] = []
        for i in 0..<8 {
            let t = Self.t0.addingTimeInterval(Double(i) * 24 * Self.hour + 12 * Self.hour)
            food.append(FoodIntakeEvent(timestamp: t, attributes: [.caffeine]))
            doses.append(Dose(timestamp: t.addingTimeInterval(-20 * 60), name: "Sinemet")) // 20 min before
            for m in stride(from: 12.0, through: 2.0, by: -2.0) {
                samples.append(TremorPoint(timestamp: t.addingTimeInterval(-m * 60), tremorScore: 1.0))
            }
            for m in stride(from: 10.0, through: 90.0, by: 10.0) {
                samples.append(TremorPoint(timestamp: t.addingTimeInterval(m * 60),
                                           tremorScore: i % 2 == 0 ? 2.0 : 2.1))
            }
        }
        // Every serving dose-shadowed → guard drops all → no honest card.
        #expect(CorrelationEngine.windowedEffectInsight(
            entry: entry, samples: samples, doses: doses, workouts: [], food: food,
            preMin: 15, postMin: 120) == nil)
        // Control: same data, no doses logged → guard keeps everything → card surfaces.
        #expect(CorrelationEngine.windowedEffectInsight(
            entry: entry, samples: samples, doses: [], workouts: [], food: food,
            preMin: 15, postMin: 120) != nil)
    }
}
