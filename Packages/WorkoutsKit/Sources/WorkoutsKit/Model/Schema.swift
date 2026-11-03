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
    /// The app's container. `cloudKit: true` syncs through the private CloudKit database (`.automatic`); `false`
    /// keeps the store local (`.none`). `inMemory` is for tests and previews.
    public static func workouts(inMemory: Bool = false, cloudKit: Bool = true) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKit ? .automatic : .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: WorkoutsMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
