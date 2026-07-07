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

    /// Append `count` daily doses of `name` at `atHour`, each densely sampled with a pulse of
    /// the given shape (or a flat, no-pulse trace when `inert`).
    private static func addDoses(
        name: String, atHour: Double, count: Int,
        onsetEnd: Double = 40, basePlateau: Double = 160, plateauStep: Double = 10,
        inert: Bool = false,
        history: inout [TremorPoint], doses: inout [Dose]
    ) {
        for i in 0..<count {
            let t0 = base.addingTimeInterval(Double(i) * 24 * hour + atHour * hour)
            doses.append(Dose(timestamp: t0, name: name))
            let plateauEnd = basePlateau + Double(i % 5) * plateauStep
            for m in stride(from: -30.0, through: 300.0, by: 5.0) {
                let v = inert ? 1.5 : pulse(m, onsetEnd: onsetEnd, plateauEnd: plateauEnd)
                history.append(TremorPoint(timestamp: t0.addingTimeInterval(m * 60), tremorScore: v))
            }
        }
    }

    private static func signal(_ history: [TremorPoint]) -> [(time: Date, value: Double)] {
        history.map { (time: $0.timestamp, value: $0.tremorScore) }
    }

    // Two real levodopa formulations at non-overlapping times of day: a long-acting Sinemet
    // (08:00) and a faster/shorter Mucuna (15:00).
    private static func mixed() -> (history: [TremorPoint], doses: [Dose]) {
        var history: [TremorPoint] = []; var doses: [Dose] = []
        addDoses(name: "Sinemet", atHour: 8, count: 22,
                 onsetEnd: 40, basePlateau: 160, plateauStep: 10, history: &history, doses: &doses)
        addDoses(name: "Mucuna", atHour: 15, count: 22,
                 onsetEnd: 25, basePlateau: 95, plateauStep: 8, history: &history, doses: &doses)
        return (history, doses)
    }

    /// Both formulations clear the gate and get DISTINCT timing — the long-acting one has a
    /// longer projected ON-duration. Pooling would have collapsed them to one median.
    @Test func stratifiesEstimableFormulationsWithDistinctTiming() throws {
        let c = Self.mixed()
        let models = CorrelationEngine.estimableFormulations(signal: Self.signal(c.history), doses: c.doses)
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
        var history: [TremorPoint] = []; var doses: [Dose] = []
        Self.addDoses(name: "Sinemet", atHour: 8, count: 22, history: &history, doses: &doses)
        Self.addDoses(name: "Vitamin D", atHour: 12, count: 22, inert: true, history: &history, doses: &doses)
        let models = CorrelationEngine.estimableFormulations(signal: Self.signal(history), doses: doses)
        #expect(models["sinemet"] != nil)
        #expect(models["vitamin d"] == nil)     // flat trace → no pulse → excluded
        #expect(models.count == 1)
    }

    /// Single-formulation data reduces to exactly one stratum — the graceful-degrade path
    /// that keeps behavior identical to before stratification.
    @Test func singleFormulationIsOneStratum() {
        var history: [TremorPoint] = []; var doses: [Dose] = []
        Self.addDoses(name: "Sinemet 25-100", atHour: 8, count: 22, history: &history, doses: &doses)
        let models = CorrelationEngine.estimableFormulations(signal: Self.signal(history), doses: doses)
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
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: today(7)))

        let onSegs = f.segments
            .filter { !$0.observed && $0.phase == .on }
            .sorted { $0.start < $1.start }
        #expect(onSegs.count == 2)
        let sinemetOn = onSegs[0].end.timeIntervalSince(onSegs[0].start)   // 08:00 dose
        let mucunaOn = onSegs[1].end.timeIntervalSince(onSegs[1].start)    // 15:00 dose
        #expect(sinemetOn > mucunaOn)
    }

    /// A confirmed non-pulsatile substance logged today paints NO ON band — the fallback must
    /// not invent a levodopa pulse for a vitamin, even though estimable levodopa history exists.
    @Test func forecastOmitsConfirmedInertDose() throws {
        var history: [TremorPoint] = []; var doses: [Dose] = []
        Self.addDoses(name: "Sinemet", atHour: 8, count: 22, history: &history, doses: &doses)
        Self.addDoses(name: "Vitamin D", atHour: 12, count: 22, inert: true, history: &history, doses: &doses)
        let today = { (h: Double) in Self.dayStart.addingTimeInterval(h * Self.hour) }
        let f = try #require(CorrelationEngine.dayForecast(
            history: history, allDoses: doses,
            todaysDoses: [Dose(timestamp: today(12), name: "Vitamin D")],   // only an inert dose today
            todaysReadings: [], dayStart: Self.dayStart, dayEnd: Self.dayEnd, now: today(9)))

        // No projected ON band anywhere — the vitamin is judged non-pulsatile, not fallen back.
        #expect(f.segments.filter { !$0.observed && $0.phase == .on }.isEmpty)
    }
}
