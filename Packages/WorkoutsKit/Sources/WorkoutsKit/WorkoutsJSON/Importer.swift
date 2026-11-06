import Foundation
import SwiftData
import os

/// Applies a ``WorkoutsJSON`` document to a store. Safe to run any number of times with the same or
/// an overlapping document.
///
/// Idempotence rules:
/// - **Match by id.** A row whose id exists is updated, never duplicated. Sticky notes also match an
///   existing note for the same exercise (the app keeps one note per exercise).
/// - **Last write wins by `updatedAt`.** Folders, templates, template exercises, custom exercises,
///   sticky notes, workouts and workout exercises carry `updatedAt`: the document's row is applied only
///   when its `updatedAt` is strictly newer than the store's; equal or older is *skipped*.
/// - **Children follow their parent.** Sets have no timestamp, and a parent applied from the document
///   replaces its children: children are matched by id (updated, or inserted), and local children the
///   document does not list are deleted (`removed`). A skipped parent leaves its children untouched
///   (they count as skipped). Importing the same document twice therefore skips everything.
/// - **Never a second in-progress workout.** A document workout with `finishedAt == nil` whose id differs from the
///   store's in-progress workout is skipped (counted in ``ImportReport/skippedInProgress``) while one exists. With
///   none running, only the newest unfinished workout of the document (by `startedAt`) is imported as in progress, and
///   the caller resumes the engine; any other unfinished workout in the document is imported as finished, ending at its
///   latest completed set (`completedAt`), else at its `startedAt`.
/// - **Relationships are wired by id**: template to folder, workout to template. An id that matches no
///   row leaves the relationship nil and counts in `danglingReferences`.
/// - **Exercise references** resolve to ids through ``LibraryID`` (library) or the custom id. A library
///   reference missing from `catalog` is reported in `unknownLibraryRefs` and the row is still imported,
///   keeping its `exerciseName` snapshot.
public enum Importer {
    /// Applies `doc` to `context` and saves it.
    ///
    /// - Parameter catalog: the library to check library references against. Without one nothing is
    ///   reported as unknown.
    /// - Throws: ``ImportError/unsupportedVersion(_:)`` before touching the store, or a SwiftData error or
    ///   ``ImportError/unstorableHealthData(_:)`` (the context is rolled back when the workouts pass or the final save
    ///   fails).
    public static func apply(
        _ doc: WorkoutsJSON,
        to context: ModelContext,
        catalog: LibraryCatalog? = nil
    ) throws -> ImportReport {
        guard doc.version == WorkoutsJSON.currentVersion else {
            throw ImportError.unsupportedVersion(doc.version)
        }
        var run = try Run(context: context)
        run.report.unknownLibraryRefs = unknownRefs(in: doc, catalog: catalog)
        run.importCustomExercises(doc.customExercises)
        run.importStickyNotes(doc.stickyNotes)
        run.importFolders(doc.folders)
        run.importTemplates(doc.templates)
        do {
            try run.importWorkouts(doc.workouts)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return run.report
    }

    // MARK: Unknown library references

    private static func unknownRefs(in doc: WorkoutsJSON, catalog: LibraryCatalog?) -> [UnknownLibraryRef] {
        guard let catalog else { return [] }
        var found: [String: UnknownLibraryRef] = [:]
        func note(_ ref: ExerciseRefDTO, name: String?) {
            guard case .library(let source, let sourceId) = ref, catalog.exercise(id: ref.exerciseID) == nil else {
                return
            }
            var entry =
                found["\(source)\u{0}\(sourceId)"]
                ?? UnknownLibraryRef(source: source, sourceId: sourceId, names: [], uses: 0)
            entry.uses += 1
            if let name, !name.isEmpty, !entry.names.contains(name) { entry.names.append(name) }
            found["\(source)\u{0}\(sourceId)"] = entry
        }
        for template in doc.templates {
            for exercise in template.exercises { note(exercise.exercise, name: exercise.exerciseName) }
        }
        for workout in doc.workouts {
            for exercise in workout.exercises { note(exercise.exercise, name: exercise.exerciseName) }
        }
        for sticky in doc.stickyNotes { note(sticky.exercise, name: nil) }
        return found.values
            .map {
                UnknownLibraryRef(source: $0.source, sourceId: $0.sourceId, names: $0.names.sorted(), uses: $0.uses)
            }
            .sorted { ($0.source, $0.sourceId) < ($1.source, $1.sourceId) }
    }

    // MARK: Working state

    private struct Run {
        let context: ModelContext
        var report = ImportReport()

        var folders: [UUID: TemplateFolder]
        var templates: [UUID: Template]
        var templateExercises: [UUID: TemplateExercise]
        var templateSets: [UUID: TemplateSet]
        var customExercises: [UUID: Exercise]
        var stickyNotes: [UUID: StickyNote]
        var workouts: [UUID: Workout]
        var workoutExercises: [UUID: WorkoutExercise]
        var workoutSets: [UUID: WorkoutSet]
        /// The store's in-progress workout (newest `startedAt`, as the engine resumes it), if any.
        let inProgressID: UUID?
        /// With no workout running in the store, the one unfinished document workout that stays in progress.
        var resumedID: UUID?

        init(context: ModelContext) throws {
            self.context = context
            folders = Self.index(try context.fetch(FetchDescriptor<TemplateFolder>()), by: \.id)
            templates = Self.index(try context.fetch(FetchDescriptor<Template>()), by: \.id)
            templateExercises = Self.index(try context.fetch(FetchDescriptor<TemplateExercise>()), by: \.id)
            templateSets = Self.index(try context.fetch(FetchDescriptor<TemplateSet>()), by: \.id)
            customExercises = Self.index(try context.fetch(FetchDescriptor<Exercise>()), by: \.id)
            stickyNotes = Self.index(try context.fetch(FetchDescriptor<StickyNote>()), by: \.id)
            workouts = Self.index(try context.fetch(FetchDescriptor<Workout>()), by: \.id)
            workoutExercises = Self.index(try context.fetch(FetchDescriptor<WorkoutExercise>()), by: \.id)
            workoutSets = Self.index(try context.fetch(FetchDescriptor<WorkoutSet>()), by: \.id)
            inProgressID = try context.fetch(Workout.inProgress).first?.id
        }

        private static func index<T>(_ rows: [T], by id: KeyPath<T, UUID>) -> [UUID: T] {
            Dictionary(rows.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
        }

        /// Strictly newer wins; equal or older keeps the store's row.
        private func isNewer(_ incoming: Date, than existing: Date) -> Bool { incoming > existing }

        // MARK: Custom exercises

        mutating func importCustomExercises(_ dtos: [CustomExerciseDTO]) {
            for dto in dtos {
                if let existing = customExercises[dto.id] {
                    guard isNewer(dto.updatedAt, than: existing.updatedAt) else {
                        report[.customExercises].skipped += 1
                        continue
                    }
                    copy(dto, into: existing)
                    report[.customExercises].updated += 1
                } else {
                    let row = Exercise(id: dto.id)
                    context.insert(row)
                    copy(dto, into: row)
                    customExercises[dto.id] = row
                    report[.customExercises].inserted += 1
                }
            }
        }

        private func copy(_ dto: CustomExerciseDTO, into row: Exercise) {
            row.name = dto.name
            row.aliases = dto.aliases
            row.equipment = dto.equipment
            row.bodyPart = dto.bodyPart
            row.weightType = dto.weightType
            row.instructions = dto.instructions
            row.unit = dto.unit
            row.barType = dto.barType
            row.barWeight = dto.barWeight
            row.restSeconds = dto.restSeconds
            row.retired = dto.retired
            row.createdAt = dto.createdAt
            row.updatedAt = dto.updatedAt
        }

        // MARK: Sticky notes

        mutating func importStickyNotes(_ dtos: [StickyNoteDTO]) {
            for dto in dtos {
                let exerciseID = dto.exercise.exerciseID
                let existing =
                    stickyNotes[dto.id]
                    ?? stickyNotes.values.first { $0.exerciseID == exerciseID }
                if let existing {
                    guard isNewer(dto.updatedAt, than: existing.updatedAt) else {
                        report[.stickyNotes].skipped += 1
                        continue
                    }
                    existing.exerciseID = exerciseID
                    existing.text = dto.text
                    existing.updatedAt = dto.updatedAt
                    report[.stickyNotes].updated += 1
                } else {
                    let row = StickyNote(
                        id: dto.id,
                        exerciseID: exerciseID,
                        text: dto.text,
                        updatedAt: dto.updatedAt
                    )
                    context.insert(row)
                    stickyNotes[dto.id] = row
                    report[.stickyNotes].inserted += 1
                }
            }
        }

        // MARK: Folders and templates

        mutating func importFolders(_ dtos: [FolderDTO]) {
            for dto in dtos {
                if let existing = folders[dto.id] {
                    guard isNewer(dto.updatedAt, than: existing.updatedAt) else {
                        report[.folders].skipped += 1
                        continue
                    }
                    copy(dto, into: existing)
                    report[.folders].updated += 1
                } else {
                    let row = TemplateFolder(id: dto.id)
                    context.insert(row)
                    copy(dto, into: row)
                    folders[dto.id] = row
                    report[.folders].inserted += 1
                }
            }
        }

        private func copy(_ dto: FolderDTO, into row: TemplateFolder) {
            row.name = dto.name
            row.position = dto.position
            row.createdAt = dto.createdAt
            row.updatedAt = dto.updatedAt
        }

        mutating func importTemplates(_ dtos: [TemplateDTO]) {
            for dto in dtos {
                let row: Template
                if let existing = templates[dto.id] {
                    guard isNewer(dto.updatedAt, than: existing.updatedAt) else {
                        report[.templates].skipped += 1
                        countSkipped(dto.exercises)
                        continue
                    }
                    row = existing
                    report[.templates].updated += 1
                } else {
                    row = Template(id: dto.id)
                    context.insert(row)
                    templates[dto.id] = row
                    report[.templates].inserted += 1
                }
                row.name = dto.name
                row.note = dto.note
                row.position = dto.position
                row.createdAt = dto.createdAt
                row.updatedAt = dto.updatedAt
                row.folder = resolve(dto.folderId, in: folders)
                syncExercises(of: row, with: dto.exercises)
            }
        }

        private mutating func syncExercises(of template: Template, with dtos: [TemplateExerciseDTO]) {
            let keep = Set(dtos.map(\.id))
            for local in template.exercises ?? [] where !keep.contains(local.id) {
                report[.templateSets].removed += local.sets?.count ?? 0
                report[.templateExercises].removed += 1
                for set in local.sets ?? [] { templateSets[set.id] = nil }
                templateExercises[local.id] = nil
                context.delete(local)
            }
            for dto in dtos {
                let row: TemplateExercise
                if let existing = templateExercises[dto.id] {
                    row = existing
                    report[.templateExercises].updated += 1
                } else {
                    row = TemplateExercise(id: dto.id)
                    context.insert(row)
                    templateExercises[dto.id] = row
                    report[.templateExercises].inserted += 1
                }
                row.exerciseID = dto.exercise.exerciseID
                row.exerciseName = dto.exerciseName
                row.position = dto.position
                row.supersetGroup = dto.supersetGroup
                row.note = dto.note
                row.restSeconds = dto.restSeconds
                row.unit = dto.unit
                row.barType = dto.barType
                row.barWeight = dto.barWeight
                row.updatedAt = dto.updatedAt
                row.template = template
                syncSets(of: row, with: dto.sets)
            }
        }

        private mutating func syncSets(of exercise: TemplateExercise, with dtos: [TemplateSetDTO]) {
            let keep = Set(dtos.map(\.id))
            for local in exercise.sets ?? [] where !keep.contains(local.id) {
                report[.templateSets].removed += 1
                templateSets[local.id] = nil
                context.delete(local)
            }
            for dto in dtos {
                let row: TemplateSet
                if let existing = templateSets[dto.id] {
                    row = existing
                    report[.templateSets].updated += 1
                } else {
                    row = TemplateSet(id: dto.id)
                    context.insert(row)
                    templateSets[dto.id] = row
                    report[.templateSets].inserted += 1
                }
                row.position = dto.position
                row.kind = dto.kind
                row.weight = dto.weight
                row.reps = dto.reps
                row.durationSeconds = dto.durationSeconds
                row.distanceMeters = dto.distanceMeters
                row.templateExercise = exercise
            }
        }

        private mutating func countSkipped(_ exercises: [TemplateExerciseDTO]) {
            report[.templateExercises].skipped += exercises.count
            report[.templateSets].skipped += exercises.reduce(0) { $0 + $1.sets.count }
        }

        // MARK: Workouts

        mutating func importWorkouts(_ dtos: [WorkoutDTO]) throws {
            if inProgressID == nil {
                resumedID =
                    dtos.filter { $0.finishedAt == nil }
                    .max { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }?.id
            }
            for dto in dtos {
                // Never a second in-progress workout: an unfinished row that is not the store's own is skipped.
                if dto.finishedAt == nil, let inProgressID, dto.id != inProgressID {
                    report[.workouts].skipped += 1
                    report.skippedInProgress += 1
                    countSkipped(dto.exercises)
                    continue
                }
                let row: Workout
                if let existing = workouts[dto.id] {
                    guard isNewer(dto.updatedAt, than: existing.updatedAt) else {
                        report[.workouts].skipped += 1
                        countSkipped(dto.exercises)
                        continue
                    }
                    row = existing
                    report[.workouts].updated += 1
                } else {
                    row = Workout(id: dto.id)
                    context.insert(row)
                    workouts[dto.id] = row
                    report[.workouts].inserted += 1
                }
                row.name = dto.name
                row.note = dto.note
                row.startedAt = dto.startedAt
                row.finishedAt = dto.finishedAt ?? finishedAtForDemoted(dto)
                row.createdAt = dto.createdAt
                row.updatedAt = dto.updatedAt
                row.restEndsAt = dto.restEndsAt
                row.restSeconds = dto.restSeconds
                row.restSetID = dto.restSetId
                try importHealth(dto, into: row)
                row.template = resolve(dto.templateId, in: templates)
                syncExercises(of: row, with: dto.exercises)
            }
        }

        /// The end time for an unfinished document workout that is not the one kept in progress (nil for that one):
        /// its latest completed set, else its start.
        private func finishedAtForDemoted(_ dto: WorkoutDTO) -> Date? {
            guard dto.finishedAt == nil, dto.id != inProgressID, dto.id != resumedID else { return nil }
            let lastSet = dto.exercises.flatMap(\.sets).filter(\.completed).compactMap(\.completedAt).max()
            return lastSet.map { max($0, dto.startedAt) } ?? dto.startedAt
        }

        /// A document without Fitness data (an older file) never clears what the store already has; `healthCheckedAt`
        /// only moves forward.
        private func importHealth(_ dto: WorkoutDTO, into row: Workout) throws {
            if let checked = dto.healthCheckedAt, checked > (row.healthCheckedAt ?? .distantPast) {
                row.healthCheckedAt = checked
            }
            guard let id = dto.healthWorkoutId else { return }
            row.healthWorkoutID = id
            row.activeEnergyKcal = dto.activeEnergyKcal
            row.totalEnergyKcal = dto.totalEnergyKcal
            row.avgHeartRate = dto.avgHeartRate
            row.maxHeartRate = dto.maxHeartRate
            row.heartRateSeriesData =
                try (dto.heartRateSeries?.isEmpty ?? true)
                ? nil : Self.encodeHealth(dto.heartRateSeries, "heartRateSeries")
            row.effortScore = dto.effortScore
            row.effortIsEstimated = dto.effortIsEstimated
            row.heartRateZonesData =
                try (dto.heartRateZones?.isEmpty ?? true)
                ? nil : Self.encodeHealth(dto.heartRateZones, "heartRateZones")
            row.weatherTemperatureCelsius = dto.weatherTemperatureCelsius
            row.weatherHumidityPercent = dto.weatherHumidityPercent
            row.healthTimeZone = dto.healthTimeZone
            row.healthDetailsData = try dto.healthDetails.map { try Self.encodeHealth($0, "healthDetails") }
        }

        /// Encodes a Fitness field for storage. A failure aborts the import (rolled back) instead of silently dropping
        /// data the file is the only copy of.
        private static func encodeHealth<T: Encodable>(_ value: T, _ field: String) throws -> Data {
            do {
                return try JSONEncoder().encode(value)
            } catch {
                KitLog.health.error(
                    "Import could not encode \(field, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                throw ImportError.unstorableHealthData(field)
            }
        }

        private mutating func syncExercises(of workout: Workout, with dtos: [WorkoutExerciseDTO]) {
            let keep = Set(dtos.map(\.id))
            for local in workout.exercises ?? [] where !keep.contains(local.id) {
                report[.workoutSets].removed += local.sets?.count ?? 0
                report[.workoutExercises].removed += 1
                for set in local.sets ?? [] { workoutSets[set.id] = nil }
                workoutExercises[local.id] = nil
                context.delete(local)
            }
            for dto in dtos {
                let row: WorkoutExercise
                if let existing = workoutExercises[dto.id] {
                    row = existing
                    report[.workoutExercises].updated += 1
                } else {
                    row = WorkoutExercise(id: dto.id)
                    context.insert(row)
                    workoutExercises[dto.id] = row
                    report[.workoutExercises].inserted += 1
                }
                row.exerciseID = dto.exercise.exerciseID
                row.exerciseName = dto.exerciseName
                row.position = dto.position
                row.supersetGroup = dto.supersetGroup
                row.note = dto.note
                row.restSeconds = dto.restSeconds
                row.unit = dto.unit
                row.barType = dto.barType
                row.barWeight = dto.barWeight
                row.updatedAt = dto.updatedAt
                row.workout = workout
                syncSets(of: row, with: dto.sets)
            }
        }

        private mutating func syncSets(of exercise: WorkoutExercise, with dtos: [WorkoutSetDTO]) {
            let keep = Set(dtos.map(\.id))
            for local in exercise.sets ?? [] where !keep.contains(local.id) {
                report[.workoutSets].removed += 1
                workoutSets[local.id] = nil
                context.delete(local)
            }
            for dto in dtos {
                let row: WorkoutSet
                if let existing = workoutSets[dto.id] {
                    row = existing
                    report[.workoutSets].updated += 1
                } else {
                    row = WorkoutSet(id: dto.id)
                    context.insert(row)
                    workoutSets[dto.id] = row
                    report[.workoutSets].inserted += 1
                }
                row.position = dto.position
                row.kind = dto.kind
                row.weight = dto.weight
                row.reps = dto.reps
                row.durationSeconds = dto.durationSeconds
                row.distanceMeters = dto.distanceMeters
                row.completed = dto.completed
                row.completedAt = dto.completedAt
                row.rpe = dto.rpe
                row.workoutExercise = exercise
            }
        }

        private mutating func countSkipped(_ exercises: [WorkoutExerciseDTO]) {
            report[.workoutExercises].skipped += exercises.count
            report[.workoutSets].skipped += exercises.reduce(0) { $0 + $1.sets.count }
        }

        // MARK: Relationships

        /// Looks `id` up; a non-nil id with no match counts as a dangling reference.
        private mutating func resolve<T>(_ id: UUID?, in rows: [UUID: T]) -> T? {
            guard let id else { return nil }
            guard let row = rows[id] else {
                report.danglingReferences += 1
                return nil
            }
            return row
        }
    }
}
