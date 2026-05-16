import SwiftUI
import SwiftData

struct EventDetailSheet: View {
    let event: DayEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var healthKit: HealthKitManager

    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var showEditScreen = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(event.iconColor.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: event.iconName)
                            .foregroundStyle(event.iconColor)
                            .font(.system(size: 26))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(categoryLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(event.iconColor)
                            .textCase(.uppercase)
                        Text(primaryTitle)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detailLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                // Food description / attributes
                if case .food(_, _, let desc, let attrs) = event {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        if !desc.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Entry").font(.caption).foregroundStyle(.secondary)
                                Text(desc).font(.subheadline)
                            }
                        }
                        if !attrs.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Detected").font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    ForEach(attrs, id: \.rawValue) { attr in
                                        Text(attr.displayName)
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(Color.brown.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }

                // Health app note for workout (read-only)
                if case .workout = event {
                    healthAppNote
                } else if case .medication = event {
                    healthAppNote
                }

                Spacer()

                // Action buttons
                VStack(spacing: 10) {
                    if case .food = event {
                        HStack(spacing: 12) {
                            Button {
                                showEditScreen = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)

                            Button(role: .destructive) {
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    } else if case .mindfulness = event {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete entry", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Button("Done") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .padding([.horizontal, .bottom])
            }
            .navigationDestination(isPresented: $showEditScreen) {
                if case .food(let id, _, let desc, _) = event {
                    EditFoodScreen(
                        foodId: id,
                        initialDescription: desc,
                        initialTimestamp: event.time,
                        onSaved: { dismiss() }
                    )
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .alert("Delete entry?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .disabled(isDeleting)
    }

    private var healthAppNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("To edit or delete, open the Health app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func performDelete() {
        isDeleting = true
        switch event {
        case .food(let id, _, _, _):
            let foodId = id
            let descriptor = FetchDescriptor<FoodEvent>(predicate: #Predicate { $0.id == foodId })
            if let record = try? modelContext.fetch(descriptor).first {
                modelContext.delete(record)
            }
            dismiss()

        case .mindfulness(_, let start, let duration):
            Task {
                try? await healthKit.deleteMindfulSession(start: start, duration: duration)
                await MainActor.run { dismiss() }
            }

        default:
            dismiss()
        }
    }

    private var categoryLabel: String {
        switch event {
        case .medication:  return "Medication"
        case .workout:     return "Workout"
        case .mindfulness: return "Meditation"
        case .food:        return "Food"
        }
    }

    private var primaryTitle: String { event.label }

    private var detailLine: String {
        switch event {
        case .medication(_, let time, _):
            return "Taken at \(time.formatted(.dateTime.hour().minute()))"
        case .workout(_, let start, let duration, _):
            return "\(Int(duration / 60)) min · \(start.formatted(.dateTime.hour().minute()))"
        case .mindfulness(_, let start, let duration):
            return "\(Int(duration / 60)) min · \(start.formatted(.dateTime.hour().minute()))"
        case .food(_, let time, _, _):
            return time.formatted(.dateTime.hour().minute())
        }
    }
}

// MARK: - Edit food screen

struct EditFoodScreen: View {
    let foodId: UUID
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var description: String
    @State private var timestamp: Date

    init(foodId: UUID, initialDescription: String, initialTimestamp: Date, onSaved: @escaping () -> Void) {
        self.foodId = foodId
        self.onSaved = onSaved
        _description = State(initialValue: initialDescription)
        _timestamp = State(initialValue: initialTimestamp)
    }

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
            }

            Section(header: Text("When")) {
                DatePicker("Date & time", selection: $timestamp, in: ...Date.now,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
        }
        .navigationTitle("Edit food entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = foodId
        let descriptor = FetchDescriptor<FoodEvent>(predicate: #Predicate { $0.id == id })
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        record.userDescription = trimmed
        record.timestamp = timestamp
        record.attributes = FoodAttribute.detect(in: trimmed)
        onSaved()
    }
}
