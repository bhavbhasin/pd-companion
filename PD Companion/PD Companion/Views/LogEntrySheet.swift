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

    enum Destination: Hashable { case food, mindfulness, symptom, therapy }
    @State private var path: [Destination] = []
    @State private var showMedInfo = false
    @State private var showVoice = false
    /// ⚠️ Movement check is a `.fullScreenCover`, not a pushed `Destination` — deliberately,
    /// after a device-found data-integrity bug. A `.sheet` (which this whole screen is)
    /// carries a system interactive-dismiss drag gesture, and a tremor-affected fast tap
    /// includes a little unintended drag; that drag was winning gesture arbitration against
    /// the tap target often enough to lose real taps — on a tremor-affected hand specifically,
    /// which is exactly the hand this feature exists to measure honestly. A full-screen cover
    /// has no drag-to-dismiss gesture at all, so there is nothing left to compete with the tap.
    @State private var showMovementCheck = false
    /// Same full-screen-cover reasoning as tapping: a measurement screen is the root of its own
    /// stack, not a page inside this sheet.
    @State private var showRotation = false

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
                menuRow(
                    icon: GISymptom.timelineSymbol, iconBg: GISymptom.tint.opacity(0.15), iconColor: GISymptom.tint,
                    title: "Symptoms", subtitle: "Bowel, mood, etc."
                ) { path.append(.symptom) }
                // "Therapy", never "Custom" — see docs/design/therapy-logging.md. "Custom" is an
                // empty box that fills with naps, travel and arguments, which makes Kampa a general
                // life-event logger and gives an engine nothing repeatable to work on. It is also a
                // developer's word: nobody thinks "I am logging a custom."
                menuRow(
                    icon: TherapyStyle.timelineSymbol, iconBg: TherapyStyle.tint.opacity(0.15),
                    iconColor: TherapyStyle.tint,
                    // One line, deliberately. "bodywork" dropped so the subtitle never wraps —
                    // the examples are a hint at the category, not an inventory of it.
                    title: "Therapy", subtitle: "Acupuncture, PEMF, etc."
                ) { path.append(.therapy) }
                // ⭐ The category became a real SECTION the moment a second instrument existed.
                // "Movement check", never "Test" — a test implies a grade and invites "did I
                // pass?", which these surfaces must never answer. See
                // docs/design/movement-checks.md.
                //
                // ⚠️ This Section belongs INSIDE the List. Closing the List before it made the
                // Section a SIBLING of the list inside the NavigationStack, so the sheet rendered
                // three separate views, each one picking up the navigation title, the Cancel
                // toolbar item and the voice-button safe-area inset — three Cancels and three
                // microphones on one screen.
                //
                // ⛔ Deliberately two rows under a header rather than a chooser screen: each test
                // has to open as the ROOT of its own full-screen cover. That is what removes the
                // sheet's drag-to-dismiss gesture (which was silently eating taps on the
                // tremor-affected hand) and what makes each screen's single explicit "Cancel"
                // correct. Pushing them inside a chooser would hand both back a second exit.
                Section("Movement check") {
                    menuRow(
                        icon: MovementCheckStyle.timelineSymbol,
                        iconBg: MovementCheckStyle.tint.opacity(0.15),
                        iconColor: MovementCheckStyle.tint,
                        title: "Tapping", subtitle: "Alternating taps, both hands"
                    ) { showMovementCheck = true }
                    menuRow(
                        icon: RotationStyle.timelineSymbol,
                        iconBg: RotationStyle.tint.opacity(0.15),
                        iconColor: RotationStyle.tint,
                        title: "Rotation", subtitle: "Turning your hand over, both hands"
                    ) { showRotation = true }
                }
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
            .fullScreenCover(isPresented: $showMovementCheck) {
                NavigationStack {
                    LogMovementCheckScreen { date in
                        showMovementCheck = false
                        onLogged(date)
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showRotation) {
                NavigationStack {
                    LogRotationScreen { date in
                        showRotation = false
                        onLogged(date)
                        dismiss()
                    }
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
                case .symptom:
                    LogSymptomScreen(defaultDate: defaultDate) { date in onLogged(date); dismiss() }
                case .therapy:
                    LogTherapyScreen(defaultDate: defaultDate) { date in onLogged(date); dismiss() }
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
                // ⛔ The "Food, medication, mindfulness, or a symptom" subline was DELETED
                // Aug 5 2026. "Tap to log by voice" already says what the button does, and the
                // list was an inventory nobody needs to read before speaking — it was also
                // drifting out of date (it named medication, and never named therapy).
                Text("Tap to log by voice")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        // ⛔ No `.thinMaterial` behind this. It drew a visible grey slab across the bottom of
        // the sheet, and there is nothing for it to separate — the list ends well above the
        // button and never scrolls under it. Removing it is theme-safe in both directions:
        // the material was the only thing tinting this strip, so light and dark now both show
        // the sheet's own background.
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
    @State private var showingScanner = false
    // Set when a barcode scan resolved a product: the exact name we filled in, and the
    // corpus-derived attributes. Save prefers these over re-classifying the text — but
    // only while the description is still the scanned name (editing it reverts to the
    // text classifier, since the user is now describing a different food).
    @State private var scannedName: String?
    @State private var scannedAttributes: [FoodAttribute]?
    @State private var scanMissMessage: String?

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
                Button {
                    scanMissMessage = nil
                    showingScanner = true
                } label: {
                    Label("Scan a package barcode", systemImage: "barcode.viewfinder")
                }
                if let scanMissMessage {
                    Text(scanMissMessage).font(.caption).foregroundStyle(.secondary)
                } else if let note = scanResultNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Describe it, or scan a package. We'll estimate protein, fiber, and sugar for you later.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
        .sheet(isPresented: $showingScanner) {
            BarcodeScannerView { code in handleScan(code) }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Barcode attributes win while the text is still the scanned name;
                    // once the user edits it, fall back to the free-text classifier.
                    let attrs: [FoodAttribute]
                    if trimmed == scannedName, let scanned = scannedAttributes {
                        attrs = scanned
                    } else {
                        attrs = FoodAttributeClassifier.shared.classify(trimmed)
                    }
                    let event = FoodEvent(timestamp: timestamp, userDescription: trimmed, attributes: attrs)
                    modelContext.insert(event)
                    onSaved(timestamp)
                }
                .fontWeight(.semibold)
                .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // A logged barcode resolves the product name into the description + its corpus
    // attributes; a miss leaves a quiet note and the user types it instead.
    private func handleScan(_ code: String) {
        if let product = BarcodeCorpus.shared.product(forScanned: code) {
            description = product.name
            scannedName = product.name
            scannedAttributes = BarcodeCorpus.shared.attributes(product)
            scanMissMessage = nil
        } else {
            scanMissMessage = "Barcode not recognized - describe it instead."
        }
    }

    // The "what we'll record" line, shown only while the description still matches the
    // scanned product (an edit reverts to text classification, so the note clears).
    private var scanResultNote: String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scannedName, trimmed == scannedName, let attrs = scannedAttributes else { return nil }
        guard !attrs.isEmpty else {
            return "Scanned. No notable protein, sugar, fiber, fat, or caffeine."
        }
        return "Scanned - recording: \(attrs.map(\.displayName).joined(separator: ", "))."
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

// MARK: - Log therapy screen
//
// Sessions the user is trying: ozone, PEMF, TPS, acupuncture, bodywork. Kampa records them
// and says nothing about whether they worked — see docs/design/therapy-logging.md for why
// that silence is the feature and not a gap.
//
// No HealthKit type exists for any of this, so unlike mindfulness there is nothing to write
// out to Health; the session lives in Kampa's own store and is always the user's to edit.

struct LogTherapyScreen: View {
    @Environment(\.modelContext) private var modelContext
    /// The catalog, not the history: logging is a PICK. Archived therapies are filtered out
    /// below rather than in the query, so restoring one takes effect without a refetch.
    @Query(sort: \Therapy.name) private var catalog: [Therapy]
    let onSaved: (Date) -> Void

    @State private var selected: Therapy?
    @State private var starts: Date
    @State private var ends: Date
    /// Until the user touches the end time, it follows the start and keeps the 30-minute
    /// default. Once they set it deliberately, moving the start must not overwrite their number.
    @State private var endEdited = false
    @State private var showingAdd = false
    @State private var showingManage = false

    init(defaultDate: Date, onSaved: @escaping (Date) -> Void) {
        self.onSaved = onSaved
        // Anchor to the viewed day at the current time of day, never the future — same rule
        // as food, mindfulness and symptoms.
        let now = Date.now
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: now)
        let onViewedDay = cal.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0,
                                   second: 0, of: defaultDate) ?? defaultDate
        let start = min(onViewedDay, now)
        _starts = State(initialValue: start)
        _ends = State(initialValue: start.addingTimeInterval(TherapyStyle.defaultDuration))
    }

    private var active: [Therapy] { catalog.filter { !$0.isArchived } }

    private var canSave: Bool { selected != nil && ends >= starts }

    var body: some View {
        Form {
            Section {
                if active.isEmpty {
                    Text("No therapies yet. Add the first one below.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(active) { therapy in chip(therapy) }
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    showingAdd = true
                } label: {
                    Label("Add a therapy", systemImage: "plus.circle")
                }
                // The ONE entry point to the catalog, and it is here rather than in Settings:
                // this is where the user already is when they notice a name is wrong.
                Button {
                    showingManage = true
                } label: {
                    Label("Edit my therapies", systemImage: "slider.horizontal.3")
                }
            } header: {
                Text("Which therapy?")
            }

            // ⛔ No explanatory footers here. The prefilled end time explains itself — the two
            // pickers are on screen showing 2:57 and 3:30 — and "Edit my therapies" says what it
            // does. Permanent copy on a screen the user sees every week has to earn its place;
            // only the error state does. The engine's no-verdict rule is enforced in the ENGINE
            // (`docs/design/therapy-logging.md`), not by a disclaimer the user reads every time.
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
        // The end follows the start until the user takes ownership of it.
        .onChange(of: starts) { _, newStart in
            guard !endEdited else { return }
            ends = newStart.addingTimeInterval(TherapyStyle.defaultDuration)
        }
        .onChange(of: ends) { _, new in
            // Ignore the programmatic move above; only a user edit counts.
            if abs(new.timeIntervalSince(starts) - TherapyStyle.defaultDuration) > 1 { endEdited = true }
        }
        // Selecting the therapy the user just created saves them a second tap, and makes the
        // add-then-log path read as one action.
        .sheet(isPresented: $showingAdd) {
            AddTherapySheet(existing: catalog) { created in selected = created }
        }
        .sheet(isPresented: $showingManage) {
            TherapyManagementScreen()
        }
        // A therapy archived or removed while managing must not stay selected underneath —
        // Save would then log a session against something no longer in the list.
        .onChange(of: showingManage) { _, isShowing in
            guard !isShowing, let current = selected else { return }
            if current.isArchived || !catalog.contains(where: { $0.id == current.id }) {
                selected = nil
            }
        }
        .navigationTitle("Log therapy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
    }

    private func chip(_ therapy: Therapy) -> some View {
        let isSelected = selected?.id == therapy.id
        return Button { selected = therapy } label: {
            Text(therapy.name)
                .font(.subheadline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 8).padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(isSelected ? TherapyStyle.tint.opacity(0.18) : Color.secondary.opacity(0.12),
                            in: Capsule())
                .foregroundStyle(isSelected ? TherapyStyle.tint : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func save() {
        guard let selected else { return }
        let session = TherapySession(therapy: selected, start: starts, end: ends)
        modelContext.insert(session)
        // Commit explicitly, matching the food path: the day's @Query observes the save, so the
        // timeline shows the new marker without waiting on autosave timing.
        try? modelContext.save()
        onSaved(starts)
    }
}

/// Adding a therapy to the catalog. Shared by the log flow and the maintenance screen so the
/// duplicate check lives in exactly one place.
struct AddTherapySheet: View {
    let existing: [Therapy]
    let onCreated: (Therapy) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var match: Therapy? { TherapyStyle.match(trimmed, in: existing) }
    /// Only an ACTIVE match blocks. An archived one is offered back instead — see `match`.
    private var blocked: Bool { match.map { !$0.isArchived } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Acupuncture", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } footer: {
                    if let match, match.isArchived {
                        // Names the stored spelling, so restoring "Pemf" after typing "PEMF"
                        // isn't a surprise.
                        Text("You archived a therapy called \"\(match.name)\". Restore it and keep its \(match.sessionCount) logged \(match.sessionCount == 1 ? "session" : "sessions").")
                    } else if blocked {
                        Text("You already have a therapy with this name.")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("New therapy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(match?.isArchived == true ? "Restore" : "Add") { add() }
                        .fontWeight(.semibold)
                        .disabled(trimmed.isEmpty || blocked)
                }
            }
        }
    }

    private func add() {
        // Restoring keeps the therapy's OWN spelling rather than adopting what was just typed:
        // it is the same therapy with the same history, and silently renaming it on the way back
        // would be a change the user didn't ask for. Rename is one tap away if they want it.
        if let match, match.isArchived {
            match.isArchived = false
            try? modelContext.save()
            onCreated(match)
            dismiss()
            return
        }
        let therapy = Therapy(name: trimmed)
        modelContext.insert(therapy)
        try? modelContext.save()
        onCreated(therapy)
        dismiss()
    }
}

// MARK: - Symptom value controls
//
// Shared by the "+" screen and the voice confirm screen so the two stay identical.

/// The large glyph above the value picker. It changes with the selection — colour and size for
/// a graded symptom, thumb up/down for a presence-only one — so the screen responds as you
/// choose. The labelled control below it stays the precise part; this is the felt part.
struct SymptomHeroSymbol: View {
    let symptom: GISymptom
    let severity: GISeverity

    var body: some View {
        Image(systemName: symptom.heroSymbol(for: severity))
            .font(.system(size: severity.symbolSize))
            .foregroundStyle(severity.valueColor)
            .symbolRenderingMode(.hierarchical)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentTransition(.symbolEffect(.replace))
            .animation(.snappy(duration: 0.25), value: severity)
            .accessibilityHidden(true)   // the picker below already announces the value
    }
}

/// Two thumbs for the presence-only symptoms. Deliberately not a segmented picker: a segmented
/// control renders its contents as template images and would strip the green/amber, and two big
/// buttons are an easier target than two narrow segments.
struct ThumbPicker: View {
    let symptom: GISymptom
    @Binding var severity: GISeverity

    var body: some View {
        HStack(spacing: 10) {
            ForEach(symptom.valueOptions) { option in
                let selected = option == severity
                Button {
                    severity = option
                } label: {
                    Label(option.thumbCaption, systemImage: option.thumbSymbol)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? option.valueColor : Color.secondary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(selected ? option.valueColor.opacity(0.16)
                                             : Color.secondary.opacity(0.12),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.thumbCaption)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
        .animation(.snappy(duration: 0.2), value: severity)
    }
}

// MARK: - Log GI symptom screen
//
// Curated GI chips (not Apple Health's giant alphabetical symptom list) → severity →
// time → Save. Writes an HKCategorySample, same close-loop pattern as mindfulness. We
// log the problem; a normal bowel movement is the silent baseline (no HealthKit type,
// and it adds nothing to the levodopa-absorption correlation).

struct LogSymptomScreen: View {
    @EnvironmentObject var healthKit: HealthKitManager
    let onSaved: (Date) -> Void

    @State private var symptom: GISymptom = .constipation
    @State private var severity: GISeverity = .mild
    @State private var when: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(defaultDate: Date, onSaved: @escaping (Date) -> Void) {
        self.onSaved = onSaved
        let now = Date.now
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: now)
        let onViewedDay = cal.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0,
                                   second: 0, of: defaultDate) ?? defaultDate
        _when = State(initialValue: min(onViewedDay, now))
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    /// Mood is the one symptom worth logging on a good day, so its footnote can't repeat the
    /// "a normal day needs no entry" rule the graded symptoms follow. Kept short deliberately:
    /// this is permanent copy on a screen the user sees every time, not a place to teach.
    private var footnote: String {
        symptom.isSeverityGraded
            ? "Saved to Apple Health. Log a symptom when it's present - a normal day needs no entry."
            : "Saved to Apple Health. You can log multiple times a day."
    }

    var body: some View {
        Form {
            Section("Symptom") {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(GISymptom.loggable) { chip($0) }
                }
                .padding(.vertical, 4)
            }
            // Presence-only symptoms (see GISymptom.isSeverityGraded) have no grades in Apple
            // Health, so offering Mild/Moderate/Severe would promise a distinction the stored
            // sample cannot carry. They get the two thumbs instead.
            if symptom.isSeverityGraded {
                Section("Severity") {
                    SymptomHeroSymbol(symptom: symptom, severity: severity)
                    Picker("Severity", selection: $severity) {
                        ForEach(symptom.valueOptions) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } else {
                Section("How is it?") {
                    SymptomHeroSymbol(symptom: symptom, severity: severity)
                    ThumbPicker(symptom: symptom, severity: $severity)
                }
            }
            Section("When") {
                DatePicker("Date & time", selection: $when, in: ...Date.now,
                           displayedComponents: [.date, .hourAndMinute])
            }
            Section {
                Text(footnote)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.caption) }
            }
        }
        // The two pickers don't share a value set, so carry the selection across a symptom
        // switch instead of leaving a grade selected on a faces picker (or vice versa).
        .onChange(of: symptom) { _, new in
            severity = new.validValue(severity)
        }
        .navigationTitle("Log symptom")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.fontWeight(.semibold).disabled(isSaving)
            }
        }
    }

    private func chip(_ s: GISymptom) -> some View {
        let selected = s == symptom
        return Button { symptom = s } label: {
            Label(s.displayName, systemImage: s.iconName)
                .font(.subheadline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 8).padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(selected ? GISymptom.tint.opacity(0.18) : Color.secondary.opacity(0.12),
                            in: Capsule())
                .foregroundStyle(selected ? GISymptom.tint : .primary)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await healthKit.writeGISymptom(symptom, severity: severity, at: when)
                await healthKit.fetchDayInReview(for: Calendar.current.startOfDay(for: when))
                onSaved(when)
            } catch {
                errorMessage = "Could not save: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

