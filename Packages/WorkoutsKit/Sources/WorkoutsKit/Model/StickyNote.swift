import Foundation
import SwiftData

/// Exists only so `SchemaV1` can name the entity for the V1 → V2 lightweight migration (V2 drops it). Do not use.
@Model
public final class StickyNote {
    public var id: UUID = UUID()
    public var exerciseID: UUID = UUID()
    public var text: String = ""
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(), exerciseID: UUID = UUID(), text: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.exerciseID = exerciseID
        self.text = text
        self.updatedAt = updatedAt
    }
}
