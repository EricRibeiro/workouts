import Foundation
import SwiftData

/// A custom exercise. Library exercises are not rows: they come from the bundled read-only `LibraryCatalog`.
/// Templates, workouts and sticky notes refer to either kind by `id` (`exerciseID`), never by relationship.
@Model
public final class Exercise {
    public var id: UUID = UUID()
    public var name: String = ""
    public var aliases: [String] = []
    public var equipment: [String] = []
    public var bodyPart: String = ""
    public var weightType: WeightType = WeightType.barbell
    public var instructions: [String] = []
    /// The unit a new row for this exercise starts from; nil = the Settings default.
    public var unit: WeightUnit?
    public var barType: BarType = BarType.olympic
    public var barWeight: Double?
    public var restSeconds: Int?
    /// Archived: hidden from the picker and list, still in history and fetchable by id.
    public var retired: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        name: String = "",
        aliases: [String] = [],
        equipment: [String] = [],
        bodyPart: String = "",
        weightType: WeightType = .barbell,
        instructions: [String] = [],
        unit: WeightUnit? = nil,
        barType: BarType = .olympic,
        barWeight: Double? = nil,
        restSeconds: Int? = nil,
        retired: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.equipment = equipment
        self.bodyPart = bodyPart
        self.weightType = weightType
        self.instructions = instructions
        self.unit = unit
        self.barType = barType
        self.barWeight = barWeight
        self.restSeconds = restSeconds
        self.retired = retired
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
