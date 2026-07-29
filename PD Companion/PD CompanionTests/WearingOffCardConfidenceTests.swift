//
//  WearingOffCardConfidenceTests.swift
//  PD CompanionTests
//
//  The wearing-off card's confidence tier comes from how well the card's OWN CLAIM is
//  known, not from how many doses produced it. docs/design/wearing-off-card-confidence.md.
//
//  The gate this replaced tiered on dose count — Strong at 40 doses, Moderate at 20 — which
//  is the same class of unsourced number the group-3 work exists to remove. The two card
//  tests below are built so the OLD gate and the NEW rule must disagree, in both directions:
//
//    countNoLongerCapsTheTier  30 doses, known to ±2.5  -> was Moderate (n < 40), now Strong
//    wideUncertaintyDemotes    48 doses, known to ±20   -> was Strong (n >= 40), now Moderate
//
//  Both were run against the pre-change engine and observed to fail with exactly the
//  inverted tier ("Got moderate" / "Got strong"); a test that only ever passes proves
//  nothing. So was `precisionIsUnmeasurableWhenEveryDurationIsIdentical` (old: ±2.5 for
//  every n). BACKLOG standing rule, engine changes.
//

import Foundation
import Testing
@testable import PD_Companion

struct WearingOffCardConfidenceTests {

    // MARK: - Helpers

    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private func pinCalendar() { CorrelationEngine.calendar = Self.cal }

    private static func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: day, hour: h, minute: m))!
    }

    /// A tremor series with EXPLICIT per-dose ON windows, so a fixture can control the
    /// spread of measured durations (and therefore how precisely the median is known)
    /// independently of the dose schedule. 5-min steps = the engine's own bin width.
    ///
    /// `1.5` reads as OFF and `0.2` as ON (`offThreshold` = 1.0). Sleep reads as 0.0, which
    /// is how real sleep behaves — but the engine censors at sleep onset regardless.
    private static func series(days: Range<Int>,
                               onWindows: [(start: Date, minutes: Double)],
                               sleep: [SleepInterval]) -> [TremorPoint] {
        let on = onWindows.map { ($0.start, $0.start.addingTimeInterval($0.minutes * 60)) }
        var out: [TremorPoint] = []
        var t = at(days.lowerBound, 0)
        let end = at(days.upperBound - 1, 23, 55)
        while t <= end {
            let score: Double
            if sleep.contains(where: { $0.start <= t && t < $0.end }) {
                score = 0.0
            } else if on.contains(where: { $0.0 <= t && t < $0.1 }) {
                score = 0.2
            } else {
                score = 1.5
            }
            out.append(TremorPoint(timestamp: t, tremorScore: score))
            t = t.addingTimeInterval(5 * 60)
        }
        return out
    }

    /// Nightly sleep, same clock every night.
    private static func nights(_ days: Range<Int>, from: (h: Int, m: Int), to: (h: Int, m: Int))
    -> [SleepInterval] {
        CorrelationEngine.mergeSleep(days.map {
            SleepInterval(start: at($0 - 1, from.h, from.m), end: at($0, to.h, to.m))
        })
    }

    /// The pooled precision and the two ends of the claim, computed the way the card does —
    /// so a test can report WHY a tier came out, not just that it did.
    private static func diagnostics(samples: [TremorPoint], doses: [Dose], sleep: [SleepInterval])
    -> (n: Int, kmMedian: Double, precision: Double) {
        let sig = samples.map { (time: $0.timestamp, value: $0.tremorScore) }
        let lo = samples.map(\.timestamp).min()!, hi = samples.map(\.timestamp).max()!
        let censor = CorrelationEngine.censoringSleep(recorded: sleep, doses: doses.map(\.timestamp),
                                                     covering: lo...hi)
        let s = CorrelationEngine.survivalDuration(signal: sig, events: doses.map(\.timestamp),
                                                   onThreshold: CorrelationEngine.offThreshold,
                                                   sleep: censor)
        return (s.durations.count, s.kmMedian,
                CorrelationEngine.kmMedianPrecisionMin(durations: s.durations.map(\.durationMin),
                                                       observed: s.durations.map(\.observed)))
    }

    // MARK: - The tier rule itself (pure, no fixture)

    /// The rule in isolation: below the clinical bar there is no card at all; above it the
    /// tier is decided by where that bar falls inside the claim's interval.
    @Test func tierRuleReadsTheIntervalAgainstTheMCID() {
        let mcid = CorrelationEngine.wearingOffMCIDMinPerDay   // 60 min/day
        func tier(_ point: Double, _ lower: Double) -> Insight.Confidence? {
            CorrelationEngine.wearingOffCardConfidence(dailyUncovered: point, lowerBound: lower)
        }
        // Below the bar: silence, at any precision. Perceptibility, not confidence.
        #expect(tier(mcid - 1, mcid - 1) == nil)
        #expect(tier(mcid - 1, 0) == nil)
        // Whole interval clears the bar.
        #expect(tier(500, 495) == .strong)
        // Exactly at the bar still counts as clearing it (the firing test is >=).
        #expect(tier(mcid, mcid) == .strong)
        // Point clears, interval straddles.
        #expect(tier(100, mcid - 1) == .moderate)
        #expect(tier(500, 10) == .moderate)
        // Precision unavailable: the claim stands, its firmness does not.
        #expect(tier(500, .nan) == .emerging)
        #expect(tier(mcid, .nan) == .emerging)
        // ...and NaN must not fall through to Moderate, which is what any `<` against NaN
        // would silently do if the guard were ordered after the comparison.
        #expect(tier(500, .nan) != .moderate)
    }

    // MARK: - Precision: measured vs unmeasurable

    /// Every duration IDENTICAL ⇒ the survival curve jumps 1 → 0 in one step and the
    /// estimator never engages. That used to fall through to the ±half-a-bin floor and
    /// report ±2.5 — a resolution claim made on no measurement. It is `.nan` now.
    ///
    /// Driven by TIES, not by sample size: 144 identical durations are as uninformative as 3.
    @Test func precisionIsUnmeasurableWhenEveryDurationIsIdentical() {
        for n in [3, 5, 16, 144] {
            let p = CorrelationEngine.kmMedianPrecisionMin(durations: [Double](repeating: 180, count: n),
                                                           observed: [Bool](repeating: true, count: n))
            #expect(p.isNaN, "\(n) identical durations must not report a precision, got ±\(p)")
        }
    }

    /// The floor is still correct where it was earned: bands WERE computed, none of them
    /// straddled the midpoint, so the interval really is finer than the 5-min grid.
    /// 40 doses clustered on 175/180/185 — the honest ±2.5, not the fabricated one.
    @Test func precisionKeepsTheFloorWhenBandsWereActuallyComputed() {
        let dur = [Double](repeating: 175, count: 14)
            + [Double](repeating: 180, count: 12)
            + [Double](repeating: 185, count: 14)
        let p = CorrelationEngine.kmMedianPrecisionMin(durations: dur,
                                                       observed: [Bool](repeating: true, count: dur.count))
        #expect(abs(p - CorrelationEngine.binMin / 2) < 0.001,
                "a genuinely tight sample keeps the half-bin floor, got ±\(p)")
    }

    // MARK: - The card: dose count no longer caps the tier

    /// 30 doses — under the old gate's 40-dose Strong bar, so it was capped at Moderate no
    /// matter how well the number was known. The claim here is enormous (a once-daily
    /// regimen leaves most of the waking day uncovered) and the duration is tightly
    /// measured, so the whole interval clears the 60 min/day bar: Strong.
    ///
    /// ⚠️ The ON windows deliberately vary (165/170/175) rather than being identical. All-
    /// identical durations are genuinely unmeasurable and would correctly read Emerging —
    /// see `precisionIsUnmeasurableWhenEveryDurationIsIdentical`.
    @Test func countNoLongerCapsTheTier() throws {
        pinCalendar()
        let days = 1..<31
        let doses = days.map { Dose(timestamp: Self.at($0, 8), name: "Sinemet") }
        let sleep = Self.nights(days, from: (23, 0), to: (7, 0))
        let onWindows = doses.enumerated().map {
            (start: $0.element.timestamp, minutes: [165.0, 170.0, 175.0][$0.offset % 3])
        }
        let samples = Self.series(days: days, onWindows: onWindows, sleep: sleep)

        let d = Self.diagnostics(samples: samples, doses: doses, sleep: sleep)
        #expect(d.n == 30, "fixture should produce one duration per dose, got \(d.n)")
        #expect(d.n < 40, "the point of this fixture is to sit under the old 40-dose bar")
        #expect(!d.precision.isNaN, "durations vary, so precision must be measurable")

        let card = try #require(CorrelationEngine.wearingOffInsight(
            samples: samples, doses: doses, sleep: sleep))
        #expect(card.confidence == .strong,
                """
                30 doses, duration known to ±\(d.precision) min (median \(d.kmMedian)): \
                a tightly-known claim must not be capped at Moderate for want of a 40th dose. \
                Got \(String(describing: card.confidence)).
                """)
    }

    // MARK: - The card: wide uncertainty demotes it

    /// The mirror image, and the one that proves precision is really doing the work: plenty
    /// of doses (well past the old 40-dose Strong bar), but the duration is poorly known and
    /// the shortfall is modest — so shifting the duration to the optimistic end of its
    /// interval drops the claim under the 60 min/day bar. Point estimate fires; interval
    /// straddles; Moderate.
    ///
    /// Construction, and every part of it is load-bearing:
    ///   - doses every 4h holding ~222 min ⇒ each daytime gap is nearly covered, so the daily
    ///     shortfall is small (69 min/day) rather than the hundreds a real regimen produces.
    ///     It has to sit just ABOVE the 60 min/day bar for the interval to be able to cross it.
    ///   - ON durations alternate between a graded spread (100/140/180/220) and 300 min, which
    ///     exceeds the 240-min gap and is therefore right-censored by the next dose. The
    ///     grading plus the censoring is what keeps the survival curve shallow through the
    ///     midpoint and leaves the median known only to ±20 min.
    ///
    /// Measured on this fixture: n=48, median 222.5 min, precision ±20, claim 69 min/day.
    /// At the optimistic end (222.5 + 20 = 242.5 min) every daytime gap is fully covered and
    /// only the overnight remainder survives, which is far below the bar ⇒ Moderate.
    ///
    /// ⚠️ Sensitive to the duration spread by design — that IS the thing under test. Widening
    /// it past ~14 days drives the precision back to ±2.5 (more data, better-estimated median)
    /// and the tier back to the boundary. If this test starts failing, read the numbers in the
    /// message before adjusting the fixture: the engine may be right and the fixture stale.
    @Test func wideUncertaintyDemotesTheTier() throws {
        pinCalendar()
        let days = 1..<13
        let doseHours = [(7, 15), (11, 15), (15, 15), (19, 15)]
        let doses = days.flatMap { d in doseHours.map { Dose(timestamp: Self.at(d, $0.0, $0.1), name: "Sinemet") } }
        let sleep = Self.nights(days, from: (23, 0), to: (7, 0))
        let spread: [Double] = [100, 300, 140, 300, 180, 300, 220, 300]
        let onWindows = doses.enumerated().map {
            (start: $0.element.timestamp, minutes: spread[$0.offset % spread.count])
        }
        let samples = Self.series(days: days, onWindows: onWindows, sleep: sleep)

        let d = Self.diagnostics(samples: samples, doses: doses, sleep: sleep)
        #expect(d.n >= 40, "fixture must clear the old 40-dose Strong bar, got \(d.n)")
        #expect(!d.precision.isNaN)
        #expect(d.precision > CorrelationEngine.binMin / 2,
                """
                the point is a WIDE interval; ±\(d.precision) is the floor, so this fixture \
                no longer tests what it claims to
                """)

        let card = try #require(CorrelationEngine.wearingOffInsight(
            samples: samples, doses: doses, sleep: sleep))
        #expect(card.confidence == .moderate,
                """
                \(d.n) doses but duration known only to ±\(d.precision) min (median \(d.kmMedian)): \
                dose count must not buy Strong when the claim's own interval straddles the \
                60 min/day bar. Got \(String(describing: card.confidence)).
                """)
    }
}
