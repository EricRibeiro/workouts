import Foundation
import SwiftData

/// One logged (or planned, not yet completed) set of a workout exercise. No `updatedAt`.
@Model
public final class WorkoutSet {
    public var id: UUID = UUID()
    public var position: Int = 0
    public var kind: SetKind = SetKind.normal
    public var weight: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var completed: Bool = false
    public var completedAt: Date?
    /// Rate of perceived exertion, 1...10.
    public var rpe: Double?

    public var workoutExercise: WorkoutExercise?

    public init(
        id: UUID = UUID(),
        position: Int = 0,
        kind: SetKind = .normal,
        weight: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        completed: Bool = false,
        completedAt: Date? = nil,
        rpe: Double? = nil,
        workoutExercise: WorkoutExercise? = nil
    ) {
        self.id = id
        self.position = position
        self.kind = kind
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.completed = completed
        self.completedAt = completedAt
        self.rpe = rpe
        self.workoutExercise = workoutExercise
    }
}
