import SwiftUI

struct WatchDashboardView: View {
    @EnvironmentObject var movementManager: MovementDisorderManager
    @StateObject private var focusSession = FocusSessionManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !movementManager.isAvailable {
                    Text("Movement tracking unavailable on this device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if movementManager.recentTremorSamples.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Text("Monitoring active")
                            .font(.headline)
                        Text("Tremor data will appear as it becomes available")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    latestReadingView
                    todaySummaryView
                }
                focusSessionView
            }
            .padding()
        }
        .navigationTitle("PD Companion")
    }

    private var focusSessionView: some View {
        VStack(spacing: 6) {
            Divider()
            if focusSession.isActive {
                if focusSession.willExpireSoon {
                    Text("Session ending soon")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Button(role: .destructive) {
                    focusSession.stop()
                } label: {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                        Text("End Focus")
                    }
                }
                if let started = focusSession.startedAt {
                    Text("Live since \(started.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    focusSession.start()
                } label: {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("Start Focus")
                    }
                }
                Text("Live monitoring up to ~1 hour")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var latestReadingView: some View {
        let latest = movementManager.recentTremorSamples.last
        return VStack(spacing: 4) {
            Text("Latest Tremor")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f", latest?.tremorScore ?? 0))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(colorForScore(latest?.tremorScore ?? 0))
            Text(labelForScore(latest?.tremorScore ?? 0))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var todaySummaryView: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let todaySamples = movementManager.recentTremorSamples.filter {
            $0.timestamp >= today
        }
        let avgTremor = todaySamples.isEmpty ? 0 :
            todaySamples.reduce(0.0) { $0 + $1.tremorScore } / Double(todaySamples.count)
        let avgDyskinesia = todaySamples.isEmpty ? 0 :
            todaySamples.reduce(0.0) { $0 + $1.dyskinesiaScore } / Double(todaySamples.count)

        return VStack(spacing: 8) {
            Divider()
            HStack {
                VStack {
                    Text("Tremor")
                        .font(.caption2)
                    Text(String(format: "%.1f", avgTremor))
                        .font(.headline)
                        .foregroundStyle(colorForScore(avgTremor))
                }
                Spacer()
                VStack {
                    Text("Dyskinesia")
                        .font(.caption2)
                    Text(String(format: "%.1f", avgDyskinesia))
                        .font(.headline)
                        .foregroundStyle(colorForScore(avgDyskinesia))
                }
            }
            Text("Today's averages")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func colorForScore(_ score: Double) -> Color {
        switch score {
        case 0..<1: return .green
        case 1..<2: return .yellow
        case 2..<3: return .orange
        default: return .red
        }
    }

    private func labelForScore(_ score: Double) -> String {
        switch score {
        case 0..<0.5: return "None"
        case 0.5..<1.5: return "Slight"
        case 1.5..<2.5: return "Mild"
        case 2.5..<3.5: return "Moderate"
        default: return "Strong"
        }
    }
}
