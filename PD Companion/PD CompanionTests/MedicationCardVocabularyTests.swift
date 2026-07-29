//
//  MedicationCardVocabularyTests.swift
//  PD CompanionTests
//
//  Group 4, build steps 1-3: the registry can now ASK a per-substance question.
//  docs/design/medication-cards.md.
//
//  This file covers the GRAMMAR and the STAMPING — that the registry can phrase a per-substance
//  question at all, and which substances it phrases one for. The card's own content is
//  `MedicationCardTests`. (Steps 1-3 shipped with `renderer: nil` and these tests asserted
//  dormancy; step 4 wired the renderer, so the dormancy test became a dispatch test.)
//  Above all, the property the whole feature rests on:
//
//    ⭐ A substance earns a card by being TAKEN, never by having worked.
//
//  Gating a card on a measured effect would make its existence test a restatement of its own
//  content, and would bias displayed effects upward worst where data is thinnest. So a
//  supplement that does nothing must be stamped exactly like Sinemet.
//

import Foundation
import Testing
@testable import PD_Companion

struct MedicationCardVocabularyTests {

    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    private func pinCalendar() { CorrelationEngine.calendar = Self.cal }

    private static func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: day, hour: h, minute: m))!
    }

    private static var template: RegistryEntry {
        InsightRegistry.starter.first { $0.id == "medication-tremor" }!
    }

    // MARK: - 1. Vocabulary

    /// The defect this fixes is *missing expressiveness*, not a gate: before `.medication(key)`
    /// there was one flat `.levodopaDose` and no way to phrase a per-substance question at all.
    @Test func registryCanExpressAPerSubstanceQuestion() {
        let v = Variable.medication("mucuna")
        #expect(v.medicationKey == "mucuna")
        // The bridge answers nil for everything that is not a per-substance medication —
        // including the pooled dose variable and the template's own exposure.
        #expect(Variable.levodopaDose.medicationKey == nil)
        #expect(Variable.anyMedication.medicationKey == nil)
        #expect(Variable.tremor.medicationKey == nil)
        // Distinct substances are distinct variables (they key dictionaries and Sets).
        #expect(Variable.medication("mucuna") != Variable.medication("sinemet"))
        #expect(Variable.medication("mucuna") == Variable.medication("mucuna"))
        #expect(Set([Variable.medication("a"), .medication("a"), .medication("b")]).count == 2)
    }

    /// `.levodopaDose` must SURVIVE. It answers a pooled, deliberately cross-substance question
    /// ("how many waking hours does my dose spacing leave uncovered") that per-substance cards
    /// do not replace. Losing it would silently delete the coverage card.
    @Test func pooledDoseQuestionsAreUntouched() {
        let pooled = InsightRegistry.starter.filter { $0.exposure == .levodopaDose }
        #expect(pooled.count >= 2, "expected the wearing-off + dose-response entries to remain")
        #expect(pooled.contains { $0.id == "dose-tremor-wearing-off" })
        #expect(pooled.contains { $0.id == "dose-tremor-by-tod" })
    }

    /// The primitive is named for what it runs. `fitPulseModel` fits onset AND duration; calling
    /// it `.survivalDuration` would name the duration half only.
    @Test func templateDeclaresThePulseModelPrimitive() {
        let t = Self.template
        #expect(t.exposure == .anyMedication)
        #expect(t.outcome == .tremor)
        #expect(t.instantiation == .perObservedType)
        #expect(t.category == .medication)
        #expect(t.safety == .clinicalReferral, "medication copy may never propose a dosing change")
        guard case .pulseModel(let onThreshold) = t.primitive else {
            Issue.record("expected .pulseModel, got \(t.primitive)"); return
        }
        #expect(onThreshold == CorrelationEngine.offThreshold,
                "the template's OFF threshold must track the engine's, not drift from it")
        #expect(t.renderer == .medication, "step 4 wired the bespoke renderer")
    }

    // MARK: - 2. Stamping

    @Test func stampsOneQuestionPerObservedSubstance() {
        let out = InsightRegistry.instantiate(Self.template,
                                              observedSubstances: ["sinemet", "mucuna", "vitamin d"])
        #expect(out.count == 3)
        #expect(out.map(\.exposure) == [.medication("mucuna"), .medication("sinemet"),
                                        .medication("vitamin d")],
                "sorted by key, so the surfaced set is stable across runs")
        #expect(Set(out.map(\.id)).count == 3, "ids must be unique per substance")
        #expect(out.allSatisfy { $0.instantiation == .singular }, "an instance must never re-expand")
        #expect(out.allSatisfy { $0.primitive == Self.template.primitive })
        #expect(out.allSatisfy { $0.safety == .clinicalReferral })
        #expect(InsightRegistry.instantiate(Self.template, observedSubstances: []).isEmpty)
    }

    /// ⭐ The property the feature exists for. The workout template SKIPS types it cannot name;
    /// the medication template must skip nothing. An Ayurvedic preparation and a compounded
    /// formulation are measured on the same terms as Sinemet — no drug list stands between a
    /// substance and its card, because a list cannot recognise what it has not heard of.
    @Test func noSubstanceIsSkippedForBeingUnrecognised() {
        let exotic: Set<String> = ["sinemet", "kapikachhu", "low-dose naltrexone",
                                   "compounded cd-ld", "ashwagandha", "zzz unknown substance"]
        let out = InsightRegistry.instantiate(Self.template, observedSubstances: exotic)
        #expect(out.count == exotic.count,
                "every logged substance earns a question; got \(out.count) of \(exotic.count)")
        #expect(Set(out.compactMap(\.exposure.medicationKey)) == exotic)
        // And the workout template's behaviour is genuinely different — the contrast is the
        // point, so pin it rather than trusting the comment.
        let unnameable = InsightRegistry.instantiate(
            InsightRegistry.starter.first { $0.id == "workout-tremor" }!,
            observedRawValues: [3000])   // not a real HKWorkoutActivityType
        #expect(unnameable.isEmpty, "an unnameable WORKOUT is still skipped")
    }

    // MARK: - 3. Which substances earn a card

    /// Logged on more than one day. One day is a trial or a mis-entry; a second day is a
    /// pattern the person chose to continue. A screen-clutter line, not an evidence claim —
    /// nothing about a card's content or confidence depends on it.
    @Test func aSubstanceEarnsACardOnTheSecondDay() {
        pinCalendar()
        let doses = [
            // Two days → in.
            Dose(timestamp: Self.at(1, 8), name: "Sinemet"),
            Dose(timestamp: Self.at(2, 8), name: "Sinemet"),
            // Three doses but all on ONE day → out.
            Dose(timestamp: Self.at(1, 9), name: "Trialled Once"),
            Dose(timestamp: Self.at(1, 13), name: "Trialled Once"),
            Dose(timestamp: Self.at(1, 19), name: "Trialled Once"),
            // A single dose on each of two days → in. Frequency is not the test.
            Dose(timestamp: Self.at(3, 7), name: "Vitamin D"),
            Dose(timestamp: Self.at(9, 7), name: "Vitamin D"),
        ]
        let keys = CorrelationEngine.observedSubstanceKeys(doses: doses)
        #expect(keys == ["sinemet", "vitamin d"],
                "expected sinemet + vitamin d, got \(keys.sorted())")
        #expect(!keys.contains("trialled once"),
                "three doses inside ONE day is a trial, not yet a pattern")
        #expect(CorrelationEngine.observedSubstanceKeys(doses: []).isEmpty)
    }

    /// Dosage strength must not split one substance into two cards.
    @Test func strengthVariantsCollapseToOneSubstance() {
        pinCalendar()
        let doses = [
            Dose(timestamp: Self.at(1, 8), name: "Sinemet 25-100"),
            Dose(timestamp: Self.at(2, 8), name: "sinemet"),
            Dose(timestamp: Self.at(3, 8), name: "Sinemet 25/100 mg"),
        ]
        #expect(CorrelationEngine.observedSubstanceKeys(doses: doses) == ["sinemet"])
    }

    /// ⭐ Existence decoupled from effect, end to end: a substance with a real pulse and one
    /// that is completely inert must both be stamped. The inert one is exactly the case a
    /// naive "show it once it works" gate would hide.
    @Test func anInertSubstanceIsStampedJustLikeAnEffectiveOne() {
        pinCalendar()
        var doses: [Dose] = []
        for d in 1..<20 {
            doses.append(Dose(timestamp: Self.at(d, 8), name: "Sinemet"))
            doses.append(Dose(timestamp: Self.at(d, 14), name: "Vitamin D"))
        }
        // Tremor responds to the 08:00 dose and ignores the 14:00 one entirely.
        var samples: [TremorPoint] = []
        for d in 1..<20 {
            var t = Self.at(d, 0)
            while t < Self.at(d, 23, 55) {
                let h = Self.cal.component(.hour, from: t)
                samples.append(TremorPoint(timestamp: t,
                                           tremorScore: (h >= 8 && h < 11) ? 0.2 : 1.5))
                t = t.addingTimeInterval(5 * 60)
            }
        }
        let sig = samples.map { (time: $0.timestamp, value: $0.tremorScore) }
        let estimable = Set(CorrelationEngine.estimableFormulations(signal: sig, doses: doses).keys)
        let carded = CorrelationEngine.observedSubstanceKeys(doses: doses)

        #expect(carded.contains("vitamin d"),
                "an inert substance must still earn a card — that is the whole design")
        #expect(carded.contains("sinemet"))
        #expect(!estimable.contains("vitamin d"),
                "…while still contributing NO coverage to the pooled analyses")
        #expect(carded.isSuperset(of: estimable),
                "the card set must never be narrower than the estimable set")
    }

    // MARK: - Dormancy

    /// The dispatch seam, end to end: a stamped entry must reach the `.medication` renderer
    /// and come back as a card. This test previously asserted the OPPOSITE — that the entries
    /// stayed dormant — which was correct for steps 1-3 and is exactly what step 4 ends.
    @Test func stampedEntriesNowRenderThroughTheDispatch() throws {
        pinCalendar()
        var doses: [Dose] = []
        var samples: [TremorPoint] = []
        for d in 1..<20 {
            doses.append(Dose(timestamp: Self.at(d, 8), name: "Sinemet"))
            doses.append(Dose(timestamp: Self.at(d, 14), name: "Mucuna"))
            var t = Self.at(d, 0)
            while t < Self.at(d, 23, 55) {
                let h = Self.cal.component(.hour, from: t)
                samples.append(TremorPoint(timestamp: t,
                                           tremorScore: (h >= 8 && h < 11) ? 0.2 : 1.5))
                t = t.addingTimeInterval(5 * 60)
            }
        }
        let stamped = InsightRegistry.instantiate(
            Self.template, observedSubstances: CorrelationEngine.observedSubstanceKeys(doses: doses))
        #expect(stamped.count == 2, "fixture should stamp sinemet + mucuna, got \(stamped.count)")
        for entry in stamped {
            let card = try #require(
                CorrelationEngine.run(entry, samples: samples, doses: doses,
                                      gait: [:], workouts: [], food: [], sleep: [], allDoses: doses),
                "\(entry.id) must now render")
            // .clinicalReferral ⇒ no experiment offered, ever.
            #expect(card.stage == .clinicalDiscussion)
        }

        // And the substance that did nothing still surfaces in a full run.
        let all = CorrelationEngine.generateInsights(
            samples: samples, doses: doses, gait: [:], workouts: [], food: [], sleep: [])
        #expect(all.contains { $0.title.hasPrefix("Mucuna") },
                "the inert substance must still get a card; titles: \(all.map(\.title))")
    }
}
