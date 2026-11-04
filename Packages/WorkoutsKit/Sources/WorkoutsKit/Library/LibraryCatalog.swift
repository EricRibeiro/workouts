import Foundation

/// One bundled library exercise, as written by `scripts/build-library`. Read-only.
public nonisolated struct LibraryExercise: Decodable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let source: String
    public let sourceId: String
    public let name: String
    /// Absent from the file when the exercise has none.
    public let aliases: [String]
    public let bodyPart: String
    public let equipment: [String]
    public let tags: [String]
    public let weightType: WeightType
    /// `""`, `compound` or `isolation`.
    public let mechanics: String
    /// `""`, `alternating`, `bilateral` or `unilateral`.
    public let laterality: String
    /// Muscle key to intensity, 0...100.
    public let muscles: [String: Int]
    public let description: String
    public let instructions: [String]
    public let tips: [String]
    public let mistakes: [String]
    /// Library ids (already resolved by the build script).
    public let alternatives: [UUID]
    public let recommended: [UUID]
    public let usedCount: Int
    /// ISO 8601 string as scraped; nil when unknown.
    public let sourceCreatedAt: String?
    public let sourceUrl: String
    /// Language code to the same page in that language.
    public let alternates: [String: String]
    public let retired: Bool
    public let hasThumbnails: Bool
    public let hasVideos: Bool

    private enum CodingKeys: String, CodingKey {
        case id, source, sourceId, name, aliases, bodyPart, equipment, tags, weightType, mechanics, laterality
        case muscles, description, instructions, tips, mistakes, alternatives, recommended, usedCount
        case sourceCreatedAt, sourceUrl, alternates, retired, hasThumbnails, hasVideos
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        source = try c.decode(String.self, forKey: .source)
        sourceId = try c.decode(String.self, forKey: .sourceId)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        bodyPart = try c.decode(String.self, forKey: .bodyPart)
        equipment = try c.decodeIfPresent([String].self, forKey: .equipment) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        weightType = try c.decode(WeightType.self, forKey: .weightType)
        mechanics = try c.decodeIfPresent(String.self, forKey: .mechanics) ?? ""
        laterality = try c.decodeIfPresent(String.self, forKey: .laterality) ?? ""
        muscles = try c.decodeIfPresent([String: Int].self, forKey: .muscles) ?? [:]
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        instructions = try c.decodeIfPresent([String].self, forKey: .instructions) ?? []
        tips = try c.decodeIfPresent([String].self, forKey: .tips) ?? []
        mistakes = try c.decodeIfPresent([String].self, forKey: .mistakes) ?? []
        alternatives = try c.decodeIfPresent([UUID].self, forKey: .alternatives) ?? []
        recommended = try c.decodeIfPresent([UUID].self, forKey: .recommended) ?? []
        usedCount = try c.decodeIfPresent(Int.self, forKey: .usedCount) ?? 0
        sourceCreatedAt = try c.decodeIfPresent(String.self, forKey: .sourceCreatedAt)
        sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl) ?? ""
        alternates = try c.decodeIfPresent([String: String].self, forKey: .alternates) ?? [:]
        retired = try c.decodeIfPresent(Bool.self, forKey: .retired) ?? false
        hasThumbnails = try c.decodeIfPresent(Bool.self, forKey: .hasThumbnails) ?? false
        hasVideos = try c.decodeIfPresent(Bool.self, forKey: .hasVideos) ?? false
    }
}

/// Display names for the keys used by `LibraryExercise` (`bodyPart`, `equipment`, `muscles`).
public nonisolated struct LibraryLabels: Decodable, Sendable, Hashable {
    public let bodyParts: [String: String]
    public let muscles: [String: String]
    public let muscleGroups: [String: String]
    public let equipment: [String: String]

    public init(
        bodyParts: [String: String] = [:],
        muscles: [String: String] = [:],
        muscleGroups: [String: String] = [:],
        equipment: [String: String] = [:]
    ) {
        self.bodyParts = bodyParts
        self.muscles = muscles
        self.muscleGroups = muscleGroups
        self.equipment = equipment
    }

    private enum CodingKeys: String, CodingKey {
        case bodyParts, muscles, muscleGroups, equipment
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bodyParts = try c.decodeIfPresent([String: String].self, forKey: .bodyParts) ?? [:]
        muscles = try c.decodeIfPresent([String: String].self, forKey: .muscles) ?? [:]
        muscleGroups = try c.decodeIfPresent([String: String].self, forKey: .muscleGroups) ?? [:]
        equipment = try c.decodeIfPresent([String: String].self, forKey: .equipment) ?? [:]
    }
}

/// The bundled, read-only exercise library, decoded once from `Library/library.json`.
public nonisolated struct LibraryCatalog: Decodable, Sendable {
    public let version: Int
    public let source: String
    public let scrapedAt: String
    public let labels: LibraryLabels
    /// In file order (the build script writes them sorted by name).
    public let exercises: [LibraryExercise]
    private let indexByID: [UUID: Int]

    private enum CodingKeys: String, CodingKey {
        case version, source, scrapedAt, labels, exercises
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        scrapedAt = try c.decodeIfPresent(String.self, forKey: .scrapedAt) ?? ""
        labels = try c.decodeIfPresent(LibraryLabels.self, forKey: .labels) ?? LibraryLabels()
        exercises = try c.decode([LibraryExercise].self, forKey: .exercises)
        indexByID = Self.index(exercises)
    }

    /// Decodes `library.json` bytes.
    public init(data: Data) throws {
        self = try JSONDecoder().decode(LibraryCatalog.self, from: data)
    }

    /// Reads `Library/library.json` from `bundle` (the app ships `Library/` as a folder reference).
    public static func bundled(in bundle: Bundle) throws -> LibraryCatalog {
        guard let url = bundle.url(forResource: "library", withExtension: "json", subdirectory: "Library") else {
            throw LibraryCatalogError.missingResource
        }
        return try LibraryCatalog(data: Data(contentsOf: url))
    }

    /// The library exercise with this id, nil when it is not in the catalog.
    public func exercise(id: UUID) -> LibraryExercise? {
        indexByID[id].map { exercises[$0] }
    }

    private static func index(_ exercises: [LibraryExercise]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        result.reserveCapacity(exercises.count)
        for (offset, exercise) in exercises.enumerated() where result[exercise.id] == nil {
            result[exercise.id] = offset
        }
        return result
    }
}

public nonisolated enum LibraryCatalogError: Error, Equatable, Sendable {
    /// `Library/library.json` is not in the bundle.
    case missingResource
}
