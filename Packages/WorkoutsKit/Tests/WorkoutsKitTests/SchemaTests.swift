import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@Suite struct SchemaTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer.workouts(inMemory: true, cloudKit: false))
    }

    private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    @Test func containerBuildsWithAllNineModels() throws {
        let container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
        #expect(container.schema.entities.count == 9)
        #expect(SchemaV1.models.count == 9)
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(WorkoutsMigrationPlan.schemas.count == 1)
        #expect(WorkoutsMigrationPlan.stages.isEmpty)
    }

    // MARK: Insert and fetch each model

    @Test func exerciseRoundTrips() throws {
        let context = try makeContext()
        let id = UUID()
        context.insert(
            Exercise(
                id: id,
                name: "Cable Row",
                aliases: ["Seated Row"],
                equipment: ["cable"],
                bodyPart: "back",
                weightType: .machine,
                instructions: ["Pull"],
                unit: .kg,
                barType: .none,
                barWeight: 17.25,
                restSeconds: 75
            )
        )
        try context.save()
        let fetched = try #require(try context.fetch(FetchDescriptor<Exercise>()).first)
        #expect(fetched.id == id)
        #expect(fetched.name == "Cable Row")
        #expect(fetched.aliases == ["Seated Row"])
        #expect(fetched.equipment == ["cable"])
        #expect(fetched.weightType == .machine)
        #expect(fetched.unit == .kg)
        #expect(fetched.barType == BarType.none)
        #expect(fetched.barWeight == 17.25)
        #expect(fetched.restSeconds == 75)
        #expect(fetched.retired == false)
    }

    @Test func exerciseDefaults() throws {
        let exercise = Exercise()
        #expect(exercise.weightType == .barbell)
        #expect(exercise.barType == .olympic)
        #expect(exercise.unit == nil)
        #expect(exercise.aliases.isEmpty)
    }

    @Test func stickyNoteRoundTrips() throws {
        let context = try makeContext()
        let exerciseID = UUID()
        context.insert(StickyNote(exerciseID: exerciseID, text: "Elbows in"))
        try context.save()
        let fetched = try #require(try context.fetch(FetchDescriptor<StickyNote>()).first)
        #expect(fetched.exerciseID == exerciseID)
        #expect(fetched.text == "Elbows in")
    }

    @Test func folderTemplateExerciseSetRoundTrip() throws {
        let context = try makeContext()
        let folder = TemplateFolder(name: "Push", position: 2)
        context.insert(folder)
        let template = Template(name: "Day A", note: "heavy", position: 1, folder: folder)
        context.insert(template)
        let exercise = TemplateExercise(
            exerciseName: "Bench Press",
            position: 0,
            supersetGroup: 1,
            restSeconds: 120,
            unit: .kg,
            template: template
        )
        context.insert(exercise)
        let set = TemplateSet(
            position: 0,
            kind: .warmup,
            weight: 17.25,
            reps: 8,
            durationSeconds: 30,
            distanceMeters: 100.5,
            templateExercise: exercise
        )
        context.insert(set)
        try context.save()

        let fetchedFolder = try #require(try context.fetch(FetchDescriptor<TemplateFolder>()).first)
        #expect(fetchedFolder.name == "Push")
        #expect(fetchedFolder.templates?.count == 1)
        let fetchedTemplate = try #require(try context.fetch(FetchDescriptor<Template>()).first)
        #expect(fetchedTemplate.folder?.id == folder.id)
        #expect(fetchedTemplate.exercises?.count == 1)
        let fetchedExercise = try #require(try context.fetch(FetchDescriptor<TemplateExercise>()).first)
        #expect(fetchedExercise.template?.id == template.id)
        #expect(fetchedExercise.unit == .kg)
        #expect(fetchedExercise.supersetGroup == 1)
        #expect(fetchedExercise.sets?.count == 1)
        let fetchedSet = try #require(try context.fetch(FetchDescriptor<TemplateSet>()).first)
        #expect(fetchedSet.templateExercise?.id == exercise.id)
        #expect(fetchedSet.kind == .warmup)
        #expect(fetchedSet.weight == 17.25)
        #expect(fetchedSet.distanceMeters == 100.5)
    }

    @Test func workoutExerciseSetRoundTrip() throws {
        let context = try makeContext()
        let restSetID = UUID()
        let ends = Date(timeIntervalSince1970: 1_000_000)
        let workout = Workout(name: "Morning", restEndsAt: ends, restSeconds: 90, restSetID: restSetID)
        context.insert(workout)
        let exercise = WorkoutExercise(exerciseName: "Squat", workout: workout)
        context.insert(exercise)
        let set = WorkoutSet(
            weight: 100.25,
            reps: 5,
            completed: true,
            completedAt: ends,
            rpe: 8.5,
            workoutExercise: exercise
        )
        context.insert(set)
        try context.save()

        let fetchedWorkout = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(fetchedWorkout.finishedAt == nil)
        #expect(fetchedWorkout.restEndsAt == ends)
        #expect(fetchedWorkout.restSeconds == 90)
        #expect(fetchedWorkout.restSetID == restSetID)
        #expect(fetchedWorkout.exercises?.count == 1)
        let fetchedExercise = try #require(try context.fetch(FetchDescriptor<WorkoutExercise>()).first)
        #expect(fetchedExercise.workout?.id == workout.id)
        #expect(fetchedExercise.unit == .lb)
        #expect(fetchedExercise.sets?.count == 1)
        let fetchedSet = try #require(try context.fetch(FetchDescriptor<WorkoutSet>()).first)
        #expect(fetchedSet.workoutExercise?.id == exercise.id)
        #expect(fetchedSet.weight == 100.25)
        #expect(fetchedSet.completed)
        #expect(fetchedSet.rpe == 8.5)
    }

    @Test func workoutSetDefaultsToIncomplete() {
        let set = WorkoutSet()
        #expect(set.completed == false)
        #expect(set.kind == .normal)
        #expect(set.completedAt == nil)
        #expect(Workout().restEndsAt == nil)
    }

    // MARK: Delete rules

    @Test func deletingWorkoutCascadesToExercisesAndSets() throws {
        let context = try makeContext()
        let workout = Workout(name: "W")
        context.insert(workout)
        let exercise = WorkoutExercise(workout: workout)
        context.insert(exercise)
        context.insert(WorkoutSet(workoutExercise: exercise))
        context.insert(WorkoutSet(position: 1, workoutExercise: exercise))
        try context.save()
        #expect(try count(WorkoutSet.self, in: context) == 2)

        context.delete(workout)
        try context.save()
        #expect(try count(Workout.self, in: context) == 0)
        #expect(try count(WorkoutExercise.self, in: context) == 0)
        #expect(try count(WorkoutSet.self, in: context) == 0)
    }

    @Test func deletingWorkoutExerciseKeepsWorkoutAndDropsSets() throws {
        let context = try makeContext()
        let workout = Workout()
        context.insert(workout)
        let exercise = WorkoutExercise(workout: workout)
        context.insert(exercise)
        context.insert(WorkoutSet(workoutExercise: exercise))
        try context.save()

        context.delete(exercise)
        try context.save()
        #expect(try count(Workout.self, in: context) == 1)
        #expect(try count(WorkoutSet.self, in: context) == 0)
    }

    @Test func deletingTemplateCascadesButNullifiesWorkouts() throws {
        let context = try makeContext()
        let folder = TemplateFolder(name: "F")
        context.insert(folder)
        let template = Template(name: "T", folder: folder)
        context.insert(template)
        let exercise = TemplateExercise(template: template)
        context.insert(exercise)
        context.insert(TemplateSet(templateExercise: exercise))
        let workout = Workout(name: "From T", template: template)
        context.insert(workout)
        context.insert(WorkoutExercise(workout: workout))
        try context.save()
        #expect(workout.template?.id == template.id)

        context.delete(template)
        try context.save()
        #expect(try count(Template.self, in: context) == 0)
        #expect(try count(TemplateExercise.self, in: context) == 0)
        #expect(try count(TemplateSet.self, in: context) == 0)
        #expect(try count(TemplateFolder.self, in: context) == 1)
        // The workout and its history survive; only the link is cleared.
        let survivor = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(survivor.template == nil)
        #expect(survivor.exercises?.count == 1)
        #expect(try count(WorkoutExercise.self, in: context) == 1)
    }

    @Test func deletingFolderCascadesToTemplates() throws {
        let context = try makeContext()
        let folder = TemplateFolder(name: "F")
        context.insert(folder)
        let template = Template(folder: folder)
        context.insert(template)
        let exercise = TemplateExercise(template: template)
        context.insert(exercise)
        context.insert(TemplateSet(templateExercise: exercise))
        let workout = Workout(template: template)
        context.insert(workout)
        try context.save()

        context.delete(folder)
        try context.save()
        #expect(try count(TemplateFolder.self, in: context) == 0)
        #expect(try count(Template.self, in: context) == 0)
        #expect(try count(TemplateExercise.self, in: context) == 0)
        #expect(try count(TemplateSet.self, in: context) == 0)
        let survivor = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(survivor.template == nil)
    }

    @Test func deletingChildDoesNotDeleteParent() throws {
        let context = try makeContext()
        let template = Template(name: "T")
        context.insert(template)
        let exercise = TemplateExercise(template: template)
        context.insert(exercise)
        try context.save()

        context.delete(exercise)
        try context.save()
        #expect(try count(Template.self, in: context) == 1)
        #expect(template.exercises?.isEmpty == true)
    }
}
