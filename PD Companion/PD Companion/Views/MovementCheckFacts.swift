import SwiftUI

/// Both hands of one session as a matrix: two columns (left / right), three rows (taps,
/// travel, pause). Used by the result screen and by the timeline detail sheet so the two
/// presentations of the same session can never drift apart.
///
/// ⭐ **Why a matrix and not two stacked blocks** (his call, Aug 5 2026): the less-affected
/// hand is the only internal control this design has, so the between-hands GAP is the signal.
/// Stacked per-hand blocks put the two numbers far enough apart that comparing them meant
/// scrolling — the layout was hiding the one comparison the feature exists to support. Side
/// by side, it reads in a glance and the whole session fits without scrolling.
///
/// ⛔ No delta column, no highlight on the faster side, no ranking. Two columns already invite
/// a scoreboard reading, and this feature never renders a verdict — see
/// `docs/design/movement-checks.md`. The numbers sit next to each other; the reader compares.
struct MovementCheckMatrix: View {
    /// Optional so a half-finished session (left captured, flow cancelled before right)
    /// still renders honestly as a column of "—" rather than crashing or hiding the hand
    /// that was recorded.
    let left: MovementCheckTrial?
    let right: MovementCheckTrial?
    /// Every other trial, both hands — the usual-range band for a cell is built from the same
    /// hand's own history, excluding the trial being shown.
    let history: [MovementCheckTrial]
    /// ⭐ ONE line for the session, not one per hand. The two trials are seconds apart and
    /// anchored to the same dose, so printing it twice made one fact look like two (and they
    /// could differ by a minute, which made it look like a discrepancy).
    let doseFact: String?
    /// The result screen defines its terms; the detail sheet doesn't. A definition earns its
    /// space at first contact, right after you've tapped — on a surface you reach by tapping
    /// a glyph on a chart weeks later, it's the thing pushing the numbers off screen.
    var showsDefinitions: Bool = false

    /// ⛔ **Pause was here and was removed Aug 5 2026 — do not add it back.** It is
    /// `(last - first) / (n - 1)`: the tap rate inverted, so it restates the Taps row in a
    /// different unit. The matrix was showing one measurement three times.
    ///
    /// ⚠️ **Spread is not a grade** — hence the name. "Accuracy" reads as pass/fail, and this
    /// feature never answers that. It is a distance: how far taps landed from the middle of
    /// the box, on average. It earns its row by being free to vary when the tap count doesn't,
    /// ⛔ NOT by being validated — the PLOS One study measured count, travel and dwell, not
    /// this, and it carries its own confound (tap faster, land sloppier).
    private enum Metric: CaseIterable {
        case taps, travel, spread
        var label: String {
            switch self {
            case .taps:   "Taps"
            case .travel: "Travel"
            case .spread: "Spread"
            }
        }
        var definition: String? {
            switch self {
            case .taps:   nil
            case .travel: "Travel is how far your finger moved on screen, tap to tap."
            case .spread: "Spread is how far your taps landed from the middle of the box, on average."
            }
        }
        /// `nil` where a trial can't answer — a trial captured before the app stored its
        /// capture geometry has no scale to turn stored points into a distance.
        func value(for trial: MovementCheckTrial) -> Double? {
            let s = MovementCheckMetrics.summary(for: trial)
            switch self {
            case .taps:   return Double(s.tapCount)
            case .travel: return s.travelMeters
            case .spread: return s.offTargetMM
            }
        }
        func text(_ value: Double?) -> String {
            guard let value else { return "—" }
            switch self {
            case .taps:   return String(format: "%.0f", value)
            case .travel: return String(format: "%.1f m", value)
            case .spread: return String(format: "%.0f mm", value)
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

            if showsDefinitions {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Metric.allCases.compactMap(\.definition), id: \.self) { line in
                        Text(line)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MovementCheckStyle.tint)
    }

    private func cell(_ metric: Metric, hand: MovementCheckHand, trial: MovementCheckTrial?) -> some View {
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

/// Pure helpers shared by every screen that needs to place a trial in the dose cycle.
enum MovementCheckDoseFact {
    /// The last dose before a trial, stated passively.
    ///
    /// ⛔ **Was "19h 21m after your 02:40 Sinemet" — do not go back to that shape.** Leading
    /// with elapsed time next to a measurement reads as attribution: it invites "so this is
    /// what the Sinemet did", which is exactly the claim this feature never makes (two
    /// confounds, selection and practice, both worse than therapy logging's). Passive voice
    /// and no elapsed figure leaves a fact the reader can use without a causal frame attached.
    ///
    /// ⭐ The DATE is deliberate, not decoration: on a once-a-day regimen the last dose is
    /// routinely on a different calendar day, and a bare clock time silently implies today.
    static func text(for timestamp: Date, doses: [Dose]) -> String? {
        guard let last = doses.filter({ $0.timestamp <= timestamp }).max(by: { $0.timestamp < $1.timestamp })
        else { return nil }
        let when = last.timestamp.formatted(.dateTime.hour().minute())
        let day = last.timestamp.formatted(.dateTime.month(.abbreviated).day())
        return "Last dose was \(last.name) at \(when), \(day)"
    }
}
