import SwiftUI

/// Both hands of one rotation session as a matrix — same grammar as Tapping's, deliberately,
/// so the two instruments in Movement check read identically.
///
/// ⛔ Two rows, and both earn their place: `Turns` is speed, `Amplitude` is how far the hand
/// actually travelled per flip. MDS-UPDRS 3.6 scores those separately because someone can flip
/// fast and shallow or slow and full, and `RotationMetricsTests` pins that they separate on
/// synthetic signals. ⛔ Turns/second is NOT shown — with a fixed 10 s it is the turn count
/// scaled, the same restatement trap that removed Pause and Travel from the tapping matrix.
/// Peak velocity and decrement are computed and exported, never displayed.
struct RotationMatrix: View {
    let left: RotationTrial?
    let right: RotationTrial?
    let history: [RotationTrial]
    let doseFact: String?

    private enum Metric: CaseIterable {
        case turns, amplitude
        var label: String {
            switch self {
            case .turns:     "Turns"
            case .amplitude: "Amplitude"
            }
        }
        var definition: String? {
            switch self {
            case .turns:     nil
            case .amplitude: RotationCopy.amplitudeDefinition
            }
        }
        func value(for trial: RotationTrial) -> Double? {
            guard let s = RotationMetrics.summary(for: trial) else { return nil }
            switch self {
            case .turns:     return Double(s.turns)
            case .amplitude: return s.meanAmplitudeDegrees
            }
        }
        func text(_ value: Double?) -> String {
            guard let value else { return "—" }
            switch self {
            case .turns:     return String(format: "%.0f", value)
            case .amplitude: return String(format: "%.0f°", value)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Color.clear.frame(width: 0, height: 0).gridColumnAlignment(.leading)
                    header("Left").gridColumnAlignment(.trailing)
                    header("Right").gridColumnAlignment(.trailing)
                }
                ForEach(Metric.allCases, id: \.self) { metric in
                    GridRow {
                        Text(metric.label).foregroundStyle(.secondary)
                        cell(metric, hand: .left, trial: left)
                        cell(metric, hand: .right, trial: right)
                    }
                }
            }

            if let doseFact {
                Text(doseFact).font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Metric.allCases.compactMap(\.definition), id: \.self) { Text($0) }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(RotationStyle.tint)
    }

    private func cell(_ metric: Metric, hand: MovementCheckHand, trial: RotationTrial?) -> some View {
        let ownHistory = history.filter { $0.hand == hand && $0.id != trial?.id }
        let range = MovementCheckMetrics.usualRange(ownHistory.compactMap { metric.value(for: $0) })
        return VStack(alignment: .trailing, spacing: 2) {
            Text(metric.text(trial.flatMap { metric.value(for: $0) }))
                .font(.body.weight(.medium))
                .monospacedDigit()
            if let range {
                Text("usual \(metric.text(range.lo)) - \(metric.text(range.hi))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Wording that has to read identically wherever a rotation number appears.
enum RotationCopy {
    static let amplitudeDefinition =
        "Amplitude is how far your hand turned on each flip, on average."
}
