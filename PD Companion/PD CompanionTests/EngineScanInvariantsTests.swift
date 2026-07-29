//
//  EngineScanInvariantsTests.swift
//  PD CompanionTests
//
//  Two optimizations landed together on Jul 29 2026, both of the same shape — stop rescanning
//  a list from the head — and both required to be OUTPUT-IDENTICAL:
//
//    1. `asleepMinutes` binary-searches its starting interval instead of walking the whole
//       merged sleep list per call.
//    2. `survivalDuration` / `doseResponseByTimeOfDay` skip `signal.sorted { ... }` when the
//       signal is already time-ascending.
//
//  ⚠️ These are NOT fail-first tests and cannot be — the old code passes them by construction.
//  That is the point: they pin that behaviour did not move. The protection against a real
//  regression is `CorrelationEngineParityTests` plus the reference implementation below, which
//  is the pre-change algorithm kept verbatim as an oracle.
//

import Foundation
import Testing
@testable import PD_Companion

struct EngineScanInvariantsTests {

    // MARK: - Deterministic pseudo-randomness (no flaky tests)

    /// Tiny LCG so the fuzz below is reproducible on every machine and every run.
    private struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
        mutating func int(_ range: Range<Int>) -> Int {
            range.lowerBound + Int(next() >> 33) % (range.upperBound - range.lowerBound)
        }
    }

    // MARK: - 1. asleepMinutes

    /// The pre-change implementation, verbatim, as the oracle.
    private static func asleepMinutesLinear(from a: Date, to b: Date,
                                            sleep: [SleepInterval]) -> Double {
        guard b > a, !sleep.isEmpty else { return 0 }
        var total = 0.0
        for iv in sleep {
            if iv.start >= b { break }
            if iv.end <= a { continue }
            total += min(b, iv.end).timeIntervalSince(max(a, iv.start)) / 60
        }
        return total
    }

    /// 300 merged nights, 2,000 pseudo-random windows of wildly varying length and position.
    /// Every one must agree with the linear scan to the femtosecond — this is the same
    /// arithmetic over the same intervals, only reached differently.
    @Test func binarySearchedAsleepMinutesMatchesTheLinearScan() throws {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let day = 24.0 * 3600
        // Nights of varying length, with varying bedtimes — then merged, which is the
        // precondition the binary search relies on.
        var rng = LCG(state: 42)
        var raw: [SleepInterval] = []
        for d in 0..<300 {
            let bedShift = Double(rng.int(-120..<120)) * 60
            let length = Double(rng.int(200..<560)) * 60
            let start = base.addingTimeInterval(Double(d) * day + 23 * 3600 + bedShift)
            raw.append(SleepInterval(start: start, end: start.addingTimeInterval(length)))
            // Occasional nap, so some days carry two intervals.
            if rng.int(0..<4) == 0 {
                let nap = base.addingTimeInterval(Double(d) * day + 14 * 3600)
                raw.append(SleepInterval(start: nap, end: nap.addingTimeInterval(Double(rng.int(20..<150)) * 60)))
            }
        }
        let sleep = CorrelationEngine.mergeSleep(raw)
        #expect(sleep.count > 250, "fixture should produce a long list to search, got \(sleep.count)")

        var checked = 0
        for _ in 0..<2000 {
            let startOffset = Double(rng.int(0..<(300 * 24))) * 3600
            let lengthMin = Double(rng.int(1..<3000))
            let a = base.addingTimeInterval(startOffset)
            let b = a.addingTimeInterval(lengthMin * 60)
            let want = Self.asleepMinutesLinear(from: a, to: b, sleep: sleep)
            let got = CorrelationEngine.asleepMinutes(from: a, to: b, sleep: sleep)
            #expect(got == want,
                    "window \(a) → \(b): binary search says \(got), linear scan says \(want)")
            checked += 1
        }
        #expect(checked == 2000)
    }

    /// The edge cases the binary search could plausibly get wrong, named explicitly rather
    /// than left to the fuzz: a window entirely inside one interval, one that starts before
    /// the first interval, one after the last, one exactly on a boundary, and an empty list.
    @Test func asleepMinutesEdgesAroundIntervalBoundaries() {
        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        func at(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }
        let sleep = CorrelationEngine.mergeSleep([
            SleepInterval(start: at(1), end: at(5)),
            SleepInterval(start: at(10), end: at(12)),
        ])
        func both(_ a: Date, _ b: Date) -> (Double, Double) {
            (CorrelationEngine.asleepMinutes(from: a, to: b, sleep: sleep),
             Self.asleepMinutesLinear(from: a, to: b, sleep: sleep))
        }
        for (a, b, label) in [
            (at(2), at(3), "wholly inside the first interval"),
            (at(0), at(0.5), "entirely before the first interval"),
            (at(20), at(21), "entirely after the last interval"),
            (at(5), at(10), "exactly the gap between two intervals"),
            (at(1), at(5), "exactly one interval"),
            (at(0), at(24), "spanning everything"),
            (at(4), at(11), "straddling two intervals and the gap"),
            (at(12), at(13), "starting exactly at an interval's end"),
        ] {
            let (got, want) = both(a, b)
            #expect(got == want, "\(label): got \(got), want \(want)")
        }
        // Empty list, and a zero-width window.
        #expect(CorrelationEngine.asleepMinutes(from: at(1), to: at(2), sleep: []) == 0)
        #expect(CorrelationEngine.asleepMinutes(from: at(2), to: at(2), sleep: sleep) == 0)
    }

    // MARK: - 2. The skipped sort

    @Test func isTimeAscendingRecognisesOrder() {
        let t = Date(timeIntervalSince1970: 1_750_000_000)
        let asc = (0..<50).map { (time: t.addingTimeInterval(Double($0) * 60), value: 1.0) }
        #expect(CorrelationEngine.isTimeAscending(asc))
        #expect(CorrelationEngine.isTimeAscending([]))
        #expect(CorrelationEngine.isTimeAscending(Array(asc.prefix(1))))
        // Ties are ascending — equal timestamps must not be called out of order, or the
        // primitives would pointlessly re-sort a signal that is already fine.
        let tied = [(time: t, value: 1.0), (time: t, value: 2.0), (time: t, value: 3.0)]
        #expect(CorrelationEngine.isTimeAscending(tied))
        // One element out of place anywhere is enough.
        var broken = asc
        broken.swapAt(10, 40)
        #expect(!CorrelationEngine.isTimeAscending(broken))
        var lastOnly = asc
        lastOnly[49] = (time: t, value: 1.0)
        #expect(!CorrelationEngine.isTimeAscending(lastOnly))
    }

    /// The invariant that matters: whether the caller hands over a sorted signal or a shuffled
    /// one, the primitives must produce the same answer. Sorted input now takes the new
    /// skip-the-sort path; shuffled input still falls through to the sort.
    @Test func primitivesAgreeOnSortedAndShuffledInput() throws {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        var doses: [Date] = []
        var signal: [(time: Date, value: Double)] = []
        for d in 0..<20 {
            for k in 0..<3 {
                doses.append(base.addingTimeInterval(Double(d) * 86400 + Double(8 + k * 4) * 3600))
            }
            var m = 0.0
            while m < 24 * 60 {
                let t = base.addingTimeInterval(Double(d) * 86400 + m * 60)
                // A dip for ~150 min after each of the three doses, OFF otherwise.
                let sinceDose = doses.filter { $0 <= t }.map { t.timeIntervalSince($0) / 60 }.min() ?? 999
                signal.append((time: t, value: sinceDose < 150 ? 0.3 : 1.6))
                m += 5
            }
        }
        var rng = LCG(state: 7)
        var shuffled = signal
        for i in stride(from: shuffled.count - 1, to: 0, by: -1) {
            shuffled.swapAt(i, rng.int(0..<(i + 1)))
        }
        #expect(CorrelationEngine.isTimeAscending(signal))
        #expect(!CorrelationEngine.isTimeAscending(shuffled))

        let a = CorrelationEngine.survivalDuration(
            signal: signal, events: doses, onThreshold: CorrelationEngine.offThreshold)
        let b = CorrelationEngine.survivalDuration(
            signal: shuffled, events: doses, onThreshold: CorrelationEngine.offThreshold)
        #expect(a.kmMedian == b.kmMedian, "KM median: sorted \(a.kmMedian) vs shuffled \(b.kmMedian)")
        #expect(a.observedCount == b.observedCount)
        #expect(a.durations.count == b.durations.count)
        for (x, y) in zip(a.durations, b.durations) {
            #expect(x.durationMin.isNaN == y.durationMin.isNaN)
            if !x.durationMin.isNaN { #expect(x.durationMin == y.durationMin) }
            #expect(x.observed == y.observed)
        }

        let p = CorrelationEngine.doseResponseByTimeOfDay(
            signal: signal, events: doses,
            preMin: CorrelationEngine.preMin, postMin: CorrelationEngine.postMin)
        let q = CorrelationEngine.doseResponseByTimeOfDay(
            signal: shuffled, events: doses,
            preMin: CorrelationEngine.preMin, postMin: CorrelationEngine.postMin)
        #expect(p.traces.count == q.traces.count)
        for (x, y) in zip(p.traces, q.traces) {
            #expect(x.tHalf.isNaN == y.tHalf.isNaN)
            if !x.tHalf.isNaN { #expect(x.tHalf == y.tHalf) }
        }
    }
}
