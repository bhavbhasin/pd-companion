//
//  DosePanelRowTests.swift
//  PD CompanionTests
//
//  The Day-in-Review Doses panel primitive. docs/design/dose-onset-coverage-surfaces.md.
//
//  The property under test is the one the design doc puts a star on: onset and coverage are
//  gated INDEPENDENTLY. A dose taken while tremor was already low has no onset (nothing to fall
//  from) but keeps its coverage, because "you were still ON when the next one came" is exactly
//  the evidence that matters. Applying one exclusion to both is the bug that produced a card
//  reading "180 couldn't be measured" for a six-doses-a-day patient.
//
//  ⛔ These tests pin STATES, not prose. The row copy lives in the view and is free to change;
//  a test that pinned the sentence would fail on a wording pass and teach nothing.
//

import Foundation
import Testing
@testable import PD_Companion

struct DosePanelRowTests {

    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    private func pinCalendar() { CorrelationEngine.calendar = Self.cal }

    private static func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: day, hour: h, minute: m))!
    }

    private static func dayBounds(_ day: Int) -> (Date, Date) {
        (at(day, 0), at(day + 1, 0))
    }

    /// Tremor at 5-min steps across `days`. OFF (1.6) unless inside an ON window (0.2) or
    /// asleep (0.0). `gaps` drop the readings entirely, which is how a watch off the wrist
    /// looks to the engine — absent, not zero.
    private static func series(days: Range<Int>, on: [(Date, Double)],
                               sleep: [SleepInterval] = [],
                               gaps: [(Date, Date)] = []) -> [TremorPoint] {
        let windows = on.map { ($0.0, $0.0.addingTimeInterval($0.1 * 60)) }
        var out: [TremorPoint] = []
        var t = at(days.lowerBound, 0)
        let end = at(days.upperBound - 1, 23, 55)
        while t <= end {
            defer { t = t.addingTimeInterval(5 * 60) }
            if gaps.contains(where: { $0.0 <= t && t < $0.1 }) { continue }
            let v: Double
            if sleep.contains(where: { $0.start <= t && t < $0.end }) { v = 0.0 }
            else if windows.contains(where: { $0.0 <= t && t < $0.1 }) { v = 0.2 }
            else { v = 1.6 }
            out.append(TremorPoint(timestamp: t, tremorScore: v))
        }
        return out
    }

    private static func rows(day: Int, samples: [TremorPoint], doses: [Dose],
                             sleep: [SleepInterval] = []) -> [CorrelationEngine.DoseRow] {
        let (ds, de) = dayBounds(day)
        return CorrelationEngine.dosePanelRows(
            dayStart: ds, dayEnd: de, samples: samples, allDoses: doses, sleep: sleep)
    }

    // MARK: - The six row states

    /// Measured start to finish: tremor was high, fell, and came back while we watched.
    @Test func measuredOnsetAndCoverage() {
        pinCalendar()
        let t0 = Self.at(10, 10, 0)
        // ON for 170 min, then OFF again well before the next day.
        let samples = Self.series(days: 10..<12, on: [(t0.addingTimeInterval(20 * 60), 170)])
        let doses = [Dose(timestamp: t0, name: "Sinemet")]
        let r = Self.rows(day: 10, samples: samples, doses: doses)

        #expect(r.count == 1)
        guard case .measured(let onset) = r[0].onset else {
            Issue.record("expected a measured onset, got \(r[0].onset)"); return
        }
        // The fall is at +20 min; smoothing can shift the halfway crossing by a bin either way.
        #expect(onset > 0 && onset <= 40)
        guard case .held(let held) = r[0].coverage else {
            Issue.record("expected held coverage, got \(r[0].coverage)"); return
        }
        #expect(held > 120 && held < 240)
        #expect(r[0].name == "Sinemet")
    }

    /// ⭐ The load-bearing case. Dosed while the previous one was still working: no onset,
    /// but coverage survives. This is INFORMATION, not a blank.
    @Test func takenWhileStillCoveredKeepsItsCoverage() {
        pinCalendar()
        let first = Self.at(10, 10, 0)
        let second = Self.at(10, 13, 0)
        // Continuous ON from 10:20 through 16:10, so the 13:00 dose lands on quiet tremor
        // and tremor returns (above threshold) at 16:10, before any next dose.
        let samples = Self.series(days: 10..<12, on: [(first.addingTimeInterval(20 * 60), 350)])
        let doses = [Dose(timestamp: first, name: "Sinemet"),
                     Dose(timestamp: second, name: "Sinemet")]
        let r = Self.rows(day: 10, samples: samples, doses: doses)

        #expect(r.count == 2)
        let row = r[1]
        #expect(row.onset == .tremorAlreadyLow)
        // Coverage is NOT excluded with the onset.
        if case .learnedNothing = row.coverage {
            Issue.record("already-covered dose lost its coverage — the two gates are coupled")
        }
        if case .noReading = row.coverage {
            Issue.record("already-covered dose reported no reading")
        }
    }

    /// Re-dosed before it wore off: the window closes at the next dose, and the row can name
    /// which substance ended it.
    @Test func reDosedBeforeWearingOff() {
        pinCalendar()
        let t0 = Self.at(10, 10, 0)
        let next = Self.at(10, 12, 0)
        // Still ON when the next dose arrives at 12:00.
        let samples = Self.series(days: 10..<12, on: [(t0.addingTimeInterval(15 * 60), 300)])
        let doses = [Dose(timestamp: t0, name: "Sinemet"),
                     Dose(timestamp: next, name: "Mucuna")]
        let r = Self.rows(day: 10, samples: samples, doses: doses)

        guard case .endedByNextDose(let m) = r[0].coverage else {
            Issue.record("expected the window to close at the next dose, got \(r[0].coverage)")
            return
        }
        #expect(abs(m - 120) <= CorrelationEngine.binMin)
        // Named from the whole record, so a cross-substance re-dose reads correctly.
        #expect(r[0].endedBy == "Mucuna")
    }

    /// Fell asleep while still covered: a floor, and the reason is sleep — measured, not assumed.
    @Test func sleptWhileStillCovered() {
        pinCalendar()
        let t0 = Self.at(10, 21, 0)
        let sleep = [SleepInterval(start: Self.at(10, 23, 0), end: Self.at(11, 7, 0))]
        // ON from 21:30 and never returns before sleep onset at 23:00.
        let samples = Self.series(days: 10..<12,
                                  on: [(t0.addingTimeInterval(30 * 60), 600)], sleep: sleep)
        let doses = [Dose(timestamp: t0, name: "Sinemet")]
        let r = Self.rows(day: 10, samples: samples, doses: doses, sleep: sleep)

        guard case .endedBySleep(let m) = r[0].coverage else {
            Issue.record("expected sleep to end the watching, got \(r[0].coverage)"); return
        }
        #expect(abs(m - 120) <= CorrelationEngine.binMin)
    }

    /// ⭐ The watch comes off. `durationMin` here is the OBSERVATION CEILING, not a watched
    /// span — the row must report how long we actually had a reading, never the ceiling.
    @Test func lostReadingReportsWhatWeActuallyWatched() {
        pinCalendar()
        let t0 = Self.at(10, 10, 0)
        // ON from 10:20; readings stop entirely at 11:00 and never resume. No next dose,
        // no sleep, so nothing else can close the window.
        let samples = Self.series(days: 10..<12,
                                  on: [(t0.addingTimeInterval(20 * 60), 60)],
                                  gaps: [(Self.at(10, 11, 0), Self.at(12, 0, 0))])
        let doses = [Dose(timestamp: t0, name: "Sinemet")]
        let r = Self.rows(day: 10, samples: samples, doses: doses)

        guard case .endedByLostReading(let m) = r[0].coverage else {
            Issue.record("expected a lost reading, got \(r[0].coverage)"); return
        }
        // ~60 min of real readings. The bug this pins would report ~1440 (the 24 h ceiling).
        #expect(m <= 90, "reported \(m) min watched — that is the observation ceiling, not a watched span")
        #expect(m > 0)
    }

    /// The ONE genuine blank: tremor was already quiet AND sleep ended the watching within a
    /// bin. Neither fact alone is disqualifying.
    @Test func alreadyQuietThenAsleepIsTheOnlyBlank() {
        pinCalendar()
        let t0 = Self.at(11, 1, 30)
        let sleep = [SleepInterval(start: Self.at(10, 23, 0), end: Self.at(11, 1, 25)),
                     SleepInterval(start: Self.at(11, 1, 40), end: Self.at(11, 7, 0))]
        // Quiet around the dose, and asleep again ten minutes later.
        let samples = Self.series(days: 10..<13,
                                  on: [(Self.at(11, 0, 0), 100)], sleep: sleep)
        let doses = [Dose(timestamp: t0, name: "Mucuna")]
        let r = Self.rows(day: 11, samples: samples, doses: doses, sleep: sleep)

        #expect(r.count == 1)
        #expect(r[0].coverage == .learnedNothing)
        #expect(r[0].onset == .tremorAlreadyLow)
    }

    // MARK: - Day scoping and completeness

    /// ⛔ A dose the user logged must never be missing from the panel — that reads as data
    /// loss. A day with no tremor record at all still lists every dose.
    @Test func dosesAreNeverDroppedWhenThereIsNoTremorRecord() {
        pinCalendar()
        let doses = [Dose(timestamp: Self.at(10, 8, 0), name: "Sinemet"),
                     Dose(timestamp: Self.at(10, 13, 0), name: "Sinemet")]
        let r = Self.rows(day: 10, samples: [], doses: doses)

        #expect(r.count == 2)
        #expect(r.allSatisfy { $0.coverage == .noReading })
        // ⛔ Never `.learnedNothing` — that copy asserts tremor was quiet, which we never saw.
        #expect(!r.contains { $0.coverage == .learnedNothing })
    }

    /// ⭐ Dosed while ALREADY asleep. The observation window is zero, so `survivalDuration`
    /// drops the dose entirely — but the readings exist, so "no tremor readings" would be a
    /// lie. Pinned to the real shape of the Jul 6 02:43 Sinemet dose (07-30 dump): 240 readings
    /// around it, taken inside a recorded 02:14-02:55 sleep interval.
    @Test func dosedWhileAsleepSaysSoInsteadOfClaimingNoData() {
        pinCalendar()
        let t0 = Self.at(11, 2, 43)
        let sleep = [SleepInterval(start: Self.at(11, 2, 14), end: Self.at(11, 2, 55)),
                     SleepInterval(start: Self.at(11, 3, 7), end: Self.at(11, 5, 21))]
        // Readings exist right through the dose — this is not a data gap.
        let samples = Self.series(days: 10..<13, on: [], sleep: sleep)
        let r = Self.rows(day: 11, samples: samples, doses: [Dose(timestamp: t0, name: "Sinemet")],
                          sleep: sleep)

        #expect(r.count == 1)
        #expect(r[0].coverage == .asleepAtDose)
        // ⛔ The two must never be confused: one is about missing data, the other about a dose
        // taken at a moment nothing could be observed.
        #expect(r[0].coverage != .noReading)
    }

    /// Decision 3: match Day in Review's plain-midnight day, and accept the consequence rather
    /// than invent a second definition — a 00:47 dose belongs to the NEXT calendar day.
    @Test func dayBoundaryIsPlainMidnight() {
        pinCalendar()
        let evening = Dose(timestamp: Self.at(10, 22, 0), name: "Sinemet")
        let afterMidnight = Dose(timestamp: Self.at(11, 0, 47), name: "Mucuna")
        let samples = Self.series(days: 10..<13, on: [(Self.at(10, 22, 20), 120)])

        let day10 = Self.rows(day: 10, samples: samples, doses: [evening, afterMidnight])
        let day11 = Self.rows(day: 11, samples: samples, doses: [evening, afterMidnight])

        #expect(day10.map(\.t0) == [evening.timestamp])
        #expect(day11.map(\.t0) == [afterMidnight.timestamp])
    }

    /// The observation window is bounded by the next dose of ANY substance, so the rows must
    /// be computed from the whole record even though only one day is displayed.
    @Test func horizonUsesDosesOutsideTheDisplayedDay() {
        pinCalendar()
        let t0 = Self.at(10, 23, 0)
        let nextDay = Self.at(11, 1, 0)
        let samples = Self.series(days: 10..<13, on: [(t0.addingTimeInterval(15 * 60), 400)])
        let r = Self.rows(day: 10, samples: samples,
                          doses: [Dose(timestamp: t0, name: "Sinemet"),
                                  Dose(timestamp: nextDay, name: "Sinemet")])

        #expect(r.count == 1)
        // Bounded at the 01:00 dose (120 min), not run out to the ceiling.
        guard case .endedByNextDose(let m) = r[0].coverage else {
            Issue.record("expected the next day's dose to bound the window, got \(r[0].coverage)")
            return
        }
        #expect(abs(m - 120) <= CorrelationEngine.binMin)
    }

    /// ⛔ No verdict, no comparison: the primitive returns rows in dose order and nothing else.
    /// Pins the absence of a ranking the retired afternoon-dose card is not allowed to grow back.
    @Test func rowsAreInDoseOrderWithNoRanking() {
        pinCalendar()
        let doses = [Dose(timestamp: Self.at(10, 19, 0), name: "Sinemet"),
                     Dose(timestamp: Self.at(10, 7, 0), name: "Sinemet"),
                     Dose(timestamp: Self.at(10, 13, 0), name: "Sinemet")]
        let samples = Self.series(days: 10..<12, on: [(Self.at(10, 7, 20), 120)])
        let r = Self.rows(day: 10, samples: samples, doses: doses)

        #expect(r.map(\.t0) == doses.map(\.timestamp).sorted())
    }
}
