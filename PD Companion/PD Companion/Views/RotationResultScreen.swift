import SwiftUI
import SwiftData

/// What a rotation session reports. ⛔ No score, no verdict, no before/after comparison — the
/// same silence Tapping keeps, and for the same two confounds: selection (you reach for this
/// when something feels off) and practice (people get faster for weeks regardless of
/// medication). See docs/design/movement-checks.md.
struct RotationResultScreen: View {
    let left: RotationTrial
    let right: RotationTrial
    let onDone: () -> Void

    @Query(sort: \RotationTrial.timestamp) private var allTrials: [RotationTrial]
    @EnvironmentObject private var healthKit: HealthKitManager
    @State private var recentDoses: [Dose] = []
    @State private var showHistory = false

    var body: some View {
        List {
            Section {
                RotationMatrix(
                    left: left,
                    right: right,
                    history: allTrials,
                    doseFact: MovementCheckDoseFact.text(
                        for: min(left.timestamp, right.timestamp), doses: recentDoses)
                )
            }

            Section {
                Button {
                    showHistory = true
                } label: {
                    Label("History & trend", systemImage: "chart.xyaxis.line")
                }
            }
        }
        .navigationTitle("Rotation")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onDone() }.fontWeight(.semibold)
            }
        }
        .navigationDestination(isPresented: $showHistory) {
            RotationHistoryScreen()
        }
        .task {
            let earliest = min(left.timestamp, right.timestamp)
            recentDoses = await healthKit.fetchMedicationDoses(
                since: earliest.addingTimeInterval(-24 * 3600))
        }
    }
}
