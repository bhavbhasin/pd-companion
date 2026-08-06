import SwiftUI

/// Picks which instrument to run. **Movement check** is the category; **Tapping** and
/// **Rotation** are the instruments inside it. See `docs/design/movement-checks.md`.
///
/// ⚠️ **Swaps its content rather than pushing.** Whichever test is chosen becomes the root of
/// this full-screen cover's own stack, which is what keeps two properties that were each paid
/// for with a device-testing round: no `.sheet` drag-to-dismiss gesture competing with a tap
/// (it was silently eating taps on the tremor-affected hand), and exactly ONE explicit Cancel
/// per screen instead of a back button arguing with it.
///
/// ⛔ Not a `NavigationLink` list. A pushed test would inherit a back button on top of its own
/// Cancel, which is the exact ambiguity the tapping screen already had removed once.
struct MovementCheckChooser: View {
    let onSaved: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Instrument: Hashable { case tapping, rotation }
    @State private var chosen: Instrument?

    var body: some View {
        NavigationStack {
            switch chosen {
            case .tapping:
                LogMovementCheckScreen(onSaved: onSaved)
            case .rotation:
                LogRotationScreen(onSaved: onSaved)
            case nil:
                picker
            }
        }
    }

    private var picker: some View {
        List {
            Section {
                row(icon: MovementCheckStyle.timelineSymbol, tint: MovementCheckStyle.tint,
                    title: "Tapping", subtitle: "Alternating finger taps") {
                    chosen = .tapping
                }
                row(icon: RotationStyle.timelineSymbol, tint: RotationStyle.tint,
                    title: "Rotation", subtitle: "Turning palm up & down") {
                    chosen = .rotation
                }
            } footer: {
                // ⛔ No scores, no streaks, no schedule — stated once, here, where someone is
                // deciding whether to bother. Each test then repeats nothing about grading.
                Text("Both hands, about 30 seconds. Nothing here is scored.")
            }
        }
        .navigationTitle("Movement check")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func row(icon: String, tint: Color, title: String, subtitle: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
