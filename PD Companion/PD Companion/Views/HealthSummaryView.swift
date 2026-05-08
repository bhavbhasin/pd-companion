import SwiftUI

struct HealthSummaryView: View {
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Today")
                .font(.headline)

            if let snapshot = healthKit.todaySnapshot {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    HealthMetricTile(
                        icon: "bed.double.fill",
                        title: "Sleep",
                        value: snapshot.sleepHours.map { String(format: "%.1f hrs", $0) },
                        color: .indigo
                    )
                    HealthMetricTile(
                        icon: "heart.fill",
                        title: "Resting HR",
                        value: snapshot.restingHeartRate.map { String(format: "%.0f bpm", $0) },
                        color: .red
                    )
                    HealthMetricTile(
                        icon: "waveform.path.ecg",
                        title: "HRV",
                        value: snapshot.hrvAverage.map { String(format: "%.0f ms", $0) },
                        color: .orange
                    )
                    HealthMetricTile(
                        icon: "figure.run",
                        title: "Exercise",
                        value: snapshot.exerciseMinutes.map { String(format: "%.0f min", $0) },
                        color: .green
                    )
                    HealthMetricTile(
                        icon: "brain.head.profile",
                        title: "Mindfulness",
                        value: snapshot.mindfulnessMinutes.map { String(format: "%.0f min", $0) },
                        color: .cyan
                    )
                    HealthMetricTile(
                        icon: "figure.walk",
                        title: "Steps",
                        value: snapshot.stepCount.map { String(format: "%.0f", $0) },
                        color: .teal
                    )
                }
            } else if let error = healthKit.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Loading health data...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct HealthMetricTile: View {
    let icon: String
    let title: String
    let value: String?
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value ?? "--")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
