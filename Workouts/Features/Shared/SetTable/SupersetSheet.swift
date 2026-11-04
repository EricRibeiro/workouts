//
//  SupersetSheet.swift
//  Workouts
//

import SwiftUI

/// "Superset…" from a block's header menu (task 3.6): the workout's blocks as checkmark rows. The block the menu was opened
/// from is ticked and locked; tick at least one more to enable **Create Superset** (**Update Superset** when the block is
/// already in one, where the rest of its group starts ticked). **Remove from Superset** shows only for a block in a group.
/// `onSave` receives the ticked blocks other than the current one, in list order; the owner builds the group from
/// `[current] + picked`.
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

    var body: some View {
        NavigationStack {
            List(blocks) { block in
                let isCurrent = block.id == currentID
                let isOn = isCurrent || picked.contains(block.id)
                Button {
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
            .navigationTitle("Superset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("superset.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        onSave(blocks.map(\.id).filter { picked.contains($0) && $0 != currentID })
                        dismiss()
                    } label: {
                        Text(isInSuperset ? "Update Superset" : "Create Superset")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(picked.subtracting([currentID]).isEmpty)
                    .accessibilityIdentifier("superset.save")
                    if isInSuperset {
                        Button(role: .destructive) {
                            onRemove()
                            dismiss()
                        } label: {
                            Text("Remove from Superset")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("superset.remove")
                    }
                }
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("superset.sheet")
    }
}
