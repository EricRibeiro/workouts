import Foundation
import SwiftData

/// Version 1.0.0 of the store: the nine models.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            StickyNote.self,
            TemplateFolder.self,
            Template.self,
            TemplateExercise.self,
            TemplateSet.self,
            Workout.self,
            WorkoutExercise.self,
            WorkoutSet.self,
        ]
    }
}

/// Version 2.0.0: V1 without `StickyNote` (the feature was removed; the lightweight stage drops the entity).
public enum SchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            TemplateFolder.self,
            Template.self,
            TemplateExercise.self,
            TemplateSet.self,
            Workout.self,
            WorkoutExercise.self,
            WorkoutSet.self,
        ]
    }
}

/// Migration plan: V1 → V2 is lightweight (drops the `StickyNote` entity). Add stages here when a V3 appears.
public enum WorkoutsMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

/// Whether the store syncs through CloudKit: the pure rule behind ``ModelContainer/workouts(inMemory:cloudKit:)``.
public nonisolated enum CloudKitChoice: Sendable, Equatable {
    case none
    case automatic

    /// `.automatic` only when the flag is on **and** the store is on disk. An in-memory store with `.automatic` is an
    /// invalid configuration (review C-11), so `inMemory` wins whatever the flag says.
    public static func resolve(inMemory: Bool, cloudKit: Bool) -> CloudKitChoice {
        cloudKit && !inMemory ? .automatic : .none
    }
}

extension ModelContainer {
    /// The app's container. The store is local (`cloudKitDatabase: .none`) while `cloudKit` is false, which every
    /// caller passes until PLAN 8.1 flips it (JC54); an in-memory store (tests, previews, UI tests) is always local, see
    /// ``CloudKitChoice/resolve(inMemory:cloudKit:)``.
    public static func workouts(inMemory: Bool = false, cloudKit: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let database: ModelConfiguration.CloudKitDatabase =
            switch CloudKitChoice.resolve(inMemory: inMemory, cloudKit: cloudKit) {
            case .none: .none
            case .automatic: .automatic
            }
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            // Explicit on purpose (JC54 / PLAN 8.1): the app carries the iCloud entitlement, and SwiftData would
            // otherwise start syncing to CloudKit on its own.
            cloudKitDatabase: database
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: WorkoutsMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
