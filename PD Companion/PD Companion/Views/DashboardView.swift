import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var connectivity: PhoneConnectivityManager
    @Query(sort: \TremorReading.timestamp, order: .reverse) var readings: [TremorReading]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    connectionStatusView
                    tremorSummaryCard
                    TremorChartView(readings: Array(readings.prefix(200)))
                    HealthSummaryView()
                        .environmentObject(healthKit)
                }
                .padding()
            }
            .navigationTitle("PD Companion")
            .refreshable {
                await healthKit.fetchTodaySnapshot()
            }
        }
    }

    private var connectionStatusView: some View {
        HStack {
            Image(systemName: connectivity.isWatchReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                .foregroundStyle(connectivity.isWatchReachable ? .green : .secondary)
            Text(connectivity.isWatchReachable ? "Watch connected" : "Watch not connected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let latest = readings.first {
                Text("Updated \(latest.timestamp.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var tremorSummaryCard: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let todayReadings = readings.filter { $0.timestamp >= today }
        let avgTremor = todayReadings.isEmpty ? nil :
            todayReadings.reduce(0.0) { $0 + $1.tremorScore } / Double(todayReadings.count)
        let avgDyskinesia = todayReadings.isEmpty ? nil :
            todayReadings.reduce(0.0) { $0 + $1.dyskinesiaScore } / Double(todayReadings.count)

        return VStack(spacing: 12) {
            Text("Today")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let avgTremor, let avgDyskinesia {
                HStack(spacing: 24) {
                    ScoreCard(title: "Tremor", score: avgTremor)
                    ScoreCard(title: "Dyskinesia", score: avgDyskinesia)
                }
            } else {
                Text("No readings yet today. Wear your Apple Watch to start tracking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ScoreCard: View {
    let title: String
    let score: Double

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f", score))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(colorForScore(score))
            Text(labelForScore(score))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
