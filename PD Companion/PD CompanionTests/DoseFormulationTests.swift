//
//  DoseFormulationTests.swift
//  PD CompanionTests
//
//  Per-formulation dose modeling (Phase A): the forecast + wearing-off primitives stratify
//  by formulation instead of pooling every dose into one curve, and the estimability gate —
//  not a name allowlist — decides which substances show a real levodopa pulse. Synthetic,
//  deterministic data. The pooled primitives themselves stay pinned by the parity test; here
//  we test the stratification, the gate-as-classifier (inert substances self-exclude), and
//  that each dose is projected forward with its OWN formulation's timing.
//

import Foundation
import Testing
@testable import PD_Companion

struct DoseFormulationTests {

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)
    private static let hour = 3600.0

    /// A per-dose wearing-off pulse (minutes since dose): OFF → onset ramp to a deep ON
    /// plateau → wear-off ramp back to OFF. `onsetEnd`/`plateauEnd` shape onset speed and
    /// ON-duration, so two formulations get genuinely different KM medians.
    private static func pulse(_ m: Double, onsetEnd: Double, plateauEnd: Double) -> Double {
        if m < 0 { return 2.0 }
        if m < onsetEnd { return 2.0 - (m / onsetEnd) * 1.6 }                   // → 0.4
        if m < plateauEnd { return 0.4 }                                        // ON plateau
        if m < plateauEnd + 30 { return 0.4 + ((m - plateauEnd) / 30) * 1.6 }   // wear-off ramp
        return 2.0
    }

    /// One substance's daily schedule and pulse shape.
    private struct Med {
        let name: String
        let atHour: Double
        var onsetEnd: Double = 40
        var basePlateau: Double = 160
        var plateauStep: Double = 10
        var inert: Bool = false
    }

    /// A CONTINUOUS record: a reading every 5 minutes across the whole period, not islands
    /// around each dose.
    ///
    /// ⚠️ Why this replaced the old per-dose sampler (Jul 28 2026). The old builder emitted
    /// readings only in ±300-min windows around each dose and supplied NO sleep. That was
    /// harmless while the observation horizon was capped at 5 h — the engine never looked into
    /// the gaps. Once the horizon became event-bounded, one day's dose window ran to the next
    /// day's dose and read ITS pulse as the first dose's ending, so an inert substance picked up
    /// a borrowed duration. The fixture, not the engine, was the unrealistic part: a real watch
    /// records all day and a real patient sleeps.
    ///
    /// Tremor here = an OFF baseline of 2.0, pulled down by any dose currently acting (the
    /// minimum across active pulses, since a drug lowers tremor), and 0.0 while asleep because
    /// rest tremor abates in sleep whatever the drug is doing. An `inert` substance contributes
    /// nothing at all — that IS what inert means, and it is why it can never be estimable.
    private static func record(days: Int, meds: [Med])
        -> (history: [TremorPoint], doses: [Dose], sleep: [SleepInterval]) {
        var doses: [Dose] = []
        var shapes: [(t0: Date, med: Med, plateauEnd: Double)] = []
        for i in 0..<days {
            for m in meds {
                let t0 = base.addingTimeInterval(Double(i) * 24 * hour + m.atHour * hour)
                doses.append(Dose(timestamp: t0, name: m.name))
                shapes.append((t0, m, m.basePlateau + Double(i % 5) * m.plateauStep))
            }
        }
        // Asleep 23:00 -> 07:00, expressed relative to `base` so no machine calendar is involved.
        let sleep = CorrelationEngine.mergeSleep((0..<days).map { i in
            let d = base.addingTimeInterval(Double(i) * 24 * hour)
            return SleepInterval(start: d.addingTimeInterval(23 * hour),
                                 end: d.addingTimeInterval(31 * hour))
        })

        var history: [TremorPoint] = []
        let end = Double(days) * 24 * 60
        for step in stride(from: 0.0, to: end, by: 5.0) {
            let t = base.addingTimeInterval(step * 60)
            let hod = step.truncatingRemainder(dividingBy: 24 * 60) / 60
            if hod >= 23 || hod < 7 {
                history.append(TremorPoint(timestamp: t, tremorScore: 0.0))
                continue
            }
            var v = 2.0                                   // OFF baseline
            for s in shapes where !s.med.inert {
                let m = t.timeIntervalSince(s.t0) / 60
                guard m >= 0, m <= s.plateauEnd + 60 else { continue }
                v = min(v, pulse(m, onsetEnd: s.med.onsetEnd, plateauEnd: s.plateauEnd))
            }
            history.append(TremorPoint(timestamp: t, tremorScore: v))
        }
        return (history, doses, sleep)
    }

    private static func signal(_ history: [TremorPoint]) -> [(time: Date, value: Double)] {
        history.map { (time: $0.timestamp, value: $0.tremorScore) }
    }

    // Two real levodopa formulations at non-overlapping times of day: a long-acting Sinemet
    // (08:00) and a faster/shorter Mucuna (15:00), over a continuous 22-day record.
    private static func mixed() -> (history: [TremorPoint], doses: [Dose], sleep: [SleepInterval]) {
        record(days: 22, meds: [
            Med(name: "Sinemet", atHour: 8, onsetEnd: 40, basePlateau: 160, plateauStep: 10),
            Med(name: "Mucuna",  atHour: 15, onsetEnd: 25, basePlateau: 95,  plateauStep: 8),
        ])
    }

    /// Sinemet plus a substance that does nothing at all.
    private static func withInert() -> (history: [TremorPoint], doses: [Dose], sleep: [SleepInterval]) {
        record(days: 22, meds: [
            Med(name: "Sinemet",   atHour: 8),
            Med(name: "Vitamin D", atHour: 12, inert: true),
        ])
    }

    /// Both formulations clear the gate and get DISTINCT timing — the long-acting one has a
    /// longer projected ON-duration. Pooling would have collapsed them to one median.
    @Test func stratifiesEstimableFormulationsWithDistinctTiming() throws {
        let c = Self.mixed()
        let models = CorrelationEngine.estimableFormulations(
            signal: Self.signal(c.history), doses: c.doses, sleep: c.sleep)
        #expect(models.count == 2)
        let sinemet = try #require(models["sinemet"])
        let mucuna = try #require(models["mucuna"])
        #expect(sinemet.onDuration > mucuna.onDuration)     // Sinemet lasts longer than Mucuna
        #expect(sinemet.durationsCount >= 20)
        #expect(mucuna.durationsCount >= 20)
    }

    /// The estimability gate IS the classifier: an inert substance (many doses, no ON pulse)
    /// produces no estimable model and self-excludes — no drug dictionary, no name filter.
    @Test func inertSubstanceSelfExcludes() {
        let c = Self.withInert()
        let models = CorrelationEngine.estimableFormulations(
            signal: Self.signal(c.history), doses: c.doses, sleep: c.sleep)
        #expect(models["sinemet"] != nil)
        #expect(models["vitamin d"] == nil)     // flat trace → no pulse → excluded
        #expect(models.count == 1)
    }

    /// Single-formulation data reduces to exactly one stratum — the graceful-degrade path
    /// that keeps behavior identical to before stratification.
    @Test func singleFormulationIsOneStratum() {
        let c = Self.record(days: 22, meds: [Med(name: "Sinemet 25-100", atHour: 8)])
        let models = CorrelationEngine.estimableFormulations(
            signal: Self.signal(c.history), doses: c.doses, sleep: c.sleep)
        #expect(models.count == 1)
        #expect(models["sinemet"] != nil)       // dosage tokens stripped: "Sinemet 25-100" → "sinemet"
    }

    // MARK: forecast projects each dose with its own formulation's timing

    private static let dayStart = base.addingTimeInterval(100 * 24 * hour)
    private static var dayEnd: Date { dayStart.addingTimeInterval(24 * hour) }

    /// Two doses today — a long Sinemet (08:00) and a short Mucuna (15:00) — projected before
    /// either lands (`now` 07:00). The forecast paints two separate ON bands; the Sinemet band
    /// is longer than the Mucuna one, which pooling could never produce.
    @Test func forecastProjectsPerFormulationDurations() throws {
        let c = Self.mixed()
        let today = { (h: Double) in Self.dayStart.addingTimeInterval(h * Self.hour) }
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [Dose(timestamp: today(8), name: "Sinemet"),
                          Dose(timestamp: today(15), name: "Mucuna")],
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: today(7),
            sleep: c.sleep))

        let onSegs = f.segments
            .filter { !$0.observed && $0.phase == .on }
            .sorted { $0.start < $1.start }
        // ⚠️ #require, not #expect: #expect does not halt, so indexing below on a wrong count
        // traps and kills the whole test PROCESS — every other suite then reports 0.000s
        // "failures" that have nothing to do with them. Never subscript after a bare #expect.
        try #require(onSegs.count == 2, "expected two ON bands, got \(onSegs.count)")
        let sinemetOn = onSegs[0].end.timeIntervalSince(onSegs[0].start)   // 08:00 dose
        let mucunaOn = onSegs[1].end.timeIntervalSince(onSegs[1].start)    // 15:00 dose
        #expect(sinemetOn > mucunaOn)
    }

    /// A confirmed non-pulsatile substance logged today paints NO ON band — the fallback must
    /// not invent a levodopa pulse for a vitamin, even though estimable levodopa history exists.
    @Test func forecastOmitsConfirmedInertDose() throws {
        let c = Self.withInert()
        let today = { (h: Double) in Self.dayStart.addingTimeInterval(h * Self.hour) }
        let f = try #require(CorrelationEngine.dayForecast(
            history: c.history, allDoses: c.doses,
            todaysDoses: [Dose(timestamp: today(12), name: "Vitamin D")],   // only an inert dose today
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: today(9),
            sleep: c.sleep))

        // No projected ON band anywhere — the vitamin is judged non-pulsatile, not fallen back.
        #expect(f.segments.filter { !$0.observed && $0.phase == .on }.isEmpty)
    }

    /// A DATA-THIN substance — too few doses for a duration to be measurable — paints no ON
    /// band either. It used to borrow the combined levodopa timing ("benefit of the doubt"),
    /// which asserted an ON-window nobody had measured for that substance.
    ///
    /// This pins the Jul 28 2026 collapse: one question, "does this substance have a measurable
    /// duration", replacing two copies of a `< 20` / `>= 20` dose count that stated the same rule
    /// with the polarity flipped. The old thin branch was NEVER covered by a test, which is why
    /// deleting it broke nothing — the suite could not see it.
    ///
    /// ⚠️ This is the **conservative-but-wrong** trade-off decided Jul 26 2026
    /// (docs/design/medication-cards.md): a genuinely effective new drug contributes nothing
    /// until its own duration is estimable. If that is ever revisited, this test is the thing
    /// that will fail, and it is meant to — read the doc before changing the expectation.
    @Test func forecastOmitsDataThinSubstance() throws {
        // Real pulse, real levodopa — simply not enough of it to measure a duration yet.
        let full = Self.record(days: 22, meds: [Med(name: "Sinemet", atHour: 8)])
        let thin = Self.record(days: 4,  meds: [Med(name: "Rytary", atHour: 12,
                                                    onsetEnd: 30, basePlateau: 120, plateauStep: 8)])
        let history = full.history
        let doses = full.doses + thin.doses
        let sleep = full.sleep

        // Sanity: the thin substance genuinely has no model, while the established one does.
        let models = CorrelationEngine.estimableFormulations(
            signal: Self.signal(history), doses: doses, sleep: sleep)
        #expect(models[CorrelationEngine.formulationKey("Sinemet")] != nil)
        #expect(models[CorrelationEngine.formulationKey("Rytary")] == nil)

        let today = { (h: Double) in Self.dayStart.addingTimeInterval(h * Self.hour) }
        let f = try #require(CorrelationEngine.dayForecast(
            history: history, allDoses: doses,
            todaysDoses: [Dose(timestamp: today(12), name: "Rytary")],   // only the thin one today
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: today(9),
            sleep: sleep))

        #expect(f.segments.filter { !$0.observed && $0.phase == .on }.isEmpty)
    }
}
