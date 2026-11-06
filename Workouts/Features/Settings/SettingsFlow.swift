//
//  SettingsFlow.swift
//  Workouts
//

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
            do {
                let document = try await DataTransfer.readDocument(at: url)
                let report = try DataTransfer.apply(document, to: context, catalog: catalog)
                generation?.bump()
                // Imported custom exercises must reach the pickers and detail screens.
                exerciseStore?.setCustom(try context.fetch(FetchDescriptor<Exercise>()))
                // A legitimately imported unfinished workout (no other running) shows at once, not after relaunch.
                if engine?.workout == nil { try engine?.resume() }
                outcome = TransferOutcome(title: report.headline, message: report.summary)
                // Imported history needs its Fitness look-up: ask the view to run it (see `backfillRequest`).
                backfillRequest += 1
            } catch {
                outcome = TransferOutcome(title: "Could Not Import", message: DataTransfer.message(for: error))
            }
        }
    }

    /// True while the "Turn Off Video Downloads?" alert shows.
    var isConfirmingVideoRemoval = false
    /// What the alert offers to free: the size of the media cache when it was raised.
    private(set) var videoCacheBytes: Int64 = 0

    /// Turns "Download all videos" off. With nothing downloaded that is all there is to it; otherwise the alert asks
    /// whether to keep the videos (Cancel leaves the setting on). The caller's toggle stays on until this decides.
    func requestTurnOffVideos(settings: SettingsStore, store: MediaStore = ExerciseMedia.store) {
        Task {
            let bytes = await store.cacheSize()
            if bytes == 0 {
                _ = BulkVideoDownload.shared.cancel()
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
        Task {
            do {
                try await health.turnOff(remove: removeData, context: context)
            } catch {
                outcome = TransferOutcome(
                    title: "Could Not Remove Fitness Data",
                    message: error.localizedDescription
                )
            }
        }
    }
}
