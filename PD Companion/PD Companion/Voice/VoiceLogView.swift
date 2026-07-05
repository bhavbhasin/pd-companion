import SwiftUI
import SwiftData

/// The in-app "+" voice logger — the reliable, richer-context alternative to Siri.
/// You speak one natural sentence ("took my Sinemet at 9", "5 almonds and chai",
/// "20 minute breathing session"); Kampa transcribes it on-device, classifies the
/// type itself, and shows a draft you confirm before anything is written. No Siri
/// arbitration means medication and mindfulness never get crossed here.
///
/// Scaffold scope: Food and Mindfulness commit directly (Kampa owns those stores).
/// Medication hands off to Apple Health's Medications screen, exactly as the typed
/// "+" flow does, because Apple's Medications API is read-only. Capturing the spoken
/// dose *context* as a Kampa annotation is a deliberate follow-up, flagged below.
struct VoiceLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKit: HealthKitManager
    @StateObject private var speech = SpeechTranscriber()

    let defaultDate: Date
    let onLogged: (Date) -> Void

    /// Captured when recording stops, so the preview is stable while the user reviews it.
    /// Holds the detected *type* and the parsed seed values; the editable fields below
    /// are what actually get committed, so the user can correct anything the parse got
    /// wrong (content, date, time, length) before saving.
    @State private var draft: VoiceLogDraft?
    @State private var editedText = ""
    @State private var editedDate = Date.now
    /// Editable mindfulness length — seeded from the spoken duration, or a sensible
    /// default the user can adjust (never silently committed as the spoken value).
    @State private var mindfulnessMinutes = 10
    /// Editable GI symptom + severity — seeded from the parse, corrected before saving.
    @State private var giSymptom: GISymptom = .constipation
    @State private var giSeverity: GISeverity = .present
    @State private var committing = false
    @State private var commitError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let draft, !speech.isRecording {
                    draftForm(draft)        // review + edit (Form handles the keyboard)
                } else {
                    recordingView           // transcript + mic
                }
            }
            .navigationTitle("Speak to log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { speech.stop(); dismiss() }
                }
                if let draft, !speech.isRecording {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(draft.type == .medication ? "Open Health" : "Log it") {
                            commit(draft)
                        }
                        .fontWeight(.semibold)
                        .disabled(committing || (draft.type == .food
                            && editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    }
                }
            }
            .onChange(of: speech.isRecording) { _, recording in
                // Build the draft the moment recording stops, then seed the editable
                // fields from it so the user can correct anything before committing.
                if !recording {
                    let d = VoiceLogDraft(transcript: speech.transcript, defaultDate: defaultDate)
                    draft = d
                    if let d {
                        editedText = d.description
                        editedDate = d.when
                        if d.type == .mindfulness { mindfulnessMinutes = d.durationMinutes ?? 10 }
                        if d.type == .symptom {
                            giSymptom = d.giSymptom ?? .constipation
                            giSeverity = d.giSeverity
                        }
                    }
                }
            }
            // Start listening as soon as the recorder opens — the user already tapped the
            // mic to get here, so don't make them tap a second time.
            .task { await speech.start() }
        }
    }

    // MARK: - Recording mode

    private var recordingView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            transcriptArea
            Spacer()
            if let message = speech.errorMessage {
                Text(message)
                    .font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            micButton.padding(.bottom, 32)
        }
        .padding()
    }

    private var transcriptArea: some View {
        VStack(spacing: 6) {
            if speech.isRecording {
                Text("Listening…").font(.headline).foregroundStyle(.secondary)
            }
            Text(speech.transcript.isEmpty
                 ? "Tap the mic and say what you want to log."
                 : speech.transcript)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(speech.transcript.isEmpty ? .tertiary : .primary)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
    }

    private var micButton: some View {
        Button {
            if speech.isRecording {
                speech.stop()
            } else {
                draft = nil
                commitError = nil
                Task { await speech.start() }
            }
        } label: {
            Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(speech.isRecording ? Color.red : Color.accentColor, in: Circle())
                .shadow(radius: speech.isRecording ? 8 : 2)
        }
        .accessibilityLabel(speech.isRecording ? "Stop recording" : "Start recording")
    }

    // MARK: - Draft review + edit

    private func draftForm(_ draft: VoiceLogDraft) -> some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: icon(for: draft.type))
                        .foregroundStyle(color(for: draft.type))
                    Text(label(for: draft.type)).font(.headline)
                }
            }

            switch draft.type {
            case .medication:
                Section {
                    Text("Doses are recorded in Apple Health — Kampa will open it for you.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

            case .food:
                Section("What you logged") {
                    // Plain (non-vertical) field + autocapitalization off so food words
                    // like "blueberries" aren't fought by autocorrect/capitalization.
                    TextField("Description", text: $editedText)
                        .textInputAutocapitalization(.never)
                }
                Section("When") {
                    DatePicker("Date & time", selection: $editedDate, in: ...Date.now,
                               displayedComponents: [.date, .hourAndMinute])
                }

            case .mindfulness:
                // No description field — a mindful session stores only start + length in
                // HealthKit, so the spoken sentence has nowhere to go and is just noise.
                Section("When") {
                    DatePicker("Date & time", selection: $editedDate, in: ...Date.now,
                               displayedComponents: [.date, .hourAndMinute])
                }
                Section("Length") {
                    Stepper("\(mindfulnessMinutes) min",
                            value: $mindfulnessMinutes, in: 1...240)
                }

            case .symptom:
                // Editable so a misparse (wrong symptom, or a food sentence that tripped the
                // classifier) is corrected before anything is written to Apple Health.
                Section("Symptom") {
                    Picker("Symptom", selection: $giSymptom) {
                        ForEach(GISymptom.allCases) { s in
                            Label(s.displayName, systemImage: s.iconName).tag(s)
                        }
                    }
                }
                Section("Severity") {
                    Picker("Severity", selection: $giSeverity) {
                        ForEach(GISeverity.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("When") {
                    DatePicker("Date & time", selection: $editedDate, in: ...Date.now,
                               displayedComponents: [.date, .hourAndMinute])
                }
            }

            if let commitError {
                Section { Text(commitError).font(.callout).foregroundStyle(.red) }
            }

            Section {
                Button { reRecord() } label: {
                    Label("Re-record", systemImage: "mic.fill")
                }
            }
        }
    }

    private func reRecord() {
        draft = nil
        commitError = nil
        Task { await speech.start() }
    }

    // MARK: - Commit

    private func commit(_ draft: VoiceLogDraft) {
        committing = true
        commitError = nil
        let text = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.type {
        case .food:
            let attributes = FoodAttributeClassifier.shared.classify(text)
            modelContext.insert(FoodEvent(timestamp: editedDate,
                                          userDescription: text,
                                          attributes: attributes))
            onLogged(editedDate)
            dismiss()

        case .mindfulness:
            // The picker holds the session START. Clamp so a session can't extend past
            // now (e.g. start = now with a 10-min length → pull the start back instead).
            let duration = Double(mindfulnessMinutes) * 60
            var start = editedDate
            if start.addingTimeInterval(duration) > .now {
                start = Date.now.addingTimeInterval(-duration)
            }
            Task {
                do {
                    try await healthKit.writeMindfulSession(start: start, duration: duration)
                    await healthKit.fetchDayInReview(for: Calendar.current.startOfDay(for: start))
                    onLogged(start)
                    dismiss()
                } catch {
                    commitError = "Couldn't save to Apple Health: \(error.localizedDescription)"
                    committing = false
                }
            }

        case .symptom:
            let symptom = giSymptom
            let severity = giSeverity
            let when = editedDate
            Task {
                do {
                    try await healthKit.writeGISymptom(symptom, severity: severity, at: when)
                    await healthKit.fetchDayInReview(for: Calendar.current.startOfDay(for: when))
                    onLogged(when)
                    dismiss()
                } catch {
                    commitError = "Couldn't save to Apple Health: \(error.localizedDescription)"
                    committing = false
                }
            }

        case .medication:
            // TODO: Apple Health is system-of-record for the dose itself, but the spoken
            // context ("took it late, feeling stiff") is exactly what makes voice richer
            // than a tap — store it as a Kampa annotation the correlation engine reads,
            // pending the system-of-record decision. For now, hand off like the typed flow.
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

    // MARK: - Type presentation

    private func icon(for type: VoiceLogType) -> String {
        switch type {
        case .food: "fork.knife"
        case .medication: "pills.fill"
        case .mindfulness: "brain.head.profile"
        case .symptom: GISymptom.timelineSymbol
        }
    }

    private func color(for type: VoiceLogType) -> Color {
        switch type {
        case .food: .brown
        case .medication: .pink
        case .mindfulness: .cyan
        case .symptom: GISymptom.tint
        }
    }

    private func label(for type: VoiceLogType) -> String {
        switch type {
        case .food: "Food"
        case .medication: "Medication"
        case .mindfulness: "Mindfulness"
        case .symptom: "Symptom"
        }
    }
}
