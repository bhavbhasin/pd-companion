import SwiftUI
import SwiftData

struct LogEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let onLogged: (Date) -> Void

    @State private var selectedType: FoodType? = nil
    @State private var selectedAttributes: Set<FoodAttribute> = []
    @State private var chosenDateTime: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    HStack(spacing: 12) {
                        ForEach(FoodType.allCases, id: \.rawValue) { type in
                            typeChip(type)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Attributes") {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ],
                        spacing: 10
                    ) {
                        ForEach(FoodAttribute.allCases, id: \.rawValue) { attr in
                            attributeChip(attr)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("When") {
                    DatePicker(
                        "Date & Time",
                        selection: $chosenDateTime,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let type = selectedType else { return }
                        let event = FoodEvent(
                            timestamp: chosenDateTime,
                            type: type,
                            attributes: Array(selectedAttributes)
                        )
                        modelContext.insert(event)
                        onLogged(chosenDateTime)
                        dismiss()
                    }
                    .disabled(selectedType == nil)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func typeChip(_ type: FoodType) -> some View {
        let isSelected = selectedType == type
        return Button {
            selectedType = (selectedType == type) ? nil : type
        } label: {
            HStack(spacing: 8) {
                Image(systemName: type.symbolName)
                    .font(.body)
                Text(type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func attributeChip(_ attr: FoodAttribute) -> some View {
        let isSelected = selectedAttributes.contains(attr)
        return Button {
            if isSelected {
                selectedAttributes.remove(attr)
            } else {
                selectedAttributes.insert(attr)
            }
        } label: {
            Text(attr.displayName)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
