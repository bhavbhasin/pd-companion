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

    /// One source overlapping ITSELF across syncs must still dedupe rather than double-count.
    @Test func aSourceOverlappingItselfIsNotDoubleCounted() {
        let segs = HealthKitManager.resolveStages([
            Self.span(Self.at(1, 0), Self.at(2, 0), .core, tier: 1),
            Self.span(Self.at(1, 30), Self.at(2, 30), .core, tier: 1),
        ])
        #expect(Self.minutes(segs, .core) == 90)
    }
}
