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

    /// Pin the engine's calendar so day-grouping and the synthesized fallback night are
    /// deterministic regardless of the machine's zone. Swift Testing builds a fresh instance
    /// per test, so this runs for every one.
    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        CorrelationEngine.calendar = c
    }

    /// ⚠️ MIDNIGHT Pacific, not an arbitrary epoch instant (was 1_700_000_000 = 14:13 PST).
    /// Every time in this fixture is expressed as an offset from `base`, so if `base` is not
    /// aligned to a local day boundary then a "09:00" dose is really 23:13 — which lands
    /// inside the 22:00-06:00 night the engine synthesizes for a record with no sleep, and the
    /// dose is dropped as "taken while asleep". Harmless while the observation window was
    /// capped at 5h and censoring was effectively off; load-bearing now that it is not.
    private static let base = Date(timeIntervalSince1970: 1_700_035_200)
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

    /// ⭐ A THIN history still gets a forecast — it is drawn less confidently, never hidden.
    ///
    /// This inverts the old `hiddenWhenModelNotEstimable`, whose premise was literally
    /// "< 20 durations → below the gate floor". That count is gone (group 3): existence is
    /// the mathematical condition alone — did the survival curve actually reach 50% — and how
    /// well it is known travels as `precisionMin` for the drawing to use.
    ///
    /// It also closes the estimability cliff: the panel used to appear on a ZERO-dose day
    /// (flat band) and vanish at 1-19 doses, so logging your first dose made you worse off
    /// than logging none. It cost Bhav six days. A dosing user must never be worse off than a
    /// non-dosing one — that is the guardrail this test now holds.
    @Test func thinHistoryStillForecastsButLessPrecisely() throws {
        let thin = Self.corpus(doseCount: 5)
        let dense = Self.corpus(doseCount: 22)

        let f = try #require(CorrelationEngine.dayForecast(
            history: thin.history, allDoses: thin.doses,
            todaysDoses: [Dose(timestamp: Self.todayDose, name: "Sinemet")],
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now),
            "a thin history must still forecast — hiding it is the cold-start cliff")

        #expect(f.nextOffStart != nil, "a projected dose must still produce a next-OFF")

        // The honesty half: the same curve from a fifth of the data must be known LESS well.
        func precision(_ c: (history: [TremorPoint], doses: [Dose])) -> Double {
            let s = CorrelationEngine.survivalDuration(
                signal: c.history.map { (time: $0.timestamp, value: $0.tremorScore) },
                events: c.doses.map(\.timestamp), onThreshold: CorrelationEngine.offThreshold)
            return CorrelationEngine.kmMedianPrecisionMin(
                durations: s.durations.map(\.durationMin), observed: s.durations.map(\.observed))
        }
        let thinPrecision = precision(thin), densePrecision = precision(dense)
        #expect(thinPrecision >= densePrecision,
                "5 doses (±\(thinPrecision)) cannot be known better than 22 (±\(densePrecision))")
        #expect(densePrecision >= CorrelationEngine.binMin / 2,
                "precision may never claim to beat the bin grid it was measured on")
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
            // The band's quartiles come from 30-MIN BIN MEANS, so the spread has to live
            // BETWEEN bins, not just inside them: a within-bin 1.4/1.8/2.2 cycle averages to
            // exactly 1.8 in every bin, collapsing q25 == median == q75. Each day sits at a
            // different level (1.4 / 1.8 / 2.2 by day) → median 1.8, q25 ≈ 1.4, q75 ≈ 2.2, and
            // the within-bin jitter is kept so bins aren't perfectly flat either.
            let dayLevel = 1.4 + Double(i % 3) * 0.4
            for m in stride(from: 0.0, to: 600.0, by: 1.0) {   // 600 readings/day = 20 whole bins
                let level = dayLevel + (Double(Int(m) % 3) - 1) * 0.05
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

    /// A dosed day now DOES carry the band (Phase 0.5): `band` is no longer the "zero-dose
    /// day" mode flag, it is the band whenever estimable — because the hours of a dosed day
    /// after the drug clears are substrate, and need something to be compared against.
    @Test func dosedDayCarriesBandForMixedVocabulary() throws {
        let c = Self.corpusWithSubstrate(doseCount: 22)
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [Dose(timestamp: Self.todayDose, name: "Sinemet")],
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))
        #expect(f.band != nil)
        #expect(f.nextOffStart != nil)
    }

    // MARK: dose-influence envelope + below-typical (Phase 0.5)

    /// ON/OFF is confined to the dose-influence envelope: after the last dose's window plus
    /// its residual tail, the day reverts to SUBSTRATE vocabulary. This is Bhav's Jul 24 bug —
    /// one early dose used to paint "OFF (wearing-off)" across the following 13 hours.
    @Test func envelopeEndsDoseVocabulary() throws {
        let c = Self.corpusWithSubstrate(doseCount: 22)
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [Dose(timestamp: Self.todayDose, name: "Sinemet")],
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))

        // Late evening is far past the dose's envelope → substrate, never OFF.
        let evening = Self.dayStart.addingTimeInterval(21 * Self.hour)
        let seg = try #require(f.segments.first { evening >= $0.start && evening < $0.end })
        #expect(seg.phase == .typical)
        #expect(!seg.observed)
        // The wearing-off tail INSIDE the envelope is still OFF — the useful claim survives.
        #expect(f.segments.contains { $0.phase == .off })
        // And the vocabulary switches exactly once, in that order: no OFF after substrate starts.
        let firstTypical = try #require(f.segments.firstIndex { $0.phase == .typical })
        #expect(!f.segments[firstTypical...].contains { $0.phase == .off || $0.phase == .on })
    }

    /// A dose from a PREVIOUS day whose window closed long ago must not extend today's
    /// envelope: the pre-dose early morning is unmedicated time, not an OFF window.
    @Test func stalepriorDoseDoesNotExtendEnvelope() throws {
        let c = Self.corpusWithSubstrate(doseCount: 22)
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [Dose(timestamp: Self.todayDose, name: "Sinemet")],
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))

        let preDawn = Self.dayStart.addingTimeInterval(3 * Self.hour)
        let seg = try #require(f.segments.first { preDawn >= $0.start && preDawn < $0.end })
        #expect(seg.phase != .on && seg.phase != .off)
    }

    /// Measurably BELOW the user's own band, awake and dose-free → `.below`: the weaning
    /// signal the app previously had no vocabulary for (it read the same as an ordinary day).
    @Test func awakeCalmBelowBandReadsBelow() throws {
        let c = Self.corpusWithSubstrate(doseCount: 22)   // band ≈ q25 1.4 / median 1.8 / q75 2.2
        var measured: [TremorPoint] = []
        for m in stride(from: 0.0, through: 120.0, by: 5.0) {
            measured.append(TremorPoint(timestamp: Self.todayDose.addingTimeInterval(m * 60),
                                        tremorScore: 0.6))   // well under q25
        }
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [], todaysReadings: measured,
            dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))

        let probe = Self.todayDose.addingTimeInterval(30 * 60)
        let seg = try #require(f.segments.first { probe >= $0.start && probe < $0.end })
        #expect(seg.observed)
        #expect(seg.phase == .below)
    }

    /// Below the band's lower quartile but still at an OFF-level tremor → `.typical`, NOT
    /// "better than usual". The recalibrated q25 (1.40 on Bhav's data) sits above the 1.0 OFF
    /// line, so q25 alone would announce good news while the user is plainly symptomatic.
    @Test func belowBandButOffLevelIsNotBetterThanUsual() throws {
        let c = Self.corpusWithSubstrate(doseCount: 22)   // q25 ≈ 1.4, so 1.2 is under it
        var measured: [TremorPoint] = []
        for m in stride(from: 0.0, through: 120.0, by: 5.0) {
            measured.append(TremorPoint(timestamp: Self.todayDose.addingTimeInterval(m * 60),
                                        tremorScore: 1.2))   // < q25 but ≥ offThreshold
        }
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [], todaysReadings: measured,
            dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))
        let band = try #require(f.band)
        #expect(band.q25 > 1.2)                                   // the premise of the test
        let probe = Self.todayDose.addingTimeInterval(30 * 60)
        let seg = try #require(f.segments.first { probe >= $0.start && probe < $0.end })
        #expect(seg.phase == .typical)
        #expect(!f.segments.contains { $0.phase == .below })
    }

    /// The SAME calm readings while ASLEEP read `.typical`, never `.below`. The band is
    /// estimated from awake readings, so scoring a sleeping one against it is a category
    /// error — and rest tremor is suppressed in sleep, so every night would otherwise render
    /// as a "below your typical range" win and drown the real (awake) ones.
    @Test func asleepCalmDoesNotReadBelow() throws {
        let c = Self.corpusWithSubstrate(doseCount: 22)
        var measured: [TremorPoint] = []
        for m in stride(from: 0.0, through: 120.0, by: 5.0) {
            measured.append(TremorPoint(timestamp: Self.todayDose.addingTimeInterval(m * 60),
                                        tremorScore: 0.6))
        }
        let asleep = [SleepInterval(start: Self.todayDose.addingTimeInterval(-30 * 60),
                                    end: Self.todayDose.addingTimeInterval(150 * 60))]
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [], todaysReadings: measured,
            dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now, sleep: asleep))

        let probe = Self.todayDose.addingTimeInterval(30 * 60)
        let seg = try #require(f.segments.first { probe >= $0.start && probe < $0.end })
        #expect(seg.observed)
        #expect(seg.phase == .typical)
        #expect(!f.segments.contains { $0.phase == .below })
    }

    /// A bin STRADDLING a sleep edge must not enter the band. Its readings are the sliver of
    /// clean time next to the boundary — the minutes right after waking, systematically near
    /// zero — so pooling them with whole bins biases the lower quartile down and makes "better
    /// than usual" far harder to earn. Measured on real history: straddling bins had q25 = 0.18
    /// against 1.40 for whole bins. Containment, not a minimum reading count.
    @Test func boundaryStraddlingBinsExcludedFromBand() throws {
        let c = Self.corpusWithSubstrate(doseCount: 22)
        var history = c.history
        var sleep: [SleepInterval] = []
        for i in 0..<22 {
            let day = Self.base.addingTimeInterval(Double(i) * 24 * Self.hour)
            // Wake at 06:10 — ten minutes INTO the 06:00 bin.
            sleep.append(SleepInterval(start: day.addingTimeInterval(2 * Self.hour),
                                       end: day.addingTimeInterval(6 * Self.hour + 10 * 60)))
            for m in stride(from: 10.0, to: 30.0, by: 1.0) {   // post-wake sliver, near zero
                history.append(TremorPoint(timestamp: day.addingTimeInterval(6 * Self.hour + m * 60),
                                           tremorScore: 0.05))
            }
        }
        let withEdge = try #require(CorrelationEngine.substrateBand(
            history: history, allDoses: c.doses, sleep: sleep, models: [:]))
        let without = try #require(CorrelationEngine.substrateBand(
            history: c.history, allDoses: c.doses, sleep: sleep, models: [:]))
        #expect(abs(withEdge.q25 - without.q25) < 0.001)   // the sliver changed nothing
        #expect(withEdge.q25 > 1.0)                        // and the band isn't degenerate
    }

    /// An unmedicated corpus whose whole distribution is SUB-SYMPTOMATIC — every reading under
    /// the OFF line. Models Harpal K's real shape (band q25 0.25 / median 0.44 / q75 0.64).
    private static func subSymptomaticCorpus(dayCount: Int) -> [TremorPoint] {
        var history: [TremorPoint] = []
        for i in 0..<dayCount {
            let day = base.addingTimeInterval(Double(i) * 24 * hour)
            let dayLevel = 0.3 + Double(i % 3) * 0.15          // 0.30 / 0.45 / 0.60
            for m in stride(from: 0.0, to: 600.0, by: 1.0) {
                history.append(TremorPoint(timestamp: day.addingTimeInterval(14 * hour + m * 60),
                                           tremorScore: dayLevel))
            }
        }
        return history
    }

    /// For a user whose band sits entirely below the OFF line, a bin above their own q75 but
    /// still sub-symptomatic must NOT read "worse than usual" — a quarter of Harpal's bins would
    /// otherwise render red at levels he cannot feel. But a genuinely symptomatic episode still
    /// must, which is why the floor is per-bin rather than a band-level switch.
    @Test func subSymptomaticBandSuppressesWorseThanUsualButNotRealEpisodes() throws {
        let history = Self.subSymptomaticCorpus(dayCount: 22)
        var measured: [TremorPoint] = []
        for m in stride(from: 0.0, to: 60.0, by: 5.0) {        // 09:00–10:00 at 0.8
            measured.append(TremorPoint(timestamp: Self.todayDose.addingTimeInterval(m * 60),
                                        tremorScore: 0.8))
        }
        for m in stride(from: 60.0, to: 120.0, by: 5.0) {      // 10:00–11:00 at 2.5
            measured.append(TremorPoint(timestamp: Self.todayDose.addingTimeInterval(m * 60),
                                        tremorScore: 2.5))
        }
        let f = try #require(CorrelationEngine.dayForecast(
            history: history, allDoses: [], todaysDoses: [], todaysReadings: measured,
            dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))
        let band = try #require(f.band)
        #expect(band.q75 < CorrelationEngine.offThreshold)     // the premise: sub-symptomatic
        #expect(0.8 >= band.q75)                               // 0.8 IS above his own q75

        let quiet = try #require(f.segments.first {
            let t = Self.todayDose.addingTimeInterval(30 * 60); return t >= $0.start && t < $0.end })
        #expect(quiet.phase == .typical)                       // not red: below the OFF line

        let episode = try #require(f.segments.first {
            let t = Self.todayDose.addingTimeInterval(90 * 60); return t >= $0.start && t < $0.end })
        #expect(episode.phase == .above)                       // a real episode still reads red
    }

    /// Cold start (dosed day, no estimable band yet) keeps the pre-Phase-0.5 behaviour:
    /// ON/OFF across the whole day rather than a sixth "can't compare yet" phase.
    @Test func coldStartWithoutBandKeepsDoseVocabularyAllDay() throws {
        let c = Self.corpus(doseCount: 22)   // no dose-free substrate block → band nil
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [Dose(timestamp: Self.todayDose, name: "Sinemet")],
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: Self.now))
        #expect(f.band == nil)
        #expect(f.segments.last?.phase == .off)
        #expect(!f.segments.contains { $0.phase == .typical || $0.phase == .below })
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
