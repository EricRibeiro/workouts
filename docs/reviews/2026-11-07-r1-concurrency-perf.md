# Full review round 1: concurrency and performance (2026-11-07)

Read-only review of `Workouts/` and `Packages/WorkoutsKit`. Settled calls respected: JC78 (history reads on
`WorkoutStatsReader`), JC80 (notification XPC on a serial queue), JC97 (background actions flush before returning).
Measured: the real `library.json` decode test (`LibraryCatalogTests/decodesRealLibraryFile`, plus `ExerciseStoreTests`
on the real file) takes about 150 ms on this Mac in a debug build. The catalog is 4.2 MB with 1,038 exercises. The old
0x8BADF00D reports in `~/Library/Logs/DiagnosticReports` (2026-11-05) are all the pre-JC80 `removePending` XPC on the
main thread, so they predate the current code. Eric's device crash log is not on this machine.

No `@unchecked Sendable`, no `nonisolated(unsafe)`, no `Task.detached`. There is one `withCheckedContinuation` (it
resumes exactly once; see P3-1 for its missing timeout). The observation loops (`RestNotifier.track`,
`LiveActivityController.track`) re-arm correctly and cancel their debounce tasks.

## P0

### P0-1 The notification response's completion handler runs off the main thread (likely cause of the tap crash)
`Workouts/App/Notifications/RestNotifier.swift:321-327` (and `:313-319`, `willPresent`)

Both delegate methods are `nonisolated … async`. The compiler bridges them to the Objective-C
`…withCompletionHandler:` selector by starting an unstructured task on the global executor. After
`await respond(to:)` hops back off the main actor, the function returns there, so the thunk calls UIKit's completion
handler **on a background thread**. For a notification response, UIKit's completion block asserts the main thread.
The known signature is `NSInternalInconsistencyException: Call must be made on main thread` under
`-[UIApplication _performBlockAfterCATransactionCommitSynchronizes:]`. Async delegate variants have done this since
iOS 15.

Failure scenario: Eric taps the "Rest over" banner, either on a cold launch or with the app suspended. `didReceive`
runs, `openWorkout` fires, the flushes finish, and the process then aborts when the completion handler is called off
main. The Skip and +30 s buttons go through the same path. Nothing tests this: no XCUITest taps a real delivered
notification, and `RestNotifierTests` calls `respond(to:)` directly, so the real delegate thunk has never run under
test.

Confidence: high on the threading, medium that this is Eric's crash. Confirm it from the TestFlight crash log (Xcode
Organizer → Crashes). That log tells P0-1 apart from a watchdog kill (P1-1).

Fix (one worker task): replace both async methods with the completion-handler variants:
`nonisolated func userNotificationCenter(_:didReceive:withCompletionHandler:)` copies `response.actionIdentifier` and
runs `Task { @MainActor in await self.respond(to: action); completionHandler() }`. `willPresent` calls
`completionHandler([])` the same way, on main. Add an XCUITest that runs `-startSampleWorkout -sampleRestSeconds 3`,
sends the app home (`./dev home` equivalent: `XCUIDevice.shared.press(.home)`), waits for the SpringBoard banner, taps
it, and asserts that the cover appears and the app is still running. Proof:
`./dev ui-test RestNotificationTapUITests/testTappingTheRestBannerOpensTheWorkout()`.

## P1

### P1-1 Cold launch with a running workout fetches the whole history on the main thread before the first frame
`Packages/WorkoutsKit/Sources/WorkoutsKit/Session/ActiveWorkoutEngine.swift:39-73` →
`ActiveWorkoutEngine+Support.swift:259-289` (`loadPrevious`), called from `Workouts/App/WorkoutsApp.swift:82`

`ActiveWorkoutEngine.init` calls `resume()`. With a workout in progress, that calls `loadPrevious(for:)`, which fetches
**every** finished workout sorted by date. It then walks each one with `sortedExercises(of:)` and `sortedSets(of:)`,
faulting the relationships one workout at a time, until every exercise in the running workout has been found. An
exercise that is new to this workout, or last done long ago, makes it walk and fault the entire history. That is
roughly two SQL fault round trips per workout plus one per row, all synchronous inside `WorkoutsApp.init`.

A notification tap is the one launch that always has a running workout. With Eric's imported Strong history (hundreds
of workouts) this is the largest item in the launch path, and it is unbounded. It shares `init` with the catalog
decode (P2-1), the `AVAudioSession` category XPC (`WorkoutsApp.swift:226`), opening the container, and the ActivityKit
calls (P2-2). The device launch watchdog allows about 20 s, so one call alone will not reach it, but under memory
pressure or a busy `chronod` or `usernoted` the total can. The same cost hits every check of a newly added exercise
mid-workout (`loadPrevious` for that id) as a visible hitch.

Fix (one worker task): load Previous on `WorkoutStatsReader`, like JC78. Add
`WorkoutStatsReader.loadPrevious(ids:excluding:) async -> [UUID: [PreviousEntry]]`, a `Sendable` value type. Have
`resume()` set `workout` synchronously and start the load in a task the engine owns (cancelled on `resume`, `finish`
and `discard`). The Previous column shows the em-dash placeholder until the result lands. Fetch with a predicate on
`exercises.exerciseID` and a `fetchLimit` per id instead of walking everything. Kit test: a 600-workout store resolves
Previous for an exercise that is absent from the history without faulting each workout (assert the results; time it
with `ContinuousClock`). Proof: `./dev kit ActiveWorkoutEnginePreviousTests`.

## P2

### P2-1 The 4.2 MB catalog is decoded and sorted synchronously in `WorkoutsApp.init`
`Workouts/App/WorkoutsApp.swift:73-76`, `Packages/WorkoutsKit/Sources/WorkoutsKit/Library/LibraryCatalog.swift:136-141`,
`ExerciseStore.swift:87-104`

Every launch decodes all 1,038 exercises on the main thread, with full descriptions, instructions, tips and mistakes.
That took about 150 ms on an M-series Mac in debug. An iPhone in a cold, memory-pressured launch will take noticeably
longer. `ExerciseStore.rebuild` then runs a locale-aware sort and folds every name and alias. Most of that text is read
only on the About segment.

Fix (one worker task): first add `os_signpost` intervals around each step of `WorkoutsApp.init`
(audio, container, catalog, store, engine) and record the numbers in this file from an App Launch trace on the device.
If the catalog is above about 100 ms on the device, split `library.json` at build time (`scripts/build-library`) into a
launch index (id, name, aliases, weight type, flags) and a details file that `LibraryCatalog` decodes lazily on the
first `exercise(id:)` detail access. Proof: `./dev kit LibraryCatalogTests`.

### P2-2 ActivityKit's synchronous XPC calls run on the main actor during launch
`Workouts/App/Activity/LiveActivityController.swift:41, 44, 50-54, 255`; `WorkoutsApp.swift:84-88, 213-219`

`observe(_:)` starts `reconcile()` from `init` on the main actor. `apply()` reads `Activity.activities` (`existing`),
then each handle's `activityState`, then `ActivityAuthorizationInfo().areActivitiesEnabled`, and may call
`Activity.request`. Each of these is a synchronous round trip to `chronod`, run on the main thread before or around the
first frame. On a notification-tap cold launch, when the activity was ended by the system (the 8-hour limit) or the
person turned Live Activities off, this path requests a new activity. JC80 fixed the same class of watchdog for
`UNUserNotificationCenter`.

Fix (one worker task): make `SystemLiveActivityProvider`'s `existing`, `areActivitiesEnabled` and `request` `async`,
and run them through a `nonisolated` helper so the XPC leaves the main thread. `Activity` is `Sendable`. Wrap the
results on main. Update the `LiveActivityProviding` fake in `LiveActivityControllerTests`. Proof:
`./dev test LiveActivityControllerTests`.

### P2-3 Finish computes the PR summary by faulting every past workout on the main thread
`Packages/WorkoutsKit/Sources/WorkoutsKit/Session/ActiveWorkoutEngine+Support.swift:305-325` (`historySessions`), called
from `finish`

Tapping Finish fetches every finished workout and walks all their rows and sets on the main actor to build `Session`s
for the PR comparison. With 600+ workouts that is a hitch of hundreds of milliseconds to seconds, while the cover is
dismissing. JC78 moved the History and detail reads off main, but this one was missed.

Fix (one worker task): move `historySessions` to `WorkoutStatsReader`, fetching only rows whose `exerciseID` is in
`ids`. `finish()` saves synchronously, and the summary's PR section is filled in when the reader returns (the summary
sheet only appears after the cover closes, so it is usually ready by then). Proof: `./dev kit FinishSummaryTests` (or
the engine finish suite).

### P2-4 Exercise detail derives its sessions, records and history on the main thread
`Workouts/Features/Exercises/ExerciseDetailView.swift:87-104` (and `Fingerprint.init`, `:250-258`)

`.task(id: Fingerprint)` runs `ExerciseBestSets.sessions(forRows:)`, `records` and `ExerciseHistory.sessions` on the
main actor over every row of this exercise. For a staple lift with years of history that is thousands of set faults
plus the folding work. It runs when the exercise detail opens, including the logging cover's exercise pane on the
open Duo, where it competes with the set table. `Fingerprint.init` also walks all rows and their workouts
(`$0.workout?.updatedAt`) on every body evaluation.

Fix (one worker task): add `WorkoutStatsReader.loadExerciseDetail(exerciseID:weightType:options:)`, which returns
`(sessions, records, history)` as `Sendable` values, as History does. Key the task on the `newestFinishedEdit` stamp
plus the generation (`FinishedWorkoutsStamp`) instead of folding `rows`. Proof: `./dev test ExerciseDetailTests` (or
`./dev kit WorkoutStatsReaderTests` for the reader).

## P3

### P3-1 `SystemNotificationCenter.flush()` has no timeout
`Workouts/App/Notifications/RestNotifier.swift:87-91`. If `usernoted` never answers one `add`, `pendingCalls` never
empties and a background Skip or +30 s never returns. The system then kills the app for exceeding its background-time
assertion. Fix: race the continuation against a 5 s `Task.sleep` and log a timeout. Proof: `./dev test RestNotifierTests`.

### P3-2 Every rest-plan sync spawns an authorization-status XPC for the whole session
`RestNotifier.swift:263-275`. `didRequestAuthorization` is set only in the `.notDetermined` branch, so on a device
that is already authorized (every launch after the first) each debounced sync starts a task that calls
`authorizationStatus()` and `requestAuthorizationIfNeeded()`. That is two extra XPC round trips per check or rest
change. Fix: keep a `hasCheckedAuthorization` flag that is set after the first look, whatever the answer. Proof:
`./dev test RestNotifierTests`.

### P3-3 History's body walks every finished workout four times on each keystroke
`Workouts/Features/History/HistoryView.swift:87-93, 131-137, 213-224`. Typing in History search re-evaluates `body`:
`Inputs(finished…)` (ids map plus the max `updatedAt`), `activeKcalByWorkout`, `avgHeartRateByWorkout`,
`weekActiveCalories` and `weekAverageHeartRate` each loop over every model. With 600 workouts that is thousands of
SwiftData getters per character. Fix: put kcal, bpm and the week totals into `WorkoutStatsReader`'s history summary.
The `Inputs` key can use the `newestFinishedEdit` stamp plus a `fetchCount` instead of every id. Proof:
`./dev test HistoryViewTests` plus the History snapshot suite.

### P3-4 The media cache is walked in full after every fetched video
`Packages/WorkoutsKit/Sources/WorkoutsKit/Media/MediaStore.swift:133, 252-271`. `evict(keeping:)` enumerates the
whole `media/` tree after each download, so "Download all videos" costs O(n²) file stats (about 1,000 videos × up to
2,000 files). It holds the actor, so a detail screen's `video(for:)` cache hit waits behind the walk. Fix: keep a
running byte total in the actor, seeded by one walk, and walk again only when it crosses the cap. Proof:
`./dev kit MediaStoreTests`.

### P3-5 Bulk-download resume checks about 1,000 files on the main thread at every activation
`Workouts/App/RootView.swift:119-125` → `ExerciseMedia.swift:316` (`uncachedSourceIDs`, a `nonisolated` synchronous
`fileExists` per id). With "Download all videos" on, this runs on main at every `.active`, including the cold
notification launch. Fix: compute `missing` inside the task (`await store.uncachedSourceIDs` on the actor) before
showing the bar. Proof: `./dev test BulkVideoDownloadTests`.

### P3-6 Not verified: whether `TabView` evaluates the History tab's `@Query` at launch
`HistoryView.swift:25-29` fetches every finished workout without a limit. If iOS evaluates non-selected tab bodies when
the `TabView` is built, that fetch joins the launch path even though Workout is the default tab. Check it in the App
Launch trace from P2-1, and if so gate the query behind the tab's first appearance.
