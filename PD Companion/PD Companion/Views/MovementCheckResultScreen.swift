import SwiftUI
import SwiftData

/// What a trial reports: raw numbers beside the user's own usual range, and where the trial
/// fell in the dose cycle as a bare fact. ⛔ No score, no verdict, no before/after comparison
/// — see docs/design/movement-checks.md. The two confounds here (selection: a user taps when
/// something feels off; practice: tapping speed improves over weeks regardless of levodopa)
/// are worse than therapy logging's, so the silence is stricter, not looser.
struct MovementCheckResultScreen: View {
    let left: MovementCheckTrial
    let right: MovementCheckTrial
    let onDone: () -> Void

    @Query(sort: \MovementCheckTrial.timestamp) private var allTrials: [MovementCheckTrial]
    @EnvironmentObject private var healthKit: HealthKitManager
    @State private var recentDoses: [Dose] = []
    @State private var showHistory = false

    var body: some View {
        List {
            Section {
                MovementCheckMatrix(
                    left: left,
                    right: right,
                    history: allTrials,
                    // Anchored to the session, not to each hand: both trials are seconds
                    // apart and sit after the same dose.
                    doseFact: MovementCheckDoseFact.text(
                        for: min(left.timestamp, right.timestamp), doses: recentDoses)
                )
            } footer: {
                // ⚠️ Required by the design doc, and placed HERE deliberately: people get
                // measurably faster over the first weeks regardless of medication, and this
                // line is what stops that reading as a symptom change. It only does that work
                // next to the numbers.
                Text(MovementCheckCopy.practiceEffect)
            }

            Section {
                Button {
                    showHistory = true
                } label: {
                    Label("History & trend", systemImage: "chart.xyaxis.line")
                }
            }
        }
        .navigationTitle("Tapping")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onDone() }.fontWeight(.semibold)
            }
        }
        .navigationDestination(isPresented: $showHistory) {
            MovementCheckHistoryScreen()
        }
        .task {
            // One generous window covers both trials (they're seconds apart); a day back
            // is far more than any realistic dose gap, so this never misses the last dose.
            let earliest = min(left.timestamp, right.timestamp)
            let since = earliest.addingTimeInterval(-24 * 3600)
            recentDoses = await healthKit.fetchMedicationDoses(since: since)
        }
    }
}
