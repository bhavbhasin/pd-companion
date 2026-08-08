//
//  SleepSourceReconciliationTests.swift
//  PD CompanionTests
//
//  Rule 1: a moment claimed asleep only by an INFERRING source (one that has never emitted
//  Deep/REM, so it is guessing from stillness) is dropped where a STAGING source was
//  demonstrably sensing and did not call it sleep. Where nothing was sensing, the inferred
//  claim stands.
//
//  The cases below are the ones that decide the design, not a sweep of the API surface:
//
//   - `phantomNapIsDeleted` / `earlyOnsetIsTrimmed` reproduce the two shapes measured on the
//     real record (Jul 8 19:07 and Jul 6 02:14). These FAIL against the pre-Aug-2026 union.
//   - `unwitnessedNightSurvives` is the load-bearing one. It is the ONLY thing standing
//     between this change and the failure `16e6d07` fixed — an unrecorded night letting
//     overnight zeros read as the drug still working, measured once at a 3 h dose reported
//     as 9 h. Deleting it would make every other test here still pass.
//   - `sensingIsExistenceNotLevel` pins that wear is decided by whether readings exist, never
//     by what they say. A tremor threshold here would be circular with the quantity the
//     censoring exists to measure.
//

import Foundation
import Testing
@testable import PD_Companion

struct SleepSourceReconciliationTests {

    static let t0 = Date(timeIntervalSince1970: 1_770_000_000)   // arbitrary, stable

    static func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
    static func iv(_ a: Double, _ b: Double) -> SleepInterval {
        SleepInterval(start: at(a), end: at(b))
    }
    /// Tremor readings once a minute over [from, to) — the watch's real cadence.
    static func worn(_ from: Double, _ to: Double, value: Double = 1.5) -> [TremorPoint] {
        stride(from: from, to: to, by: 1).map {
            TremorPoint(timestamp: at($0), tremorScore: value)
        }
    }
    static func minutes(_ spans: [SleepInterval]) -> Double {
        spans.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }
    }

    // MARK: - The two shapes measured on the real record

    @Test("A phantom nap dies when the watch was worn and called it nothing")
    func phantomNapIsDeleted() {
        // Jul 8 shape: AutoSleep alone claims 19:07-19:41 while the watch is on the wrist
        // reporting tremor at 1.2 throughout, and reports no sleep at all.
        let out = CorrelationEngine.reconcileSleep(
            measured: [],
            inferred: [Self.iv(0, 34)],
            sensing: CorrelationEngine.wearSpans(Self.worn(-60, 120)))

        #expect(out.isEmpty, "an uncorroborated nap under a sensing watch must not survive")
    }

    @Test("An inferred source that starts the night early is trimmed to the stager's onset")
    func earlyOnsetIsTrimmed() {
        // Jul 6 shape: AutoSleep says asleep from 02:14, the watch's first sleep stage is 03:24.
        // Everything before the stager's onset is contradicted; everything after is redundant.
        let out = CorrelationEngine.reconcileSleep(
            measured: [Self.iv(70, 300)],            // watch: 03:24 -> 06:08
            inferred: [Self.iv(0, 250)],             // AutoSleep: 02:14 -> ...
            sensing: CorrelationEngine.wearSpans(Self.worn(-60, 300)))

        #expect(out.count == 1)
        #expect(out.first?.start == Self.at(70), "sleep must start at the stager's onset, not the guess")
        #expect(out.first?.end == Self.at(300))
    }

    // MARK: - The branch that must never be simplified away

    @Test("An unwitnessed night survives — nothing was sensing, so the guess is all we have")
    func unwitnessedNightSurvives() {
        // The watch is off the wrist all night: no tremor readings, no staged sleep. The
        // inferring source is the only evidence and must be believed, or the observation
        // window runs through the small hours and reads overnight zeros as the drug working.
        let out = CorrelationEngine.reconcileSleep(
            measured: [],
            inferred: [Self.iv(0, 480)],
            sensing: CorrelationEngine.wearSpans(Self.worn(-600, -60)))   // worn earlier, then off

        #expect(Self.minutes(out) == 480, "gap-fill is load-bearing: see 16e6d07")
    }

    @Test("A night only partly witnessed keeps the unwitnessed half")
    func partialWitnessKeepsTheGap() {
        // Watch worn until 02:00 then taken off; the inferring source covers 00:00-08:00.
        // 00:00-02:00 is contradicted (sensing, not called sleep); 02:00-08:00 stands.
        let out = CorrelationEngine.reconcileSleep(
            measured: [],
            inferred: [Self.iv(0, 480)],
            sensing: CorrelationEngine.wearSpans(Self.worn(-60, 120)))

        #expect(out.count == 1)
        #expect(out.first?.start == Self.at(120))
        #expect(out.first?.end == Self.at(480))
    }

    // MARK: - Invariants

    @Test("A staging source is never overruled by wear evidence")
    func measuredIsAuthoritative() {
        // Tremor readings exist right through a staged night (they do — tremor is ~0 in sleep,
        // but the watch keeps writing buckets). Measured sleep must survive that untouched.
        let out = CorrelationEngine.reconcileSleep(
            measured: [Self.iv(0, 400)],
            inferred: [],
            sensing: CorrelationEngine.wearSpans(Self.worn(-60, 500, value: 0.0)))

        #expect(Self.minutes(out) == 400)
    }

    @Test("Wear is decided by whether readings exist, never by what they say")
    func sensingIsExistenceNotLevel() {
        // Same span, same count of readings, opposite tremor values. A rule that peeked at the
        // level would diverge here — and would be circular with the quantity being censored.
        let quiet = CorrelationEngine.reconcileSleep(
            measured: [], inferred: [Self.iv(0, 60)],
            sensing: CorrelationEngine.wearSpans(Self.worn(-30, 90, value: 0.0)))
        let loud = CorrelationEngine.reconcileSleep(
            measured: [], inferred: [Self.iv(0, 60)],
            sensing: CorrelationEngine.wearSpans(Self.worn(-30, 90, value: 3.0)))

        #expect(quiet == loud)
        #expect(quiet.isEmpty)
    }

    @Test("With no inferring source at all the timeline is the stager's, unchanged")
    func inferredEmptyIsIdentity() {
        let measured = [Self.iv(0, 100), Self.iv(200, 260)]
        let out = CorrelationEngine.reconcileSleep(
            measured: measured, inferred: [],
            sensing: CorrelationEngine.wearSpans(Self.worn(-100, 400)))

        #expect(out == CorrelationEngine.mergeSleep(measured))
    }

    @Test("Output stays merged and sorted — asleepMinutes' binary search requires it")
    func outputSatisfiesTheMergeContract() {
        let out = CorrelationEngine.reconcileSleep(
            measured: [Self.iv(100, 200), Self.iv(0, 50), Self.iv(190, 240)],
            inferred: [Self.iv(45, 60), Self.iv(500, 600)],
            sensing: CorrelationEngine.wearSpans(Self.worn(0, 300)))

        for (a, b) in zip(out, out.dropFirst()) {
            #expect(a.end < b.start, "intervals must be sorted and disjoint")
        }
    }

    // MARK: - Span algebra

    @Test("subtractSpans handles the four overlap shapes and leaves disjoint spans alone")
    func subtractSpansBoundaries() {
        let span = [Self.iv(0, 100)]
        // Cut the middle out.
        #expect(CorrelationEngine.subtractSpans(span, minus: [Self.iv(40, 60)])
                == [Self.iv(0, 40), Self.iv(60, 100)])
        // Cut the head / the tail.
        #expect(CorrelationEngine.subtractSpans(span, minus: [Self.iv(-10, 30)]) == [Self.iv(30, 100)])
        #expect(CorrelationEngine.subtractSpans(span, minus: [Self.iv(70, 200)]) == [Self.iv(0, 70)])
        // Swallow it whole, and touch it not at all.
        #expect(CorrelationEngine.subtractSpans(span, minus: [Self.iv(-1, 101)]).isEmpty)
        #expect(CorrelationEngine.subtractSpans(span, minus: [Self.iv(100, 200)]) == span)
        #expect(CorrelationEngine.subtractSpans(span, minus: []) == span)
    }

    @Test("wearSpans coalesces a continuous run and breaks on a real gap")
    func wearSpansCoalesceAndBreak() {
        // 60 contiguous minutes, then a 30-minute gap, then 10 more.
        let pts = Self.worn(0, 60) + Self.worn(90, 100)
        let out = CorrelationEngine.wearSpans(pts)

        #expect(out.count == 2, "a gap in wear must not be bridged")
        #expect(out[0].start == Self.at(0))
        #expect(out[0].end == Self.at(60))     // last sample at 59 + its own 60s bucket
        #expect(out[1].start == Self.at(90))
        #expect(out[1].end == Self.at(100))
    }
}
