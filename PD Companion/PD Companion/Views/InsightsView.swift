import SwiftUI
import SwiftData
import Charts
import CoreGraphics

// MARK: - Insights: the cross-day layer
//
// Observations (ObservationsPanel) describe *what co-occurred in a single day* and
// deliberately refuse to claim cause. Insights are the other half: findings that
// hold up *across many days*, expressed as a loop you can act on —
//
//     Hypothesis  →  Experiment  →  Verdict
//                 ↘  Discuss with your neurologist   (when the lever is medical, not behavioral)
//
// SAFETY LINE: experiments only ever change *behavior you control* (meal timing,
// light, activity). The app NEVER tells you to change a dose. When a pattern is
// inherently medical (wearing-off, dose spacing), it routes you to your neurologist
// *with the data* — framing options as their decision, never an instruction to you.
//
// PROGRESSIVE DISCLOSURE: every card is collapsed to one takeaway line by default
// and expands on tap. One card answers one question. This keeps cognitive load low —
// the whole premise of the app.
//
// SAMPLE DATA below is Bhav's real 40-day findings from the Python correlation-engine
// lab (see analysis/NOTES.md). Wiring the live engine output in is the next step (TODO).

// MARK: - Model

// `nonisolated` (+ implicitly Sendable, as a value type): the engine builds and
// returns these from a background thread, so they must not be main-actor-isolated
// (which is the project default). They're consumed by SwiftUI on the main actor,
// which a nonisolated Sendable value type supports without friction.
nonisolated struct Insight: Identifiable {
    let id = UUID()
    var title: String
    var summary: String          // the one-line takeaway shown when collapsed
    var stage: Stage

    // Detail (revealed on expand)
    var finding: String          // the repeatable pattern — the "what", with numbers
    var mechanism: String        // candidate "why" from PD pharmacology (hedged)
    var confidence: Confidence
    var evidenceDays: Int
    var updatedNote: String?     // e.g. "Strengthened — now 47 days" (surfaced change)

    // Plot-ready data from the engine, rendered inside the expanded card.
    var chart: CorrelationEngine.InsightChart?

    // Populated as the loop advances
    var experiment: Experiment?
    var verdict: Verdict?
    var clinical: ClinicalDiscussion?

    var startExpanded: Bool = false

    enum Stage { case hypothesis, experiment, verdict, clinicalDiscussion }

    enum Confidence: String {
        case emerging = "Emerging"
        case moderate = "Moderate"
        case strong   = "Strong"

        var color: Color {
            switch self {
            case .emerging: return .secondary
            case .moderate: return Insight.brandBlue
            case .strong:   return .green
            }
        }
        var filledDots: Int {
            switch self { case .emerging: 1; case .moderate: 2; case .strong: 3 }
        }
    }

    // Kampa brand blue (#4A8CD6), not Apple system blue.
    static let brandBlue = Color(red: 0.290, green: 0.549, blue: 0.839)
}

nonisolated struct Experiment {
    var oneLine: String
    var controlLabel: String
    var changeLabel: String
    var metric: String
    var decisionRule: String     // pre-registered before it runs
    var targetDays: Int
    var daysElapsed: Int
    var safetyNote: String
    var progress: Double { min(1, Double(daysElapsed) / Double(targetDays)) }
}

nonisolated struct Verdict {
    var outcome: Outcome
    var controlLabel: String; var controlValue: String
    var changeLabel: String;  var changeValue: String
    var summary: String
    var nextStep: String

    enum Outcome {
        case worked, noChange, inconclusive
        var label: String {
            switch self {
            case .worked: "It worked for you"
            case .noChange: "No real difference"
            case .inconclusive: "Needs more days"
            }
        }
        var icon: String {
            switch self {
            case .worked: "checkmark.seal.fill"
            case .noChange: "equal.circle.fill"
            case .inconclusive: "questionmark.circle.fill"
            }
        }
        var color: Color {
            switch self { case .worked: .green; case .noChange: .secondary; case .inconclusive: .orange }
        }
    }
}

// A pattern whose lever is medical, not behavioral. The app surfaces it and the
// data — the decision stays entirely with the neurologist.
nonisolated struct ClinicalDiscussion {
    var whatTheyMightConsider: String   // framed as the clinician's domain, never an instruction
    var bringThisData: [String]         // bullet evidence to take to the appointment
}

// MARK: - Sample data (Bhav's real 40-day findings)

extension Insight {
    static var samples: [Insight] {
        [
            // 1) NEEDS ATTENTION — afternoon dose, behavioral lever, startable experiment.
            Insight(
                title: "Your afternoon dose works slower",
                summary: "Takes ~67 min to kick in vs. ~38 min in the morning — but lasts a normal length.",
                stage: .hypothesis,
                finding: "It also peaks weaker, while duration stays normal (~3.2 h) — so the issue is getting the dose *in*, not it wearing off early. From 137 scored doses over 40 days.",
                mechanism: "Levodopa is absorbed in the gut and enters the brain through the same transporter dietary protein uses, so a protein lunch can slow and blunt the dose after it. PD also slows stomach emptying, more after meals and later in the day. Both point to one lever you control: when you eat relative to the dose. Likely, not proven.",
                confidence: .strong,
                evidenceDays: 40,
                chart: .doseResponse(CorrelationEngine.DoseResponseChart(
                    curves: [
                        sampleCurve("Morning", bucket: .morning, doseCount: 38,
                                    lo: -30, hi: 180, baseline: 1.3, trough: 0.1, tTrough: 38, recoverBy: nil),
                        sampleCurve("Afternoon", bucket: .afternoon, doseCount: 31,
                                    lo: -30, hi: 180, baseline: 1.3, trough: 0.6, tTrough: 67, recoverBy: nil)
                    ],
                    threshold: 1.0, doseMinute: 0
                ))
            ),

            // 2) DISCUSS WITH NEUROLOGIST — wearing-off / dose spacing, medical lever.
            Insight(
                title: "Your doses are spaced wider than they last",
                summary: "Daytime gaps (~5 h) exceed how long each dose lasts (~3.2 h), opening predictable OFF windows.",
                stage: .clinicalDiscussion,
                finding: "Each dose: ON by ~40 min, peak ~122 min, worn off by ~3.5 h; median ON-duration 192 min. Your OFF time clusters in the afternoon and evening (60–70%). From 106 clean doses over 40 days.",
                mechanism: "This is the classic wearing-off pattern: the interval between doses is longer than a single dose lasts.",
                confidence: .strong,
                evidenceDays: 40,
                chart: .wearingOff(CorrelationEngine.WearingOffChart(
                    curve: sampleCurve("Typical dose", bucket: nil, doseCount: 106,
                                       lo: -30, hi: 300, baseline: 1.5, trough: 0.2, tTrough: 122, recoverBy: 280),
                    threshold: 1.0, baseline: 1.5, bestOnMinute: 122, medianDurationMin: 192
                )),
                clinical: ClinicalDiscussion(
                    whatTheyMightConsider: "When the gap between doses exceeds how long each dose lasts, predictable OFF windows open up. Neurologists have several levers for this — for example adjusting dose timing or frequency, or a longer-acting formulation. These are decisions only your neurologist can make. The value here is bringing them this pattern, with the data behind it.",
                    bringThisData: [
                        "Median ON-duration: 192 min (3.2 h), n=106 doses over 40 days",
                        "Median daytime gap between doses: ~5 h",
                        "OFF time concentrated afternoon/evening (60–70%)",
                        "Afternoon dose also slow to onset (67 vs 38 min)"
                    ]
                )
            ),

            // 3) REASSURING — gait, an informational positive.
            Insight(
                title: "Your walking hasn't declined",
                summary: "Over 5.7 years: speed slightly up, gait slightly more stable. No measurable decline.",
                stage: .verdict,
                finding: "2020 → 2026: walking speed +5%, double-support −8% (steadier), step length and asymmetry flat.",
                mechanism: "A plausible contributor is your active lifestyle. Caveat: noisy metrics across several devices (iPhone 11 → Air) — read the direction, not the decimals. Not a clinical assessment.",
                confidence: .moderate,
                evidenceDays: 2080,
                verdict: Verdict(
                    outcome: .worked,
                    controlLabel: "2020", controlValue: "baseline",
                    changeLabel: "2026", changeValue: "+5% speed",
                    summary: "No measurable gait decline over 5.7 years — quietly reassuring for a degenerative condition.",
                    nextStep: "Nothing to change. The app keeps watching the trend."
                )
            ),

            // 4) RULED OUT — honest null, kept low-key (collapsed).
            Insight(
                title: "Sleep & exercise → next-day tremor",
                summary: "No detectable effect found yet across ~42 days.",
                stage: .verdict,
                finding: "Sleep vs. next-day tremor: r ≈ +0.20, not significant. Exercise before/after: +0.06 (p=0.95). Workout vs. rest days: 1.01 vs. 1.05.",
                mechanism: "Likely buried under medication cycling and limited data, rather than truly absent.",
                confidence: .emerging,
                evidenceDays: 42,
                verdict: Verdict(
                    outcome: .noChange,
                    controlLabel: "Rest days", controlValue: "1.05",
                    changeLabel: "Workout days", changeValue: "1.01",
                    summary: "No reliable link yet between sleep or exercise and your tremor.",
                    nextStep: "Not surfacing this as advice. Reopens automatically if more data reveals a signal."
                )
            )
        ]
    }

    // Synthesizes a plausible piecewise tremor-vs-time curve for previews only:
    // flat at baseline until the dose (t=0), linear fall to the trough by `tTrough`,
    // then (if `recoverBy` is set) linear rise back to baseline = the wearing-off
    // shape. The live app uses real curves from CorrelationEngine.aggregateCurve.
    private static func sampleCurve(
        _ label: String, bucket: CorrelationEngine.Bucket?, doseCount: Int,
        lo: Double, hi: Double, baseline: Double, trough: Double, tTrough: Double,
        recoverBy: Double?
    ) -> CorrelationEngine.DoseCurve {
        var points: [CorrelationEngine.CurvePoint] = []
        var m = lo
        while m < hi {
            let t = m + 2.5
            let value: Double
            if t <= 0 {
                value = baseline
            } else if t <= tTrough {
                value = baseline + (trough - baseline) * (t / tTrough)
            } else if let r = recoverBy, t <= r {
                value = trough + (baseline - trough) * ((t - tTrough) / (r - tTrough))
            } else {
                value = recoverBy == nil ? trough : baseline
            }
            points.append(CorrelationEngine.CurvePoint(minute: t, value: value, n: doseCount))
            m += 5
        }
        return CorrelationEngine.DoseCurve(label: label, bucket: bucket, doseCount: doseCount, points: points)
    }
}

// MARK: - Screen

// Container: loads the engine's output once, then hands it to the renderer.
// Tremor readings come from SwiftData (multi-day); doses from HealthKit.
struct InsightsView: View {
    @EnvironmentObject private var healthKit: HealthKitManager
    @Query(sort: \TremorReading.timestamp, order: .forward) private var allReadings: [TremorReading]
    @State private var insights: [Insight] = []
    @State private var didLoad = false

    var body: some View {
        Group {
            if didLoad {
                // Once computed: either the cards, or the genuine empty state for a
                // user with no qualifying data (InsightsList decides which).
                InsightsList(insights: $insights)
            } else {
                // While computing: a real loading state, distinct from "no data."
                InsightsLoadingState()
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didLoad else { return }

            // Snapshot the SwiftData models into Sendable values *here on the main
            // actor* (cheap O(n) copy), then run the heavy engine off the main thread.
            // This keeps the UI — including the back button — responsive and lets the
            // loading spinner actually animate, instead of freezing for seconds.
            let samples = allReadings.map {
                TremorPoint(timestamp: $0.timestamp, tremorScore: $0.tremorScore)
            }
            let doses = await healthKit.fetchLevodopaDoses()

            insights = await Task.detached(priority: .userInitiated) {
                CorrelationEngine.generateInsights(samples: samples, doses: doses)
            }.value
            didLoad = true
        }
    }
}

// Shown while the engine computes (now off the main thread). Honest and brief —
// "analyzing," not "no data." A genuine new user falls through to InsightsEmptyState.
private struct InsightsLoadingState: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(Insight.brandBlue)
            Text("Analyzing your data…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Pure renderer: owns no data source, so it previews without a model container
// and is trivially testable. Mutations (start/stop experiment) flow back via the binding.
private struct InsightsList: View {
    @Binding var insights: [Insight]

    private var attention: [Binding<Insight>] { bindings { $0.stage == .hypothesis || $0.stage == .experiment } }
    private var clinical:  [Binding<Insight>] { bindings { $0.stage == .clinicalDiscussion } }
    private var results:   [Binding<Insight>] { bindings { $0.stage == .verdict } }

    private var hasInsights: Bool {
        !attention.isEmpty || !clinical.isEmpty || !results.isEmpty
    }

    // Priority order is implicit now that section headers are gone: actionable
    // first (hypotheses/experiments), then the clinical discussion, then results.
    private var orderedInsights: [Binding<Insight>] { attention + clinical + results }

    var body: some View {
        ScrollView {
            if hasInsights {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(orderedInsights, id: \.wrappedValue.id) { $insight in
                        InsightCard(insight: $insight, allInsights: insights)
                    }
                    disclaimerFooter
                }
                .padding()
            } else {
                InsightsEmptyState()
                    .padding()
            }
        }
    }

    // Quiet fine-print at the foot of the list rather than crowding the top.
    private var disclaimerFooter: some View {
        Text("Your data, not medical advice — never change a dose without your neurologist.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private func bindings(_ match: (Insight) -> Bool) -> [Binding<Insight>] {
        insights.indices.filter { match(insights[$0]) }.map { i in $insights[i] }
    }
}

// MARK: - Insight card (collapsed by default; expands on tap)

private struct InsightCard: View {
    @Binding var insight: Insight
    let allInsights: [Insight]   // for the full-report PDF
    @State private var expanded = false
    @State private var showWhy = false   // second-level disclosure for the mechanism
    @State private var isGeneratingPDF = false   // share button shows a spinner while the PDF renders

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 12 : 6) {
            // Header row — always visible
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        stageChip
                        Spacer()
                        ConfidenceDots(confidence: insight.confidence)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(insight.title)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Text(insight.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                detail
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(stageAccent.opacity(0.25), lineWidth: 1)
        )
        .onAppear { expanded = insight.startExpanded }
    }

    // MARK: Expanded detail, branched by stage

    @ViewBuilder
    private var detail: some View {
        Text(insight.finding).font(.subheadline)

        if let note = insight.updatedNote {
            Label(note, systemImage: "arrow.up.forward")
                .font(.caption2).foregroundStyle(Insight.brandBlue)
        }

        // The engine's plot-ready curve, rendered inside the expanded card.
        switch insight.chart {
        case .doseResponse(let dr): DoseResponseChartView(chart: dr)
        case .wearingOff(let wo):   WearingOffChartView(chart: wo)
        case .none:                 EmptyView()
        }

        switch insight.stage {
        case .hypothesis:         hypothesisDetail
        case .experiment:         experimentDetail
        case .verdict:            verdictDetail
        case .clinicalDiscussion: clinicalDetail
        }
        // Provenance (doses + days) lives in the finding sentence above, not a
        // separate gray footer — one less font/color switch per card.
    }

    private var hypothesisDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            whyBlock(insight.mechanism)
            Button {
                withAnimation(.snappy) { startExperiment() }
            } label: {
                Label("Try an experiment", systemImage: "flask")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Insight.brandBlue)
        }
    }

    @ViewBuilder
    private var experimentDetail: some View {
        if let exp = insight.experiment {
            VStack(alignment: .leading, spacing: 12) {
                Text(exp.oneLine).font(.subheadline.weight(.semibold))
                ABRow(controlLabel: exp.controlLabel, changeLabel: exp.changeLabel)
                metaRow("ruler", "Measuring", exp.metric)
                metaRow("checklist", "Success rule (set in advance)", exp.decisionRule)
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: exp.progress).tint(Insight.brandBlue)
                    Text("Day \(exp.daysElapsed) of \(exp.targetDays) — just keep logging as usual.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                safetyBanner(exp.safetyNote)
                Button(role: .destructive) {
                    withAnimation(.snappy) { stopExperiment() }
                } label: {
                    Label("Stop experiment", systemImage: "xmark.circle")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var verdictDetail: some View {
        if let v = insight.verdict {
            VStack(alignment: .leading, spacing: 12) {
                Label(v.outcome.label, systemImage: v.outcome.icon)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(v.outcome.color)
                HStack(spacing: 12) {
                    resultPill(v.controlLabel, v.controlValue, highlighted: false)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    resultPill(v.changeLabel, v.changeValue, highlighted: v.outcome == .worked)
                }
                Text(v.summary).font(.subheadline)
                metaRow("arrow.turn.down.right", "Next", v.nextStep)
            }
        }
    }

    @ViewBuilder
    private var clinicalDetail: some View {
        if let c = insight.clinical {
            VStack(alignment: .leading, spacing: 12) {
                whyBlock(c.whatTheyMightConsider, title: "What your neurologist might consider")
                // The specific data points (ON-duration, gap, doses-worn-off) are
                // intentionally NOT listed inline — they duplicate the finding above and
                // live in the shareable summary below, which is the doctor-facing artifact.
                Button {
                    isGeneratingPDF = true
                    // Defer the work one frame so SwiftUI paints the spinner (and commits
                    // its animation to the render server, where it keeps spinning) before
                    // the synchronous PDF render blocks the main thread — rasterizing the
                    // charts is the ~3s slow part. ImageRenderer requires the main actor,
                    // so this Task stays on it; the brief sleep just guarantees a frame.
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        let url = ClinicalReportPDF.generate(insights: allInsights)
                        isGeneratingPDF = false
                        if let url {
                            ShareSheetPresenter.present(items: [url])
                        } else {
                            ShareSheetPresenter.present(items: [clinicalSummaryText(c)])  // text fallback
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isGeneratingPDF {
                            ProgressView().tint(Insight.brandBlue)
                            Text("Preparing summary…")
                        } else {
                            Label("Prepare a summary to share", systemImage: "square.and.arrow.up")
                        }
                    }
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(Insight.brandBlue)
                .disabled(isGeneratingPDF)
                // No safety banner here: the "For your neurologist" header + the
                // "decisions only your neurologist can make" line above + the list's
                // global disclaimer already carry it. Three times would be nagging.
            }
        }
    }

    // Builds a clinician-ready text summary for the share sheet. Plain language +
    // the data points to discuss + an n-of-1 provenance line. The user can email,
    // AirDrop, or Print → Save as PDF to bring it to the appointment.
    private func clinicalSummaryText(_ c: ClinicalDiscussion) -> String {
        var lines: [String] = []
        lines.append("Kāmpa — symptom summary for clinical discussion")
        lines.append("")
        lines.append("Pattern: \(insight.title)")
        lines.append("Confidence: \(insight.confidence.rawValue) · based on \(daysLabel) of data")
        lines.append("")
        lines.append("\(insight.summary) \(insight.finding)")
        lines.append("")
        lines.append("For discussion:")
        lines.append(contentsOf: c.bringThisData.map { "• \($0)" })
        lines.append("")
        lines.append("Generated from passive Apple Watch tremor monitoring (Movement Disorder API). This is one person's own data (n-of-1), shared for discussion — not a diagnosis or treatment recommendation.")
        return lines.joined(separator: "\n")
    }

    // MARK: Loop transitions (prototype: in-memory; real version persists)

    private func startExperiment() {
        insight.stage = .experiment
        insight.experiment = Experiment(
            oneLine: "Take your 3 PM dose 45 min before lunch, not after.",
            controlLabel: "Dose after lunch (usual)",
            changeLabel: "Dose 45 min before lunch",
            metric: "Minutes from dose until tremor drops below your ON threshold",
            decisionRule: "Counts as working if before-lunch is ≥15 min faster, averaged over the window.",
            targetDays: 14, daysElapsed: 0,
            safetyNote: "Changes only *when you eat* around your existing 3 PM dose — not the dose itself."
        )
    }

    private func stopExperiment() {
        insight.stage = .hypothesis
        insight.experiment = nil
    }

    // MARK: Small pieces

    private func whyBlock(_ text: String, title: String = "Why this might happen") -> some View {
        DisclosureGroup(isExpanded: $showWhy) {
            Text(text)
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: "lightbulb")
                .font(.subheadline.weight(.medium)).foregroundStyle(Insight.brandBlue)
        }
        .tint(Insight.brandBlue)
    }

    private var stageChip: some View {
        let (text, icon) = stageLabel
        return Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(stageAccent.opacity(0.15)).foregroundStyle(stageAccent)
            .clipShape(Capsule())
    }

    private var stageLabel: (String, String) {
        switch insight.stage {
        case .hypothesis:         ("Hypothesis", "magnifyingglass")
        case .experiment:         ("Experiment running", "flask")
        case .verdict:            (insight.verdict?.outcome == .noChange ? "Ruled out" : "Result", "checkmark.seal")
        case .clinicalDiscussion: ("For your neurologist", "stethoscope")
        }
    }

    private var stageAccent: Color {
        switch insight.stage {
        case .hypothesis:         Insight.brandBlue
        case .experiment:         .orange
        case .verdict:            insight.verdict?.outcome.color ?? .green
        case .clinicalDiscussion: .teal
        }
    }

    private var daysLabel: String {
        insight.evidenceDays >= 365
            ? "\(insight.evidenceDays / 365)+ years"
            : "\(insight.evidenceDays) days"
    }

    private func metaRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.caption2).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(body).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func resultPill(_ label: String, _ value: String, highlighted: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(highlighted ? .green : .primary)
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background((highlighted ? Color.green : Color.secondary).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func safetyBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "cross.case").font(.caption2)
            Text(text).font(.caption2)
        }
        .foregroundStyle(.secondary).padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Reusable bits

private struct ABRow: View {
    let controlLabel: String; let changeLabel: String
    var body: some View {
        HStack(spacing: 10) {
            tag("A", controlLabel, .secondary)
            tag("B", changeLabel, Insight.brandBlue)
        }
    }
    private func tag(_ letter: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(letter).font(.caption2.bold()).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(color).clipShape(Circle())
            Text(label).font(.footnote).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConfidenceDots: View {
    let confidence: Insight.Confidence
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(i < confidence.filledDots ? confidence.color : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
            Text(confidence.rawValue).font(.caption2).foregroundStyle(confidence.color)
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 4))
            configuration.title
        }
    }
}

// MARK: - Charts
//
// Renders the engine's plot-ready `DoseResponseChart`: mean tremor vs minutes-since-
// dose, one line per time-of-day bucket, so the morning-vs-afternoon gap is visible
// rather than just asserted in prose. X=0 is the dose; the dashed line is the OFF
// threshold. Lower = better control (less tremor), so a line that dips deeper and
// sooner is the better-working dose — the morning curve, by design.

private struct DoseResponseChartView: View {
    let chart: CorrelationEngine.DoseResponseChart

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                // OFF threshold — context for "how low is good."
                RuleMark(y: .value("OFF threshold", chart.threshold))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("OFF").font(.caption2).foregroundStyle(.secondary)
                    }

                // The dose itself, at t=0.
                RuleMark(x: .value("Dose", chart.doseMinute))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("dose").font(.caption2).foregroundStyle(.tertiary)
                    }

                // One smoothed line per bucket; NaN/empty bins dropped so a truncated
                // tail (afternoon doses cut off by the evening dose) just ends early.
                ForEach(chart.curves) { curve in
                    ForEach(plottable(curve), id: \.minute) { pt in
                        LineMark(
                            x: .value("Minutes since dose", pt.minute),
                            y: .value("Tremor", pt.value),
                            series: .value("Time of day", curve.label)
                        )
                        .foregroundStyle(by: .value("Time of day", curve.label))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: chart.curves.map(\.label),
                range: chart.curves.map(color(for:))
            )
            .chartXScale(domain: -30...180)
            .chartYScale(domain: 0...yMax)   // tremor can't be negative; anchor at 0
            .chartXAxis {
                AxisMarks(values: [0, 60, 120, 180]) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let m = value.as(Int.self) { Text("\(m)m").font(.caption2) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { AxisGridLine(); AxisTick(); AxisValueLabel() }
            }
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 180)
            .accessibilityLabel("Tremor over time after each dose, comparing times of day")

            Text("Lower is better — less tremor. Earlier, deeper dip = the dose working faster.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // Drop empty bins and clamp to the visible window so interpolation stays honest.
    private func plottable(_ curve: CorrelationEngine.DoseCurve) -> [CorrelationEngine.CurvePoint] {
        curve.points.filter { !$0.value.isNaN && $0.minute >= -30 && $0.minute <= 180 }
    }

    // Upper bound rounded up to the next half-unit, with headroom for the OFF line;
    // floor of 1.5 so a well-controlled day still shows the threshold comfortably.
    private var yMax: Double {
        let vals = chart.curves.flatMap { $0.points.map(\.value) }.filter { !$0.isNaN }
        let m = max(chart.threshold, vals.max() ?? 1.5)
        return max(1.5, (m * 2).rounded(.up) / 2)
    }

    // Afternoon (the slower dose) gets the attention color; morning is brand blue
    // as the reference; pre-lunch (if present) a muted third.
    private func color(for curve: CorrelationEngine.DoseCurve) -> Color {
        switch curve.bucket {
        case .morning:   return Insight.brandBlue
        case .afternoon: return .orange
        case .preLunch:  return .teal
        default:         return .secondary
        }
    }
}

// MARK: - Wearing-off chart
//
// The canonical single-dose response, pooled across isolated doses: tremor starts at
// the pre-dose baseline (OFF), the dose pulls it down through the OFF threshold into
// the controlled "ON" zone, it bottoms out at the deepest-ON point, then drifts back
// up — wearing off. The KM marker shows where the *typical* dose has worn off (median
// ON-duration). The clinical point the card makes: that marker lands well before the
// next dose is due, so OFF windows open up. Reads left-to-right as a story, not a stat.

private struct WearingOffChartView: View {
    let chart: CorrelationEngine.WearingOffChart

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                // "Controlled" zone: anything below the OFF threshold = symptoms managed.
                RectangleMark(yStart: .value("floor", 0), yEnd: .value("OFF", chart.threshold))
                    .foregroundStyle(.green.opacity(0.06))

                // OFF threshold + pre-dose baseline as reference lines.
                RuleMark(y: .value("OFF threshold", chart.threshold))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("OFF").font(.caption2).foregroundStyle(.secondary)
                    }
                if !chart.baseline.isNaN {
                    RuleMark(y: .value("Before dose", chart.baseline))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .annotation(position: .bottom, alignment: .trailing, spacing: 2) {
                            Text("before dose").font(.caption2).foregroundStyle(.tertiary)
                        }
                }

                // The dose, at t=0.
                RuleMark(x: .value("Dose", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("dose").font(.caption2).foregroundStyle(.tertiary)
                    }

                // KM median ON-duration: where the typical dose has worn off.
                if !chart.medianDurationMin.isNaN {
                    RuleMark(x: .value("Worn off", chart.medianDurationMin))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .foregroundStyle(Insight.brandBlue.opacity(0.6))
                        .annotation(position: .top, alignment: .center, spacing: 2) {
                            Text("worn off ~\(hours(chart.medianDurationMin))")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Insight.brandBlue)
                        }
                }

                // The pooled response curve.
                ForEach(plottable, id: \.minute) { pt in
                    LineMark(
                        x: .value("Minutes since dose", pt.minute),
                        y: .value("Tremor", pt.value)
                    )
                    .foregroundStyle(Insight.brandBlue)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                // Deepest ON — the best the dose achieves.
                if let trough = troughPoint {
                    PointMark(
                        x: .value("Minutes since dose", trough.minute),
                        y: .value("Tremor", trough.value)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(60)
                    .annotation(position: .bottom, alignment: .center, spacing: 2) {
                        Text("deepest ON").font(.caption2).foregroundStyle(.green)
                    }
                }
            }
            .chartXScale(domain: -30...300)
            .chartYScale(domain: 0...yMax)   // tremor can't be negative; anchor at 0
            .chartXAxis {
                AxisMarks(values: [0, 60, 120, 180, 240, 300]) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let m = value.as(Int.self) { Text("\(m)m").font(.caption2) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { AxisGridLine(); AxisTick(); AxisValueLabel() }
            }
            .frame(height: 180)
            .accessibilityLabel("One dose over time: tremor falls after the dose, then rises as it wears off")

            Text("One typical dose, averaged. It pulls tremor into the controlled zone, then wears off — the marked point is when the average dose has faded.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var plottable: [CorrelationEngine.CurvePoint] {
        chart.curve.points.filter { !$0.value.isNaN && $0.minute >= -30 && $0.minute <= 300 }
    }

    // Upper bound includes the pre-dose baseline (the curve's high point) plus the
    // OFF line, rounded up to the next half-unit; floored at 1.5.
    private var yMax: Double {
        let base = chart.baseline.isNaN ? 0 : chart.baseline
        let m = max(chart.threshold, base, plottable.map(\.value).max() ?? 1.5)
        return max(1.5, (m * 2).rounded(.up) / 2)
    }

    // Lowest post-dose point = deepest ON (matches the engine's bestOnMinute).
    private var troughPoint: CorrelationEngine.CurvePoint? {
        plottable.filter { $0.minute > 0 }.min(by: { $0.value < $1.value })
    }

    private func hours(_ minutes: Double) -> String {
        String(format: "%.1fh", minutes / 60)
    }
}

// MARK: - PDF chart rasterization
//
// The clinical PDF (ClinicalReportPDF) is UIKit/UIGraphics and can't host SwiftUI or
// Charts directly. Rather than re-draw the curves by hand, we render the very same
// chart views to a bitmap and hand the PDF a CGImage. This lives here — not in the PDF
// file — so InsightsView stays the single owner of the chart views, and so this file
// stays UIKit-free (it returns CGImage and never names UIImage, per the file's
// no-UIKit constraint).

/// A chart sized and styled for a printed page: pinned to the PDF's content width,
/// forced to a white / light appearance so it prints cleanly no matter the device's
/// dark mode at generation time, and boxed so it reads as a figure on the page.
private struct PDFChartCard: View {
    let chart: CorrelationEngine.InsightChart

    /// US-Letter width (612pt) minus the PDF's 48pt margins on each side — the same
    /// content width ClinicalReportPDF draws text into, so the figure spans the column.
    static let contentWidth: CGFloat = 612 - 48 * 2

    var body: some View {
        Group {
            switch chart {
            case .doseResponse(let dr): DoseResponseChartView(chart: dr)
            case .wearingOff(let wo):   WearingOffChartView(chart: wo)
            }
        }
        .padding(14)
        .frame(width: PDFChartCard.contentWidth)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.88), lineWidth: 1)
        )
        .environment(\.colorScheme, .light)
    }
}

/// Rasterize an insight's engine chart for embedding in the clinical PDF. Main-actor
/// because it renders a SwiftUI view; returns a CGImage so the caller (UIKit) draws it
/// and this file never has to import UIKit. The 3× scale keeps it crisp in print; the
/// PDF draws it aspect-preserving, so the exact scale doesn't affect page layout.
@MainActor
func pdfChartImage(for chart: CorrelationEngine.InsightChart) -> CGImage? {
    let renderer = ImageRenderer(content: PDFChartCard(chart: chart))
    renderer.scale = 3
    return renderer.cgImage
}

// MARK: - Empty / early state
//
// Shown until the engine surfaces its first finding above threshold. Honest, not a
// fake card: tells the user insights appear *automatically* once there's enough data
// to be statistically meaningful, and names what's being watched for so the wait
// feels purposeful — no streaks, no nagging, consistent with the zero-burden premise.

private struct InsightsEmptyState: View {
    private let watchingFor = [
        ("pills", "How your doses affect tremor, and when they wear off"),
        ("clock.badge", "Time-of-day patterns in your symptoms"),
        ("bed.double", "Whether sleep and activity move next-day tremor"),
        ("figure.walk", "Long-term trends in your walking")
    ]

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44))
                .foregroundStyle(Insight.brandBlue)
                .padding(.top, 40)

            VStack(spacing: 8) {
                Text("Gathering your data")
                    .font(.title2.weight(.semibold))
                Text("Insights appear here on their own once there's enough data to find a pattern that's real, not noise. Nothing for you to do — keep wearing your Watch and logging as usual.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("What the app is watching for")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(watchingFor, id: \.0) { icon, text in
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundStyle(Insight.brandBlue)
                            .frame(width: 24)
                        Text(text).font(.subheadline)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("With insights") {
    NavigationStack {
        InsightsList(insights: .constant(Insight.samples))
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Empty / early state") {
    NavigationStack {
        ScrollView { InsightsEmptyState().padding() }
            .navigationTitle("Insights")
    }
}

#Preview("Dose-response chart") {
    if case .doseResponse(let dr)? = Insight.samples.first(where: { $0.chart != nil })?.chart {
        DoseResponseChartView(chart: dr)
            .padding()
    } else {
        Text("No sample chart")
    }
}

#Preview("Wearing-off chart") {
    let wo = Insight.samples.compactMap { insight -> CorrelationEngine.WearingOffChart? in
        if case .wearingOff(let c)? = insight.chart { return c }
        return nil
    }.first
    if let wo {
        WearingOffChartView(chart: wo)
            .padding()
    } else {
        Text("No sample chart")
    }
}
