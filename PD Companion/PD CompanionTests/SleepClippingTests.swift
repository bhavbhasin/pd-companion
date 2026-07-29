//
//  SleepClippingTests.swift
//  PD CompanionTests
//
//  Two jobs.
//
//  1. ORACLE TEST — the Swift engine must reproduce the number an independent Python
//     replication produced on the SAME backup before any of this was written
//     (501.7 min/day, 07-16-2026 export). Two implementations, one number. That
//     replication is what caught three wrong claims in the design note, so it has
//     earned the right to be the oracle. docs/design/wearing-off-margin.md.
//
//  2. SCENARIO TESTS — synthetic, no backup needed, pinning the cases we reasoned
//     through by hand: nap inside a gap, night interruption + rescue dose, a
//     once-daily regimen still getting a card, the evening dose contributing nothing,
//     and the no-sleep-data fallback.
//

import Foundation
import Testing
@testable import PD_Companion

struct SleepClippingTests {

    // MARK: - Helpers

    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    /// Pin bucketing/day-grouping to Pacific so results don't depend on the machine.
    private func pinCalendar() { CorrelationEngine.calendar = Self.cal }

    private static func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        Self.cal.date(from: DateComponents(year: 2026, month: 6, day: day, hour: h, minute: m))!
    }

    /// A tremor series over `days` at 5-min steps (matching the engine's bin width).
    /// `value` decides the score at each instant.
    private static func series(days: Range<Int>, value: (Date) -> Double) -> [TremorPoint] {
        var out: [TremorPoint] = []
        for d in days {
            var t = at(d, 0)
            let end = at(d, 23, 55)
            while t <= end {
                out.append(TremorPoint(timestamp: t, tremorScore: value(t)))
                t = t.addingTimeInterval(5 * 60)
            }
        }
        return out
    }

    /// The daily-uncovered figure in MINUTES. Read from `finding`, not `title`: the title
    /// carries approximate hours for glanceability, the finding carries the precise minutes.
    private static func uncovered(from insight: Insight) -> Int? {
        let digits = insight.finding.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return digits.first
    }

    // MARK: - 1. Oracle test (real backup)

    static let backupDir =
        "/Users/bhav/Documents/ParkinsonsProject/PD Companion/PD Companion Backups/07-16-2026"

    @Test func matchesPythonOracleOnRealBackup() throws {
        pinCalendar()
        // Physical devices can't see the Mac path; fail loudly rather than skip silently.
        let tremorPath = try #require(Self.findCSV(prefix: "tremor_readings"),
            "Backup not found at \(Self.backupDir). Run on an iOS Simulator, not a device.")
        let medsPath = try #require(Self.findCSV(prefix: "medication_doses"))
        let sleepPath = try #require(Self.findCSV(prefix: "sleep_stages"))

        let samples = try Self.loadTremor(tremorPath)
        let doses = try Self.loadTakenDoses(medsPath)
        let recorded = try Self.loadAsleepIntervals(sleepPath)

        #expect(doses.count == 246, "taken dose count")

        let lo = samples.map(\.timestamp).min()!
        let hi = samples.map(\.timestamp).max()!
        let sleep = CorrelationEngine.effectiveSleep(recorded: recorded, covering: lo...hi)

        let insight = try #require(
            CorrelationEngine.wearingOffInsight(samples: samples, doses: doses, sleep: sleep),
            "card should fire on the real backup")
        let n = try #require(Self.uncovered(from: insight))

        // Python oracle: 501.7 min/day. Allow a few minutes for float/binning drift
        // between the two implementations — but NOT enough to hide a real divergence.
        #expect(abs(n - 502) <= 5, "Swift says \(n) min/day, Python oracle says 502")

        // And the pre-change number must be gone: 234 was the sleep-blind figure.
        #expect(n > 400, "sleep clipping should roughly double the old 234 min/day")

        // The precision-based tier must be a NO-OP on the real record. Replacing an arbitrary
        // gate is not licence to move anyone's badge: the claim is ~500 min/day against a
        // 60 min/day bar, and the pooled duration is known to ±2.5, so even the pessimistic
        // end of the interval clears the bar by an order of magnitude. Measured Jul 28 on the
        // 07-24 export: 513.6 point, 508.4 lower, ±5.2 on the claim.
        // docs/design/wearing-off-card-confidence.md.
        #expect(insight.confidence == .strong,
                "the real record must stay Strong, got \(String(describing: insight.confidence))")
    }

    /// The duration side, independently: censoring at sleep onset must LOWER the KM
    /// median, because evening doses can no longer "survive" through unobservable sleep.
    @Test func sleepCensoringLowersDurationOnRealBackup() throws {
        pinCalendar()
        let tremorPath = try #require(Self.findCSV(prefix: "tremor_readings"))
        let medsPath = try #require(Self.findCSV(prefix: "medication_doses"))
        let sleepPath = try #require(Self.findCSV(prefix: "sleep_stages"))
        let samples = try Self.loadTremor(tremorPath)
        let doses = try Self.loadTakenDoses(medsPath)
        let recorded = try Self.loadAsleepIntervals(sleepPath)
        let sig = samples.map { (time: $0.timestamp, value: $0.tremorScore) }
        let lo = samples.map(\.timestamp).min()!, hi = samples.map(\.timestamp).max()!
        let sleep = CorrelationEngine.effectiveSleep(recorded: recorded, covering: lo...hi)

        let blind = CorrelationEngine.survivalDuration(
            signal: sig, events: doses.map(\.timestamp), onThreshold: CorrelationEngine.offThreshold)
        let clipped = CorrelationEngine.survivalDuration(
            signal: sig, events: doses.map(\.timestamp),
            onThreshold: CorrelationEngine.offThreshold, sleep: sleep)

        // Python oracle: 192.5 sleep-blind -> 177.5 sleep-censored.
        //
        // Where these two numbers come from, so nobody has to guess later: the Python lab,
        // on this same 07-16-2026 backup. Regenerate with
        //   res, _ = wearing_off.analyze(tremor, doses, sleep)   # sleep=[] for the blind figure
        //   wearing_off.km_median(wearing_off.km_summary(res))
        // Re-verified Jul 26 2026 after the lab was taught to censor sleep (it had been
        // sleep-blind, so it was NOT the source of these values until then): the fixed lab
        // reproduces both exactly, on the same 246 doses. Nothing automatically re-checks
        // that, so if the lab and these constants ever disagree, re-run the two lines above
        // before assuming the app is the one that drifted.
        #expect(abs(blind.kmMedian - 192.5) < 2.5, "sleep-blind KM")
        #expect(abs(clipped.kmMedian - 177.5) < 2.5, "sleep-censored KM")
        #expect(clipped.kmMedian < blind.kmMedian, "censoring must not inflate duration")
    }

    /// A caller that passes NO sleep must never be sleep-blind. Removing the 600-min cap
    /// removed the thing that was accidentally excluding the night, so without the fallback
    /// the card would score a whole unconscious night as waking OFF (~488 min/day on this
    /// data). The conservative 22:00-06:00 synthesis must keep it well under that — while
    /// still beating the old capped figure of 234.
    @Test func noSleepDataFallsBackRatherThanCountingTheNightAsOff() throws {
        pinCalendar()
        let tremorPath = try #require(Self.findCSV(prefix: "tremor_readings"))
        let medsPath = try #require(Self.findCSV(prefix: "medication_doses"))
        let samples = try Self.loadTremor(tremorPath)
        let doses = try Self.loadTakenDoses(medsPath)

        let card = try #require(CorrelationEngine.wearingOffInsight(samples: samples, doses: doses))
        let n = try #require(Self.uncovered(from: card))
        // The point of this test: with NO recorded sleep the card must still be roughly right,
        // and must never score an unconscious night as waking OFF.
        //
        // ⚠️ RE-PINNED Jul 28 2026: 483 → 503, against a measured-sleep answer of 502.
        // Censoring now runs on `censoringSleep`, whose guessed night starts AFTER any dose
        // logged that evening. He doses at 22:00 and his real sleep onset is ~midnight, so
        // refusing to call him asleep at 22:00 makes the guess markedly more accurate — the
        // fallback now tracks the measured answer almost exactly instead of under-claiming
        // by ~19 min.
        //
        // The old assertion `n < 502` is DELETED, not relaxed. "The fallback lands below the
        // measured answer" was an observation about the old numbers, never a derived property,
        // and at 503-vs-502 it was asserting a one-minute ordering between two different
        // censoring paths. What actually matters is tested below: close to the measured
        // answer, and nowhere near the failure modes on either side.
        #expect(abs(n - 502) <= 15, "fallback should track the measured-sleep answer: \(n)")
        #expect(n > 234, "must beat the old capped figure, which ignored whole evenings (got \(n))")
        #expect(n < 700, "must not be scoring the unconscious night as waking OFF (got \(n))")
    }

    /// Censoring must use MEASURED sleep only — never the fallback. A guessed 22:00 bedtime
    /// would discard a real 22:00 dose as "taken while asleep", when taking a pill is itself
    /// evidence of being awake. This dropped 35 of 106 doses off the parity fixture's curve
    /// before the measured/effective split existed.
    @Test func fallbackNeverCensorsARealMeasurement() throws {
        pinCalendar()
        // Dose exactly at the fallback bedtime, every day, and no measured sleep at all.
        let doses = (1..<31).map { Dose(timestamp: Self.at($0, 22), name: "Sinemet") }
        let samples = Self.series(days: 1..<31) { t in
            let h = Self.cal.component(.hour, from: t)
            if h >= 23 || h < 7 { return 0.0 }
            if h >= 22 { return 0.2 }               // the 22:00 dose visibly working
            return 1.5
        }
        let blind = CorrelationEngine.survivalDuration(
            signal: samples.map { (time: $0.timestamp, value: $0.tremorScore) },
            events: doses.map(\.timestamp), onThreshold: CorrelationEngine.offThreshold)
        // The primitive keeps every dose when given no measured sleep: it does not invent one.
        #expect(blind.durations.count == doses.count,
                "no measured sleep must mean no censoring — got \(blind.durations.count)/\(doses.count)")
    }

    // MARK: - 2. Scenario tests (synthetic)

    /// Sleep is SUBTRACTED from a gap: OFF is a waking quantity. A dose at 08:00 that
    /// holds ~3h, with the next dose 24h later, must count only the waking remainder.
    @Test func onceDailyRegimenStillGetsACard() throws {
        pinCalendar()
        // One dose/day at 08:00. Tremor: OFF (1.5) except a clean ON dip for ~3h after
        // each dose, and ~0 while asleep (as real sleep behaves).
        let doses = (1..<31).map { Dose(timestamp: Self.at($0, 8), name: "Sinemet") }
        let sleep = CorrelationEngine.mergeSleep((1..<31).map {
            SleepInterval(start: Self.at($0 - 1, 23), end: Self.at($0, 7))
        })
        let samples = Self.series(days: 1..<31) { t in
            let h = Self.cal.component(.hour, from: t)
            if h >= 23 || h < 7 { return 0.0 }          // asleep: tremor vanishes
            if h >= 8 && h < 11 { return 0.2 }          // dose working
            return 1.5                                   // OFF
        }

        let insight = try #require(
            CorrelationEngine.wearingOffInsight(samples: samples, doses: doses, sleep: sleep),
            "a once-daily regimen must still get a card: the old 600-min cap dropped its 24h gap whole and silenced the patient with the WORST wearing-off")
        let n = try #require(Self.uncovered(from: insight))
        // Waking 07:00-23:00 = 16h; ~3h covered => ~13h ≈ 780 min uncovered.
        #expect(n > 600, "expected most of the waking day uncovered, got \(n)")
    }

    /// A nap needs no special case — it is a sleep interval like any other, subtracted
    /// from the gap it falls inside.
    @Test func napInsideAGapIsSubtracted() throws {
        pinCalendar()
        let doses = (1..<31).flatMap { d in
            [Dose(timestamp: Self.at(d, 8), name: "Sinemet"),
             Dose(timestamp: Self.at(d, 18), name: "Sinemet")]
        }
        let night = (1..<31).map { SleepInterval(start: Self.at($0 - 1, 23), end: Self.at($0, 7)) }
        let nights = CorrelationEngine.mergeSleep(night)
        let withNap = CorrelationEngine.mergeSleep(
            night + (1..<31).map { SleepInterval(start: Self.at($0, 14), end: Self.at($0, 16)) })
        let samples = Self.series(days: 1..<31) { t in
            let h = Self.cal.component(.hour, from: t)
            if h >= 23 || h < 7 { return 0.0 }
            if h >= 14 && h < 16 { return 0.0 }         // napping: tremor vanishes
            if h >= 8 && h < 11 { return 0.2 }
            return 1.5
        }

        let noNap = try #require(CorrelationEngine.wearingOffInsight(
            samples: samples, doses: doses, sleep: nights))
        let napped = try #require(CorrelationEngine.wearingOffInsight(
            samples: samples, doses: doses, sleep: withNap))
        let a = try #require(Self.uncovered(from: noNap))
        let b = try #require(Self.uncovered(from: napped))
        // The 2h nap sits inside the 08:00 dose's uncovered stretch, so it comes off.
        #expect(b < a, "a nap must reduce waking uncovered time (\(b) vs \(a))")
        #expect(abs((a - b) - 120) <= 20, "expected ~120 min removed, got \(a - b)")
    }

    /// An `awake` interruption at 02:00 is simply ABSENT from the asleep list, so the
    /// OFF that drove a 2am rescue dose is still counted. This is why the adapter maps
    /// asleep* only and never `inBed`.
    @Test func nightInterruptionCountsAsWakingOff() throws {
        pinCalendar()
        let doses = (1..<31).map { Dose(timestamp: Self.at($0, 8), name: "Sinemet") }
        // Unbroken night vs. the same night with a 02:00-02:30 awake window.
        let unbroken = CorrelationEngine.mergeSleep(
            (1..<31).map { SleepInterval(start: Self.at($0 - 1, 23), end: Self.at($0, 7)) })
        let broken = CorrelationEngine.mergeSleep((1..<31).flatMap { d in
            [SleepInterval(start: Self.at(d - 1, 23), end: Self.at(d, 2)),
             SleepInterval(start: Self.at(d, 2, 30), end: Self.at(d, 7))]
        })
        let samples = Self.series(days: 1..<31) { t in
            let h = Self.cal.component(.hour, from: t)
            let m = Self.cal.component(.minute, from: t)
            if h == 2 && m < 30 { return 1.5 }          // awake, and OFF
            if h >= 23 || h < 7 { return 0.0 }
            if h >= 8 && h < 11 { return 0.2 }
            return 1.5
        }

        let unbrokenCard = try #require(
            CorrelationEngine.wearingOffInsight(samples: samples, doses: doses, sleep: unbroken))
        let brokenCard = try #require(
            CorrelationEngine.wearingOffInsight(samples: samples, doses: doses, sleep: broken))
        let a = try #require(Self.uncovered(from: unbrokenCard))
        let b = try #require(Self.uncovered(from: brokenCard))
        #expect(b > a, "a 30-min night waking must ADD waking OFF (\(b) vs \(a))")
    }

    /// With no sleep data at all the engine must not go silent — it synthesises a
    /// conservative 22:00-06:00 night. Fallback only: a day WITH sleep never gets one.
    @Test func fallbackSynthesisesAClockNightOnlyWhereSleepIsMissing() {
        pinCalendar()
        let range = Self.at(1, 0)...Self.at(3, 23)
        // Day 2 has real sleep; days 1 and 3 have none.
        let real = [SleepInterval(start: Self.at(1, 23), end: Self.at(2, 6, 30))]
        let eff = CorrelationEngine.effectiveSleep(recorded: real, covering: range)

        // The real night survives untouched (it ends 06:30, not the fallback's 06:00).
        #expect(eff.contains { $0.end == Self.at(2, 6, 30) }, "recorded sleep must win")
        // Day 3 got a synthetic 22:00->06:00 night.
        #expect(eff.contains { $0.start == Self.at(2, 22) && $0.end == Self.at(3, 6) },
                "a day with no sleep must get the fallback night")
        // Day 2 must NOT get one — it already has real sleep.
        #expect(!eff.contains { $0.start == Self.at(1, 22) && $0.end == Self.at(2, 6) },
                "a day with recorded sleep must never receive a synthetic night")
    }

    // MARK: - censoringSleep (built standalone ahead of the maxWindow change)
    //
    // Same synthesis as `effectiveSleep`, plus one rule: a guessed bedtime may never fall
    // before a dose logged that evening, because taking a pill proves the patient was awake.
    // That single rule is what lets censoring use a fallback at all — the naive version
    // discarded 35 of 106 real doses, which is why censoring previously refused any fallback.

    /// It agrees with `effectiveSleep` when no dose contradicts the guess: recorded nights
    /// win, missing nights get 22:00–06:00, covered days get nothing.
    @Test func censoringSleepSynthesisesOnlyWhereSleepIsMissing() {
        pinCalendar()
        let range = Self.at(1, 0)...Self.at(3, 23)
        let real = [SleepInterval(start: Self.at(1, 23), end: Self.at(2, 6, 30))]
        let s = CorrelationEngine.censoringSleep(recorded: real, doses: [], covering: range)

        #expect(s.contains { $0.end == Self.at(2, 6, 30) }, "recorded sleep must win")
        #expect(s.contains { $0.start == Self.at(2, 22) && $0.end == Self.at(3, 6) },
                "a day with no sleep must get the fallback night")
        #expect(!s.contains { $0.start == Self.at(1, 22) && $0.end == Self.at(2, 6) },
                "a day with recorded sleep must never receive a synthetic night")
    }

    /// ⭐ The rule that makes a censoring fallback safe: a 22:30 dose proves he was awake at
    /// 22:30, so the guessed night starts after it — never at 22:00, which would censor the
    /// dose to a zero-length window and discard it.
    @Test func censoringSleepNeverGuessesBedtimeBeforeAnEveningDose() {
        pinCalendar()
        let range = Self.at(1, 0)...Self.at(2, 23)
        let doses = [Self.at(1, 22, 30)]        // dosed after the guessed bedtime
        let s = CorrelationEngine.censoringSleep(recorded: [], doses: doses, covering: range)

        let night = try? #require(s.first { $0.start >= Self.at(1, 20) && $0.start < Self.at(2, 6) })
        let start = try? #require(night?.start)
        #expect(start.map { $0 > Self.at(1, 22, 30) } ?? false,
                "bedtime must be pushed past the 22:30 dose, got \(String(describing: start))")
        // And it must still end at the normal wake hour — only the start moves.
        #expect(night?.end == Self.at(2, 6))
    }

    /// A recorded night is never overridden by the dose rule — the rule only ever applies to
    /// a night we invented. A night owl with real sleep data keeps their real 02:00 bedtime.
    @Test func censoringSleepLeavesRecordedNightsAloneEvenWithLateDoses() {
        pinCalendar()
        let range = Self.at(1, 0)...Self.at(2, 23)
        let real = [SleepInterval(start: Self.at(2, 2), end: Self.at(2, 9))]   // asleep 02:00
        let doses = [Self.at(1, 23, 45)]                                        // dosed 23:45
        let s = CorrelationEngine.censoringSleep(recorded: real, doses: doses, covering: range)

        #expect(s.contains { $0.start == Self.at(2, 2) && $0.end == Self.at(2, 9) },
                "a recorded 02:00 bedtime must survive untouched")
        #expect(!s.contains { $0.start == Self.at(1, 22) },
                "the night was recorded, so no synthetic night may be added for it")
    }

    /// An evening dose whose coverage runs into sleep contributes ~nothing — no hour
    /// filter needed. The old `hour >= 6 && < 20` test was standing in for exactly this.
    @Test func eveningDoseCoveredBySleepContributesNothing() throws {
        pinCalendar()
        // 08:00 and 22:00 doses. The 22:00 dose holds ~3h; he's asleep from 23:00.
        let doses = (1..<31).flatMap { d in
            [Dose(timestamp: Self.at(d, 8), name: "Sinemet"),
             Dose(timestamp: Self.at(d, 22), name: "Sinemet")]
        }
        let sleep = CorrelationEngine.mergeSleep(
            (1..<31).map { SleepInterval(start: Self.at($0 - 1, 23), end: Self.at($0, 7)) })
        let samples = Self.series(days: 1..<31) { t in
            let h = Self.cal.component(.hour, from: t)
            if h >= 23 || h < 7 { return 0.0 }
            if (h >= 8 && h < 11) || h >= 22 { return 0.2 }
            return 1.5
        }
        let insight = try #require(CorrelationEngine.wearingOffInsight(
            samples: samples, doses: doses, sleep: sleep))
        let n = try #require(Self.uncovered(from: insight))
        // Waking 07:00-23:00 = 16h. Covered 08:00-11:00 and 22:00-23:00 => ~12h ≈ 720 uncovered.
        // The 22:00 dose's own gap runs into sleep and must add ~0 of it.
        #expect(n > 600 && n < 820, "got \(n)")
    }

    // MARK: - Observation window (the maxWindow removal)
    //
    // A dose's window is bounded by EVENTS — the next dose, and sleep onset — never by a clock.
    // The old 300-min cap made a long-acting drug invisible: an 8 h drug never showed an ending
    // inside 5 h, so its duration read "not estimable", and after the classification collapse
    // that means no coverage and no forecast band at all.
    //
    // The two guards below go through `censoringSleep`, which is where a real caller gets its
    // sleep. They must NOT pass `sleep:` straight to `survivalDuration` — there, `[]` means
    // "do not censor" by contract, so they would be testing a path no user is ever on.

    /// A once-daily long-acting drug (8 h) MUST yield a duration. Dose 08:00, next dose 24 h
    /// later, asleep 23:00 — sleep bounds the window at 15 h, no clock involved.
    /// ⛔ Fails under the old 300-min cap: nothing is ever observed ending.
    @Test func longActingOnceDailyRecoversItsDuration() throws {
        pinCalendar()
        let trueOn = 480.0
        let doses = (1..<31).map { Dose(timestamp: Self.at($0, 8), name: "Rytary") }
        let sleep = CorrelationEngine.mergeSleep(
            (1..<31).map { SleepInterval(start: Self.at($0 - 1, 23), end: Self.at($0, 7)) })
        let samples = Self.series(days: 1..<31) { t in
            let h = Self.cal.component(.hour, from: t)
            if h >= 23 || h < 7 { return 0.0 }
            let mins = t.timeIntervalSince(Self.at(Self.cal.component(.day, from: t), 8)) / 60
            if mins < 0 { return 2.0 }
            if mins < 45 { return 2.0 - (mins / 45) * 1.6 }
            if mins < trueOn { return 0.4 }
            if mins < trueOn + 30 { return 0.4 + ((mins - trueOn) / 30) * 1.6 }
            return 2.0
        }
        let surv = CorrelationEngine.survivalDuration(
            signal: samples.map { (time: $0.timestamp, value: $0.tremorScore) },
            events: doses.map(\.timestamp),
            onThreshold: CorrelationEngine.offThreshold, sleep: sleep)
        #expect(surv.kmMedian.isFinite, "an 8h drug must produce a duration, not silence")
        // ~480 plus the sustained-OFF-return detection lag (~18 min).
        #expect(surv.kmMedian > 420 && surv.kmMedian < 580, "got \(surv.kmMedian)")
    }

    /// GUARD — an evening dose for a user with NO recorded sleep must not read as lasting all
    /// night. Tremor is 0 overnight because he is asleep, not because the drug is working.
    /// `censoringSleep` supplies the guessed night that prevents it, and its dose-respecting
    /// rule is what stops that guess from discarding the 22:00 dose outright.
    @Test func eveningDoseWithoutSleepDataDoesNotInflate() throws {
        pinCalendar()
        let trueOn = 180.0
        let doses = (1..<31).map { Dose(timestamp: Self.at($0, 22), name: "Sinemet") }
        let samples = Self.series(days: 1..<31) { t in
            let h = Self.cal.component(.hour, from: t)
            return (h >= 23 || h < 7) ? 0.0 : 1.5
        }
        let censor = CorrelationEngine.censoringSleep(
            recorded: [], doses: doses.map(\.timestamp),
            covering: Self.at(1, 0)...Self.at(31, 0))
        let surv = CorrelationEngine.survivalDuration(
            signal: samples.map { (time: $0.timestamp, value: $0.tremorScore) },
            events: doses.map(\.timestamp),
            onThreshold: CorrelationEngine.offThreshold, sleep: censor)

        if surv.kmMedian.isFinite {
            #expect(surv.kmMedian < trueOn + 120, "inflated to \(surv.kmMedian)")
        }
        // No dose may be DISCARDED by the guess — a 22:00 dose proves he was awake at 22:00.
        #expect(surv.durations.count == doses.count,
                "the guessed night threw away \(doses.count - surv.durations.count) real doses")
    }

    /// GUARD — a user who normally records sleep but MISSED one night must not have that night's
    /// dose watched until tomorrow's bedtime. `sleepOnset` returns the NEXT recorded interval, so
    /// without a per-night fallback the window silently reaches ~24 h on exactly the users who
    /// look best covered.
    @Test func oneMissingSleepNightDoesNotOpenA24HourWindow() throws {
        pinCalendar()
        let missingDay = 15
        let doses = (1..<31).map { Dose(timestamp: Self.at($0, 20), name: "Sinemet") }
        let recorded = CorrelationEngine.mergeSleep(
            (1..<31).compactMap { d in
                d == missingDay + 1 ? nil     // the night after day 15 was never recorded
                    : SleepInterval(start: Self.at(d - 1, 23), end: Self.at(d, 7))
            })
        let samples = Self.series(days: 1..<31) { t in
            let h = Self.cal.component(.hour, from: t)
            return (h >= 23 || h < 7) ? 0.0 : 1.5
        }
        let censor = CorrelationEngine.censoringSleep(
            recorded: recorded, doses: doses.map(\.timestamp),
            covering: Self.at(1, 0)...Self.at(31, 0))
        let surv = CorrelationEngine.survivalDuration(
            signal: samples.map { (time: $0.timestamp, value: $0.tremorScore) },
            events: doses.map(\.timestamp),
            onThreshold: CorrelationEngine.offThreshold, sleep: censor)

        let longest = surv.durations.map(\.durationMin).filter { !$0.isNaN }.max() ?? 0
        #expect(longest < 12 * 60, "a missing night opened a \(longest / 60)h window")
    }

    // MARK: - KM median precision (parity with the Python reference)
    //
    // `kmMedianPrecisionMin` is hand-rolled Brookmeyer–Crowley and had NO numeric oracle when
    // it was written — the only tests were an ordering property (thin is less precise than
    // dense) and the floor, both of which would pass with wrong arithmetic. These two cases
    // fix that. Values produced by statsmodels `SurvfuncRight` on the SAME fixed inputs:
    //
    //   case A  dur/obs below      KM median 195.0   90% CI [135.0, 210.0]   half-width 37.5
    //   case B  tight, uncensored  KM median 110.0   90% CI [105.0, 110.0]   half-width  2.5
    //
    // Deliberately fixed lists rather than a backup, so the arithmetic itself is exercised and
    // the test can't drift with the data.

    /// A spread sample with censoring — a genuinely wide interval, so the band arithmetic is
    /// doing real work rather than landing on the floor.
    @Test func precisionMatchesPythonOnASpreadSample() {
        let dur: [Double] = [60,75,90,105,120,135,150,165,180,195,210,225,240,255,270,285]
        let obs: [Bool] = [true,true,false,true,true,true,false,true,true,true,true,false,true,true,false,true]
        #expect(abs(CorrelationEngine.kmMedian(durations: dur, observed: obs) - 195.0) < 0.001,
                "KM median must match the reference before its precision can mean anything")
        let p = CorrelationEngine.kmMedianPrecisionMin(durations: dur, observed: obs)
        #expect(abs(p - 37.5) < 0.001, "Brookmeyer–Crowley half-width, got \(p) want 37.5")
    }

    /// A tight, fully observed sample: the reference half-width is exactly the bin floor, so
    /// this pins that the floor and the arithmetic agree rather than the floor hiding a bug.
    @Test func precisionMatchesPythonOnATightSample() {
        let dur: [Double] = [100,100,105,105,105,110,110,110,110,115,115,115,120,120,125,125]
        let obs = [Bool](repeating: true, count: 16)
        #expect(abs(CorrelationEngine.kmMedian(durations: dur, observed: obs) - 110.0) < 0.001)
        let p = CorrelationEngine.kmMedianPrecisionMin(durations: dur, observed: obs)
        #expect(abs(p - 2.5) < 0.001, "tight sample half-width, got \(p) want 2.5")
    }

    /// No median → no precision. Silence, not a fabricated ±.
    @Test func precisionIsAbsentWhenTheMedianIs() {
        // Mostly censored early: the curve never reaches 50%.
        let dur: [Double] = [100,110,120,130,140]
        let obs: [Bool] = [false,false,false,false,false]
        #expect(CorrelationEngine.kmMedian(durations: dur, observed: obs).isNaN)
        #expect(CorrelationEngine.kmMedianPrecisionMin(durations: dur, observed: obs).isNaN)
    }

    // MARK: - Loaders

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static func date(_ s: String) -> Date? { iso.date(from: s) ?? isoPlain.date(from: s) }

    private static func findCSV(prefix: String) -> String? {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: backupDir),
              let name = files.first(where: { $0.hasPrefix(prefix) && $0.hasSuffix(".csv") })
        else { return nil }
        return backupDir + "/" + name
    }

    private static func rows(_ path: String) throws -> (idx: [String: Int], data: [[String]]) {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !lines.isEmpty else { return ([:], []) }
        let header = lines.removeFirst().split(separator: ",").map(String.init)
        var idx: [String: Int] = [:]
        for (i, h) in header.enumerated() { idx[h] = i }
        return (idx, lines.map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) })
    }

    private static func loadTremor(_ path: String) throws -> [TremorPoint] {
        let (idx, data) = try rows(path)
        guard let tsi = idx["timestamp"], let tri = idx["tremorScore"] else { return [] }
        return data.compactMap { r in
            guard r.count > max(tsi, tri), let ts = date(r[tsi]), let v = Double(r[tri]) else { return nil }
            return TremorPoint(timestamp: ts, tremorScore: v)
        }
    }

    private static func loadTakenDoses(_ path: String) throws -> [Dose] {
        let (idx, data) = try rows(path)
        guard let sdi = idx["startDate"], let sti = idx["status"], let mni = idx["medicationName"]
        else { return [] }
        return data.compactMap { r in
            guard r.count > max(sdi, sti, mni),
                  r[sti].trimmingCharacters(in: .whitespaces).lowercased() == "taken",
                  let ts = date(r[sdi]) else { return nil }
            return Dose(timestamp: ts, name: r[mni].trimmingCharacters(in: .whitespaces))
        }
    }

    /// asleep* only — never `inBed`, never `awake`. Mirrors `fetchSleepIntervals`.
    private static func loadAsleepIntervals(_ path: String) throws -> [SleepInterval] {
        let (idx, data) = try rows(path)
        guard let sdi = idx["startDate"], let edi = idx["endDate"], let sti = idx["stage"]
        else { return [] }
        let asleep: Set<String> = ["asleepcore", "asleepdeep", "asleeprem", "asleepunspecified"]
        return data.compactMap { r in
            guard r.count > max(sdi, edi, sti),
                  asleep.contains(r[sti].trimmingCharacters(in: .whitespaces).lowercased()),
                  let s = date(r[sdi]), let e = date(r[edi]), e > s else { return nil }
            return SleepInterval(start: s, end: e)
        }
    }
}
