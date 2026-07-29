//
//  MedicationCardTests.swift
//  PD CompanionTests
//
//  Group 4 step 4 — the per-substance card renderer. docs/design/medication-cards.md.
//
//  The two rules settled by measurement on Jul 29, and the property the whole feature rests on:
//    · cross-substance window — a dose's observation ends at the next dose of ANY substance
//    · observability — a dose taken while tremor is already settled is excluded from every
//      statement, because there is no fall to measure and no return to watch for
//    · ⭐ a substance earns a card by being TAKEN, never by having worked
//
//  The real-record test at the bottom checks the PREDICTION the design doc committed to before
//  this was built: excluding unobservable doses should bring Mucuna's duration near 48 min,
//  down from the ~92 that eleven sleep-censored night doses were inflating it to.
//

import Foundation
import Testing
@testable import PD_Companion

struct MedicationCardTests {

    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    private func pinCalendar() { CorrelationEngine.calendar = Self.cal }

    private static func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: day, hour: h, minute: m))!
    }

    /// Tremor at 5-min steps: OFF (1.6) unless inside an ON window (0.2) or asleep (0.0).
    private static func series(days: Range<Int>, on: [(Date, Double)],
                               sleep: [SleepInterval] = []) -> [TremorPoint] {
        let windows = on.map { ($0.0, $0.0.addingTimeInterval($0.1 * 60)) }
        var out: [TremorPoint] = []
        var t = at(days.lowerBound, 0)
        let end = at(days.upperBound - 1, 23, 55)
        while t <= end {
            let v: Double
            if sleep.contains(where: { $0.start <= t && t < $0.end }) { v = 0.0 }
            else if windows.contains(where: { $0.0 <= t && t < $0.1 }) { v = 0.2 }
            else { v = 1.6 }
            out.append(TremorPoint(timestamp: t, tremorScore: v))
            t = t.addingTimeInterval(5 * 60)
        }
        return out
    }

    private static func nights(_ days: Range<Int>, from: Int, to: Int) -> [SleepInterval] {
        CorrelationEngine.mergeSleep(days.map {
            SleepInterval(start: at($0 - 1, from), end: at($0, to))
        })
    }

    // MARK: - ⭐ Existence is decoupled from effect

    /// A substance that does nothing must still get a card, and the card must say what it
    /// can't show rather than not existing. This is the case a "show it once it works" gate
    /// would delete — and the newest, thinnest substance is exactly where that bias bites.
    @Test func anInertSubstanceStillGetsACardThatExplainsItself() throws {
        pinCalendar()
        let days = 1..<25
        var doses: [Dose] = []
        var on: [(Date, Double)] = []
        for d in days {
            doses.append(Dose(timestamp: Self.at(d, 8), name: "Sinemet"))
            on.append((Self.at(d, 8), 180))                       // Sinemet visibly works
            doses.append(Dose(timestamp: Self.at(d, 14), name: "Vitamin D"))  // nothing happens
        }
        let sleep = Self.nights(days, from: 23, to: 7)
        let samples = Self.series(days: days, on: on, sleep: sleep)

        let card = try #require(CorrelationEngine.medicationInsight(
            key: "vitamin d", samples: samples, allDoses: doses, sleep: sleep),
            "an inert substance must still earn a card — that is the whole design")
        #expect(card.title.contains("Vitamin D"))
        #expect(card.finding.contains("24 doses"), "it must still report what was logged")
        #expect(card.finding.lowercased().contains("can't"),
                "and say plainly what it cannot show: \(card.finding)")
        // Sinemet's own card is unaffected and does measure a duration.
        let sinemet = try #require(CorrelationEngine.medicationInsight(
            key: "sinemet", samples: samples, allDoses: doses, sleep: sleep))
        #expect(sinemet.title.contains("holds"), "got: \(sinemet.title)")
    }

    /// ⛔ Each card speaks only about its own substance. Cross-substance ranking is not
    /// established (log-rank p=0.52 on the reference data) and is a dosing judgment the safety
    /// line forbids — so no card may name another substance, ever.
    @Test func aCardNeverMentionsAnotherSubstance() throws {
        pinCalendar()
        let days = 1..<25
        var doses: [Dose] = []
        var on: [(Date, Double)] = []
        for d in days {
            doses.append(Dose(timestamp: Self.at(d, 8), name: "Sinemet"))
            on.append((Self.at(d, 8), 180))
            doses.append(Dose(timestamp: Self.at(d, 15), name: "Mucuna Pruriens"))
            on.append((Self.at(d, 15), 60))
        }
        let sleep = Self.nights(days, from: 23, to: 7)
        let samples = Self.series(days: days, on: on, sleep: sleep)
        for (key, forbidden) in [("mucuna pruriens", "sinemet"), ("sinemet", "mucuna")] {
            let card = try #require(CorrelationEngine.medicationInsight(
                key: key, samples: samples, allDoses: doses, sleep: sleep))
            let text = [card.title, card.summary, card.finding, card.mechanism,
                        card.clinical?.whatTheyMightConsider ?? ""]
                .joined(separator: " ").lowercased()
                + (card.clinical?.bringThisData.joined(separator: " ").lowercased() ?? "")
            #expect(!text.contains(forbidden),
                    "\(key)'s card named \(forbidden): \(text)")
        }
    }

    // MARK: - Rule 1: the cross-substance window

    /// A second substance taken in between must END the first one's observation. Otherwise
    /// part of what is reported as one drug's duration is another drug's effect — measured on
    /// the real record as a Mucuna dose being watched for a median of 1600 min.
    @Test func anotherSubstancesDoseEndsTheObservation() throws {
        pinCalendar()
        let days = 1..<25
        var doses: [Dose] = []
        var on: [(Date, Double)] = []
        for d in days {
            // The substance under test, once a day, genuinely holding ~60 min.
            doses.append(Dose(timestamp: Self.at(d, 9), name: "Adjunct"))
            on.append((Self.at(d, 9), 60))
            // A different substance 90 min later, holding 4h — without the cross-substance
            // rule this ON stretch would be attributed to Adjunct, whose next dose is 24h away.
            doses.append(Dose(timestamp: Self.at(d, 10, 30), name: "Sinemet"))
            on.append((Self.at(d, 10, 30), 240))
        }
        let sleep = Self.nights(days, from: 23, to: 7)
        let samples = Self.series(days: days, on: on, sleep: sleep)

        let card = try #require(CorrelationEngine.medicationInsight(
            key: "adjunct", samples: samples, allDoses: doses, sleep: sleep))
        // Adjunct really holds ~60 min. Truncated at the Sinemet dose (90 min later) it can
        // still be seen ending. Carried to its own next dose it would run through Sinemet's
        // four-hour ON stretch and read far longer.
        let mins = Self.durationFrom(card)
        #expect(mins != nil, "expected a measured duration, got: \(card.title)")
        if let m = mins {
            #expect(m < 120, """
                    Adjunct holds ~60 min; \(m) min means it absorbed the other substance's \
                    ON stretch
                    """)
        }
    }

    /// Pull the headline minutes back out of the card's own title, so the assertion reads what
    /// the user reads rather than an internal value.
    private static func durationFrom(_ card: Insight) -> Int? {
        let t = card.title
        guard t.contains("holds") else { return nil }
        var hours = 0, mins = 0
        if let hRange = t.range(of: #"(\d+)h"#, options: .regularExpression) {
            hours = Int(t[hRange].dropLast()) ?? 0
        }
        if let mRange = t.range(of: #"(\d+) min"#, options: .regularExpression) {
            mins = Int(t[mRange].split(separator: " ")[0]) ?? 0
        } else if let mRange = t.range(of: #"h (\d+)m"#, options: .regularExpression) {
            mins = Int(t[mRange].dropFirst(2).dropLast()) ?? 0
        }
        return hours * 60 + mins
    }

    // MARK: - Rule 2: observability

    /// A dose taken while tremor is ALREADY settled has no fall to measure and no return to
    /// watch for. Carrying such doses as "still working at t" inflated the real Mucuna
    /// duration from ~48 to ~92 min. They must be excluded — and counted out loud.
    @Test func dosesTakenWhileAlreadySettledAreExcludedAndExplained() throws {
        pinCalendar()
        let days = 1..<25
        var doses: [Dose] = []
        var on: [(Date, Double)] = []
        for d in days {
            // Readable: taken while OFF, holds 60 min.
            doses.append(Dose(timestamp: Self.at(d, 9), name: "Adjunct"))
            on.append((Self.at(d, 9), 60))
            // Unreadable: taken at 03:00, mid-sleep, tremor already 0.
            doses.append(Dose(timestamp: Self.at(d, 3), name: "Adjunct"))
        }
        let sleep = Self.nights(days, from: 23, to: 7)
        let samples = Self.series(days: days, on: on, sleep: sleep)

        let card = try #require(CorrelationEngine.medicationInsight(
            key: "adjunct", samples: samples, allDoses: doses, sleep: sleep))
        #expect(card.finding.contains("couldn't be measured"),
                "the card must account for the excluded doses: \(card.finding)")
        // ⭐ And it must name the INSTRUMENT, not the drug — the substance may well be doing
        // something tremor cannot see. "tells us nothing" is both wrong and dismissive.
        #expect(!card.finding.lowercased().contains("tell us nothing"))
        #expect(card.finding.contains("through tremor"),
                "row 4 must name what we measure with: \(card.finding)")
        // The excluded doses must not drag the duration up.
        if let m = Self.durationFrom(card) {
            #expect(m < 120, "night doses appear to still be inflating the duration (\(m) min)")
        }
    }

    // MARK: - The statement set flexes with what the data supports

    /// A long-acting once-daily substance never wears off before the next dose, so it has no
    /// measurable duration at all — only a floor. That is a finding, not a failure, and it is
    /// the shape of a drug that is WORKING. The card must say so rather than go dark.
    @Test func aLongActingSubstanceReportsAFloorNotADuration() throws {
        pinCalendar()
        let days = 1..<25
        var doses: [Dose] = []
        var on: [(Date, Double)] = []
        for d in days {
            doses.append(Dose(timestamp: Self.at(d, 8), name: "Extended Release"))
            on.append((Self.at(d, 8), 15 * 60))   // still working when the next dose arrives
        }
        // Sleep must extend one night PAST the last dose, or that dose alone is never censored
        // and a single tail event drives the whole KM median.
        let sleep = Self.nights(1..<26, from: 23, to: 7)
        let samples = Self.series(days: days, on: on, sleep: sleep)
        let card = try #require(CorrelationEngine.medicationInsight(
            key: "extended release", samples: samples, allDoses: doses, sleep: sleep))
        #expect(card.finding.contains("at least that long"),
                "expected the at-least floor: \(card.finding)")
        #expect(Self.durationFrom(card) == nil,
                "a substance never seen wearing off must not print a duration: \(card.title)")
    }

    /// Three doses of something brand new: the card exists, reports what was logged, and does
    /// not manufacture the statements it cannot support.
    @Test func aBrandNewSubstanceReportsOnlyWhatItHas() throws {
        pinCalendar()
        let doses = [1, 3, 6].map { Dose(timestamp: Self.at($0, 9), name: "Ashwagandha") }
        let samples = Self.series(days: 1..<8, on: [], sleep: Self.nights(1..<8, from: 23, to: 7))
        let card = try #require(CorrelationEngine.medicationInsight(
            key: "ashwagandha", samples: samples, allDoses: doses,
            sleep: Self.nights(1..<8, from: 23, to: 7)))
        #expect(card.title.contains("Ashwagandha"))
        #expect(card.finding.contains("3 doses"))
        #expect(card.confidence == .emerging)
    }

    // MARK: - The chart must describe the same doses as the number above it

    /// ⭐ Found on device: Mucuna's card drew a curve from ONE dose while its duration came from
    /// eight, because `wearingOffChart` keeps only doses with no other dose for 240 min after —
    /// a filter written for the POOLED curve, which the cross-substance window disqualifies
    /// almost everything from. The visible symptom was the "worn off" marker (48 min, from 8
    /// doses) landing BEFORE the "deepest ON" dot (78 min, from that 1), reading as though the
    /// dose wore off before it started working.
    @Test func theChartRestsOnTheSameDosesAsTheDuration() throws {
        pinCalendar()
        let days = 1..<25
        var doses: [Dose] = []
        var on: [(Date, Double)] = []
        for d in days {
            // Dosed every 3h — so NO dose is ever 240 min clear of the next, and the
            // isolated-only filter would keep nothing at all.
            for (i, h) in [8, 11, 14, 17].enumerated() {
                doses.append(Dose(timestamp: Self.at(d, h), name: "Adjunct"))
                on.append((Self.at(d, h), i == 3 ? 60 : 90))
            }
        }
        let sleep = Self.nights(1..<26, from: 23, to: 7)
        let samples = Self.series(days: days, on: on, sleep: sleep)

        let card = try #require(CorrelationEngine.medicationInsight(
            key: "adjunct", samples: samples, allDoses: doses, sleep: sleep))
        guard case .wearingOff(let ch)? = card.chart else {
            Issue.record("expected a wearing-off curve, got \(String(describing: card.chart))")
            return
        }
        // Under the old isolated-only rule this fixture yields ZERO usable doses.
        #expect(ch.curve.doseCount > 1, """
                the curve rests on \(ch.curve.doseCount) dose(s) — a per-substance card must \
                not plot a single dose as the typical shape
                """)
        // And the two markers must be readable together: a dose cannot wear off before it
        // reaches its deepest effect.
        if !ch.medianDurationMin.isNaN && !ch.bestOnMinute.isNaN {
            #expect(ch.medianDurationMin >= ch.bestOnMinute, """
                    worn-off marker (\(ch.medianDurationMin)) sits before deepest-ON \
                    (\(ch.bestOnMinute)) — the two are being computed from different doses
                    """)
        }
    }

    /// The pooled wearing-off card must keep isolation. Its curve is an average across
    /// formulations, where an overlapping dose genuinely does contaminate the shape.
    @Test func thePooledCardStillFiltersToIsolatedDoses() throws {
        pinCalendar()
        let days = 1..<25
        var doses: [Dose] = []
        var on: [(Date, Double)] = []
        for d in days {
            for h in [8, 11, 14, 17] {
                doses.append(Dose(timestamp: Self.at(d, h), name: "Sinemet"))
                on.append((Self.at(d, h), 90))
            }
        }
        let sleep = Self.nights(1..<26, from: 23, to: 7)
        let samples = Self.series(days: days, on: on, sleep: sleep)
        let surv = CorrelationEngine.survivalDuration(
            signal: samples.map { (time: $0.timestamp, value: $0.tremorScore) },
            events: doses.map(\.timestamp), onThreshold: CorrelationEngine.offThreshold,
            sleep: sleep)
        guard case .wearingOff(let strict) = CorrelationEngine.wearingOffChart(
                results: surv.durations, km: surv.kmMedian),
              case .wearingOff(let loose) = CorrelationEngine.wearingOffChart(
                results: surv.durations, km: surv.kmMedian, isolatedOnly: false) else {
            Issue.record("expected wearing-off charts"); return
        }
        #expect(strict.curve.doseCount < loose.curve.doseCount, """
                the default must still drop non-isolated doses \
                (\(strict.curve.doseCount) vs \(loose.curve.doseCount))
                """)
    }

    // MARK: - The prediction the design doc made before this was built

    static let backupDir =
        "/Users/bhav/Documents/ParkinsonsProject/PD Companion/PD Companion Backups/07-24-2026"

    /// docs/design/medication-cards.md committed to a PREDICTION before the renderer existed:
    /// excluding doses taken while tremor was already settled should bring Mucuna's duration
    /// near 48 min, down from the ~92 that eleven sleep-censored night doses inflated it to.
    /// This is that prediction, checked. If it fails, the design note is wrong, not the test.
    @Test func mucunaMatchesThePredictedDurationOnTheRealRecord() throws {
        pinCalendar()
        guard let tremorPath = Self.findCSV(prefix: "tremor_readings"),
              let medsPath = Self.findCSV(prefix: "medication_doses"),
              let sleepPath = Self.findCSV(prefix: "sleep_stages") else {
            Issue.record("Backup not found at \(Self.backupDir) — run on a Simulator, not a device.")
            return
        }
        let samples = try Self.loadTremor(tremorPath)
        let doses = try Self.loadTakenDoses(medsPath)
        let sleep = try Self.loadAsleepIntervals(sleepPath)
        #expect(doses.count == 273, "taken dose count on the 07-24 export")

        let card = try #require(CorrelationEngine.medicationInsight(
            key: "mucuna pruriens", samples: samples, allDoses: doses, sleep: sleep))
        let mins = try #require(Self.durationFrom(card),
                                "expected a measured duration, got title: \(card.title)")
        #expect(abs(mins - 48) <= 12, """
                design doc predicted ~48 min after excluding unobservable doses; got \(mins). \
                Title: \(card.title)
                """)
        #expect(mins < 80,
                "must be well below the ~92 min that the sleep-censored night doses produced")
        // And the eleven unobservable night doses must be accounted for on the card itself.
        #expect(card.finding.contains("couldn't be measured"),
                "the excluded doses must be visible to the reader: \(card.finding)")
    }

    // MARK: - Loaders

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
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
            guard r.count > max(sdi, max(sti, mni)),
                  r[sti].trimmingCharacters(in: .whitespaces).lowercased() == "taken",
                  let ts = date(r[sdi]) else { return nil }
            return Dose(timestamp: ts, name: r[mni].trimmingCharacters(in: .whitespaces))
        }
    }
    private static func loadAsleepIntervals(_ path: String) throws -> [SleepInterval] {
        let (idx, data) = try rows(path)
        guard let sdi = idx["startDate"], let edi = idx["endDate"], let sti = idx["stage"]
        else { return [] }
        let asleep: Set<String> = ["asleepcore", "asleepdeep", "asleeprem", "asleepunspecified"]
        return data.compactMap { r in
            guard r.count > max(sdi, max(edi, sti)),
                  asleep.contains(r[sti].trimmingCharacters(in: .whitespaces).lowercased()),
                  let s = date(r[sdi]), let e = date(r[edi]), e > s else { return nil }
            return SleepInterval(start: s, end: e)
        }
    }
}
