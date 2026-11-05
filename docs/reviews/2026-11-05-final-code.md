# Final code review (Fable, 2026-11-05) — PLAN 7.6, code half

Scope: `Workouts/`, `Packages/WorkoutsKit/`, `WorkoutsLiveActivity/`, `Shared/`, the three test targets, `dev`, the
entitlements and `project.xcproj` settings, read against `AGENTS.md`, `docs/PLAN.md`, `docs/DECISIONS.md` and
`docs/judgment-calls.md`. UX and visuals are the other reviewer's half. Read-only: nothing in product code was changed.

Runs on this worktree (commit `4f07bb7`, simulator iPhone Duo 3): `./dev kit` 707 tests green (24 s); `./dev check` green
(lint, kit, build, 40 app tests); `./dev ui-test FinishUITests` green. Two findings below (C-01, C-05) were confirmed with a
throwaway kit test that was deleted afterwards (`git status` is clean).

## Verdict

**Ship-ready for Phase 8 after two P1 fixes.** The core is sound: the engine saves every mutation and rolls structural
ones back on a failed save, the one in-progress workout survives relaunch, Finish/Discard/edit/delete all go through one
save-or-rollback path, the JSON codec round-trips, the schema is CloudKit-safe as written, and the concurrency story
(MainActor default, `@concurrent` loaders, a `@ModelActor` reader, `Sendable`-only hops) holds up. No P0. The two P1s are
both in the newest code: the importer accepts a second in-progress workout (confirmed), and the Fitness backfill
permanently stamps every workout when Health read access is denied, which HealthKit reports as "no data", not as an
error, so the recovery JC66 promises does not exist. The rest is polish: three hand-rolled timers where SwiftUI has
`TimelineView`/`PhaseAnimator`, a few fingerprints that miss import-updated rows, kit helpers without rollback, and some
dead code.

## Findings

| ID | P | Area | Where | What is wrong | Failure scenario | Native fix |
|---|---|---|---|---|---|---|
| C-01 | **P1** | Import / in-progress | `Importer.swift:312-341`, `Exporter.swift:106-118`, `SettingsView.swift:119-137`, `ActiveWorkoutEngine+Support.swift:13-20` | The exporter writes every `Workout`, the running one included (with `restEndsAt`/`restSetID`), and the importer inserts an in-progress row without checking the store's own. Nothing tells the engine afterwards. **Confirmed**: after importing a document with a `finishedAt == nil` workout while one runs, the store holds two in-progress rows; `resume()` returns the imported one as soon as the real one is finished or discarded. | Eric exports from the phone mid-workout (Settings is reachable while minimised), later imports that file (or any export taken mid-workout, or a web export with an unfinished `finished_at`). After the current workout finishes, the next launch, notification action or Live Activity intent resumes a phantom "running" workout: the resume ring appears, a Live Activity is requested with a stale rest, Start is refused with "Workout in progress". With no workout running at import time the imported row is invisible until relaunch, but Start is refused at once (`refuseIfRunning` fetches). | Importer: treat a document workout with `finishedAt == nil` as unfinished history, not a running one: skip it (counted in the report) when the store already has a different in-progress workout, else import it and have the caller `engine.resume()`. Exporter: unchanged (a backup should carry it). See brief 1. |
| C-02 | **P1** | HealthKit / backfill | `HealthKitSource.swift:36-60`, `HealthEnrichmentRun.swift:64-68, 85-99`, `WorkoutHealthFields.swift:32-34`, `HealthEnrichmentService.swift:184-196`, JC66 | HealthKit never reveals read denial: `requestAuthorization` succeeds whether the sheet was granted or denied, and `HKSampleQueryDescriptor.result` returns an empty array for a type the person turned off (`HealthKitSource.map`'s `.errorAuthorizationDenied` branch, and so `HealthEnrichmentRun`'s "ends the pass, nothing stamped" rule, is unreachable with the real source; it only fires for the fake). So a denied opt-in runs the backfill over the whole history and stamps every workout `healthCheckedAt`, and `backfill` never looks at a stamped workout again. | Eric turns the toggle on, taps "Don't Allow" (or turns Workouts off on the sheet), the 615 imported workouts are stamped within seconds. He later grants access in Settings > Health > Workouts: the routine pass only covers the last 7 days, the backfill skips everything stamped, so the history never gets Fitness data. The only way back is toggle off with "Remove Fitness Data", which also throws away matches. The same stamp blocks a plain off (Keep) → on cycle. | On every opt-in (`requestAuthorization(context:)`), clear `healthCheckedAt` on the unmatched workouts (`healthWorkoutID == nil`) before the backfill, so each opt-in is a fresh look; keep matches. Optionally probe readability once per pass (one `workouts(in:)` over the last year: if HealthKit returns nothing at all, do not stamp). See brief 2. Also drop the dead `.notAuthorized`/`.unavailable` promise from the `HealthEnrichmentRun` docs or keep it only for `.unavailable` (`isHealthDataAvailable()` is real). |
| C-03 | P2 | Rest notification / first run | `RestNotifier.swift:217-222`, `SystemNotificationCenter.schedule:41-50` | `syncNow` schedules the request first and asks for authorization after; `UNUserNotificationCenter.add` is refused while status is `.notDetermined` ("notifications are not allowed"), and nothing re-syncs when the grant lands (the next sync is the next engine change). | First workout ever (or after a reinstall): first check starts a rest, the request is refused, the permission alert appears, Eric taps Allow, the rest ends with no notification. Every rest started before he answers is lost the same way. | In `syncNow`, after `await requestAuthorizationIfNeeded()` returns true, call `sync(plan: engine.restNotificationPlan)` again. `RestNotifierTests.firstWorkoutAsksForPermission` should then assert the plan is scheduled after the grant. |
| C-04 | P2 | Caches / fingerprints | `ExercisesView.swift:166-184`, `HistoryView.swift:320-332`, `WorkoutDetailView.swift:156-168`, `WorkoutView.swift:233` | The derived caches refresh on `(ids or count, max updatedAt, settings)`. An import that *updates* an older workout (its `updatedAt` newer than the row's but older than the newest local edit) changes neither, so the rows, best sets and PR cards stay stale until relaunch. The same holds for a CloudKit-synced edit from another device (8.1). | Import a corrected export: a workout's sets change on disk, History and Exercises keep showing the old numbers. | Include a change counter in the fingerprint: `SettingsView.runImport` and `TemplateUpdate`/`PastWorkoutDraft.save` bump an `@Observable` `StoreGeneration` (or the fingerprint folds `count` + `max(updatedAt)` + `sum of updatedAt` as `Date.timeIntervalSinceReferenceDate`), or simply call the loaders after a successful import. |
| C-05 | P2 (unverified crash) | HealthKit / concurrency | `HealthEnrichmentRun.swift:85-95`, `HealthEnrichmentService.swift:157-176` | `process` holds `[Workout]` models across `await`s and then reads `finishedAt` and writes `applyHealth`. If a workout is deleted and saved meanwhile (History swipe, detail Delete) the instance is detached (`modelContext == nil`): on the macOS in-memory store the read succeeds and the write is silently dropped (probe); the engine's own `liveWorkout` comment says a property read of a deleted model traps on iOS. | Opt-in backfill over 615 workouts (seconds to a minute of HealthKit queries); Eric deletes a workout in History meanwhile; the pass reaches it. Best case the stamp is lost, worst case (unverified) a trap. | Guard each iteration as the engine does (`guard workout.modelContext != nil, !workout.isDeleted`), or carry `PersistentIdentifier`s and re-fetch with `context.model(for:)` before applying. Kit test: `FakeHealthSource(delay:)`, delete one pending workout mid-pass, expect no stamp and no crash. |
| C-06 | P2 | Save failure / kit helpers | `CustomExerciseForm.swift:217-227, 249-252` (kit), `StickyNotes.swift:20-36` | `commit`/`set`/`clear` save without `rollback()` on failure, unlike every other kit mutation. A failed delete of a custom exercise (and its note) or a failed sticky-note write stays pending in the main context and is committed by the next unrelated save (a set check in the engine), after the user saw "could not save". | Disk-full save fails on Delete Exercise; the alert says it failed; the next check in a workout silently deletes the exercise anyway. | `do { try context.save() } catch { context.rollback(); throw error }`, as `FolderOperations.save` does. |
| C-07 | P3 | Framework fit / timers | `RestRingItem.swift:108-124`, `ResumeControl.swift:80-96`, `ExerciseMedia.swift:241-249` | Three hand-rolled clocks: two `.task` loops sleeping 1 s to bump `@State now` (the arc, the haptic, `tickRest`), and a 1.5 s sleep loop toggling the thumbnail cross-fade. The ring loops also run on every tab root that applies `.resumeControl()`, so three loops tick while a workout is minimised. | None today; drift and duplicated `tickRest` calls, and each tick re-renders the toolbar item. | Arc: `TimelineView(.periodic(from: .now, by: 1))` around the `Label` (the icon stays an `Image`, which is what the strip stacks; whether the strip keeps a `TimelineView`-wrapped label stacked is unverified, DECISIONS "Minimised workout"). Expiry: one `Task.sleep(until: endsAt + grace)` then `tickRest()`, not polling. Cross-fade: `PhaseAnimator([false, true], trigger:)` with `.easeInOut(duration: 0.6).delay(0.9)` (also the JC71 cost). |
| C-08 | P3 | Dead code | `RestNotifier.swift:90, 244`; `AppNavigation.swift:62-68, 81-84, 95`; `Shared/WorkoutActivityAttributes.swift:18-20`; `HealthEnrichmentRun.swift:28` | `onRestEndedInForeground` is set only by a test (the foreground haptic is the ring loops' `restEndCount`); `AppNavigation.pop`, `openTemplate`, `closeSettings` and `WorkoutActivityAttributes.init(_ info:)` have no production caller; `Outcome.stoppedForAuthorization` is test-only. | — | Delete, or wire `onRestEndedInForeground` to the haptic and drop the loops' `restEndCount`. |
| C-09 | P3 | Queries | `PastWorkoutEditor.swift:18-21`, `WorkoutDetailView.swift:21, 139-141`, `TemplatePreview.swift:26`, `WorkoutView.swift:21` | `@Query` of every finished workout to find one by id (or to compute a fingerprint); the 6.4 work moved the walks off-main but these still fetch and observe the whole table per screen. | 600 workouts: each push re-fetches 600 faults; any save (a keystroke in the cover, C-10) invalidates them. | `init(workoutID:)` builds `_finished = Query(filter: #Predicate { $0.id == workoutID })` (the pattern `ExerciseDetailView.init` already uses). |
| C-10 | P3 | Saves per keystroke | `SetFieldCell.swift:58-60` → `EngineSetTableSource.commitWeight/commitReps` → `engine.setValues` → `context.save()` | Every keystroke is a `ModelContext.save()`; the notifier and activity controller debounce, SwiftData does not, and every `@Query` in the three tabs under the cover re-evaluates. | Typing "100" is three saves and three app-wide query invalidations. | Commit on focus loss / Next / check (the engine already keeps typed values in memory on a failed save), or keep per-keystroke `setValues` and save in `onChange(of: isFocused)`. |
| C-11 | P3 | CloudKit readiness (8.1) | `Schema.swift:31-46`, `WorkoutsApp.swift:91-99`, `ExerciseStore.swift:28-36`, `ActiveWorkoutEngine.swift:46-65` | Models are CloudKit-safe (optional relationships with inverses, defaults everywhere, no `.unique`, Codable enums and `[String]`/`Data` attributes). Three things will bite once `.automatic` is on: (a) `inMemory: true` with `.automatic` is an invalid configuration, so 8.1's `cloudKit ? .automatic : .none` must stay `.none` when `inMemory`; (b) `ExerciseStore`'s custom list and the engine's `previousCache` are snapshots refreshed only by the app's own edits, so a synced custom exercise or history is invisible until relaunch; (c) two devices can each hold a `finishedAt == nil` workout; `fetchInProgress` shows the newest and the other is a phantom (the C-01 shape). | 8.1 two-simulator proof: a custom exercise made on sim A does not appear in sim B's picker until relaunch. | (a) guard in `ModelContainer.workouts`; (b) observe `ModelContext.didSave` / `NSPersistentStoreRemoteChange` and call `setCustom` (fetch) and `engine.resume()`-style cache reloads; (c) fold the C-01 rule into `resume()` (finish or hide the older in-progress row). Flag, not fix, until 8.1. |
| C-12 | P3 | Tests | `HealthEnrichmentRunTests.swift` (the `.notAuthorized` cases), `RestNotifierTests.firstWorkoutAsksForPermission`, `HealthTests` | The `.notAuthorized` pass-stopping tests pass only with the fake; the real source cannot throw it (C-02). `firstWorkoutAsksForPermission` asserts the ask, not that the plan is scheduled after the grant (C-03). Everything else sampled tests what its name says (`ActiveWorkoutEngineSaveFailureTests`, `HealthEnrichmentServiceTests` race cases, `LiveActivityControllerTests`, `FormatStyleParityTests`). | — | Rewrite with C-02/C-03; add the C-05 kit test. |
| C-13 | P3 | Logging | `LiveActivityController.swift:179-185` | With Live Activities off in Settings every engine change logs `Live Activity request failed` (`ActivityAuthorizationError`). | A full workout with the feature disabled writes hundreds of error lines. | Check `ActivityAuthorizationInfo().areActivitiesEnabled` before requesting, or log once per workout. |

Not filed (checked, accepted): `UIApplication.shared.isIdleTimerDisabled` in `ActiveWorkoutCover` (SwiftUI has no idle-timer
API; the comment says so); `WorkoutStatsReader`'s `@concurrent` entry points to create the `@ModelActor` off the main
thread (documented behaviour of actor executors following their creating context, not private API; keep the comment);
`ExportArchive` builds the document on the main actor (JC35 accepted; `FileRepresentation` makes it lazy);
`Task.sleep` as a debounce in the notifier, the activity controller and the natural-language search (cancellable, the
documented SwiftUI pattern); `StarCelebration`'s one-shot sleep (animation end); `BenchArrangementStyle` reading
`reservedRegions(kind: .division)` (public iOS 27.1 API, JC53/JC58/JC59).

## Fix briefs (P1)

### Brief 1 (C-01): the importer never creates a second in-progress workout

One change: `Importer.importWorkouts` learns about the store's in-progress workout; Settings resumes the engine after an
import.

- `Packages/WorkoutsKit/Sources/WorkoutsKit/WorkoutsJSON/Importer.swift`: in `Run.init`, fetch the in-progress workout
  (`finishedAt == nil`, newest `startedAt`, as `ActiveWorkoutEngine.fetchInProgress` does) into `inProgressID: UUID?`.
  In `importWorkouts`, for a `dto.finishedAt == nil` row whose id is not `inProgressID` and `inProgressID != nil`: count it
  in `report[.workouts].skipped` (plus `countSkipped(dto.exercises)`), add a new `report.skippedInProgress` counter the
  summary mentions ("1 unfinished workout was skipped because one is in progress"), and `continue`. A document's
  in-progress row with the store's own id follows the usual `updatedAt` rule (a mid-workout backup re-imported is a no-op).
- `Packages/WorkoutsKit/Sources/WorkoutsKit/WorkoutsJSON/ImportReport.swift`: the counter and its line in `summary`.
- `Workouts/Features/Settings/SettingsView.swift` `runImport`: after `DataTransfer.apply`, `if engine?.workout == nil {
  try engine?.resume() }` (inject `@Environment(ActiveWorkoutEngine.self)`), so a legitimately imported unfinished workout
  (fresh install) shows its resume ring at once instead of after relaunch.
- Tests in `Packages/WorkoutsKit/Tests/WorkoutsKitTests/WorkoutsJSONTests.swift`: (1) a running engine + a document with
  a different unfinished workout → one in-progress row after import, the engine's; report says skipped; (2) no running
  workout + the same document → imported, `engine.resume()` returns it; (3) re-importing the engine's own mid-workout
  export is a no-op (existing idempotence test extended).

Proof: `./dev kit WorkoutsJSONTests`, then `./dev check`.

### Brief 2 (C-02): every opt-in looks at the unmatched history again

One change: `HealthEnrichmentService.requestAuthorization` clears the lookup stamp of unmatched workouts before the
backfill, so a denied-then-granted (or off/on) cycle recovers; the docs stop promising what HealthKit cannot give.

- `Packages/WorkoutsKit/Sources/WorkoutsKit/Health/HealthEnrichmentRun.swift`: add
  `public static func resetUnmatched(context: ModelContext) throws -> Int` (fetch `healthWorkoutID == nil &&
  healthCheckedAt != nil`, set `healthCheckedAt = nil`, save; mirror `clearAll`). Reword the `backfill`/`process` docs:
  with HealthKit a denied read is an empty answer, so "stamps nothing" only applies to `.unavailable`.
- `Workouts/Features/Health/HealthEnrichmentService.swift` `requestAuthorization(context:)`: after the sheet returns (and
  for a fixture source too), `try? HealthEnrichmentRun.resetUnmatched(context: context)` then the existing
  `request(..., backfill: true)`. Matches are kept; only stamps move.
- `Workouts/Features/Health/HealthKitSource.swift` doc comment on `requestReadAuthorization`: already says denial is
  invisible; add that `workouts(in:)` returns `[]` for a denied type, so callers must not infer authorization from errors.
- Tests: `WorkoutsTests/HealthEnrichmentServiceTests.swift`: a workout stamped by an empty source, then
  `requestAuthorization` with a source that now has the match → the workout is matched. Kit:
  `HealthEnrichmentRunTests`: `resetUnmatched` leaves matched rows alone.

Proof: `./dev test HealthEnrichmentServiceTests`, `./dev kit HealthEnrichmentRunTests`, then `./dev check`; on the Duo
simulator `./dev ui-test HealthEnrichmentUITests` (fixture path) stays green.

## Looked fine

Checked and cleared, so coverage is visible:

- **Engine correctness and data loss**: `check`/`uncheck`/`setValues`/`setKind`/`addSet`/`removeSet`/`addExercises`/
  `replaceExercise`/`removeExercise`/`reorderExercises`/`rename`, block edits, supersets, warm-ups: every mutation stamps
  `updatedAt` and saves; structural ones roll back on failure (`commitRollingBack`), value edits keep the typed value
  (JC26); `finish` rolls back deletions and `finishedAt` on a failed save and lets go of the workout only after the save;
  `discard` clears `workout` before the delete and restores it on failure; `ActiveWorkoutEngineSaveFailureTests` covers
  each path. `finishSummary`/`finishDialog` agree (tested). Previous autofill across units rounds to 0.5.
- **Persistence and relaunch**: the in-progress workout is the newest `finishedAt == nil` row; `resume()` at `init`,
  from notification actions and Live Activity intents; an expired rest is cleared on resume without a haptic (R-01); the
  cover reopens from `@AppStorage("workoutCoverWasOpen")`, ignored under `-uiTesting`; `-preview`/`-uiTesting` use an
  in-memory store so a leftover workout is never resumed in tests.
- **Edit past workouts / delete**: `PastWorkoutDraft` is a value draft, `save` applies and rolls back on failure; sets
  and exercises matched by id keep hidden fields; `completedAt` shifts with the start; empty sets and emptied exercises
  are dropped; superset groups of one dissolve. History/detail delete: `context.delete` + save, rollback and an alert on
  failure; the copy says it cannot be undone and no undo is offered (consistent).
- **JSON round-trip**: deterministic export; idempotent import by id with strict last-write-wins, children replaced with
  the parent, relationships by id with dangling counts, unknown library refs reported; Fitness fields round-trip and an
  older file never clears stored Fitness data; decode/version errors read plainly; file read/decode/encode off-main,
  apply on main (models are MainActor).
- **HealthKit enrichment (apart from C-02/C-05)**: opt-in gates every call (`isActive`); `requestAuthorization` only from
  the toggle; one serialised loop (`runningRefresh` + queued flags) so passes never overlap; `turnOff` flips the setting
  first, cancels the follow-up, awaits the in-flight pass, then clears (tests `removeWaitsForAPassInFlight…` and
  `keepLeavesWhatTheInFlightPassApplied` prove the race); claimed Fitness ids are never attached twice; `applyHealth`
  leaves `updatedAt` alone on purpose and the History/detail read kcal/`healthSummary` live from the `@Query` models, so
  enrichment shows without a fingerprint bump; backfill saves every 25; all read types requested up front (JC67); the
  app never writes to Health (the DEBUG `HealthSeeder` is `#if DEBUG`); `NSHealthShare/UpdateUsageDescription` present.
- **Live Activity**: `WorkoutActivityState` is small and Codable; `staleDate = restEndsAt`, `relevanceScore` 1 while
  resting; request/adopt/update/end reconciled with a dirty flag so runs serialise; a burst updates once; a failed request
  retries on the next change; orphans ended at launch; the extension renders timers from dates only and keeps
  accessibility strings static (the documented encode crash is avoided); `LiveActivityIntent`s run in the app, hop to the
  main actor, resume the persisted workout first; `Shared/` has MainActor default isolation in both targets, so
  `ActivityIntentRouter.handler` is actor-isolated.
- **Rest timer and notifications**: `RestTimer` stores an end date and total, never a counter; +10/+30 on an over rest
  restart from now; `tick` grace of 3 s; `.timeSensitive` with the entitlement present; one constant identifier so a plan
  replaces, nil removes pending and delivered, a past plan schedules nothing; actions not `.foreground`; delegate set in
  `App.init` (before launch finishes); `willPresent` returns `[]` in the foreground per DECISIONS.
- **Concurrency**: MainActor default everywhere; `@concurrent` only on file I/O and the stats reader; the `@ModelActor`
  hands back `Sendable` values only; `HealthSource`/`HealthEnrichment` are `nonisolated` and `Sendable`; no
  `nonisolated(unsafe)`, no force casts, no `try!` outside tests, no `DispatchQueue`/`asyncAfter`/`Timer`; long-lived
  tasks live on app-lifetime objects (`HealthEnrichmentService`, `BulkVideoDownload.shared`), view tasks are `.task(id:)`
  and cancel with the view.
- **Duo rules in code**: no `UIScreen`, `UIDevice`, idiom or orientation reads (grep clean); size classes and
  `GeometryReader`/`reservedRegions` only; one `ArrangementView` tree per screen (JC59).
- **Settings**: `SettingsStore` validates ranges on load; `-uiTesting` wipes the defaults domain so runs do not leak.
- **Secrets**: no `op read`, no key material, no `.p8` anywhere in the app or scripts beyond `./dev testflight`.
- **Tests**: Swift Testing throughout the kit and app tests; every `@Test` sampled asserts (one uses a helper
  `expectIdle`); `./dev` fails on an empty filter.
