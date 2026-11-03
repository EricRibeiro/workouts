import Foundation
import SwiftData

/// A workout. `finishedAt == nil` is the one in-progress workout. The rest-timer fields persist the running timer
/// across relaunch.
@Model
public final class Workout {
    public var id: UUID = UUID()
    public var name: String = ""
    public var note: String = ""
    public var startedAt: Date = Date()
    public var finishedAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    /// When the running rest timer ends; nil = no timer running.
    public var restEndsAt: Date?
    /// The length the running rest timer was started with.
    public var restSeconds: Int?
    /// The set whose completion started the running rest timer.
    public var restSetID: UUID?

    /// Nil when the template was deleted (or the workout was started empty).
    public var template: Template?

    /// A workout takes its exercises and sets with it.
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    public var exercises: [WorkoutExercise]? = []

    public init(
        id: UUID = UUID(),
        name: String = "",
        note: String = "",
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        template: Template? = nil,
        restEndsAt: Date? = nil,
        restSeconds: Int? = nil,
        restSetID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.template = template
        self.restEndsAt = restEndsAt
        self.restSeconds = restSeconds
        self.restSetID = restSetID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
