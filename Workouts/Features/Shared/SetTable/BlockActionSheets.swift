//
//  BlockActionSheets.swift
//  Workouts
//

import SwiftData
import SwiftUI
import WorkoutsKit

/// A block id as a sheet item.
struct BlockID: Identifiable {
    let id: UUID
}

/// One block as the block menu's prompts need it (a template draft's exercise or the active workout's row).
struct BlockActionBlock: Identifiable {
    let id: UUID
    let exerciseID: UUID
    let name: String
    let note: String
    let restSeconds: Int?
    let supersetGroup: Int?
    let unit: WeightUnit
    let barType: BarType
    let barWeight: Double?
}

/// What a `SetTable` block menu's prompts read and write (task 3.6, 3.6d): the template editor backs it with a
/// `TemplateDraft`, the logging screen with the `ActiveWorkoutEngine`. Every closure takes the block's id.
struct BlockActionHost {
    /// The blocks in list order.
    var blocks: [BlockActionBlock]
    /// Prefix of the prompts' accessibility identifiers (`"templateEditor"` gives `templateEditor.note.field`).
    var idPrefix: String
    /// The remove confirmation's message.
    var removeMessage: String
    var setNote: (UUID, String) -> Void
    /// Returns false when there was no working weight to build the ramp from (the prompt then asks for one).
    var addWarmups: (UUID) -> Bool
    var setRest: (UUID, Int?) -> Void
    var remove: (UUID) -> Void
    var replace: (UUID, ExerciseInfo) -> Void
    /// The block the menu was opened from, and the other blocks ticked with it, in list order.
    var makeSuperset: (UUID, [UUID]) -> Void
    var removeFromSuperset: (UUID) -> Void
    var savePreferences: (UUID, BlockPreferencesSheet.Values) -> Void
}

/// The pending prompts of a block menu. The owner keeps one in `@State`, builds the table's `blockActions` with
/// ``actions(host:)`` and attaches the prompts with `.blockActionSheets(_:host:)`.
@Observable
final class BlockActionState {
    var note: BlockID?
    var isWarmupAlertShown = false
    var sticky: BlockID?
    var rest: BlockID?
    var replace: BlockID?
    var superset: BlockID?
    var preferences: BlockID?
    var removeBlockID: UUID?
    /// Bumps when a block or its sticky note is removed; drives the `.warning` haptic on the owning screen.
    var destructiveCount = 0

    /// The menu entries, each opening its prompt (or acting straight away, for warm-ups).
    func actions(host: BlockActionHost) -> SetTableBlockActions {
        SetTableBlockActions(
            note: { [self] id in note = BlockID(id: id) },
            stickyNote: { [self] id in sticky = BlockID(id: id) },
            addWarmups: { [self] id in
                if !host.addWarmups(id) { isWarmupAlertShown = true }
            },
            updateRest: { [self] id in rest = BlockID(id: id) },
            remove: { [self] id in removeBlockID = id },
            replace: { [self] id in replace = BlockID(id: id) },
            superset: { [self] id in superset = BlockID(id: id) },
            preferences: { [self] id in preferences = BlockID(id: id) }
        )
    }
}

extension View {
    /// Presents the block menu's prompts: the Note sheet, the warm-up alert, the Sticky Note, Rest Timer, Replace Exercise
    /// (single-select picker), Superset and Preferences sheets, and the remove confirmation.
    func blockActionSheets(_ state: BlockActionState, host: BlockActionHost) -> some View {
        modifier(BlockActionSheets(state: state, host: host))
    }
}

private struct BlockActionSheets: ViewModifier {
    @Bindable var state: BlockActionState
    let host: BlockActionHost

    @Query private var stickyNotes: [StickyNote]

    func body(content: Content) -> some View {
        content
            .sheet(item: $state.note) { target in
                NoteSheet(initialText: block(target.id)?.note ?? "", idPrefix: "\(host.idPrefix).note") {
                    host.setNote(target.id, $0)
                }
                .presentationPlacement(.center)
            }
            .alert("Add a working weight first", isPresented: $state.isWarmupAlertShown) {
                Button("OK", role: .cancel) {}
                    .accessibilityIdentifier("\(host.idPrefix).warmup.ok")
            } message: {
                Text("Warm-up sets are built from the first set with a weight.")
            }
            .sheet(item: $state.sticky) { target in
                if let block = block(target.id) {
                    StickyNoteEditor(
                        exerciseID: block.exerciseID,
                        initialText: stickyNotes.first { $0.exerciseID == block.exerciseID }?.text ?? "",
                        onRemoved: { state.destructiveCount += 1 }
                    )
                    .presentationPlacement(.center)
                }
            }
            .sheet(item: $state.rest) { target in
                RestTimerPickerSheet(current: block(target.id)?.restSeconds) { host.setRest(target.id, $0) }
                    .presentationPlacement(.center)
            }
            .sheet(item: $state.replace) { target in
                ExercisePickerView(title: "Replace Exercise") { host.replace(target.id, $0) }
                    .presentationPlacement(.center)
            }
            .sheet(item: $state.superset) { target in
                supersetSheet(for: target.id)
                    .presentationPlacement(.center)
            }
            .sheet(item: $state.preferences) { target in
                preferencesSheet(for: target.id)
                    .presentationPlacement(.center)
            }
            .confirmationDialog(
                block(state.removeBlockID)?.name.isEmpty == false
                    ? "Remove \(block(state.removeBlockID)?.name ?? "")?" : "Remove Exercise?",
                isPresented: Binding(
                    get: { state.removeBlockID != nil },
                    set: { if !$0 { state.removeBlockID = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Exercise", role: .destructive) {
                    if let id = state.removeBlockID { host.remove(id) }
                    state.removeBlockID = nil
                    state.destructiveCount += 1
                }
                .accessibilityIdentifier("\(host.idPrefix).remove.confirm")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("\(host.idPrefix).remove.cancel")
            } message: {
                Text(host.removeMessage)
            }
            // On the owner's content, which outlives the confirmation and the sticky note sheet (a sheet that is
            // dismissing may cut the haptic off).
            .sensoryFeedback(.warning, trigger: state.destructiveCount)
    }

    private func block(_ id: UUID?) -> BlockActionBlock? {
        guard let id else { return nil }
        return host.blocks.first { $0.id == id }
    }

    @ViewBuilder
    private func supersetSheet(for id: UUID) -> some View {
        if let block = block(id) {
            let members = Set(
                host.blocks
                    .filter { block.supersetGroup != nil && $0.supersetGroup == block.supersetGroup && $0.id != id }
                    .map(\.id)
            )
            SupersetSheet(
                blocks: host.blocks.map { SupersetSheet.Block(id: $0.id, name: $0.name) },
                currentID: id,
                initialMembers: members,
                isInSuperset: block.supersetGroup != nil,
                onSave: { picked in host.makeSuperset(id, picked) },
                onRemove: { host.removeFromSuperset(id) }
            )
        }
    }

    @ViewBuilder
    private func preferencesSheet(for id: UUID) -> some View {
        if let block = block(id) {
            BlockPreferencesSheet(
                exerciseName: block.name,
                initial: BlockPreferencesSheet.Values(
                    unit: block.unit,
                    barType: block.barType,
                    barWeight: block.barWeight
                )
            ) { host.savePreferences(id, $0) }
        }
    }
}
