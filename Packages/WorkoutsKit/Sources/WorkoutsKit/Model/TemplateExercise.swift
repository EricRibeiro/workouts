import Foundation
import SwiftData

/// One exercise in a template. The exercise is referenced by id (library or custom) with a name snapshot.
@Model
public final class TemplateExercise {
    public var id: UUID = UUID()
    public var exerciseID: UUID = UUID()
    public var exerciseName: String = ""
    public var position: Int = 0
    public var supersetGroup: Int?
    public var note: String = ""
    public var restSeconds: Int?
    /// The unit of every weight in this row's sets.
    public var unit: WeightUnit = WeightUnit.lb
    public var barType: BarType = BarType.olympic
    /// The custom bar, in this row's `unit`.
    public var barWeight: Double?
    public var updatedAt: Date = Date()

    public var template: Template?

    @Relationship(deleteRule: .cascade, inverse: \TemplateSet.templateExercise)
    public var sets: [TemplateSet]? = []

    public init(
        id: UUID = UUID(),
        exerciseID: UUID = UUID(),
        exerciseName: String = "",
        position: Int = 0,
        supersetGroup: Int? = nil,
        note: String = "",
        restSeconds: Int? = nil,
        unit: WeightUnit = .lb,
        barType: BarType = .olympic,
        barWeight: Double? = nil,
        template: Template? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.position = position
        self.supersetGroup = supersetGroup
        self.note = note
        self.restSeconds = restSeconds
        self.unit = unit
        self.barType = barType
        self.barWeight = barWeight
        self.template = template
        self.updatedAt = updatedAt
    }
}
