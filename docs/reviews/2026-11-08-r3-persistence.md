# Review round 3: persistence and Health (2026-11-07)

Read-only code review. Scope: Kit `Model/`, `Health/`, `Session/ActiveWorkoutEngine*.swift` (saves/rollbacks), `Workouts/App/WorkoutsApp.swift`, `RootView.swift` (scene-phase commit, cover restore, finish hook), `Shared/SaveErrors.swift`, `History/DeleteFailure.swift` + both delete call sites, `Settings/DataTransfer.swift` + `SettingsFlow.swift` import/Fitness paths, `Features/Health/*`.

Not re-reported: r1 P-01..P-06 (incl. P-05, shared-`mainContext` rollbacks outside the engine), r1 Health P3-1..P3-4, r2 R2-xx.

## Findings

| # | Sev | Where | Failure scenario | Fix direction |
|---|---|---|---|---|
| R3-P1 | P3 | `Kit/Health/HealthEnrichmentRun.swift:96-100` (`backfill(context:)`) with `:119-122` (pre-`earliest` workouts dropped, never stamped); called on every foreground from `HealthEnrichmentService.appBecameActive` (`HealthEnrichmentService.swift:94-96`, `RootView.swift:127`) | Eric's history arrives by JSON import (years of workouts, `healthCheckedAt == nil`). iOS 27 shares only the past 30 days by default, so every workout older than that is filtered out and never stamped (on purpose). So `fetchCount(backfillCandidatesDescriptor) > 0` holds for good. Each time the app comes to the foreground it fetches every one of those `Workout` models on the main actor, calls `earliestReadableDate()`, and then drops them all. That breaks the doc's promise ("cheap once everything has been stamped", `:88-89`) and costs time on every foreground, growing with the history. `refreshNow`/opt-in `resetUnmatched` pushes even more rows into this permanent pile. | Ask `source.earliestReadableDate()` first and add `startedAt >= earliest` to the candidate predicate (and to the `fetchCount`). Out-of-range rows then cost nothing. |
| R3-P2 | P3 | `Kit/Health/HealthEnrichmentRun.swift:207-214` (`clearAll`), also `:194-201` (`resetUnmatched`); surfaced by `SettingsFlow.swift:160-170` | The person turns Apple Fitness off and picks Remove. `clearAll` clears every workout's Fitness fields in memory, then `save()` throws. The alert says "Could Not Remove Fitness Data", but the cleared fields stay dirty in the shared main context. The next unrelated save (checking a set, `commitEdits` on going inactive) commits the removal anyway. The opposite also happens: a later rollback elsewhere silently brings the data back. Either way, what the alert said does not match what is stored. | Unlike every other kit writer, these do not undo themselves on failure. Either restore the touched workouts' values on failure (snapshot before mutating), or follow the kit pattern (`rollback()`). The second carries the known P-05 shared-context caveat, so the snapshot restore is the cleaner fit. |
| R3-P3 | P3 | `Workouts/Features/Health/HeartRateChart.swift:45-47` (`points` clamps `offset < 0` to 0); offsets go negative by design (`Kit/Health/HealthEnrichment.swift:38-41`, matcher `slackBefore` 10 min) | The Watch workout starts a few minutes before Start is tapped in the app, which the matcher allows. Every heart-rate sample from those minutes gets offset 0, so the line draws a vertical spike at the left edge (the bpm range of the warm-up, stacked). Scrubbing at x=0 picks an arbitrary one of those points (`:86`). | Drop the points before 0. Keep at most one point at 0 (the last one before 0, or a value interpolated with the first one after). Do the same at the far end if needed. |

## Nits

- **N1.** `SettingsFlow.swift:100-103` (`refreshAfterImport`) re-checks the engine only when `engine.workout == nil`. A file that carries the running workout's own id with a newer `updatedAt` (finished, or with different sets) would finish or rewrite it under the open cover. That needs two devices, so today it is a PLAN 8 path. Calling `engine.reloadAfterRemoteChange()` instead of the `== nil` guard would close it at no cost.
- **N2.** `HeartRateSeries.downsample` (`HeartRateSeries.swift:28`): `bucket.contains(peak)` uses value equality, so two samples with the same offset and bpm as the peak in different buckets would both emit `peak` (a duplicate point). Unreachable in practice, since offsets are distinct.

## Checked and sound

- **One in-progress workout.** `refuseIfRunning` checks the store, not the engine field. `begin` rolls back the inserted workout on failure. `settleExtraInProgress` runs on every `resume`. Import skips a second unfinished row (`Importer.swift:363-370`) and demotes others by Finish's rule.
- **Relaunch restore.** `resume()` in `init`, best-effort clearing of an expired rest, `restoreCover` keyed on `coverWasOpen && engine.workout != nil`. Typed values are committed on every non-active scene phase (`RootView.swift:115`).
- **Engine saves.** `commitRollingBack`/`rollbackKeepingEdits` keep pending typed values across a failed structural edit. `finish` and `discard` restore `workout` on failure. A Health pass that saves the shared context mid-workout only persists those typed values early. That is harmless: `pendingEdits` stays consistent.
- **Delete cascades.** Workout → exercises → sets cascade; Template → exercises → sets cascade; Template → workouts nullify; Folder → templates cascade. A custom exercise is deletable only when unreferenced, and its sticky notes go with it. Both workout delete sites roll back and show `DeleteFailure`.
- **Health.**
  - Opt-in is enforced at every entry (`isActive`). `turnOff` order is right: setting off, follow-up cancelled, queue cleared, loop cancelled and awaited, then cleared, with a re-enable re-check. `request` waits out a cancelled loop instead of queuing onto it.
  - `process` reads model values only before awaits and re-checks liveness, window and stamps before writing, so a delete or a past-workout time edit during a lookup is safe.
  - Claimed ids stop one Fitness workout from attaching to two of ours. `applyHealth(nil)` never erases a stored match. Fitness writes leave `updatedAt` alone.
  - The read-only `requestAuthorization(toShare: [])` in release; the seeder is `#if DEBUG`.
- **Threading.** Export builds its own `ModelContext(container)` in an `@concurrent` function after flushing the main context on the main actor. Health runs on the main actor with only `Sendable` values crossing to the nonisolated source.

VERDICT: NITS-ONLY
