import Foundation
import SwiftData

/// One planned set of a template exercise. No `updatedAt`: sets are replaced with their parent.
@Model
public final class TemplateSet {
    public var id: UUID = UUID()
    public var position: Int = 0
    public var kind: SetKind = SetKind.normal
    public var weight: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?

    public var templateExercise: TemplateExercise?

    public init(
        id: UUID = UUID(),
        position: Int = 0,
        kind: SetKind = .normal,
        weight: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        templateExercise: TemplateExercise? = nil
    ) {
        self.id = id
        self.position = position
        self.kind = kind
        self.weight = weight
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.templateExercise = templateExercise
    }
}
