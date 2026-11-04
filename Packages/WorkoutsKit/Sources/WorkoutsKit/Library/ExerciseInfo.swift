import Foundation

/// A read-only view of one exercise, library or custom, so callers do not care which it is.
public nonisolated struct ExerciseInfo: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let aliases: [String]
    public let bodyPart: String
    public let equipment: [String]
    public let weightType: WeightType
    public let isCustom: Bool
    /// Library: the `retired` flag in the file. Custom: archived. Hidden from lists, still resolvable by id.
    public let isRetired: Bool
    /// Custom exercises only: the defaults a new row starts from (nil for library exercises).
    public let unit: WeightUnit?
    public let barType: BarType?
    public let barWeight: Double?
    public let restSeconds: Int?

    public init(
        id: UUID,
        name: String,
        aliases: [String] = [],
        bodyPart: String = "",
        equipment: [String] = [],
        weightType: WeightType,
        isCustom: Bool,
        isRetired: Bool = false,
        unit: WeightUnit? = nil,
        barType: BarType? = nil,
        barWeight: Double? = nil,
        restSeconds: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.bodyPart = bodyPart
        self.equipment = equipment
        self.weightType = weightType
        self.isCustom = isCustom
        self.isRetired = isRetired
        self.unit = unit
        self.barType = barType
        self.barWeight = barWeight
        self.restSeconds = restSeconds
    }

    public init(_ library: LibraryExercise) {
        self.init(
            id: library.id,
            name: library.name,
            aliases: library.aliases,
            bodyPart: library.bodyPart,
            equipment: library.equipment,
            weightType: library.weightType,
            isCustom: false,
            isRetired: library.retired
        )
    }

    @MainActor
    public init(_ custom: Exercise) {
        self.init(
            id: custom.id,
            name: custom.name,
            aliases: custom.aliases,
            bodyPart: custom.bodyPart,
            equipment: custom.equipment,
            weightType: custom.weightType,
            isCustom: true,
            isRetired: custom.retired,
            unit: custom.unit,
            barType: custom.barType,
            barWeight: custom.barWeight,
            restSeconds: custom.restSeconds
        )
    }
}
