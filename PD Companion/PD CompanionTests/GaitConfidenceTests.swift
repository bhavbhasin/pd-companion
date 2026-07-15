//
//  GaitConfidenceTests.swift
//  PD CompanionTests
//
//  The absence-claim confidence branch: a card saying "hasn't declined" is scored by
//  whether a meaningful decline is RULED OUT (non-inferiority), not by whether a trend
//  reaches significance. Synthetic data only (no backup dependency), so these run
//  anywhere and are deterministic.
//
//  Origin: the gait card read *Emerging* on 5.8 years of flat data, because a flat slope
//  can never be significant. Design: docs/design/confidence-presence-vs-absence.md
//

import Foundation
import Testing
@testable import PD_Companion

struct GaitConfidenceTests {

    private static let cal = Calendar(identifier: .gregorian)
    private static let start = Date(timeIntervalSince1970: 1_500_000_000)

    /// Build `months` of gait samples (25/month, above the engine's 20 floor) whose
    /// monthly median follows `value(monthIndex)`, plus a deterministic ± jitter so the
    /// fit has residual scatter — without scatter the SE is 0 and every test is trivial.
    private static func series(months: Int, jitter: Double = 0,
                               value: (Int) -> Double) -> [GaitSample] {
        var out: [GaitSample] = []
        for m in 0..<months {
            let monthStart = cal.date(byAdding: .month, value: m, to: start)!
            let base = value(m)
            // Symmetric offsets around `base` keep the MEDIAN exactly `base`; the
            // month-to-month wobble comes from `jitter` via an alternating sign.
            let wobble = jitter * (m % 2 == 0 ? 1 : -1)
            for i in 0..<25 {
                let d = cal.date(byAdding: .day, value: i, to: monthStart)!
                let spread = (Double(i % 5) - 2) * 0.004      // within-month noise
                out.append(GaitSample(date: d, value: base + wobble + spread))
            }
        }
        return out
    }

    /// The other three metrics, held flat so they never fire `anySignificantWorsening`
    /// and the hero metric alone decides the verdict.
    private static func supporting(months: Int) -> [GaitMetric: [GaitSample]] {
        [.stepLength:    series(months: months) { _ in 0.65 },
         .doubleSupport: series(months: months) { _ in 0.25 },
         .asymmetry:     series(months: months) { _ in 0.05 }]
    }

    private static func card(speed: [GaitSample], months: Int) -> Insight? {
        var s = supporting(months: months)
        s[.walkingSpeed] = speed
        return CorrelationEngine.gaitInsight(series: s)
    }

    // MARK: - The origin case

    /// THE REGRESSION TEST. A long, clean, flat record is the case that used to read
    /// Emerging forever: effect ≈ 0 → never significant → capped. Under the absence
    /// branch it earns Strong, because 71 months of flat pins the interval tightly
    /// inside the ±0.06 m/s margin.
    @Test func longFlatRecordIsStrong() throws {
        let speed = Self.series(months: 71, jitter: 0.02) { _ in 1.025 }
        let insight = try #require(Self.card(speed: speed, months: 71))

        #expect(insight.title == "Your mobility hasn't declined")
        #expect(insight.confidence == .strong)
    }

    /// The one-sided point: the card claims "hasn't DECLINED", not "hasn't CHANGED", so a
    /// genuine improvement must not weaken it. A two-sided equivalence test would fail
    /// here — the interval escapes +margin — which would punish good news on a
    /// reassurance card.
    @Test func realImprovementStaysStrong() throws {
        // +4%/5.8y ≈ +0.007 m/s per year: a rise that clears the margin upward.
        let speed = Self.series(months: 71, jitter: 0.02) { m in 1.025 + 0.0007 * Double(m) }
        let insight = try #require(Self.card(speed: speed, months: 71))

        #expect(insight.title == "Your mobility hasn't declined")
        #expect(insight.confidence == .strong)
    }

    // MARK: - Graceful degradation

    /// Thin, noisy data can't establish absence: the interval is too wide to exclude a
    /// meaningful decline, so it stays Emerging. This is the state the old gate wrongly
    /// conflated with "confidently flat" — both used to read Emerging; now only this does.
    /// 20 months is the shortest span that still clears `gaitInsight`'s 1.5-year floor.
    @Test func shortNoisyRecordCannotClaimAbsence() throws {
        let speed = Self.series(months: 20, jitter: 0.09) { _ in 1.025 }
        let insight = try #require(Self.card(speed: speed, months: 20))

        #expect(insight.title == "Your mobility hasn't declined")
        #expect(insight.confidence == .emerging)
    }

    /// A real, significant decline must still route to the PRESENCE branch — the absence
    /// branch must never launder a decline into reassurance.
    @Test func realDeclineIsNotReassurance() throws {
        // −2 cm/s/yr over 6 years — within the range published cohorts report for PD.
        let speed = Self.series(months: 72, jitter: 0.01) { m in 1.10 - 0.00167 * Double(m) }
        let insight = try #require(Self.card(speed: speed, months: 72))

        #expect(insight.title == "Your mobility shows some change")
    }

    // MARK: - The margin rule

    /// Clean/long data resolves well below the clinical floor, so this user CAN speak to a
    /// meaningful change. (Bhav, Jul 2026: own ≈ 0.037 vs MCID 0.06.)
    @Test func cleanDataResolvesTheMCID() throws {
        let speed = Self.series(months: 71, jitter: 0.02) { _ in 1.025 }
        let trend = try #require(CorrelationEngine.metricTrend(.walkingSpeed, samples: speed))

        #expect(trend.ownDetectableMargin < 0.06)
        #expect(trend.canResolveMCID)
        #expect(trend.absenceMargin == 0.06)
    }

    /// The mirror case: a noisy record's own wobble exceeds the MCID, so it cannot resolve
    /// a clinically meaningful change. The margin must NOT follow the noise upward — that
    /// was the circular rule (t ≈ 1.96 always → always Moderate) this test pins against.
    @Test func noisyDataCannotResolveButMarginHoldsFixed() throws {
        let speed = Self.series(months: 20, jitter: 0.09) { _ in 1.025 }
        let trend = try #require(CorrelationEngine.metricTrend(.walkingSpeed, samples: speed))

        #expect(trend.ownDetectableMargin > 0.06)
        #expect(!trend.canResolveMCID)
        #expect(trend.absenceMargin == 0.06)   // fixed clinical floor, never noise-scaled
    }

    // MARK: - The primitive

    /// `nonInferiorityP` against Bhav's actual Jul 2026 gait figures, computed
    /// independently from the CSV export (71 monthly medians, 5.83 y, foreign-device
    /// samples excluded as the app excludes them): change +0.041 m/s, SE 0.0225,
    /// margin 0.06, df 69 → t ≈ 4.48 → one-sided p ≈ 1.4e−5. Well inside Strong (0.01).
    @Test func nonInferiorityPMatchesHandComputedCase() throws {
        let p = try #require(CorrelationEngine.nonInferiorityP(
            change: 0.041, stdErr: 0.0225, margin: 0.06, df: 69))

        #expect(p < 0.01)
        #expect(p > 0)
    }

    /// Direction sanity: an estimate sitting BELOW −margin (a decline worse than the
    /// margin) must produce a large p — absence emphatically not established.
    @Test func nonInferiorityPRejectsRealDecline() throws {
        let p = try #require(CorrelationEngine.nonInferiorityP(
            change: -0.12, stdErr: 0.0187, margin: 0.06, df: 69))

        #expect(p > 0.99)
    }
}
