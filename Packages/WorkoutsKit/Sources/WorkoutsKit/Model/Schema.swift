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

/// Migration plan: V1 only. Add stages here when a V2 appears.
public enum WorkoutsMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

extension ModelContainer {
    /// The app's container. The store is always local (`cloudKitDatabase: .none`) until PLAN 8.1 turns sync on, so
    /// `cloudKit` is accepted but ignored for now (JC54). `inMemory` is for tests and previews.
    public static func workouts(inMemory: Bool = false, cloudKit: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            // Explicit on purpose (JC54 / PLAN 8.1): the app now carries the iCloud entitlement, and SwiftData
            // would otherwise start syncing to CloudKit on its own. 8.1 replaces this with `cloudKit ? .automatic : .none`.
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: WorkoutsMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
