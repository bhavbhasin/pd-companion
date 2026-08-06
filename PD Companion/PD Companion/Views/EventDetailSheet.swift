import SwiftUI
import SwiftData

// MARK: - Per-dose onset + coverage, in words
//
// docs/design/dose-onset-coverage-surfaces.md. Lived in a dedicated Doses panel on Day in
// Review until Aug 5 2026; moved here because a per-dose fact belongs on the per-dose object,
// and the glyph is already sitting on the chart at the dose time. The engine side
// (`CorrelationEngine.dosePanelRows`) is unchanged — only the display moved.
//
// ⛔ No verdict, no badge, no comparison with another dose. The moment this says one dose beat
// another it is the retired afternoon-dose card again at a smaller scale.
enum DoseRowCopy {

    /// "40 min" / "2h 52m" / "3h". Minutes below an hour stay minutes: "0h 40m" reads as a
    /// precision the measurement doesn't have.
    static func dur(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }

    /// Clause 1. A missing onset is INFORMATION, not a blank — render the reason, never an
    /// em dash.
    ///
    /// ⛔ "taken while still covered" was RETIRED Aug 5 2026. Bhav killed it with the right
    /// question: *"do we really mean covered, or do we mean I'm in the ON state?"* We mean the
    /// second. "Covered" claims the previous dose was still working; the engine only knows
    /// tremor sat below threshold. Jul 11 22:44 proves the difference — baseline 0.82 read as
    /// "covered" while the previous dose was 376 min earlier and had been observed to hold
    /// 1h 3m.
    static func onsetClause(_ o: CorrelationEngine.DoseOnset) -> String {
        switch o {
        case .measured(let m):    return "on in \(dur(m))"
        case .tremorAlreadyLow:   return "tremor was already low"
        // ⛔ Was "no clear reading before it" — BACKWARDS. This state has TWO causes and that
        // copy named only one: Jul 9 11:01 had a baseline of 1.64 over 29 readings and an empty
        // POST-dose window (watch off 11:00-12:00). Names our observation, never the drug.
        case .notSeen:            return "we couldn't see it take hold"
        }
    }

    /// Clause 2. ⭐ Every censored case NAMES WHAT ENDED THE WATCHING, because the number is
    /// the length of the observation window, not a fact about the drug. A bare "coverage 1 min"
    /// next to a real "172 min" reads as a dose that failed, when all it records is that the
    /// next dose arrived a minute later.
    static func coverageClause(_ c: CorrelationEngine.DoseCoverage, endedBy: String?) -> String? {
        switch c {
        case .held(let m):
            return "held \(dur(m))"
        case .endedByNextDose(let m):
            let who = endedBy.map { "when you took \($0)" } ?? "when your next dose came"
            return "still working \(dur(m)) later, \(who)"
        case .endedBySleep(let m):
            return "watched \(dur(m)), then you slept"
        case .watchedToEnd(let m):
            return "watched \(dur(m)) without seeing it wear off"
        case .endedByLostReading(let m):
            return "watched \(dur(m)), then we lost the reading"
        case .learnedNothing, .noReading, .asleepAtDose:
            return nil
        }
    }

    /// The cases that replace the two-clause line entirely.
    static func blankSentence(_ c: CorrelationEngine.DoseCoverage) -> String? {
        switch c {
        case .learnedNothing:
            return "Your tremor was already quiet and you fell asleep soon after, so we never "
                 + "saw what it did."
        // ⛔ Never a flat "you were asleep": measured Aug 5 2026, ALL asleep-at-dose doses in the
        // record come from AutoSleep and most are contradicted by the tremor itself. Attribute
        // the claim to the RECORD, which stays true even when the record is wrong.
        case .asleepAtDose:
            return "Your sleep record says you were asleep here, so there was nothing to watch."
        case .noReading:
            return "No tremor readings around this dose, so there was nothing to watch."
        default:
            return nil
        }
    }

    /// The whole line, however it is composed.
    static func sentence(for row: CorrelationEngine.DoseRow) -> String {
        blankSentence(row.coverage)
            ?? (onsetClause(row.onset)
                + (coverageClause(row.coverage, endedBy: row.endedBy).map { " · \($0)" } ?? ""))
    }
}

struct EventDetailSheet: View {
    let event: DayEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var healthKit: HealthKitManager

    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var showEditScreen = false
    @State private var deleteError: String?
    /// nil until the engine answers, or permanently if this dose has no row (no dose record).
    @State private var doseRow: CorrelationEngine.DoseRow?
    @State private var doseRowLoaded = false

    // Trivial row count (dozens at most, never the tremor/dyskinesia scale the
    // never-@Query-for-counts rule is about) — a plain @Query is fine here.
    @Query(sort: \MovementCheckTrial.timestamp) private var allMovementChecks: [MovementCheckTrial]
    @State private var movementCheckDoses: [Dose] = []

    /// ⚠️ **Why this shows BOTH hands regardless of which glyph was tapped.** Left and right
    /// trials happen seconds apart, so on a full-day chart they sit at the same pixel — the
    /// nearest-event tap lookup (`DayInReviewView.handleTap`) can only resolve to ONE of the
    /// two, essentially arbitrarily. Rather than chase pixel-perfect disambiguation that's
    /// unsolvable at this zoom level, this shows the whole SESSION (every trial within 5
    /// minutes of whichever one was tapped) — the same "both hands together" unit the result
    /// screen already uses, so a tap into the timeline reads the same as finishing a fresh one.
    private func pairedMovementChecks(around time: Date) -> [MovementCheckTrial] {
        allMovementChecks
            .filter { abs($0.timestamp.timeIntervalSince(time)) < 5 * 60 }
            .sorted { $0.hand.rawValue < $1.hand.rawValue }   // "left" < "right"
    }

    /// Food is the one detail with extra content and an edit-screen push, so its actions
    /// pin to the bottom of the sheet; every other event hugs its content.
    private var isFood: Bool { if case .food = event { true } else { false } }

    /// This dose's own onset + coverage. Computed here rather than passed in: the sheet is
    /// presented from the OUTER Day-in-Review view, which never held the rows, and threading
    /// them through two view layers to serve one tap is more plumbing than the work costs.
    ///
    /// ⭐ Bounded ~25 h window, not the all-history fetch. A dose needs its own baseline
    /// (30 min before) and its observation horizon (the next dose, or the 24 h ceiling), so the
    /// doses and sleep are fetched over the same span — without the NEXT dose present, an
    /// evening dose would be watched to the ceiling and print a floor it never earned.
    private func loadDoseRow(at time: Date) async {
        defer { doseRowLoaded = true }
        let cal = Calendar.current
        let ds = cal.startOfDay(for: time)
        let de = cal.date(byAdding: .day, value: 1, to: ds) ?? ds.addingTimeInterval(86400)
        let lo = ds.addingTimeInterval(-CorrelationEngine.preMin * 60)
        let hi = de.addingTimeInterval(CorrelationEngine.observationCeilingMin * 60)

        let samples = ((try? modelContext.fetch(FetchDescriptor<TremorReading>(
            predicate: #Predicate { $0.timestamp >= lo && $0.timestamp < hi },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? [])
            .map { TremorPoint(timestamp: $0.timestamp, tremorScore: $0.tremorScore) }

        let doses = await healthKit.fetchMedicationDoses(since: lo).filter { $0.timestamp < hi }
        guard !doses.isEmpty else { return }
        let sleep = await healthKit.fetchSleepIntervals(from: lo, to: hi)

        let rows = await Task.detached(priority: .userInitiated) {
            CorrelationEngine.dosePanelRows(dayStart: ds, dayEnd: de,
                                            samples: samples, allDoses: doses, sleep: sleep)
        }.value
        // Match on the timestamp, with a second of slack for any round-tripping through
        // HealthKit. Never by index — the row set is the DAY's doses, not this one.
        doseRow = rows.first { abs($0.t0.timeIntervalSince(time)) < 1 }
    }

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

                    // ⛔ The ✕ was REMOVED Aug 5 2026. This sheet already had three ways out —
                    // the grabber, this button, and the always-present "Done" below — and the ✕
                    // was the smallest target of the three. Fewer, larger targets is the right
                    // trade for a tremor user. `dismiss()` is unchanged everywhere else.
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

                // What this dose did, in words. Only for medication, and only once the engine
                // has answered — a placeholder that resolves into a sentence is worse than a
                // sentence that simply appears.
                if case .medication(_, let time, _) = event {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What this dose did")
                            .font(.caption).foregroundStyle(.secondary)
                        if let row = doseRow {
                            Text(DoseRowCopy.sentence(for: row))
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if doseRowLoaded {
                            Text("We couldn't measure this dose.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .task { await loadDoseRow(at: time) }
                }

                // Both hands of the session, same "no score, no verdict" grammar as the
                // result screen — see `pairedMovementChecks` for why it's the whole session
                // rather than just the one trial that happened to be tapped.
                if case .movementCheck(_, let time, _, _) = event {
                    Divider()
                    // Same matrix the result screen renders, minus the definitions — this is
                    // a return visit, not first contact, and the whole session has to fit
                    // without scrolling.
                    let pair = pairedMovementChecks(around: time)
                    MovementCheckMatrix(
                        left: pair.first { $0.hand == .left },
                        right: pair.first { $0.hand == .right },
                        history: allMovementChecks,
                        doseFact: (pair.map(\.timestamp).min()).flatMap {
                            MovementCheckDoseFact.text(for: $0, doses: movementCheckDoses)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .task {
                        let since = time.addingTimeInterval(-24 * 3600)
                        movementCheckDoses = await healthKit.fetchMedicationDoses(since: since)
                    }
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
                    } else if case .movementCheck = event {
                        // No Edit — there's nothing sensible to hand-edit about a raw tap
                        // stream. No isEditable check, same reasoning as therapy: no
                        // HealthKit type, Kampa authored every trial, always deletable.
                        // Deletes the WHOLE session (every trial in `pairedMovementChecks`)
                        // so "delete this test" doesn't leave an orphaned single-hand row —
                        // matches the "both hands together" unit shown above.
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete this session", systemImage: "trash")
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
            if case .movementCheck = event {
                Text("This deletes both hands' trials from this session. This cannot be undone.")
            } else {
                Text("This cannot be undone.")
            }
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

    /// ⚠️ Shown for workouts, medication, and non-editable mindfulness / GI entries — so the
    /// deep link is **medication-only**. `x-apple-health://Medications` is the one screen we can
    /// land on accurately; sending a workout tap there would be worse than the plain sentence.
    private var healthAppNote: some View {
        Group {
            if case .medication = event {
                Button(action: openMedications) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                        Text("Edit or delete in the Health app")
                            .font(.caption)
                        Spacer()
                        // ⭐ `arrow.up.forward.app`, not a chevron — the same symbol the Log
                        // screen's Medication row uses. A chevron promises a screen pushed
                        // inside Kampa; this leaves the app entirely. One meaning, one glyph.
                        Image(systemName: "arrow.up.forward.app")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Insight.brandBlue)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("To edit or delete, open the Health app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    /// Straight to the Health app's Medications screen. Lifted verbatim from `LogEntrySheet` so
    /// there is one behaviour, not two: the scheme is undocumented but device-verified, and it
    /// falls back to Health's home if the path ever stops resolving, so the row never dead-ends.
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

        case .movementCheck(_, let time, _, _):
            // Deletes every trial in the SESSION (both hands, ±5 min — same grouping as the
            // content block above), not just the one trial the tap happened to resolve to.
            for trial in pairedMovementChecks(around: time) {
                modelContext.delete(trial)
            }
            try? modelContext.save()
            dismiss()

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
        case .movementCheck: return "Movement check"
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
        case .movementCheck(_, let time, _, _):
            // Same reason as the title: a per-hand rate here described one trial on a card
            // that shows two.
            return "Both hands · " + time.formatted(.dateTime.hour().minute())
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
