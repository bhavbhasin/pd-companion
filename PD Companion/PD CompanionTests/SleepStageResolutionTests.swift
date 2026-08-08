//
//  SleepStageResolutionTests.swift
//  PD CompanionTests
//
//  Chain A Rule 2: between two sources of EQUAL capability, `awake` must stop being the weakest
//  claim. `stagePriority` ranked every asleep stage above awake, so one instrument's sleep painted
//  over another's detected wakefulness. Measured on the 07-30 export: Watch awake vs Oura asleep
//  490 min, Oura awake vs Watch asleep 527 min — ~17 h, all of it scored as sleep.
//
//  ⛔ These pin the RESOLUTION, not the score. `resolveStages` is the pure half of
//  `flattenSleepStages`; the HK-typed half cannot be tested because `tier` comes from
//  `sourceRevision`, which HealthKit owns and a locally-built sample cannot fake.
//

import Foundation
import Testing
@testable import PD_Companion

struct SleepStageResolutionTests {

    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private static func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: h, minute: m))!
    }

    private static func span(_ from: Date, _ to: Date,
                             _ stage: SleepStage, tier: Int) -> HealthKitManager.StagedSpan {
        HealthKitManager.StagedSpan(start: from, end: to, stage: stage, tier: tier)
    }

    private static func minutes(_ segs: [SleepStageSegment], _ stage: SleepStage) -> Double {
        segs.filter { $0.stage == stage }
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60
    }

    /// ⭐ THE RULE. Two staging sources, same tier, flatly contradicting each other. The one that
    /// DETECTED something — wakefulness — is not the one to discard.
    @Test func aDetectedWakefulnessIsNotOverwrittenByAnotherInstrumentsSleep() {
        let segs = HealthKitManager.resolveStages([
            Self.span(Self.at(1, 0), Self.at(3, 0), .core, tier: 1),   // Oura: asleep
            Self.span(Self.at(1, 30), Self.at(2, 0), .awake, tier: 1), // Watch: awake, measured
        ])
        #expect(Self.minutes(segs, .awake) == 30,
                "the 30 measured awake minutes were painted over as sleep")
        #expect(Self.minutes(segs, .core) == 90)
    }

    /// The reverse pairing must behave identically — the rule is about capability, never about
    /// which source happens to be named first or which one is Apple's.
    @Test func theRuleIsSymmetricBetweenTheTwoInstruments() {
        let a = HealthKitManager.resolveStages([
            Self.span(Self.at(1, 0), Self.at(3, 0), .deep, tier: 1),
            Self.span(Self.at(1, 30), Self.at(2, 0), .awake, tier: 1),
        ])
        let b = HealthKitManager.resolveStages([
            Self.span(Self.at(1, 30), Self.at(2, 0), .awake, tier: 1),
            Self.span(Self.at(1, 0), Self.at(3, 0), .deep, tier: 1),
        ])
        #expect(Self.minutes(a, .awake) == Self.minutes(b, .awake))
        #expect(Self.minutes(a, .awake) == 30)
    }

    /// ⛔ THE PROTECTION THAT MUST SURVIVE. The rule this replaces existed so "a stray awake layer
    /// never carves a hole in real sleep". That job belongs to `tier`, which is compared FIRST —
    /// a COARSE source's awake still loses to a stager's sleep. If this ever fails, Rule 2 went
    /// too far and AutoSleep-style sources are punching holes in the Watch's night.
    @Test func aCoarseSourcesAwakeStillCannotCarveAHoleInAStagersSleep() {
        let segs = HealthKitManager.resolveStages([
            Self.span(Self.at(1, 0), Self.at(3, 0), .core, tier: 1),    // Watch: staged sleep
            Self.span(Self.at(1, 30), Self.at(2, 0), .awake, tier: 0),  // coarse source: awake
        ])
        #expect(Self.minutes(segs, .awake) == 0, "a coarse source overruled a staging source")
        #expect(Self.minutes(segs, .core) == 120)
    }

    /// A coarse source still gap-fills where the stager tracked nothing — Rule 1's branch, which
    /// Rule 2 must leave alone.
    @Test func aCoarseSourceStillFillsWhereNoStagerTracked() {
        let segs = HealthKitManager.resolveStages([
            Self.span(Self.at(1, 0), Self.at(2, 0), .core, tier: 1),
            Self.span(Self.at(2, 0), Self.at(3, 0), .core, tier: 0),
        ])
        #expect(Self.minutes(segs, .core) == 120)
    }

    /// Deep and REM still outrank core, so the stage breakdown is unchanged where nobody
    /// disagrees about being asleep. Rule 2 changed one comparison, not the ordering.
    @Test func asleepStagesKeepTheirOrderAmongThemselves() {
        let segs = HealthKitManager.resolveStages([
            Self.span(Self.at(1, 0), Self.at(2, 0), .core, tier: 1),
            Self.span(Self.at(1, 0), Self.at(1, 30), .deep, tier: 1),
        ])
        #expect(Self.minutes(segs, .deep) == 30)
        #expect(Self.minutes(segs, .core) == 30)
        #expect(Self.minutes(segs, .awake) == 0)
    }

    // MARK: - Real record

    static let backupDir =
        "/Users/bhav/Documents/ParkinsonsProject/PD Companion/PD Companion Backups/07-24-2026"

    private static func findCSV(prefix: String) -> String? {
        (try? FileManager.default.contentsOfDirectory(atPath: backupDir))?
            .first { $0.hasPrefix(prefix) && $0.hasSuffix(".csv") }
            .map { backupDir + "/" + $0 }
    }

    /// ⭐ Rule 2 on Bhav's actual record, as a PROPERTY rather than a pinned total: wherever two
    /// staging sources overlap and one of them says `awake`, the resolved timeline must say awake.
    /// A pinned minute count would only be true of one export.
    ///
    /// ⚠️ **Stated limit — this test cannot check DIRECTION.** Rule 1 was validated against the
    /// tremor stream, an instrument that took no part in the rule. That is impossible here: every
    /// stager-vs-stager conflict on this record is Oura vs Apple Watch, Oura's data ends
    /// 2026-01-03, and the tremor record begins 2026-05-08. So this pins that the rule DOES what
    /// it says, never that the minutes it flips were truly awake. ⛔ Do not describe Rule 2 as
    /// validated on real data.
    @Test func onTheRealRecordAConflictAlwaysResolvesToAwake() throws {
        let path = try #require(Self.findCSV(prefix: "sleep_stages"),
            "Backup not found at \(Self.backupDir). Run on an iOS Simulator, not a device.")
        let spans = try SleepFixture.stagedSpans(path)
        let stagerSpans = spans.filter { $0.tier == 1 }
        #expect(stagerSpans.contains { $0.stage == .awake },
                "fixture has no staged awake at all — this test would prove nothing")

        // Conflicts: a tier-1 awake span overlapped in time by a tier-1 asleep span.
        let awake = stagerSpans.filter { $0.stage == .awake }
        let asleep = stagerSpans.filter { $0.stage != .awake }
        var conflicts: [(Date, Date)] = []
        for a in awake {
            for s in asleep where s.start < a.end && s.end > a.start {
                let lo = max(a.start, s.start), hi = min(a.end, s.end)
                if hi > lo { conflicts.append((lo, hi)) }
            }
        }
        #expect(!conflicts.isEmpty,
                "no stager-vs-stager conflict in the fixture — nothing for Rule 2 to act on")

        let resolved = HealthKitManager.resolveStages(spans)
        // Sample the midpoint of each conflict; the resolved timeline must call it awake.
        var checked = 0
        for (lo, hi) in conflicts {
            let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
            guard let seg = resolved.first(where: { $0.start <= mid && mid < $0.end }) else { continue }
            checked += 1
            #expect(seg.stage == .awake,
                    "a measured awake at \(mid) was overwritten as \(seg.stage)")
        }
        #expect(checked > 0, "no conflict midpoint landed inside a resolved segment")
    }

    /// One source overlapping ITSELF across syncs must still dedupe rather than double-count.
    @Test func aSourceOverlappingItselfIsNotDoubleCounted() {
        let segs = HealthKitManager.resolveStages([
            Self.span(Self.at(1, 0), Self.at(2, 0), .core, tier: 1),
            Self.span(Self.at(1, 30), Self.at(2, 30), .core, tier: 1),
        ])
        #expect(Self.minutes(segs, .core) == 90)
    }
}
