import SwiftUI
import SwiftData

/// Manage the therapy catalog: add, rename, archive, restore, and — only for a therapy nobody
/// has used — delete.
///
/// ⭐ **Reached from `+ → Therapy`, never from Settings.** One entry point, and it is the place
/// the user already is when they notice a name is wrong. Settings stays a settings screen.
///
/// ⭐ **Renaming here renames the whole history.** That is the entire reason the catalog exists:
/// when the name lived on each session, fixing a typo fixed one row and left every other one
/// spelled the old way.
///
/// ⛔ **No swipe actions.** Rename and delete were swipe-only in the first build and the user
/// never found them — and a hidden horizontal gesture is the wrong affordance in an app whose
/// user has a tremor. Every action is a labelled button on a screen of its own.
struct TherapyManagementScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Therapy.name) private var catalog: [Therapy]

    @State private var showingAdd = false

    private var active: [Therapy] { catalog.filter { !$0.isArchived } }
    private var archived: [Therapy] { catalog.filter { $0.isArchived } }

    var body: some View {
        NavigationStack {
            List {
                if catalog.isEmpty {
                    Section {
                        Text("No therapies yet. Add your first one below.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if !active.isEmpty {
                    Section {
                        ForEach(active) { therapy in row(therapy) }
                    } header: {
                        Text("Your therapies")
                    }
                }

                if !archived.isEmpty {
                    Section {
                        ForEach(archived) { therapy in row(therapy) }
                    } header: {
                        Text("Archived")
                    } footer: {
                        Text("Archived therapies don't appear when you log a session. Everything you already logged is unchanged.")
                    }
                }

                Section {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add a therapy", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Therapies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: Therapy.self) { therapy in
                TherapyDetailScreen(therapy: therapy, existing: catalog)
            }
            .sheet(isPresented: $showingAdd) {
                AddTherapySheet(existing: catalog) { _ in }
            }
        }
    }

    private func row(_ therapy: Therapy) -> some View {
        NavigationLink(value: therapy) {
            HStack(spacing: 12) {
                Image(systemName: TherapyStyle.timelineSymbol)
                    .foregroundStyle(therapy.isArchived ? Color.secondary : TherapyStyle.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(therapy.name)
                        .foregroundStyle(therapy.isArchived ? .secondary : .primary)
                    Text(sessionSummary(therapy))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sessionSummary(_ therapy: Therapy) -> String {
        let n = therapy.sessionCount
        let base = n == 0 ? "No sessions logged"
                          : "\(n) session\(n == 1 ? "" : "s") logged"
        return therapy.isArchived ? "\(base) · archived" : base
    }
}

// MARK: - One therapy: rename, archive, delete

struct TherapyDetailScreen: View {
    let therapy: Therapy
    let existing: [Therapy]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: TherapyStyle.timelineSymbol)
                        .font(.title2)
                        .foregroundStyle(therapy.isArchived ? Color.secondary : TherapyStyle.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(therapy.name).font(.headline)
                        Text(therapy.sessionCount == 0
                             ? "No sessions logged"
                             : "\(therapy.sessionCount) session\(therapy.sessionCount == 1 ? "" : "s") logged")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    renaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            } footer: {
                if therapy.sessionCount > 0 {
                    Text("Renaming updates every session you've already logged.")
                }
            }

            // ⭐ One action per state, and never both. Archive exists to PRESERVE history, so it
            // is meaningless on a therapy with none — offering it there parks clutter in an
            // Archived section for no benefit, when Remove is lossless and complete. Same
            // reasoning that took Remove off a therapy with sessions. Bhav's call, both times.
            if therapy.isArchived {
                Section {
                    Button {
                        therapy.isArchived = false
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                } footer: {
                    Text("Restoring puts it back in the list you pick from when logging.")
                }
            } else if !therapy.canBeDeleted {
                Section {
                    Button {
                        therapy.isArchived = true
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                } footer: {
                    Text("Archiving hides it when you log. Your logged sessions stay exactly as they are.")
                }
            }

            // ⛔ Remove is not shown at all once a therapy has sessions. Offering a destructive
            // button that always refuses, with a footnote explaining the refusal, is two
            // competing destructive-looking actions and a rule the user has to read. Archive
            // above already carries the whole story. Bhav's call, and correct.
            if therapy.canBeDeleted {
                Section {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(therapy.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $renaming) {
            RenameTherapySheet(therapy: therapy, existing: existing)
        }
        .alert("Remove \(therapy.name)?", isPresented: $confirmingDelete) {
            Button("Remove", role: .destructive) {
                modelContext.delete(therapy)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing has been logged against it, so nothing is lost.")
        }
    }
}

// MARK: - Rename

/// Renaming the type. One edit, and every session logged under the old name reads the new one.
struct RenameTherapySheet: View {
    let therapy: Therapy
    let existing: [Therapy]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(therapy: Therapy, existing: [Therapy]) {
        self.therapy = therapy
        self.existing = existing
        _name = State(initialValue: therapy.name)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The therapy's own current name is not a duplicate of itself — otherwise Save is disabled
    /// the moment the sheet opens. Archived therapies still count here: renaming ONTO an
    /// archived name would produce two therapies that look identical the moment it is restored.
    private var clash: Therapy? {
        TherapyStyle.match(trimmed, in: existing.filter { $0.id != therapy.id })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Therapy name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } footer: {
                    if let clash {
                        Text(clash.isArchived
                             ? "You have an archived therapy called \"\(clash.name)\". Restore that one instead of renaming this to match it."
                             : "You already have a therapy with this name.")
                            .foregroundStyle(.orange)
                    } else if therapy.sessionCount > 0 {
                        Text("This renames all \(therapy.sessionCount) logged \(therapy.sessionCount == 1 ? "session" : "sessions") too.")
                    }
                }
            }
            .navigationTitle("Rename therapy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        therapy.name = trimmed
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmed.isEmpty || clash != nil)
                }
            }
        }
    }
}
