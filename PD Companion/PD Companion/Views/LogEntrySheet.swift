import SwiftUI
import SwiftData

// MARK: - Entry point: category menu

struct LogEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onLogged: (Date) -> Void

    enum Destination: Hashable { case food }
    @State private var path: [Destination] = []
    @State private var showMedInfo = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                menuRow(
                    icon: "fork.knife", iconBg: Color.brown.opacity(0.15), iconColor: .brown,
                    title: "Food", subtitle: "A meal, snack, or drink"
                ) { path.append(.food) }
                menuRow(
                    icon: "pills.fill", iconBg: Color.pink.opacity(0.15), iconColor: .pink,
                    title: "Medication", subtitle: "Logged in Apple Health",
                    trailing: "arrow.up.forward.app"
                ) { showMedInfo = true }
            }
            .listStyle(.insetGrouped)
            .alert("Logging your medications", isPresented: $showMedInfo) {
                Button("Open Apple Health") { openMedications() }
                Button("Not now", role: .cancel) { }
            } message: {
                Text("🔍 → Medications")
            }
            .navigationTitle("Log entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: Destination.self) { dest in
                switch dest {
                case .food:
                    LogFoodScreen { date in onLogged(date); dismiss() }
                }
            }
        }
    }

    private func menuRow(
        icon: String, iconBg: Color, iconColor: Color,
        title: String, subtitle: String,
        trailing: String = "chevron.right",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconBg)
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .foregroundStyle(iconColor)
                        .font(.system(size: 20))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).fontWeight(.medium).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: trailing).foregroundStyle(.tertiary).font(.subheadline)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // Deep-links straight to the Health app's Medications screen. The scheme is
    // undocumented but verified on device (x-apple-health://Medications). Falls back to
    // opening Health's home if the path ever stops resolving, so the row never dead-ends.
    private func openMedications() {
        let medications = URL(string: "x-apple-health://Medications")!
        openURL(medications) { accepted in
            if !accepted, let health = URL(string: "x-apple-health://") {
                openURL(health) { _ in dismiss() }
            } else {
                dismiss()
            }
        }
    }
}

// MARK: - Log food screen

struct LogFoodScreen: View {
    @Environment(\.modelContext) private var modelContext
    let onSaved: (Date) -> Void

    @State private var description: String = ""
    @State private var timestamp: Date = .now

    var body: some View {
        Form {
            Section(header: Text("What did you eat or drink?")) {
                ZStack(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("e.g. 5 almonds with tea for breakfast")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 4)
                    }
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }
                Text("Just describe it. We'll estimate protein, fiber, and sugar for you later.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(header: Text("When")) {
                DatePicker("Date & time", selection: $timestamp, in: ...Date.now,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
        }
        .navigationTitle("Log food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
                    let attrs = FoodAttribute.detect(in: trimmed)
                    let event = FoodEvent(timestamp: timestamp, userDescription: trimmed, attributes: attrs)
                    modelContext.insert(event)
                    onSaved(timestamp)
                }
                .fontWeight(.semibold)
                .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

