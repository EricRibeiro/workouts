//
//  SettingsFlow.swift
//  Workouts
//

import OSLog
import SwiftData
import SwiftUI
import WorkoutsKit

/// The long-running work behind Settings (import, Apple Fitness opt-in and opt-out), kept out of the view so it owns its
/// task handles instead of fire-and-forget `Task {}`s.
///
/// Cancellation is a per-operation decision:
/// - the look-up of Fitness data for imported history is restartable (workouts are stamped as they are handled, and the
///   foreground pass repeats it), so it is **cancelled** with the sheet: the flow only raises ``backfillRequest`` and
///   the view's `.task(id:)` runs it, so it lives and dies with the view;
/// - an import, the Health opt-in and the opt-out are **deliberately not cancelled**. Each is a user-confirmed change
///   to stored data that is only consistent when it finishes (an import applies then saves, an opt-out clears data after
///   the setting flipped), and the person would believe it happened. The flow stays alive until they are done, since
///   their tasks retain it.
@Observable
final class SettingsFlow {
    /// True while an import runs; disables the Import button.
    private(set) var isImporting = false
    /// The result alert after an import or a failed removal.
    var outcome: TransferOutcome?

    /// What the result alert shows.
    struct TransferOutcome {
        let title: String
        let message: String
    }

    /// Bumped after an import; the view runs the Fitness look-up in `.task(id: backfillRequest)`.
    private(set) var backfillRequest = 0

    /// Reads and applies the JSON export at `url`. Runs to completion on purpose (see the type's comment).
    func runImport(
        _ url: URL,
        context: ModelContext,
        catalog: LibraryCatalog?,
        exerciseStore: ExerciseStore?,
        engine: ActiveWorkoutEngine?,
        generation: StoreGeneration?,
    ) {
        isImporting = true
        Task {
            defer { isImporting = false }
            await performImport(
                url,
                context: context,
                catalog: catalog,
                generation: generation,
                refresh: { try Self.refreshAfterImport(context: context, exerciseStore: exerciseStore, engine: engine) }
            )
        }
    }

    /// The import itself, then the follow-up. Only reading and applying the file decide success: once `apply` has saved,
    /// the import happened, so a failure in `refresh` (re-reading the store for the pickers, resuming an imported
    /// unfinished workout) is logged and noted on the alert but never reported as "Could Not Import", and the Fitness
    /// look-up still runs.
    func performImport(
        _ url: URL,
        context: ModelContext,
        catalog: LibraryCatalog?,
        generation: StoreGeneration?,
        refresh: () throws -> Void
    ) async {
        let report: ImportReport
        do {
            let document = try await DataTransfer.readDocument(at: url)
            report = try DataTransfer.apply(document, to: context, catalog: catalog)
        } catch {
            outcome = TransferOutcome(title: "Could Not Import", message: DataTransfer.message(for: error))
            return
        }
        generation?.bump()
        var message = report.summary
        do {
            try refresh()
        } catch {
            Self.logger.error("Refreshing after an import failed: \(error.localizedDescription)")
            message +=
                "\n\nThe data was imported, but the app could not refresh everything. Restart Workouts to see it all."
        }
        outcome = TransferOutcome(title: report.headline, message: message)
        // Imported history needs its Fitness look-up: ask the view to run it (see `backfillRequest`).
        backfillRequest += 1
    }

    /// Imported custom exercises must reach the pickers and detail screens, and a legitimately imported unfinished
    /// workout (no other running) shows at once, not after relaunch.
    private static func refreshAfterImport(
        context: ModelContext,
        exerciseStore: ExerciseStore?,
        engine: ActiveWorkoutEngine?
    ) throws {
        exerciseStore?.setCustom(try context.fetch(FetchDescriptor<Exercise>()))
        if engine?.workout == nil { try engine?.resume() }
    }

    private static let logger = Logger(subsystem: "com.ericribeiro.Workouts", category: "SettingsFlow")

    /// True while the "Turn Off Video Downloads?" alert shows.
    var isConfirmingVideoRemoval = false
    /// What the alert offers to free: the size of the media cache when it was raised.
    private(set) var videoCacheBytes: Int64 = 0

    /// Turns "Download all videos" off. With nothing downloaded that is all there is to it; otherwise the alert asks
    /// whether to keep the videos (Cancel leaves the setting on). The caller's toggle stays on until this decides.
    func requestTurnOffVideos(
        settings: SettingsStore,
        download: BulkVideoDownload = .shared,
        store: MediaStore = ExerciseMedia.store
    ) {
        Task {
            var bytes = await store.cacheSize()
            if bytes == 0 {
                // A running download may be mid-file: let it land (a cancelled prefetch still finishes its current
                // video), then look again, so that file is offered for removal instead of silently kept.
                await download.cancel()?.value
                bytes = await store.cacheSize()
            }
            if bytes == 0 {
                settings.downloadAllVideos = false
            } else {
                videoCacheBytes = bytes
                isConfirmingVideoRemoval = true
            }
        }
    }

    /// The alert's Keep / Remove: flips the setting, stops the download and, for Remove, clears the media cache once the
    /// cancelled download has finished its current file (so none lands after the clear). Runs to completion on purpose:
    /// the setting has flipped and a removal cut short would leave the videos the person asked to drop.
    func turnOffVideos(
        removeVideos: Bool,
        settings: SettingsStore,
        download: BulkVideoDownload,
        store: MediaStore = ExerciseMedia.store
    ) {
        let stopping = download.cancel()
        settings.downloadAllVideos = false
        guard removeVideos else { return }
        Task {
            await stopping?.value
            await store.clearCache()
        }
    }

    /// Shows the Health read sheet and looks up what is waiting. Runs to completion on purpose: the setting is already on.
    func requestAuthorization(health: HealthEnrichmentService, context: ModelContext) {
        Task { await health.requestAuthorization(context: context) }
    }

    /// Turns Apple Fitness off, optionally removing the data already added. Runs to completion on purpose: the setting
    /// has flipped, and a removal cut short would leave half the data behind.
    func turnOffFitness(removeData: Bool, health: HealthEnrichmentService, context: ModelContext) {
        Task { await performTurnOff { try await health.turnOff(remove: removeData, context: context) } }
    }

    /// The failure handling behind `turnOffFitness`, with the work injected so a test can make it throw.
    func performTurnOff(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            outcome = TransferOutcome(
                title: "Could Not Remove Fitness Data",
                message: error.localizedDescription
            )
        }
    }
}
