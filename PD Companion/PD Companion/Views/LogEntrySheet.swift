import SwiftUI
import SwiftData

// MARK: - Entry point: category menu

struct LogEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// The day currently shown on the Review screen — a new entry defaults to this
    /// date (at the current time of day) instead of always today.
    let defaultDate: Date
    let onLogged: (Date) -> Void

    enum Destination: Hashable { case food, mindfulness }
    @State private var path: [Destination] = []
    @State private var showMedInfo = false
    @State private var showVoice = false

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
                menuRow(
                    icon: "figure.mind.and.body", iconBg: Color.cyan.opacity(0.15), iconColor: .cyan,
                    title: "Mindfulness", subtitle: "A meditation or breathing session"
                ) { path.append(.mindfulness) }
            }
            .listStyle(.insetGrouped)
            .alert("Logging your medications", isPresented: $showMedInfo) {
                Button("Open Apple Health") { openMedications() }
                Button("Not now", role: .cancel) { }
            } message: {
                Text("🔍 → Medications")
            }
            .safeAreaInset(edge: .bottom) { voiceButton }
            .sheet(isPresented: $showVoice) {
                VoiceLogView(defaultDate: defaultDate) { date in
                    onLogged(date); dismiss()
                }
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
                    LogFoodScreen(defaultDate: defaultDate) { date in onLogged(date); dismiss() }
                case .mindfulness:
                    LogMindfulnessScreen(defaultDate: defaultDate) { date in onLogged(date); dismiss() }
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

    // The voice recorder lives right here at the bottom of the "+" screen — one tap goes
    // straight into listening (VoiceLogView auto-starts), no intermediate row. This is
    // the most capable path: Kampa transcribes and routes itself, so it logs all three
    // flows — food, medication, and mindfulness — without Siri's homophone collision.
    private var voiceButton: some View {
        Button { showVoice = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 6, y: 2)
                Text("Tap to log by voice")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("Food, medication, or mindfulness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.thinMaterial)
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
    @State private var timestamp: Date

    init(defaultDate: Date, onSaved: @escaping (Date) -> Void) {
        self.onSaved = onSaved
        // Default to the viewed day at the current time of day, never in the future
        // (the picker's range is ...now). Logging on a past day no longer silently
        // records it as today.
        let now = Date.now
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: now)
        let onViewedDay = cal.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0,
                                   second: 0, of: defaultDate) ?? defaultDate
        _timestamp = State(initialValue: min(onViewedDay, now))
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
                    let attrs = FoodAttributeClassifier.shared.classify(trimmed)
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

// MARK: - Log mindfulness screen
//
// Mirrors Apple Health's "Mindful Minutes" Add-Data screen — a Starts and an Ends
// row (each a date + time) — so the from/to experience matches what users already
// know. Unlike Medication (Apple's Medications API isn't app-writable, so that row
// deep-links to Health), mindful sessions ARE app-writable, so Kampa writes the
// session itself; it then appears in both Kampa and Apple Health's Mindful Minutes.

struct LogMindfulnessScreen: View {
    @EnvironmentObject var healthKit: HealthKitManager
    let onSaved: (Date) -> Void

    @State private var starts: Date
    @State private var ends: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(defaultDate: Date, onSaved: @escaping (Date) -> Void) {
        self.onSaved = onSaved
        // Anchor to the viewed day at the current time of day (never the future),
        // matching LogFoodScreen; default to a 1-hour session the user can adjust.
        let now = Date.now
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: now)
        let onViewedDay = cal.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0,
                                   second: 0, of: defaultDate) ?? defaultDate
        let end = min(onViewedDay, now)
        _ends = State(initialValue: end)
        _starts = State(initialValue: end.addingTimeInterval(-3600))
    }

    private var durationValid: Bool { ends > starts }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 30))
                        .foregroundStyle(.cyan)
                        .frame(width: 64, height: 64)
                        .background(Color.cyan.opacity(0.12), in: Circle())
                    Text("Mindful Minutes")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                DatePicker("Starts", selection: $starts, in: ...Date.now,
                           displayedComponents: [.date, .hourAndMinute])
                DatePicker("Ends", selection: $ends, in: ...Date.now,
                           displayedComponents: [.date, .hourAndMinute])
            } footer: {
                if !durationValid {
                    Text("End time must be after the start time.")
                        .foregroundStyle(.orange)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .navigationTitle("Log mindfulness")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!durationValid || isSaving)
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await healthKit.writeMindfulSession(
                    start: starts,
                    duration: ends.timeIntervalSince(starts)
                )
                // Mindful sessions are read from HealthKit (not SwiftData), so refresh
                // the logged day explicitly — logging on the already-viewed day won't
                // otherwise re-trigger the day's fetch.
                await healthKit.fetchDayInReview(for: Calendar.current.startOfDay(for: starts))
                onSaved(starts)
            } catch {
                errorMessage = "Could not save: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

