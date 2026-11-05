import Foundation
import SwiftData

/// Reads a store into a ``WorkoutsJSON`` document (round-trip tests, Settings → Export…).
///
/// Output is deterministic: folders, templates and their children by `position` (then id), custom
/// exercises by name, sticky notes by update time, workouts by start time; ties break on the id.
public enum Exporter {
    /// Builds the document for everything in `context`.
    ///
    /// - Parameters:
    ///   - catalog: when given, an exercise id the catalog knows is written as a library reference
    ///     `{source, sourceId}`; otherwise (and for custom exercises) as `{id}`.
    ///   - exportedAt: the document's timestamp.
    public static func document(
        from context: ModelContext,
        catalog: LibraryCatalog? = nil,
        exportedAt: Date = Date()
    ) throws -> WorkoutsJSON {
        func ref(_ id: UUID) -> ExerciseRefDTO {
            if let entry = catalog?.exercise(id: id) {
                return .library(source: entry.source, sourceId: entry.sourceId)
            }
            return .custom(id: id)
        }

        let folders = try context.fetch(FetchDescriptor<TemplateFolder>())
            .sorted { ($0.position, $0.id.uuidString) < ($1.position, $1.id.uuidString) }
            .map {
                FolderDTO(
                    id: $0.id,
                    name: $0.name,
                    position: $0.position,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }

        let templates = try context.fetch(FetchDescriptor<Template>())
            .sorted { ($0.position, $0.id.uuidString) < ($1.position, $1.id.uuidString) }
            .map { template in
                TemplateDTO(
                    id: template.id,
                    name: template.name,
                    note: template.note,
                    position: template.position,
                    folderId: template.folder?.id,
                    createdAt: template.createdAt,
                    updatedAt: template.updatedAt,
                    exercises: ordered(template.exercises).map { exercise in
                        TemplateExerciseDTO(
                            id: exercise.id,
                            exercise: ref(exercise.exerciseID),
                            exerciseName: exercise.exerciseName,
                            position: exercise.position,
                            supersetGroup: exercise.supersetGroup,
                            note: exercise.note,
                            restSeconds: exercise.restSeconds,
                            unit: exercise.unit,
                            barType: exercise.barType,
                            barWeight: exercise.barWeight,
                            updatedAt: exercise.updatedAt,
                            sets: ordered(exercise.sets).map {
                                TemplateSetDTO(
                                    id: $0.id,
                                    position: $0.position,
                                    kind: $0.kind,
                                    weight: $0.weight,
                                    reps: $0.reps,
                                    durationSeconds: $0.durationSeconds,
                                    distanceMeters: $0.distanceMeters
                                )
                            }
                        )
                    }
                )
            }

        let customExercises = try context.fetch(FetchDescriptor<Exercise>())
            .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
            .map {
                CustomExerciseDTO(
                    id: $0.id,
                    name: $0.name,
                    aliases: $0.aliases,
                    equipment: $0.equipment,
                    bodyPart: $0.bodyPart,
                    weightType: $0.weightType,
                    instructions: $0.instructions,
                    unit: $0.unit,
                    barType: $0.barType,
                    barWeight: $0.barWeight,
                    restSeconds: $0.restSeconds,
                    retired: $0.retired,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }

        let stickyNotes = try context.fetch(FetchDescriptor<StickyNote>())
            .sorted { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }
            .map {
                StickyNoteDTO(id: $0.id, exercise: ref($0.exerciseID), text: $0.text, updatedAt: $0.updatedAt)
            }

        let workouts = try context.fetch(FetchDescriptor<Workout>())
            .sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
            .map { workout in
                WorkoutDTO(
                    id: workout.id,
                    name: workout.name,
                    note: workout.note,
                    startedAt: workout.startedAt,
                    finishedAt: workout.finishedAt,
                    templateId: workout.template?.id,
                    createdAt: workout.createdAt,
                    updatedAt: workout.updatedAt,
                    restEndsAt: workout.restEndsAt,
                    restSeconds: workout.restSeconds,
                    restSetId: workout.restSetID,
                    healthWorkoutId: workout.healthWorkoutID,
                    activeEnergyKcal: workout.activeEnergyKcal,
                    totalEnergyKcal: workout.totalEnergyKcal,
                    avgHeartRate: workout.avgHeartRate,
                    maxHeartRate: workout.maxHeartRate,
                    heartRateSeries: workout.heartRateSeries,
                    healthCheckedAt: workout.healthCheckedAt,
                    effortScore: workout.effortScore,
                    effortIsEstimated: workout.effortIsEstimated,
                    heartRateZones: workout.heartRateZones,
                    weatherTemperatureCelsius: workout.weatherTemperatureCelsius,
                    weatherHumidityPercent: workout.weatherHumidityPercent,
                    healthTimeZone: workout.healthTimeZone,
                    healthDetails: workout.healthDetails,
                    exercises: ordered(workout.exercises).map { exercise in
                        WorkoutExerciseDTO(
                            id: exercise.id,
                            exercise: ref(exercise.exerciseID),
                            exerciseName: exercise.exerciseName,
                            position: exercise.position,
                            supersetGroup: exercise.supersetGroup,
                            note: exercise.note,
                            restSeconds: exercise.restSeconds,
                            unit: exercise.unit,
                            barType: exercise.barType,
                            barWeight: exercise.barWeight,
                            updatedAt: exercise.updatedAt,
                            sets: ordered(exercise.sets).map {
                                WorkoutSetDTO(
                                    id: $0.id,
                                    position: $0.position,
                                    kind: $0.kind,
                                    weight: $0.weight,
                                    reps: $0.reps,
                                    durationSeconds: $0.durationSeconds,
                                    distanceMeters: $0.distanceMeters,
                                    completed: $0.completed,
                                    completedAt: $0.completedAt,
                                    rpe: $0.rpe
                                )
                            }
                        )
                    }
                )
            }

        return WorkoutsJSON(
            exportedAt: exportedAt,
            folders: folders,
            templates: templates,
            customExercises: customExercises,
            stickyNotes: stickyNotes,
            workouts: workouts
        )
    }

    private static func ordered<T: Positioned>(_ children: [T]?) -> [T] {
        (children ?? []).sorted { ($0.position, $0.id.uuidString) < ($1.position, $1.id.uuidString) }
    }
}

/// Children that sort by `position` then `id`.
private protocol Positioned {
    var id: UUID { get }
    var position: Int { get }
}

extension TemplateExercise: Positioned {}
extension TemplateSet: Positioned {}
extension WorkoutExercise: Positioned {}
extension WorkoutSet: Positioned {}
