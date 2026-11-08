import SwiftUI

/// A compact list of the exercise names with drag handles: the easy way to reorder when the blocks themselves are too
/// tall to lift. `onMove` receives the `List`'s own move; the owner turns it into the order for `source.reorder`.
struct ReorderExercisesSheet: View {
    let sections: [SetTableSection]
    let onMove: (IndexSet, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let numbers = SetTableSection.supersetNumbers(for: sections)
        NavigationStack {
            List {
                ForEach(sections) { section in
                    HStack {
                        Text(section.name)
                        if let number = numbers[section.id] {
                            Spacer()
                            Text("Superset \(number)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("reorder.row.\(section.id.uuidString)")
                }
                .onMove(perform: onMove)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .accessibilityLabel("Done")
                        .accessibilityIdentifier("reorder.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    let group = 1
    ReorderExercisesSheet(
        sections: [
            SetTableSection(id: UUID(), exerciseID: UUID(), name: "Bench Press", supersetGroup: group, rows: []),
            SetTableSection(id: UUID(), exerciseID: UUID(), name: "Barbell Row", supersetGroup: group, rows: []),
            SetTableSection(id: UUID(), exerciseID: UUID(), name: "Squat", supersetGroup: nil, rows: []),
        ],
        onMove: { _, _ in }
    )
}
