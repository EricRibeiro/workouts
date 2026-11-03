import Foundation
import SwiftData

/// A workout template: an ordered list of exercises with planned sets.
@Model
public final class Template {
    public var id: UUID = UUID()
    public var name: String = ""
    public var note: String = ""
    /// Order key within the folder; gaps and ties are tolerated.
    public var position: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var folder: TemplateFolder?

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    public var exercises: [TemplateExercise]? = []

    /// Workouts started from this template survive its deletion; their `template` becomes nil.
    @Relationship(deleteRule: .nullify, inverse: \Workout.template)
    public var workouts: [Workout]? = []

    public init(
        id: UUID = UUID(),
        name: String = "",
        note: String = "",
        position: Int = 0,
        folder: TemplateFolder? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.position = position
        self.folder = folder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
