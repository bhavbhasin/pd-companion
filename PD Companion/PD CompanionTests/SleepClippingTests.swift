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
        // 483 with the fallback vs 502 with this user's real sleep — the fallback lands
        // BELOW the measured answer, which is the whole intent: 22:00 is a conservative
        // bedtime (his real onset is ~midnight) and without measured sleep nothing is
        // censored, so the dose reads longer-lasting. It errs toward under-claiming.
        #expect(abs(n - 483) <= 5, "fallback figure drifted: \(n)")
        #expect(n < 502, "fallback must not exceed the measured-sleep answer (got \(n))")
        #expect(n > 234, "fallback must still beat the old capped figure (got \(n))")
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
