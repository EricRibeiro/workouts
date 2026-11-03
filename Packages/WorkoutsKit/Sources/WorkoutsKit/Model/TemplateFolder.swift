import Foundation
import SwiftData

/// A folder of templates. Every template lives in a folder. The collapsed flag is per-device state, not stored here.
@Model
public final class TemplateFolder {
    public var id: UUID = UUID()
    public var name: String = ""
    public var position: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    /// Deleting a folder deletes its templates; the app moves them to another folder first when the user asks.
    @Relationship(deleteRule: .cascade, inverse: \Template.folder)
    public var templates: [Template]? = []

    public init(
        id: UUID = UUID(),
        name: String = "",
        position: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
