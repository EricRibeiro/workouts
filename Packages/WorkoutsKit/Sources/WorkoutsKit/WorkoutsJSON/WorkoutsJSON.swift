import Foundation

/// The one document Workouts reads and writes for migration and backup: the web export (task 1.7's
/// `scripts/export-web`), Settings → Import, and Settings → Export… all use this shape.
///
/// ```json
/// {
///   "version": 1,
///   "exportedAt": "2026-11-03T12:00:00.000Z",
///   "folders": [{"id": "…", "name": "Splits", "position": 0, "createdAt": "…", "updatedAt": "…"}],
///   "templates": [{
///     "id": "…", "name": "Push", "note": "", "position": 0, "folderId": "…",
///     "createdAt": "…", "updatedAt": "…",
///     "exercises": [{
///       "id": "…", "exercise": {"source": "smartworkout", "sourceId": "123"},
///       "exerciseName": "Bench Press", "position": 0, "supersetGroup": null, "note": "",
///       "restSeconds": 120, "unit": "lb", "barType": "olympic", "barWeight": 45, "updatedAt": "…",
///       "sets": [{"id": "…", "position": 0, "kind": "normal", "weight": 135, "reps": 8,
///                 "durationSeconds": null, "distanceMeters": null}]
///     }]
///   }],
///   "customExercises": [{"id": "…", "name": "Sled Push", "weightType": "weighted", "…": "…"}],
///   "workouts": [{
///     "id": "…", "name": "Push", "note": "", "startedAt": "…", "finishedAt": "…", "templateId": "…",
///     "createdAt": "…", "updatedAt": "…", "restEndsAt": null, "restSeconds": null, "restSetId": null,
///     "exercises": [{"…": "same fields as a template exercise",
///       "sets": [{"id": "…", "position": 0, "kind": "normal", "weight": 135, "reps": 8,
///                 "durationSeconds": null, "distanceMeters": null, "completed": true,
///                 "completedAt": "…", "rpe": 8.5}]}]
///   }]
/// }
/// ```
///
/// Conventions:
/// - Ids are UUID strings. Every row has a stable id; importing is idempotent by id (see ``Importer``).
/// - Dates are ISO 8601 with fractional seconds (`2026-11-03T12:00:00.000Z`). The decoder also accepts
///   them without fractional seconds.
/// - Enums are their raw values (`SetKind`, `WeightUnit`, `WeightType`, `BarType`).
/// - An **exercise reference** (`exercise`) is either a library reference `{"source", "sourceId"}`, which
///   resolves to `LibraryID.id(source:sourceID:)`, or a custom exercise `{"id"}`. Template and workout
///   exercises also carry an `exerciseName` snapshot, kept even when the reference cannot be resolved.
/// - On decode, the top-level arrays may be missing (treated as empty); everything inside a row is
///   required except the optionals shown as `null` above.
public nonisolated struct WorkoutsJSON: Codable, Hashable, Sendable {
    /// The document version this build reads and writes.
    public static let currentVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var folders: [FolderDTO]
    public var templates: [TemplateDTO]
    public var customExercises: [CustomExerciseDTO]
    public var workouts: [WorkoutDTO]

    public init(
        version: Int = WorkoutsJSON.currentVersion,
        exportedAt: Date = Date(),
        folders: [FolderDTO] = [],
        templates: [TemplateDTO] = [],
        customExercises: [CustomExerciseDTO] = [],
        workouts: [WorkoutDTO] = []
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.folders = folders
        self.templates = templates
        self.customExercises = customExercises
        self.workouts = workouts
    }

    // Explicit keys: a document from an older build carrying a key that no longer exists still decodes.
    private enum CodingKeys: String, CodingKey {
        case version, exportedAt, folders, templates, customExercises, workouts
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        folders = try c.decodeIfPresent([FolderDTO].self, forKey: .folders) ?? []
        templates = try c.decodeIfPresent([TemplateDTO].self, forKey: .templates) ?? []
        customExercises = try c.decodeIfPresent([CustomExerciseDTO].self, forKey: .customExercises) ?? []
        workouts = try c.decodeIfPresent([WorkoutDTO].self, forKey: .workouts) ?? []
    }
}

// MARK: - Coding

extension WorkoutsJSON {
    /// The encoder for the document: ISO 8601 dates with fractional seconds, sorted keys. A fresh
    /// instance per call (`JSONEncoder` is not `Sendable`), all configured here.
    public nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Self.fractionalStyle))
        }
        return encoder
    }

    /// The decoder for the document: accepts ISO 8601 dates with or without fractional seconds.
    public nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: Self.fractionalStyle) { return date }
            if let date = try? Date(text, strategy: Self.plainStyle) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date, got \"\(text)\"."
            )
        }
        return decoder
    }

    /// The document as JSON bytes, using ``encoder``.
    public nonisolated func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    /// Parses JSON bytes with ``decoder``.
    ///
    /// - Throws: ``ImportError/unsupportedVersion(_:)`` for a file written by another format version, checked before the
    ///   full decode (a newer file may hold values this build cannot parse, which would read as "damaged"); a
    ///   `DecodingError` for anything that is not a Workouts file.
    public nonisolated static func decode(_ data: Data) throws -> WorkoutsJSON {
        struct Header: Decodable { var version: Int }
        let header = try decoder.decode(Header.self, from: data)
        guard header.version == currentVersion else { throw ImportError.unsupportedVersion(header.version) }
        return try decoder.decode(WorkoutsJSON.self, from: data)
    }

    /// The file name Export… offers: `workouts-export-YYYY-MM-DD.json`, the day read in `timeZone` (the device's by default).
    public nonisolated static func exportFileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let style = Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: timeZone).year().month().day()
        return "workouts-export-\(date.formatted(style)).json"
    }

    private nonisolated static var fractionalStyle: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    }

    private nonisolated static var plainStyle: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle()
    }
}

// MARK: - Exercise reference

/// Points at an exercise: a library exercise by `{source, sourceId}`, or a custom exercise by `{id}`.
public nonisolated enum ExerciseRefDTO: Codable, Hashable, Sendable {
    case library(source: String, sourceId: String)
    case custom(id: UUID)

    private enum CodingKeys: String, CodingKey { case source, sourceId, id }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let source = try c.decodeIfPresent(String.self, forKey: .source)
        let sourceId = try c.decodeIfPresent(String.self, forKey: .sourceId)
        if let source, let sourceId {
            self = .library(source: source, sourceId: sourceId)
        } else if let id = try c.decodeIfPresent(UUID.self, forKey: .id) {
            self = .custom(id: id)
        } else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "An exercise reference needs {source, sourceId} or {id}."
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .library(let source, let sourceId):
            try c.encode(source, forKey: .source)
            try c.encode(sourceId, forKey: .sourceId)
        case .custom(let id):
            try c.encode(id, forKey: .id)
        }
    }

    /// The exercise id the reference stands for: `LibraryID` for a library reference, the custom id otherwise.
    public var exerciseID: UUID {
        switch self {
        case .library(let source, let sourceId): LibraryID.id(source: source, sourceID: sourceId)
        case .custom(let id): id
        }
    }
}

// MARK: - Rows

public nonisolated struct FolderDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var position: Int
    public var createdAt: Date
    public var updatedAt: Date
}

public nonisolated struct TemplateDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var note: String
    public var position: Int
    public var folderId: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var exercises: [TemplateExerciseDTO]
}

public nonisolated struct TemplateExerciseDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var exercise: ExerciseRefDTO
    public var exerciseName: String
    public var position: Int
    public var supersetGroup: Int?
    public var note: String
    public var restSeconds: Int?
    public var unit: WeightUnit
    public var barType: BarType
    public var barWeight: Double?
    public var updatedAt: Date
    public var sets: [TemplateSetDTO]
}

public nonisolated struct TemplateSetDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var position: Int
    public var kind: SetKind
    public var weight: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
}

public nonisolated struct CustomExerciseDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var aliases: [String]
    public var equipment: [String]
    public var bodyPart: String
    public var weightType: WeightType
    public var instructions: [String]
    public var unit: WeightUnit?
    public var barType: BarType
    public var barWeight: Double?
    public var restSeconds: Int?
    public var retired: Bool
    public var createdAt: Date
    public var updatedAt: Date
}

public nonisolated struct WorkoutDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var note: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var templateId: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var restEndsAt: Date?
    public var restSeconds: Int?
    public var restSetId: UUID?
    /// Apple Fitness enrichment (PLAN 7.1b). All optional; files written before it existed decode with these nil.
    public var healthWorkoutId: String? = nil
    public var activeEnergyKcal: Double? = nil
    public var totalEnergyKcal: Double? = nil
    public var avgHeartRate: Double? = nil
    public var maxHeartRate: Double? = nil
    public var heartRateSeries: [HeartRatePoint]? = nil
    public var healthCheckedAt: Date? = nil
    /// More Fitness details (PLAN 7.1b e4); all optional, absent in older files.
    public var effortScore: Double? = nil
    public var effortIsEstimated: Bool? = nil
    public var heartRateZones: [HeartRateZoneTime]? = nil
    public var weatherTemperatureCelsius: Double? = nil
    public var weatherHumidityPercent: Double? = nil
    public var healthTimeZone: String? = nil
    public var healthDetails: HealthWorkoutDetails? = nil
    public var exercises: [WorkoutExerciseDTO]
}

public nonisolated struct WorkoutExerciseDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var exercise: ExerciseRefDTO
    public var exerciseName: String
    public var position: Int
    public var supersetGroup: Int?
    public var note: String
    public var restSeconds: Int?
    public var unit: WeightUnit
    public var barType: BarType
    public var barWeight: Double?
    public var updatedAt: Date
    public var sets: [WorkoutSetDTO]
}

public nonisolated struct WorkoutSetDTO: Codable, Hashable, Sendable {
    public var id: UUID
    public var position: Int
    public var kind: SetKind
    public var weight: Double?
    public var reps: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var completed: Bool
    public var completedAt: Date?
    public var rpe: Double?
}
