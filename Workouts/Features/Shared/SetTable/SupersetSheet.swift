//
//  SupersetSheet.swift
//  Workouts
//

import SwiftUI

/// "Superset…" from a block's header menu (task 3.6): the workout's blocks as checkmark rows. The block the menu was opened
/// from is ticked and locked; tick at least one more to enable **Create Superset** (**Update Superset** when the block is
/// already in one, where the rest of its group starts ticked), a confirmation item in the navigation bar (nothing is
/// pinned to the bottom edge). **Remove from Superset** is a destructive row below the list and shows only for a block in
/// a group. `onSave` receives the ticked blocks other than the current one, in list order; the owner builds the group
/// from `[current] + picked`.
struct SupersetSheet: View {
    struct Block: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    let blocks: [Block]
    let currentID: UUID
    let isInSuperset: Bool
    let onSave: ([UUID]) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<UUID>

    /// `initialMembers` are the other blocks already in the current block's superset (empty when it is in none).
    init(
        blocks: [Block],
        currentID: UUID,
        initialMembers: Set<UUID>,
        isInSuperset: Bool,
        onSave: @escaping ([UUID]) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.blocks = blocks
        self.currentID = currentID
        self.isInSuperset = isInSuperset
        self.onSave = onSave
        self.onRemove = onRemove
        _picked = State(initialValue: initialMembers)
    }

    private var saveTitle: String { isInSuperset ? "Update Superset" : "Create Superset" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(blocks) { block in
                        row(for: block)
                    }
                } footer: {
                    Text("Select two or more exercises to create a superset")
                }
                if isInSuperset {
                    Section {
                        Button("Remove from Superset", systemImage: "minus.circle", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                        .accessibilityIdentifier("superset.remove")
                    }
                }
            }
            .navigationTitle(isInSuperset ? "Edit Superset" : "Create Superset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("superset.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle, systemImage: "checkmark") {
                        onSave(blocks.map(\.id).filter { picked.contains($0) && $0 != currentID })
                        dismiss()
                    }
                    .disabled(picked.subtracting([currentID]).isEmpty)
                    .accessibilityLabel(saveTitle)
                    .accessibilityIdentifier("superset.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("superset.sheet")
    }

    private func row(for block: Block) -> some View {
        let isCurrent = block.id == currentID
        let isOn = isCurrent || picked.contains(block.id)
        return Button {
            if picked.contains(block.id) {
                picked.remove(block.id)
            } else {
                picked.insert(block.id)
            }
        } label: {
            HStack {
                Text(block.name)
                    .foregroundStyle(isCurrent ? .secondary : .primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(isCurrent ? .secondary : Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .disabled(isCurrent)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("superset.row.\(block.id.uuidString)")
    }
}
