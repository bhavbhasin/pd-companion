import SwiftUI
import Charts

struct TremorChartView: View {
    let readings: [TremorReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tremor Trend")
                .font(.headline)

            if readings.isEmpty {
                Text("Chart will appear once tremor data is collected from your Apple Watch.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(readings, id: \.timestamp) { reading in
                        LineMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("Tremor", reading.tremorScore)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(readings, id: \.timestamp) { reading in
                        LineMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("Dyskinesia", reading.dyskinesiaScore)
                        )
                        .foregroundStyle(.purple)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: 0...4)
                .chartYAxis {
                    AxisMarks(values: [0, 1, 2, 3, 4]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(labelForLevel(intValue))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "Tremor": .blue,
                    "Dyskinesia": .purple,
                ])
                .frame(height: 200)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func labelForLevel(_ level: Int) -> String {
        switch level {
        case 0: return "None"
        case 1: return "Slight"
        case 2: return "Mild"
        case 3: return "Moderate"
        case 4: return "Strong"
        default: return ""
        }
    }
}
