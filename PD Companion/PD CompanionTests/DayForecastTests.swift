//
//  DayForecastTests.swift
//  PD CompanionTests
//
//  Unit tests for the Tier-1 day-ahead forecast (CorrelationEngine.dayForecast) — the
//  wearing-off / dose-response curve run FORWARD from today's logged doses. Synthetic
//  data only (no backup dependency), fully deterministic. The underlying survival + onset
//  primitives are pinned by the parity test; here we test the forward projection, the
//  estimability gate, the observed-vs-projected split, and the uncertainty band.
//

import Foundation
import Testing
@testable import PD_Companion

struct DayForecastTests {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)
    private static let hour = 3600.0

    /// A clean per-dose wearing-off profile (minutes since dose): OFF baseline → ON dip
    /// after onset → ON plateau → rise back to OFF. Varying `plateauEnd` per dose spreads
    /// the ON-durations so the KM median is real and the IQR band is non-zero.
    private static func profile(_ m: Double, plateauEnd: Double) -> Double {
        if m < 0 { return 2.0 }                                   // pre-dose OFF
        if m < 40 { return 2.0 - (m / 40) * 1.6 }                 // onset ramp → 0.4 by 40 min
        if m < plateauEnd { return 0.4 }                          // ON plateau
        if m < plateauEnd + 30 { return 0.4 + ((m - plateauEnd) / 30) * 1.6 } // wear-off ramp
        return 2.0                                                // OFF again
    }

    /// `doseCount` isolated daily doses at 09:00, each with the clean profile densely
    /// sampled every 5 min over [-30, +300]. Returns the full-history corpus the forecast
    /// fits its curve from.
    private static func corpus(doseCount: Int) -> (history: [TremorPoint], doses: [Dose]) {
        var history: [TremorPoint] = []
        var doses: [Dose] = []
        for i in 0..<doseCount {
            let doseTime = base.addingTimeInterval(Double(i) * 24 * hour + 9 * hour)
            doses.append(Dose(timestamp: doseTime, name: "Sinemet"))
            let plateauEnd = 150.0 + Double(i % 5) * 10.0
            for m in stride(from: -30.0, through: 300.0, by: 5.0) {
                history.append(TremorPoint(timestamp: doseTime.addingTimeInterval(m * 60),
                                           tremorScore: profile(m, plateauEnd: plateauEnd)))
            }
        }
        return (history, doses)
    }

    // A synthetic "today": distinct from the corpus days, one dose at 09:00, "now" at 11:00.
    private static let dayStart = base.addingTimeInterval(100 * 24 * hour)
    private static var dayEnd: Date { dayStart.addingTimeInterval(24 * hour) }
    private static var todayDose: Date { dayStart.addingTimeInterval(9 * hour) }
    private static var now: Date { dayStart.addingTimeInterval(11 * hour) }

    /// With an estimable history + a dose logged today, the forecast projects a full-day
    /// timeline and a next-OFF onset after `now` (the dose's ON window wearing off).
    @Test func producesForecastFromLoggedDoses() throws {
        let c = Self.corpus(doseCount: 22)
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [Dose(timestamp: Self.todayDose, name: "Sinemet")],
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))

        #expect(f.confidence == .moderate)                  // n=22: ≥ moderate, < strong(40)
        #expect(!f.segments.isEmpty)
        #expect(f.segments.first?.start == Self.dayStart)   // covers the whole day
        #expect(f.segments.last?.end == Self.dayEnd)

        let off = try #require(f.nextOffStart)
        #expect(off > Self.todayDose)   // OFF only after the dose's ON window
        #expect(off > Self.now)         // still in the future
        #expect(off < Self.dayEnd)
    }

    /// Too little history to estimate the curve → nil (panel hidden), the correct cold-start.
    @Test func hiddenWhenModelNotEstimable() {
        let c = Self.corpus(doseCount: 5)   // < 20 durations → below the gate floor
        #expect(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [Dose(timestamp: Self.todayDose, name: "Sinemet")],
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now) == nil)
    }

    /// No dose logged today AND the substrate is too thin (the corpus only has ~16 clean
    /// dose-free readings/day, under the ~1h floor) → nil. The zero-dose day itself no
    /// longer hides the panel — thin data does (Phase 0, forecast-composition-model.md).
    @Test func hiddenWithoutTodaysDoseWhenSubstrateThin() {
        let c = Self.corpus(doseCount: 22)
        #expect(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [], todaysReadings: [],
            dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now) == nil)
    }

    // MARK: zero-dose flat band (Phase 0)

    /// The dosed corpus + a dense awake dose-free afternoon block each day (hours 14–19,
    /// well past the dose ON window, one reading/min at a stable level with spread).
    /// Enough clean days for the band; the dosed path is untouched by the addition.
    private static func corpusWithSubstrate(doseCount: Int) -> (history: [TremorPoint], doses: [Dose]) {
        var (history, doses) = corpus(doseCount: doseCount)
        for i in 0..<doseCount {
            let day = base.addingTimeInterval(Double(i) * 24 * hour)
            for m in stride(from: 0.0, to: 300.0, by: 1.0) {   // 300 readings/day
                // Levels cycle 1.4 / 1.8 / 2.2 → median 1.8, q25 ≈ 1.4, q75 ≈ 2.2.
                let level = 1.4 + Double(Int(m) % 3) * 0.4
                history.append(TremorPoint(timestamp: day.addingTimeInterval(14 * hour + m * 60),
                                           tremorScore: level))
            }
        }
        return (history, doses)
    }

    /// Zero-dose day with an estimable substrate → the flat-band forecast: band values
    /// from the clean readings, whole-day coverage, a flat `.typical` projection, and no
    /// dose vocabulary (no next-OFF).
    @Test func zeroDoseDayGetsFlatBand() throws {
        let c = Self.corpusWithSubstrate(doseCount: 22)
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [], todaysReadings: [],
            dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))

        let band = try #require(f.band)
        #expect(abs(band.median - 1.8) < 0.05)
        #expect(band.q25 < band.median && band.median < band.q75)
        #expect(band.nDays == 22)
        #expect(f.confidence == .moderate)                  // 22 days: ≥14, <28
        #expect(f.nextOffStart == nil)                      // no dose vocabulary
        #expect(f.segments.first?.start == Self.dayStart)   // covers the whole day
        #expect(f.segments.last?.end == Self.dayEnd)
        // The un-elapsed remainder is the flat band, never ON/OFF.
        let future = f.segments.filter { !$0.observed }
        #expect(!future.isEmpty)
        #expect(future.allSatisfy { $0.phase == .typical })
    }

    /// The elapsed part of a zero-dose day is measured tremor classified against the
    /// band's own upper edge: a morning running clearly above q75 reads `.above`, one
    /// inside the band reads `.typical` — and per the persistence NO-GO, neither changes
    /// the flat projection after `now`.
    @Test func zeroDoseObservedClassifiesAgainstBand() throws {
        let c = Self.corpusWithSubstrate(doseCount: 22)
        var measured: [TremorPoint] = []
        for m in stride(from: 0.0, through: 120.0, by: 5.0) {   // 9:00–11:00, well above q75
            measured.append(TremorPoint(timestamp: Self.todayDose.addingTimeInterval(m * 60),
                                        tremorScore: 3.0))
        }
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [], todaysReadings: measured,
            dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))

        let probe = Self.todayDose.addingTimeInterval(30 * 60)
        let seg = try #require(f.segments.first { probe >= $0.start && probe < $0.end })
        #expect(seg.observed)
        #expect(seg.phase == .above)
        // The rough morning must NOT recenter the remainder (persistence NO-GO).
        #expect(f.segments.filter { !$0.observed }.allSatisfy { $0.phase == .typical })
    }

    /// A never-medicated user (no doses anywhere) gets the same band through the same
    /// code path — medication is an event, not a user trait.
    @Test func unmedicatedUserGetsFlatBand() throws {
        let c = Self.corpusWithSubstrate(doseCount: 22)
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: [],
            todaysDoses: [], todaysReadings: [],
            dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))
        #expect(f.band != nil)
    }

    /// A dosed day carries NO band — the two vocabularies never mix.
    @Test func dosedDayCarriesNoBand() throws {
        let c = Self.corpusWithSubstrate(doseCount: 22)
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [Dose(timestamp: Self.todayDose, name: "Sinemet")],
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))
        #expect(f.band == nil)
        #expect(f.nextOffStart != nil)
    }

    /// Below the cold-start floor (7 clean days) → nil, the honest "learning your rhythm".
    @Test func zeroDoseHiddenBelowColdStartFloor() {
        let c = Self.corpusWithSubstrate(doseCount: 5)
        #expect(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [], todaysReadings: [],
            dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now) == nil)
    }

    /// The elapsed day is drawn from MEASURED tremor, not the projection. If the dose
    /// visibly did NOT work today (tremor stayed OFF where the curve predicts ON), the
    /// past segment reads observed-OFF — reality overrides the forecast up to `now`.
    @Test func measuredPastOverridesProjection() throws {
        let c = Self.corpus(doseCount: 22)
        var measured: [TremorPoint] = []
        for m in stride(from: 0.0, through: 120.0, by: 5.0) {
            measured.append(TremorPoint(timestamp: Self.todayDose.addingTimeInterval(m * 60),
                                        tremorScore: 2.0))   // stayed OFF all morning
        }
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [Dose(timestamp: Self.todayDose, name: "Sinemet")],
            todaysReadings: measured, dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))

        // dose+30min: the projection would call this ON; the measurement says OFF.
        let probe = Self.todayDose.addingTimeInterval(30 * 60)
        let seg = try #require(f.segments.first { probe >= $0.start && probe < $0.end })
        #expect(seg.observed)
        #expect(seg.phase == .off)
    }

    // MARK: de-noise (despeckle)

    typealias Phase = CorrelationEngine.DayForecast.Phase

    /// A lone single-bin flip between two same-phase neighbors is noise → absorbed.
    @Test func despeckleAbsorbsSingleBinBlip() {
        let out = CorrelationEngine.despeckle([.off, .off, .on, .off, .off], minRun: 2)
        #expect(out == [.off, .off, .off, .off, .off])
    }

    /// A genuine ≥2-bin (≥1h) run is a real episode → left intact.
    @Test func despeckleKeepsSustainedRun() {
        let input: [Phase] = [.off, .off, .on, .on, .off, .off]
        #expect(CorrelationEngine.despeckle(input, minRun: 2) == input)
    }

    /// A not-worn gap (unknown) is honest signal, never absorbed; a short run flanked
    /// only by unknown has no evidence to merge into and is left alone.
    @Test func despeckleLeavesGapsIntact() {
        let a: [Phase] = [.on, .on, .unknown, .off, .off]
        #expect(CorrelationEngine.despeckle(a, minRun: 2) == a)
        let b: [Phase] = [.unknown, .on, .unknown]
        #expect(CorrelationEngine.despeckle(b, minRun: 2) == b)
    }

    /// Confidence gate: a lone OFF bin whose severity is a clear margin past the line (Jul 6:
    /// a 30-min wearing-off bin at ~1.6 while flanked by ON) is a REAL episode, not jitter —
    /// so with per-bin means supplied it must survive de-noise instead of being painted ON.
    @Test func despeckleSparesDecisiveShortEpisode() {
        let phases: [Phase] = [.on, .on, .off, .on, .on]
        let means: [Double?] = [0.3, 0.4, 1.6, 0.4, 0.3]   // the lone OFF bin is decisively OFF
        #expect(CorrelationEngine.despeckle(phases, means: means, minRun: 2) == phases)
    }

    /// But a lone OFF bin sitting just past the line (ambiguous, ~1.1) is still treated as a
    /// flip and absorbed — the gate spares decisive episodes, not every one-bin blip.
    @Test func despeckleAbsorbsAmbiguousShortFlip() {
        let phases: [Phase] = [.on, .on, .off, .on, .on]
        let means: [Double?] = [0.3, 0.4, 1.1, 0.4, 0.3]   // barely over the 1.0 line
        #expect(CorrelationEngine.despeckle(phases, means: means, minRun: 2)
                == [.on, .on, .on, .on, .on])
    }

    /// The responsive live-edge read is overlaid on the band's tail so the bar agrees with the
    /// headline: a segment that was ON up to `now` gets its final 15-min window flipped to the
    /// measured OFF, carrying the live severity, while the earlier part stays ON.
    @Test func liveEdgeOverlaysBandTail() {
        let now = Self.now
        let onSeg = CorrelationEngine.DayForecast.Segment(
            start: now.addingTimeInterval(-3600), end: now, phase: .on, observed: true)
        let out = CorrelationEngine.applyLiveEdge([onSeg], live: (.off, 1.8), now: now, windowMin: 15)
        let last = try! #require(out.last)
        #expect(last.phase == .off)
        #expect(last.end == now)
        #expect(last.start == now.addingTimeInterval(-15 * 60))
        #expect(last.meanTremor == 1.8)
        let first = try! #require(out.first)
        #expect(first.phase == .on)                         // earlier part untouched
        #expect(first.end == now.addingTimeInterval(-15 * 60))
    }

    /// nil live read (too little recent data) leaves the band untouched.
    @Test func liveEdgeNoOpWhenNil() {
        let seg = CorrelationEngine.DayForecast.Segment(
            start: Self.dayStart, end: Self.now, phase: .on, observed: true)
        #expect(CorrelationEngine.applyLiveEdge([seg], live: nil, now: Self.now).count == 1)
    }

    // MARK: projected-timeline de-jitter (mergeIntervals gap bridge)

    /// Two consecutive doses whose ON windows leave a sub-bin (<30min) OFF gap between them
    /// must NOT paint a hairline OFF sliver — the projected side gets the same de-jitter floor
    /// the observed side already has. Bridged into one continuous ON.
    @Test func mergeBridgesSubBinGap() {
        let b = Self.base
        let ivs = [(start: b, end: b.addingTimeInterval(60 * 60)),                       // 0–60
                   (start: b.addingTimeInterval(80 * 60), end: b.addingTimeInterval(140 * 60))] // 80–140 (20min gap)
        let out = CorrelationEngine.mergeIntervals(ivs, gapTolSec: 30 * 60)
        #expect(out.count == 1)
        #expect(out.first?.start == b)
        #expect(out.first?.end == b.addingTimeInterval(140 * 60))
    }

    /// A gap LONGER than the tolerance is a real OFF episode → the two ON windows stay separate.
    @Test func mergeKeepsGenuineGap() {
        let b = Self.base
        let ivs = [(start: b, end: b.addingTimeInterval(60 * 60)),                        // 0–60
                   (start: b.addingTimeInterval(105 * 60), end: b.addingTimeInterval(165 * 60))] // 105–165 (45min gap)
        let out = CorrelationEngine.mergeIntervals(ivs, gapTolSec: 30 * 60)
        #expect(out.count == 2)
    }

    /// Default tolerance (0) preserves the original touching-only union: a 1-second gap is kept.
    @Test func mergeDefaultToleranceUnchanged() {
        let b = Self.base
        let ivs = [(start: b, end: b.addingTimeInterval(60 * 60)),
                   (start: b.addingTimeInterval(60 * 60 + 1), end: b.addingTimeInterval(120 * 60))]
        #expect(CorrelationEngine.mergeIntervals(ivs).count == 2)   // not bridged at tol=0
    }

    /// The next-OFF uncertainty band is derived from the spread of observed ON-durations
    /// (IQR), not a hard-coded ±. Varied plateau lengths → a real band bracketing the onset.
    @Test func offRangeSpreadFromDurationSpread() throws {
        let c = Self.corpus(doseCount: 22)
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [Dose(timestamp: Self.todayDose, name: "Sinemet")],
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))

        let off = try #require(f.nextOffStart)
        let range = try #require(f.nextOffRange)
        #expect(range.lowerBound < off)
        #expect(range.upperBound > off)
        #expect(range.contains(off))
    }
}
