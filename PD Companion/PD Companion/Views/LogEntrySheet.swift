import SwiftUI
import SwiftData

// MARK: - Entry point: category menu

struct LogEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onLogged: (Date) -> Void

    enum Destination: Hashable { case food, meditation }
    @State private var path: [Destination] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                menuRow(
                    icon: "fork.knife", iconBg: Color.brown.opacity(0.15), iconColor: .brown,
                    title: "Food", subtitle: "A meal, snack, or drink"
                ) { path.append(.food) }

                menuRow(
                    icon: "figure.mind.and.body", iconBg: Color.cyan.opacity(0.15), iconColor: .cyan,
                    title: "Meditation", subtitle: "Mindfulness or breathing"
                ) { path.append(.meditation) }
            }
            .listStyle(.insetGrouped)
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
                case .meditation:
                    LogMeditationScreen { date in onLogged(date); dismiss() }
                }
            }
        }
    }

    private func menuRow(
        icon: String, iconBg: Color, iconColor: Color,
        title: String, subtitle: String,
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
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.subheadline)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
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

// MARK: - Log meditation screen

struct LogMeditationScreen: View {
    @EnvironmentObject var healthKit: HealthKitManager
    let onSaved: (Date) -> Void

    @State private var timestamp: Date = .now
    @State private var durationMinutes: Int = 10
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let quickPicks = [5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        Form {
            Section(header: Text("When")) {
                DatePicker("Date & time", selection: $timestamp, in: ...Date.now,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            Section(header: Text("Duration")) {
                HStack {
                    Button {
                        if durationMinutes > 1 { durationMinutes -= 1 }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                    Text("\(durationMinutes) min")
                        .font(.title2.bold())
                        .monospacedDigit()
                    Spacer()

                    Button { durationMinutes += 1 } label: {
                        Image(systemName: "plus")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPicks, id: \.self) { mins in
                            Button("\(mins) min") { durationMinutes = mins }
                                .buttonStyle(.bordered)
                                .tint(durationMinutes == mins ? .cyan : .secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .navigationTitle("Log meditation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await healthKit.writeMindfulSession(
                    start: timestamp,
                    duration: TimeInterval(durationMinutes * 60)
                )
                onSaved(timestamp)
            } catch {
                errorMessage = "Could not save: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

