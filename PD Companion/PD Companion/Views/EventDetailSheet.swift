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
    @State private var deleteError: String?

    /// Food is the one detail with extra content and an edit-screen push, so its actions
    /// pin to the bottom of the sheet; every other event hugs its content.
    private var isFood: Bool { if case .food = event { true } else { false } }

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
                } else if case .mindfulness(_, _, _, let isEditable, _) = event, !isEditable {
                    healthAppNote
                } else if case .giSymptom(_, _, _, _, let isEditable) = event, !isEditable {
                    healthAppNote
                }

                // Food pins its actions to the bottom of the sheet; every other event keeps
                // its actions directly under the content they act on, with the remaining
                // sheet height left empty below.
                if isFood { Spacer() }

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
                    } else if case .mindfulness(_, _, _, let isEditable, _) = event, isEditable {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete entry", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    } else if case .giSymptom(_, _, _, _, let isEditable) = event, isEditable {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete entry", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    } else if case .therapy = event {
                        // No isEditable check: there is no HealthKit type for therapy, so Kampa
                        // authored every session and all of them are the user's to change.
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
                } else if case .therapy(let id, let start, let duration, _) = event {
                    EditTherapyScreen(
                        sessionId: id,
                        initialStart: start,
                        initialEnd: start.addingTimeInterval(duration),
                        onSaved: { dismiss() }
                    )
                }
            }
        }
        // Was: a content-fitted detent driven by .onGeometryChange. That measurement was
        // attached to the NavigationStack's content, which fills the sheet, which is exactly
        // `fittedHeight` tall - so it resolved to `fittedHeight = fittedHeight` and stayed
        // pinned at its 260 seed forever. Medication and workout details, which are taller
        // than 260, clipped with no way to reach the rest.
        //
        // A correct self-sizing sheet needs the content measured outside the detent's own
        // constraint; `.medium` plus a `.large` the user can drag to costs a little dead
        // space on the shortest sheets and cannot truncate anything.
        .presentationDetents(isFood ? [.medium] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Delete entry?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Delete failed", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
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
                // Commit explicitly for parity with edit; don't leave the removal to
                // autosave timing.
                try? modelContext.save()
            }
            dismiss()

        case .mindfulness(let id, _, _, _, _):
            // id IS the HealthKit sample UUID (set in fetchMindfulnessSessionsInRange),
            // so we delete the exact sample rather than reconstructing its timestamps.
            Task {
                do {
                    try await healthKit.deleteMindfulSession(uuid: id)
                    // Optimistically drop it from the published events so the timeline
                    // updates immediately, independent of HealthKit read-back timing.
                    await MainActor.run {
                        healthKit.dayEvents.removeAll { $0.id == id }
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        isDeleting = false
                        deleteError = "Couldn't delete this session: \(error.localizedDescription)"
                    }
                }
            }

        case .therapy(let id, _, _, _):
            let therapyId = id
            let descriptor = FetchDescriptor<TherapySession>(predicate: #Predicate { $0.id == therapyId })
            if let record = try? modelContext.fetch(descriptor).first {
                modelContext.delete(record)
                try? modelContext.save()
            }
            dismiss()

        case .giSymptom(let id, _, let symptom, _, _):
            // id IS the HealthKit sample UUID (set in fetchGISymptomsInRange).
            Task {
                do {
                    try await healthKit.deleteGISymptom(symptom, uuid: id)
                    await MainActor.run {
                        healthKit.dayEvents.removeAll { $0.id == id }
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        isDeleting = false
                        deleteError = "Couldn't delete this symptom: \(error.localizedDescription)"
                    }
                }
            }

        default:
            dismiss()
        }
    }

    private var categoryLabel: String {
        switch event {
        case .medication:  return "Medication"
        case .workout:     return "Workout"
        case .mindfulness: return "Mindfulness"
        case .food:        return "Food"
        case .giSymptom:   return "Symptom"
        case .therapy:     return "Therapy"
        }
    }

    private var primaryTitle: String { event.label }

    private var detailLine: String {
        switch event {
        case .medication(_, let time, _):
            return "Taken at \(time.formatted(.dateTime.hour().minute()))"
        case .workout(_, let start, let duration, _):
            return "\(Int(duration / 60)) min · \(start.formatted(.dateTime.hour().minute()))"
        case .mindfulness(_, let start, let duration, let isEditable, let source):
            let base = "\(Int(duration / 60)) min · \(start.formatted(.dateTime.hour().minute()))"
            // Kampa-authored sessions (isEditable) omit the source — "Kampa · …" is noise.
            // Third-party sessions name the source so a passive device (Apollo, Oura…)
            // reads as what it is rather than an unexplained marker.
            return isEditable || source.isEmpty ? base : "\(source) · \(base)"
        case .food(_, let time, _, _):
            return time.formatted(.dateTime.hour().minute())
        case .giSymptom(_, let time, _, _, _):
            return "Logged at \(time.formatted(.dateTime.hour().minute()))"
        case .therapy(_, let start, let duration, _):
            return "\(Int(duration / 60)) min · \(start.formatted(.dateTime.hour().minute()))"
        }
    }
}

// MARK: - Edit therapy screen

/// Editing one SESSION: which therapy it was, and when. ⛔ Not where a therapy is renamed —
/// that is `Edit my therapies`, and it deliberately applies to the whole history. Offering a
/// free-text name here would recreate the per-session-name defect the catalog removed.
struct EditTherapyScreen: View {
    let sessionId: UUID
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Therapy.name) private var catalog: [Therapy]
    @State private var selected: Therapy?
    @State private var starts: Date
    @State private var ends: Date

    init(sessionId: UUID, initialStart: Date, initialEnd: Date,
         onSaved: @escaping () -> Void) {
        self.sessionId = sessionId
        self.onSaved = onSaved
        _starts = State(initialValue: initialStart)
        _ends = State(initialValue: initialEnd)
    }

    /// An archived therapy still appears here when it is the one this session used — otherwise
    /// editing the time of an old session would silently reassign it to something else.
    private var choices: [Therapy] {
        catalog.filter { !$0.isArchived || $0.id == selected?.id }
    }

    var body: some View {
        Form {
            Section("Therapy") {
                Picker("Therapy", selection: $selected) {
                    ForEach(choices) { therapy in
                        Text(therapy.name).tag(Optional(therapy))
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }
            Section {
                DatePicker("Starts", selection: $starts, in: ...Date.now,
                           displayedComponents: [.date, .hourAndMinute])
                DatePicker("Ends", selection: $ends, in: starts...,
                           displayedComponents: [.date, .hourAndMinute])
            } footer: {
                if ends < starts {
                    Text("End time must be after the start time.").foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Edit session")
        .navigationBarTitleDisplayMode(.inline)
        .task { if selected == nil { selected = currentSession()?.therapy } }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(selected == nil || ends < starts)
            }
        }
    }

    private func currentSession() -> TherapySession? {
        let id = sessionId
        let descriptor = FetchDescriptor<TherapySession>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func save() {
        guard let record = currentSession(), let selected else { return }
        record.therapy = selected
        record.nameSnapshot = selected.name
        record.start = starts
        record.end = ends
        // Explicit commit for the same reason as EditFoodScreen: an in-place edit is not a
        // collection change, so autosave would leave the day's @Query on the pre-edit snapshot.
        try? modelContext.save()
        onSaved()
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
        record.attributes = FoodAttributeClassifier.shared.classify(trimmed)
        // Commit explicitly: an in-place edit isn't a collection change, so relying on
        // autosave leaves the @Query-backed timeline showing the pre-edit snapshot. The
        // save emits a didSave the day's @Query observes, so the glyph reflects the edit.
        try? modelContext.save()
        onSaved()
    }
}
