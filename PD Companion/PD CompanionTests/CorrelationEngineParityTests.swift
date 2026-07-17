//
//  CorrelationEngineParityTests.swift
//  PD CompanionTests
//
//  Trust gate for the Swift port of the Python correlation lab. Runs the engine
//  on the SAME CSV backup the Python validated against and asserts it reproduces
//  the lab's numbers. If this is green, the Swift dose-response port is faithful.
//
//  Targets captured from `analysis/` (18-06-2026 backup), Pacific time:
//      buckets/onset (mean t_half): Morning 39.81 · Pre-lunch 36.29 ·
//                                   Afternoon 66.72 · Evening 43.88
//      137 traces · 134 with onset · 147 levodopa "taken" doses · 41 days
//
//  NOTE: reads Bhav's local backup folder (gitignored health data). On a machine
//  without it, the test no-ops rather than failing.

import Foundation
import Testing
@testable import PD_Companion

struct CorrelationEngineParityTests {

    static let backupDir =
        "/Users/bhav/Documents/ParkinsonsProject/PD Companion/PD Companion Backups/18-06-2026"

    @Test func engineMatchesPythonLab() throws {
        // Pin bucketing to Pacific so the test is deterministic regardless of the
        // machine's timezone (the Python lab works in America/Los_Angeles).
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        CorrelationEngine.calendar = cal

        // Fail loudly if the data isn't reachable — never skip silently (a silent
        // skip masquerades as a pass). Physical devices can't see the Mac path, so
        // this test must be run on an iOS Simulator.
        let tremorPath = try #require(
            Self.findCSV(prefix: "tremor_readings"),
            "Backup CSVs not found at \(Self.backupDir). Run this test on an iOS Simulator — a physical device cannot read the Mac filesystem."
        )
        let medsPath = try #require(Self.findCSV(prefix: "medication_doses"))

        let samples = try Self.loadTremor(tremorPath)
        let doses = try Self.loadLevodopaTakenDoses(medsPath)

        #expect(samples.count == 54731, "tremor row count")
        #expect(doses.count == 147, "levodopa 'taken' dose count")

        let traces = CorrelationEngine.buildTraces(samples: samples, doses: doses)
        #expect(traces.count == 137, "total dose traces")
        #expect(traces.filter { !$0.tHalf.isNaN }.count == 134, "traces with onset")

        func onsetMean(_ b: CorrelationEngine.Bucket) -> Double {
            let xs = traces.filter { $0.bucket == b && !$0.tHalf.isNaN }.map(\.tHalf)
            return xs.isEmpty ? .nan : xs.reduce(0, +) / Double(xs.count)
        }
        // tol 0.5 min: same algorithm, so any real drift means a port bug.
        #expect(abs(onsetMean(.morning)      - 39.808) < 0.5, "morning onset")
        #expect(abs(onsetMean(.preLunch)     - 36.293) < 0.5, "pre-lunch onset")
        #expect(abs(onsetMean(.afternoon)    - 66.719) < 0.5, "afternoon onset")
        #expect(abs(onsetMean(.eveningNight) - 43.883) < 0.5, "evening onset")

        let days = Set(traces.map { cal.startOfDay(for: $0.t0) }).count
        #expect(days == 41, "distinct days")

        // The surfaced insight should fire, be Strong, and quote the real numbers.
        let insight = CorrelationEngine.afternoonDoseInsight(samples: samples, doses: doses)
        #expect(insight != nil)
        #expect(insight?.confidence == .strong)
        #expect(insight?.summary.contains("67") == true)
        #expect(insight?.summary.contains("40") == true)

        // --- Wearing-off / Kaplan–Meier parity ---
        let durations = CorrelationEngine.analyzeWearingOff(samples: samples, doses: doses)
        #expect(durations.count == 147, "dose-duration count")
        let observed = durations.filter { $0.observed }.count
        #expect(observed == 101, "observed OFF-returns")
        #expect(durations.count - observed == 46, "censored")
        #expect(durations.filter { $0.isolated }.count == 106, "isolated doses")

        let km = CorrelationEngine.kmMedian(
            durations: durations.map(\.durationMin), observed: durations.map(\.observed))
        #expect(abs(km - 192.5) < 0.6, "KM median ON-duration")

        var dayIv: [Double] = []
        for r in durations where r.hour >= 6 && r.hour < 20 && !r.intervalMin.isNaN && r.intervalMin < 600 {
            dayIv.append(r.intervalMin)
        }
        #expect(abs(CorrelationEngine.median(dayIv) - 242.244) < 1.0, "median daytime interval")

        let wInsight = CorrelationEngine.wearingOffInsight(samples: samples, doses: doses)
        #expect(wInsight != nil)
        #expect(wInsight?.stage == .clinicalDiscussion)
        #expect(wInsight?.confidence == .strong)

        // --- Chart data (plot-ready engine output) ---
        // Dose-response overlay: morning + afternoon curves present, and the morning
        // curve reaches a deeper ON (lower trough) than the afternoon one — the visual
        // form of "afternoon works slower / less complete" (NOTES: ~0.0 vs ~0.15).
        guard case .doseResponse(let dr)? = insight?.chart else {
            Issue.record("afternoon insight should carry a dose-response chart"); return
        }
        func curve(_ label: String) -> CorrelationEngine.DoseCurve? { dr.curves.first { $0.label == label } }
        let morningCurve = try #require(curve("Morning"))
        let afternoonCurve = try #require(curve("Afternoon"))
        func postMin(_ c: CorrelationEngine.DoseCurve) -> Double {
            c.points.filter { $0.minute > 0 && !$0.value.isNaN }.map(\.value).min() ?? .nan
        }
        #expect(postMin(morningCurve) < postMin(afternoonCurve), "morning reaches deeper ON than afternoon")
        // Bins should sit on the shared grid centers (-27.5 first, 5-min spacing).
        #expect(abs((morningCurve.points.first?.minute ?? .nan) + 27.5) < 0.001, "first bin center")

        // Wearing-off curve: pooled isolated doses, deepest ON in the expected window,
        // baseline above the OFF line (doses taken from an OFF state), KM marker = 192.
        guard case .wearingOff(let wo)? = wInsight?.chart else {
            Issue.record("wearing-off insight should carry a wearing-off chart"); return
        }
        #expect(wo.curve.doseCount == 106, "pooled over isolated doses")
        #expect(wo.bestOnMinute > 60 && wo.bestOnMinute < 200, "deepest ON in plausible window")
        #expect(wo.baseline > wo.threshold, "pre-dose baseline is in the OFF range")
        #expect(abs(wo.medianDurationMin - 192.5) < 0.6, "KM marker matches the headline")

        // --- Decimal curve parity vs the Python lab (anchor points) ---
        // Reference values captured from analysis/dump_curve_anchors.py on the
        // 18-06-2026 backup. Dose-response = mean of RAW per-dose bins; wearing-off =
        // mean of SMOOTHED per-dose bins (matching each Python module). tol 1e-3:
        // identical arithmetic, so anything looser would mask a real port bug. This is
        // the trust gate before these curves go into a clinician-facing PDF.
        func value(_ c: CorrelationEngine.DoseCurve, at minute: Double) -> Double {
            c.points.first { abs($0.minute - minute) < 0.01 }?.value ?? .nan
        }
        let tol = 0.001

        #expect(abs(value(morningCurve, at: -2.5)  - 1.738565) < tol, "morning @ -2.5")
        #expect(abs(value(morningCurve, at: 42.5)  - 0.419370) < tol, "morning @ 42.5")
        #expect(abs(value(morningCurve, at: 92.5)  - 0.356462) < tol, "morning @ 92.5")
        #expect(abs(value(morningCurve, at: 142.5) - 0.258925) < tol, "morning @ 142.5")

        #expect(abs(value(afternoonCurve, at: -2.5)  - 1.736589) < tol, "afternoon @ -2.5")
        #expect(abs(value(afternoonCurve, at: 42.5)  - 1.263052) < tol, "afternoon @ 42.5")
        #expect(abs(value(afternoonCurve, at: 92.5)  - 0.873869) < tol, "afternoon @ 92.5")
        #expect(abs(value(afternoonCurve, at: 142.5) - 0.480668) < tol, "afternoon @ 142.5")

        #expect(abs(value(wo.curve, at: -2.5)  - 1.652807) < tol, "wearing-off @ -2.5")
        #expect(abs(value(wo.curve, at: 2.5)   - 1.644887) < tol, "wearing-off @ 2.5")
        #expect(abs(value(wo.curve, at: 62.5)  - 0.533881) < tol, "wearing-off @ 62.5")
        #expect(abs(value(wo.curve, at: 122.5) - 0.208692) < tol, "wearing-off @ 122.5")
        #expect(abs(value(wo.curve, at: 182.5) - 0.580301) < tol, "wearing-off @ 182.5")
        #expect(abs(value(wo.curve, at: 242.5) - 0.965670) < tol, "wearing-off @ 242.5")
        #expect(abs(wo.baseline - 1.385752) < tol, "wearing-off baseline")
        #expect(abs(wo.bestOnMinute - 122.5) < 0.01, "wearing-off deepest-ON minute")

        // --- Gait progression parity (analysis/src/gait.py on the same backup) ---
        // Foreign-source ("Japnit kaur's iPhone") rows excluded, as in the lab. Anchors
        // from analysis/dump_gait_anchors.py. Slopes/intercepts are pure OLS (tol 1e-6);
        // the p-values exercise the hand-rolled t-distribution tail (tol 1e-3).
        let prog = try #require(
            CorrelationEngine.analyzeGait(series: Self.loadGait()),
            "gait analysis should produce trends")

        func gtrend(_ m: GaitMetric) throws -> CorrelationEngine.MetricTrend {
            try #require(prog.trend(m), "\(m) trend present")
        }

        let speed = try gtrend(.walkingSpeed)
        #expect(speed.nMonths == 70, "speed months")
        #expect(abs(speed.slopePerYear - 0.0090484269) < 1e-6, "speed slope/yr")
        #expect(abs(speed.intercept - 0.9977190145) < 1e-4, "speed intercept")
        #expect(abs(speed.pValue - 0.0184220697) < 1e-3, "speed p-value")
        #expect(abs(speed.pctChange - 5.211792) < 1e-2, "speed % change")
        #expect(abs(speed.spanYears - 5.7467488022) < 1e-3, "gait span years")
        #expect(speed.isWorsening == false, "speed up = not worsening")

        let step = try gtrend(.stepLength)
        #expect(step.nMonths == 70, "step months")
        #expect(abs(step.slopePerYear - -0.0006050328) < 1e-6, "step slope/yr")
        #expect(abs(step.pValue - 0.6849955061) < 1e-3, "step p-value (n.s.)")

        let dsup = try gtrend(.doubleSupport)
        #expect(dsup.nMonths == 70, "double-support months")
        #expect(abs(dsup.slopePerYear - -0.0041791122) < 1e-6, "double-support slope/yr")
        #expect(abs(dsup.pctChange - -7.858397) < 1e-2, "double-support % change")
        #expect(dsup.pValue < 0.001, "double-support highly significant")
        #expect(dsup.isWorsening == false, "double-support down = improving")

        let asym = try gtrend(.asymmetry)
        #expect(asym.nMonths == 67, "asymmetry months")
        #expect(abs(asym.slopePerYear - -0.0007519235) < 1e-6, "asymmetry slope/yr")
        #expect(abs(asym.pValue - 0.1728188659) < 1e-3, "asymmetry p-value (n.s.)")
        #expect(asym.pctReliable == false, "asymmetry % unreliable (near-zero baseline)")

        // Net read: nothing significantly worsening → the reassuring verdict.
        #expect(prog.anySignificantWorsening == false, "no significant gait decline")

        // --- End-to-end dispatch (registry → run() → renderer) ---
        // The blocks above call each renderer directly. This exercises the seam they
        // skip: the registry-driven path, where `generateInsights` iterates the entries
        // and dispatches each on its `renderer` (no id-switch). With no workouts passed,
        // the exercise/diet/sleep/HRV entries stay dormant, so exactly the three built
        // medication + gait cards fire — and they must match the direct-call results.
        let surfaced = CorrelationEngine.generateInsights(
            samples: samples, doses: doses, gait: Self.loadGait(), workouts: [])
        #expect(surfaced.count == 3, "only the three built cards fire when no workouts are supplied")

        // Both medication cards are .clinicalReferral, so the safety-derived stage
        // (CorrelationEngine.stage(for:)) routes them to .clinicalDiscussion — neither
        // offers an experiment. This is the fix: the .doseResponse renderer previously
        // hard-stamped .hypothesis, so the afternoon-dose card wrongly showed a
        // "Try an experiment" button despite being a medication-regimen finding.
        let doseCard = try #require(
            surfaced.first { $0.title.localizedCaseInsensitiveContains("afternoon dose") },
            "afternoon-dose card should surface via the .doseResponse renderer")
        #expect(doseCard.confidence == .strong)
        #expect(doseCard.stage == .clinicalDiscussion, "dose entry is .clinicalReferral → no experiment")

        // Keyed on title, not stage: dose AND wearing-off now both carry
        // .clinicalDiscussion (both .clinicalReferral), so stage no longer uniquely
        // identifies this card. "uncovered" is the stable word in a title that now
        // leads with the summed daily shortfall (the number itself varies with data).
        let wearCard = try #require(
            surfaced.first { $0.title.localizedCaseInsensitiveContains("uncovered") },
            "wearing-off card should surface via the .wearingOff renderer")
        #expect(wearCard.confidence == .strong)
        #expect(wearCard.stage == .clinicalDiscussion)
        // The card must state the shortfall outright rather than leave the reader to subtract
        // two medians — but the VALUE is pinned in SleepClippingTests, not here. This fixture
        // carries no sleep CSV, so the card takes the conservative fallback path; that number
        // says nothing about whether the Swift port matches the Python lab, which is the only
        // question this test exists to answer.
        #expect(wearCard.title.localizedCaseInsensitiveContains("uncovered"))

        // .verdict still uniquely identifies the gait composite — it's the one card
        // whose stage is NOT safety-derived (a progression readout, set in gaitInsight),
        // while the two medication cards are both .clinicalDiscussion.
        _ = try #require(
            surfaced.first { $0.stage == .verdict },
            "gait card should surface via the .gaitComposite renderer")
    }

    // MARK: - Minimal CSV loaders (test-only; the app writes CSV, never reads it)

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func findCSV(prefix: String) -> String? {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: backupDir) else { return nil }
        guard let name = files.first(where: { $0.hasPrefix(prefix) && $0.hasSuffix(".csv") }) else { return nil }
        return backupDir + "/" + name
    }

    /// Returns (header→index, data rows as [[String]]). Naive split — the backup
    /// CSVs have no quoted commas.
    private static func rows(_ path: String) throws -> (idx: [String: Int], data: [[String]]) {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !lines.isEmpty else { return ([:], []) }
        let header = lines.removeFirst().split(separator: ",").map(String.init)
        var idx: [String: Int] = [:]
        for (i, h) in header.enumerated() { idx[h] = i }
        let data = lines.map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        return (idx, data)
    }

    private static func loadTremor(_ path: String) throws -> [TremorPoint] {
        let (idx, data) = try rows(path)
        guard let tsi = idx["timestamp"], let tri = idx["tremorScore"] else { return [] }
        return data.compactMap { r in
            guard r.count > max(tsi, tri),
                  let ts = iso.date(from: r[tsi]),
                  let tremor = Double(r[tri]) else { return nil }
            return TremorPoint(timestamp: ts, tremorScore: tremor)
        }
    }

    private static func loadLevodopaTakenDoses(_ path: String) throws -> [Dose] {
        let (idx, data) = try rows(path)
        guard let sdi = idx["startDate"], let sti = idx["status"], let mni = idx["medicationName"]
        else { return [] }
        return data.compactMap { r in
            guard r.count > max(sdi, sti, mni) else { return nil }
            let status = r[sti].trimmingCharacters(in: .whitespaces).lowercased()
            guard status == "taken" else { return nil }
            let name = r[mni].trimmingCharacters(in: .whitespaces)
            let key = name.lowercased()
            guard key.contains("sinemet") || key.contains("mucuna") else { return nil }
            guard let ts = iso.date(from: r[sdi]) else { return nil }
            return Dose(timestamp: ts, name: name)
        }
    }

    // Gait CSVs may lack fractional seconds; try both ISO forms.
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ s: String) -> Date? {
        iso.date(from: s) ?? isoPlain.date(from: s)
    }

    /// Load one mobility-metric series from the backup, dropping foreign-source rows
    /// (a family member's device that synced in) exactly as the Python lab does.
    private static func loadGaitSeries(prefix: String) -> [GaitSample] {
        guard let path = findCSV(prefix: prefix),
              let (idx, data) = try? rows(path),
              let sdi = idx["startDate"], let vi = idx["value"], let sci = idx["source"]
        else { return [] }
        return data.compactMap { r in
            guard r.count > max(sdi, vi, sci) else { return nil }
            if r[sci].lowercased().contains("japnit") { return nil }   // foreign device
            guard let d = parseDate(r[sdi]), let v = Double(r[vi]) else { return nil }
            return GaitSample(date: d, value: v)
        }
    }

    private static func loadGait() -> [GaitMetric: [GaitSample]] {
        [
            .walkingSpeed:  loadGaitSeries(prefix: "walking_speed_m_s"),
            .stepLength:    loadGaitSeries(prefix: "walking_step_length_m"),
            .doubleSupport: loadGaitSeries(prefix: "walking_double_support_pct"),
            .asymmetry:     loadGaitSeries(prefix: "walking_asymmetry_pct"),
        ]
    }
}
