import SwiftData

extension PersistentModel {
    /// True when this model was saved and has since been deleted: a deleted-and-saved model reports no context and
    /// `isDeleted == false`, yet its backing data is gone, so reading a persisted attribute traps. A model that was never
    /// inserted (preview and snapshot fixtures) has no context either but still holds its values and a temporary
    /// identifier, so it is not gone.
    nonisolated var isGone: Bool {
        isDeleted || (modelContext == nil && !persistentModelID.isTemporary)
    }
}
