import SwiftUI
import HealthKit

struct HealthSummaryView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.openURL) private var openURL

    private func openHealthApp() {
        if let url = URL(string: "x-apple-health://") {
            openURL(url)
        }
    }

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
                        color: .indigo,
                        action: openHealthApp
                    )
                    HealthMetricTile(
                        icon: "pills.fill",
                        title: medicationTitle,
                        value: medicationValue,
                        color: .pink,
                        action: openHealthApp
                    )
                    HealthMetricTile(
                        icon: "waveform.path.ecg",
                        title: "HRV",
                        value: snapshot.hrvAverage.map { String(format: "%.0f ms", $0) },
                        color: .orange,
                        action: openHealthApp
                    )
                    HealthMetricTile(
                        icon: workoutIcon,
                        title: workoutTitle,
                        value: workoutValue(snapshot: snapshot),
                        color: .green,
                        action: openHealthApp
                    )
                    HealthMetricTile(
                        icon: "brain.head.profile",
                        title: "Mindfulness",
                        value: snapshot.mindfulnessMinutes.map { String(format: "%.0f min", $0) },
                        color: .cyan,
                        action: openHealthApp
                    )
                    HealthMetricTile(
                        icon: "figure.walk",
                        title: "Steps",
                        value: snapshot.stepCount.map { String(format: "%.0f", $0) },
                        color: .teal,
                        action: openHealthApp
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

    private var medicationTitle: String {
        if let name = healthKit.lastMedicationName {
            return "Last \(name)"
        }
        return "Last Dose"
    }

    private var medicationValue: String? {
        guard let date = healthKit.lastMedicationDoseDate else { return nil }
        let elapsed = Date().timeIntervalSince(date)
        let hours = Int(elapsed / 3600)
        let minutes = Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 {
            return "\(hours)h \(minutes)m ago"
        }
        return "\(minutes)m ago"
    }

    private var workoutIcon: String {
        if let dominant = dominantWorkout {
            switch dominant.workoutActivityType {
            case .taiChi, .yoga, .pilates, .mindAndBody, .flexibility:
                return "figure.mind.and.body"
            case .pickleball, .tennis, .tableTennis:
                return "figure.tennis"
            case .running:
                return "figure.run"
            case .walking, .hiking:
                return "figure.walk"
            case .cycling:
                return "figure.outdoor.cycle"
            case .swimming:
                return "figure.pool.swim"
            case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining:
                return "figure.strengthtraining.traditional"
            case .highIntensityIntervalTraining:
                return "figure.highintensity.intervaltraining"
            case .boxing, .martialArts:
                return "figure.boxing"
            case .dance:
                return "figure.dance"
            default:
                return "figure.run"
            }
        }
        return "figure.run"
    }

    private var workoutTitle: String {
        if healthKit.todayWorkouts.isEmpty {
            return "Exercise"
        }
        if let dominant = dominantWorkout, healthKit.todayWorkouts.count == 1 {
            return dominant.workoutActivityType.displayName
        }
        return "Workouts"
    }

    private func workoutValue(snapshot: HealthSample) -> String? {
        let workouts = healthKit.todayWorkouts
        if workouts.isEmpty {
            return snapshot.exerciseMinutes.map { String(format: "%.0f min", $0) }
        }
        if workouts.count == 1, let only = workouts.first {
            return formatDuration(only.duration)
        }
        let total = workouts.reduce(0.0) { $0 + $1.duration }
        return "\(workouts.count) • \(formatDuration(total))"
    }

    private var dominantWorkout: HKWorkout? {
        healthKit.todayWorkouts.max(by: { $0.duration < $1.duration })
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}

struct HealthMetricTile: View {
    let icon: String
    let title: String
    let value: String?
    let color: Color
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
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
        .contentShape(Rectangle())
    }
}
