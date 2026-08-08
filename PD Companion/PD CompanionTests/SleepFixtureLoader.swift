//
//  SleepFixtureLoader.swift
//  PD CompanionTests
//
//  ONE loader for sleep out of a real backup CSV, shared by every real-data suite.
//
//  ⛔ **Why this exists.** Three suites each had their own copy that read `startDate`, `endDate`
//  and `stage` and threw `source` away — so none of them could apply Rule 1 (`bb0b580`), and all
//  stayed green against the pre-Aug-2026 union in which a source that GUESSES sleep from stillness
//  overrides one that MEASURES it. Found Aug 7 2026 when `mucunaMatchesThePredictedDurationOnTheRealRecord`
//  asserted ~48 min while the shipping app showed 93 on the same data. Both were "right" for
//  different versions of the engine, which is the exact shape of a test giving false assurance.
//  A fourth copy would drift the same way, so there is now one.
//
//  Mirrors `HealthKitManager.fetchSleepIntervals` + `CorrelationEngine.reconcileSleep`, and the
//  Python lab's `loaders.load_sleep_intervals`.
//
//  ⚠️ The CSV carries a display name where the app carries a bundle identifier, so capability is
//  keyed on `source` here and on `SleepStagerPrefs` in the app. Same rule, same result on these
//  fixtures — and in neither place is a name ever compared against a known brand.
//

import Foundation
@testable import PD_Companion

enum SleepFixture {

    /// Merged asleep-only intervals with Rule 1 applied.
    ///
    /// - Parameter sensing: spans where the watch was demonstrably on the wrist, normally
    ///   `CorrelationEngine.wearSpans(samples)`. This is what lets an inferred claim be dropped
    ///   where a staging source was sensing and did not call it sleep — and kept where nothing
    ///   was sensing at all. ⛔ Pass the real wear spans; `[]` silently means "nothing was ever
    ///   sensing", which restores the old union.
    static func asleepIntervals(_ path: String, sensing: [SleepInterval]) throws -> [SleepInterval] {
        let (idx, data) = try rows(path)
        guard let si = idx["startDate"], let ei = idx["endDate"],
              let sti = idx["stage"], let srci = idx["source"]
        else { return [] }

        let asleep: Set<String> = ["asleepcore", "asleepdeep", "asleeprem", "asleepunspecified"]
        let staging: Set<String> = ["asleepdeep", "asleeprem"]

        func field(_ r: [String], _ i: Int) -> String {
            r.count > i ? r[i].trimmingCharacters(in: .whitespaces) : ""
        }

        // Capability, never a brand: a source qualifies by having emitted Deep or REM anywhere.
        let stagers = Set(data.compactMap { r -> String? in
            guard staging.contains(field(r, sti).lowercased()) else { return nil }
            let name = field(r, srci)
            return name.isEmpty ? nil : name
        })

        var measured: [SleepInterval] = []
        var inferred: [SleepInterval] = []
        for r in data {
            guard asleep.contains(field(r, sti).lowercased()),
                  let a = date(field(r, si)), let b = date(field(r, ei)), b > a else { continue }
            let iv = SleepInterval(start: a, end: b)
            if stagers.contains(field(r, srci)) { measured.append(iv) } else { inferred.append(iv) }
        }
        return CorrelationEngine.reconcileSleep(
            measured: measured, inferred: inferred, sensing: sensing)
    }

    /// The pre-Rule-1 union, kept ONLY for tests that deliberately pin the old behaviour.
    /// ⛔ Never use this to stand in for the engine — that is the defect this file documents.
    static func unreconciledAsleepIntervals(_ path: String) throws -> [SleepInterval] {
        let (idx, data) = try rows(path)
        guard let si = idx["startDate"], let ei = idx["endDate"], let sti = idx["stage"]
        else { return [] }
        let asleep: Set<String> = ["asleepcore", "asleepdeep", "asleeprem", "asleepunspecified"]
        return data.compactMap { r in
            guard r.count > max(si, max(ei, sti)),
                  asleep.contains(r[sti].trimmingCharacters(in: .whitespaces).lowercased()),
                  let s = date(r[si]), let e = date(r[ei]), e > s else { return nil }
            return SleepInterval(start: s, end: e)
        }
    }

    /// Every staged span in the fixture, tiered by capability, ready for
    /// `HealthKitManager.resolveStages`. Used by the Rule 2 real-data test.
    /// `awake` is included here — unlike `asleepIntervals`, which is asleep-only by contract.
    static func stagedSpans(_ path: String) throws -> [HealthKitManager.StagedSpan] {
        let (idx, data) = try rows(path)
        guard let si = idx["startDate"], let ei = idx["endDate"],
              let sti = idx["stage"], let srci = idx["source"]
        else { return [] }

        func field(_ r: [String], _ i: Int) -> String {
            r.count > i ? r[i].trimmingCharacters(in: .whitespaces) : ""
        }
        let stageOf: [String: SleepStage] = [
            "asleepdeep": .deep, "asleeprem": .rem,
            "asleepcore": .core, "asleepunspecified": .core, "awake": .awake,
        ]
        let stagers = Set(data.compactMap { r -> String? in
            let s = field(r, sti).lowercased()
            guard s == "asleepdeep" || s == "asleeprem" else { return nil }
            let name = field(r, srci)
            return name.isEmpty ? nil : name
        })
        return data.compactMap { r in
            guard let stage = stageOf[field(r, sti).lowercased()],
                  let a = date(field(r, si)), let b = date(field(r, ei)), b > a else { return nil }
            return HealthKitManager.StagedSpan(
                start: a, end: b, stage: stage,
                tier: stagers.contains(field(r, srci)) ? 1 : 0)
        }
    }

    // MARK: - CSV

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

    private static func date(_ s: String) -> Date? {
        iso.date(from: s) ?? isoPlain.date(from: s)
    }

    private static func rows(_ path: String) throws -> ([String: Int], [[String]]) {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty else { return ([:], []) }
        let header = lines.removeFirst().split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var idx: [String: Int] = [:]
        for (i, h) in header.enumerated() { idx[h] = i }
        let data = lines.map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        return (idx, data)
    }
}
