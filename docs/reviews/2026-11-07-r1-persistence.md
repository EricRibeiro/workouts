# Full-app review, round 1: persistence and sync-readiness (2026-11-07)

Read-only review. Scope: the nine `@Model` types, `SchemaV1` / `ModelContainer.workouts`, `WorkoutsApp.init`, the engine's
save and rollback rules, the in-progress workout across relaunch, `RemoteChangeObserver`, deletes and cascades, the save
points in `Workouts/`, and CloudKit compatibility. Settled calls are not re-opened: JC26 (rollback scope), JC78 (reader),
JC103 (the two-in-progress rule), DECISIONS "Data and sync" / "Errors". No code was changed and no tests were run (every
finding below is from reading the code; none needed a run to confirm).

## Findings

| # | Sev | Where | Failure scenario | Fix (one worker task) |
|---|---|---|---|---|
| P-01 | P1 (blocks 8.1) | `Session/ActiveWorkoutEngine+Support.swift:89-92` (`activeWorkout()`), `:27-72` (`settleExtraInProgress`); `Workouts/App/WorkoutsApp.swift:144-153`; readers `Features/ActiveWorkout/ActiveWorkoutCover.swift:51`, `ActiveWorkout/ResumeControl.swift:26`, `Shared/SetTable/SetTableSources.swift:25`, `App/Activity/EngineActivityIntentHandler.swift:46` | Sync on, two devices. Device B discards the workout, or B's `resume()` settles it (JC103), while device A is logging it. If B settles it, B deletes A's unchecked sets and its rows with no checked set. CloudKit merges the deletes into A's main context. The remote-change handler only reloads Previous, so `engine.workout` (and the rows the set table shows) are now deleted models. `liveWorkout` guards the derived reads (rest, Activity, notification), but every mutation goes through `activeWorkout()`/`owned()`, which check only `!= nil`. The cover, the resume ring and the set table read `engine.workout` directly. A's next render or tap reads a deleted model, and SwiftData traps. If B *finished* it instead, A keeps logging into a workout History already shows as finished. | In the remote-change callback: if `engine.workout` is deleted, detached or has `finishedAt != nil`, drop it via `resume()` (and close the cover through `AppNavigation`); also call `resume()` when `engine.workout == nil`, so a workout started elsewhere appears. Make `activeWorkout()` return `liveWorkout`. Kit test: delete the running workout in a second context on the same container, then `reloadPrevious`/mutate without trapping. |
| P-02 | P2 | `Session/ActiveWorkoutEngine.swift:65-71` (`resume()`), called from `init` at `:49`; `Workouts/App/WorkoutsApp.swift:76, 107-116` | At launch, a rest that expired while the app was dead is cleared with `try commit(running, nil)`. Any failure there makes the engine's `init` throw: a failed save (disk full, a merge conflict once CloudKit runs), or `loadPrevious` failing to fetch. `WorkoutsApp.init` then catches the error and sets `container = nil`. The person sees only "Could not open the database", and Export and the History screens cannot be reached, although the store opened fine. A cosmetic timer-clear takes the whole app down. | Make the expired-rest clear in `resume()` best effort: on a failed save, `rollbackKeepingEdits` and keep the cleared timer in memory, logging the error. A fetch failure in `loadPrevious` during resume leaves Previous empty instead of throwing. Kit test with `saveHook` throwing during `init`. |
| P-03 | P2 | `Model/Schema.swift:3-20` (V1 lists the live classes); no test opens an on-disk store (`Tests/.../SchemaTests.swift` is all in-memory) | The schema already changed twice under `1.0.0` (b431eda and 54e53c9, the health fields). Eric's phone migrated only because those changes were additive and lightweight inference saved them. With CloudKit off, the phone's store is the only copy (DECISIONS). The next model change has two failure modes. A non-inferable change with no stage fails to open. A `SchemaV2` declared over the same live classes gives V1 and V2 identical checksums, which is a launch failure. The app then shows only the error view, with no Export. Nothing in `./dev check` would notice before TestFlight. | Commit a fixture SQLite store written by the current schema (`Tests/.../Fixtures/store-v1/`), plus a kit test that copies it to a temp dir and opens it with `ModelContainer.workouts`-equivalent config + `WorkoutsMigrationPlan`, asserting row counts. Any future model edit then fails `./dev kit` until a stage exists. (Freezing V1 into nested types stays with PLAN 8.1, risk table line 475.) |
| P-04 | P2 | `Session/ActiveWorkoutEngine+Support.swift:259-291` (`loadPrevious`), `:305-325` (`historySessions`); callers `begin` (Start), `resume` (inside `WorkoutsApp.init`), `addExercises`, `replaceExercise`, `finishSummary`, `finish` | These fetch *every* finished workout on the main actor and walk `workout.exercises` (one relationship fault per workout). `historySessions` also faults the sets of every matching row. With Eric's 615 imported workouts the cost lands on Start, Add Exercise, Replace and the Finish tap. For an exercise with no history `loadPrevious` never exits early, so it walks all 615. In `resume()` it runs inside the launch watchdog window. JC78 moved the History and detail walks to `WorkoutStatsReader`, but these engine walks were not moved. Not measured on the device. | Fetch `WorkoutExercise` with `#Predicate { ids.contains($0.exerciseID) && $0.workout?.finishedAt != nil }` (sorted by `workout.startedAt` desc) for both Previous and the PR history, instead of walking workouts. Proof: an existing engine Previous/finish-summary test passes, plus a `-sampleWorkouts 600` xctrace of Start → Finish. |
| P-05 | P3 | Shared-`mainContext` rollbacks outside the engine: `Templates/FolderOperations.swift:195-201`, `Library/StickyNotes.swift:68-76`, `Library/CustomExerciseForm.swift:287-296`, `History/PastWorkoutDraft.swift:195-203`, `Templates/TemplateDraft.swift:401-403`, `History/WorkoutDetail.swift:378-380`, `Templates/TemplateUpdate.swift:71-73`, `WorkoutsJSON/Importer.swift:59-61`, `Features/History/HistoryView.swift:292`, `Features/History/WorkoutDetailView.swift:218` | Every one of these calls `context.rollback()` on the app-wide main context. That also reverts the engine's typed-but-unsaved set values, while the engine's `pendingEdits` still lists them. The next `commitEdits()` then saves nothing and clears the list, so the value is gone silently. JC26 protects against exactly this inside the engine (`rollbackKeepingEdits`), but not across features. It needs a failed save while a value is typed and focus has not left the field, which makes it rare. | Expose `engine.commitEdits()` as a pre-step: every non-engine save point that may roll back calls it first (one helper beside `saveIfChanged`). Alternatively, the engine re-applies `pendingEdits` when it sees its sets reverted. |
| P-06 | P3 | `Model/Enums.swift` (`SetKind`, `WeightUnit`, `BarType`, `WeightType` stored as Codable enum attributes) | Once two devices sync, a build that adds a case (say `SetKind.cluster`) writes a value the other device's older build cannot decode, so the older build crashes reading the row. TestFlight devices update at different times. | Add a rule to DECISIONS/AGENTS: adding an enum case to a stored attribute is a schema change (bump the version and update both devices). Alternatively, store `rawValue: String` with a computed enum accessor that falls back to a default. |

**P0: 0 · P1: 1 · P2: 3 · P3: 2**

## Nits

- `ActiveWorkoutEngine.setValues` documents "Does not save", but `mainContext.autosaveEnabled` is on by default, so
  autosave can write typed values at any run-loop turn. `pendingEdits` then lists values that are already saved. This is
  harmless, but the doc comment (`ActiveWorkoutEngine.swift:169-172`) and the `PendingValues` comment overstate the
  guarantee. Either say "may be autosaved" or set `autosaveEnabled = false` on purpose.
- `HealthEnrichmentService.pass` / `backfillPass` (`Features/Health/HealthEnrichmentService.swift:171, 192, 198`) save
  the whole main context, so they commit any unrelated pending edits along the way and report a failure only to the log.
  This is fine today. Note it for P-05's helper.
- `FolderOperations.delete(_:_:in:)` with `.deleteTemplates` relies on the cascade. That is correct locally, but under sync a
  template moved into that folder on another device before the delete arrives goes with it. It is an accepted edge of
  cascade-by-relationship; no change needed.

## Out of scope (PLAN 8 or settled)

- **The flip (8.1):** TestFlight builds talk to CloudKit **Production**, so the schema has to be deployed from
  Development first (8.1 says "promote"). Check the SwiftData main context's merge policy against a concurrent CloudKit
  import on the in-progress workout's rows during the two-simulator proof. P-01 belongs to that proof.
- **The import (8.3):** `Importer.apply` runs on the main actor with full-store fetches (`DataTransfer.swift:25-30`), so a
  615-workout import freezes the UI for its duration. Its idempotency is per store: importing the same file on two
  devices before they sync gives every workout twice (same `id`, different records), and nothing de-duplicates by `id`
  after a merge. 8.3 should run on one device only, or gain a by-id de-dup pass.
- JC103's settle rule (newest start wins, older finished or deleted) is settled. P-01 only covers the *receiving*
  device's crash, not the rule.

## Checked and sound

- CloudKit model rules: every attribute is optional or defaulted, every relationship is optional with an inverse, no
  `.unique`, no `.deny` (`CloudKitSchemaRulesTests`). In-memory stores never get CloudKit (`CloudKitChoice`). Folder
  `collapsed` is not in the model.
- Cascades: Workout → exercises → sets, Template → exercises → sets, Folder → templates; Template → workouts is nullify,
  so history survives a template delete. `RootView.askToUpdateTemplate` handles the nil template.
- The one-in-progress invariant holds locally. `refuseIfRunning` fetches the store, not the engine's cache. The importer
  skips a second unfinished workout. `Workout.inProgress` and `InProgressResolution` sort the same way.
- The past-workout and template editors are value drafts written in one save, and they roll back without touching
  the models on Cancel. `StickyNotes` collapses CloudKit duplicates (newest wins). Health passes re-check `isDeleted` and
  the detached state after every await.
- Export reads through its own background `ModelContext` after flushing the main one.
