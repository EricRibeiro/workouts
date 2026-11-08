# Full review round 1: Live Activity, notifications, Health (2026-11-07)

Read-only. Scope: `RestNotifier` / `SystemNotificationCenter`, `LiveActivityController`, `EngineActivityIntentHandler` and
`Shared/ActivityIntents.swift`, `RestExpiryWatcher`, `HealthEnrichmentService` + `HealthEnrichmentRun`, `WorkoutsApp.init`
and `RootView`'s scenePhase / link handling. Settled headings in `DECISIONS.md` and JC1–JC110 are not re-opened.

## How the build actually isolates things (checked, not assumed)

The app target builds in **Swift 5 language mode** (`SWIFT_VERSION = 5.0`) with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
and approachable concurrency. `AGENTS.md` says "Swift 6 strict concurrency is on"; the build settings say otherwise. This
matters for the crash hunt:

- A probe compiled with `-swift-version 6 -default-isolation MainActor` that copies `SystemNotificationCenter.flush()`
  traps (exit 133, SIGTRAP): `DispatchGroup.notify(queue:execute:)` takes a **non-`@Sendable`** closure
  (SDK `Dispatch.swiftinterface`), so `{ continuation.resume() }` is inferred `@MainActor` and Swift 6 checks it on
  `Self.queue`. With `{ @Sendable in ... }` the probe passes.
- In the real build (Swift 5 mode) that check is **not emitted**: disassembly of `RestNotifier.o` shows the closure calls
  only `CheckedContinuation.resume`, and across every `Workouts` / `WorkoutsLiveActivity` object file the only
  `swift_task_isCurrentExecutor` calls are in `deinit`s and one `MainActor.assumeIsolated` (HingeLogger, debug).

So a Swift executor-assertion trap is **ruled out** as Eric's crash today, but `flush()` is a latent trap that fires the day
the target moves to Swift 6 mode (P2-3 below).

## Every path a rest-notification tap takes

| Path | Sequence |
|---|---|
| Cold, body tap | `App.init`: `RestNotifier.activate()` (categories queued, delegate set synchronously) → container, catalog, engine `resume()` (clears the over rest: `clearIfExpired`) → `observe` → LA `observe`. After launch UIKit calls the ObjC `didReceive…withCompletionHandler:`; the Swift `@objc` thunk starts a task (`_runTaskForBridgedAsyncMethod`) on the global executor → hop to main `respond(to:)` → `openWorkout` → `WorkoutLinkRouter.request()` → `syncNow()` (sync plan nil + `flush()` XPC wait) → `activityController.syncNow()` (ActivityKit update) → back on the **global executor**, the thunk calls UIKit's completion handler. Meanwhile `RootView` appears: `restoreCover` (may present) and `onChange(links.isPending, initial: true)` (opens), scenePhase `.active` → bulk video resume + Health `appBecameActive` (backfill fetch of every finished workout). |
| Warm, cover open | Same response path; `openActiveWorkout` is a no-op. The cover's `RestExpiryWatcher` task wakes late, `shouldBuzz` false, `tickRest()` saves. |
| Warm, minimised | Same; `openActiveWorkout` presents the cover; `ResumeControl` hands the watcher job to the cover. |
| Warm, Settings/finish sheet up | `openWorkoutLink` closes the sheet, opens the cover from `onDismiss`. |
| Container failed | Engine nil: `handleAction` returns, `openWorkout` sets a request nobody reads. Safe. |

No double resume (one `notify` per `flush`), no model access before the container exists (the delegate only gets
responses after `didFinishLaunching`, after `App.init`), and `activityState` / `restTimer` go through `liveWorkout`
(deleted/detached guard).

## Crash candidates, ranked by likelihood

1. **P1-1 (most likely): the `didReceive` completion handler is called off the main thread.** See below.
2. **P2-1: cold-launch / activation work on the main thread at the moment of the tap** (watchdog or a long hang that
   looks like a crash). Likelier only with the Health opt-in on and a large imported history.
3. **P2-2: `HealthEnrichmentRun.process` reads models that may have been deleted during its first `await`.** Real
   SwiftData fatal-error class, but needs a delete in History during a sub-second window.
4. **P2-3: `SystemNotificationCenter.flush()` closure isolation.** Not live in Swift 5 mode (proved above); listed so the
   language-mode change does not turn every notification action into a crash.

## Findings

### P1

**P1-1. Async `didReceive` returns UIKit's completion on a background thread** —
`Workouts/App/Notifications/RestNotifier.swift:321-327` (`nonisolated func userNotificationCenter(_:didReceive:) async`).

The disassembly shows the `@objc` thunk runs the method in a bridged task; the method is `nonisolated`, so after
`await respond(to:)` (main) it resumes on the global executor and the generated code calls UIKit's completion block from
there. UIKit's notification-response handling for a **foreground-opening** response (a body tap, which transitions the scene)
is main-thread-only; the async delegate variants have a long record of crashing with an `NSInternalInconsistencyException`
"Call must be made on main thread" when the completion lands off main (stated from framework history, not reproduced here:
no test can tap a banner, JC94). That matches the report exactly: the crash is on "tap the rest-over notification to return
to the app"; Skip / +30 run in the background without a scene transition, which would explain why actions never crashed.
It is also the one path no automated test executes (unit tests call `respond(to:)` directly; UI tests never tap a banner),
which is why it was never seen in the simulator.

Scenario: rest ends with the phone locked, Eric taps the banner, the app comes forward, `respond` finishes (~tens of ms
of XPC + ActivityKit), completion on a cooperative thread, UIKit asserts, app dies right as it opens. Cold or warm.

Fix (one worker task): replace both async delegate methods with the completion-handler variants, `nonisolated`, that hop to
main and call the handler there:
`Task { @MainActor in await self.respond(to: id); completionHandler() }` (and `completionHandler([])` for `willPresent`).
Prove: a unit test in `RestNotifierTests` that calls the `withCompletionHandler:` variant and asserts the handler runs on
the main thread (`Thread.isMainThread`) and after `respond`'s effects; `./dev test RestNotifierTests`. Then one manual tap on
device from TestFlight, cover open and minimised, warm and cold.

### P2

**P2-1. Main-thread work at a notification-tap launch or activation** — `Workouts/App/WorkoutsApp.swift:69-81`,
`Workouts/App/RootView.swift:114-128`, `Workouts/Features/Health/HealthEnrichmentService.swift:94-96,180-198`.

Cold: `App.init` opens the store, decodes the bundled catalog, fetches custom exercises and runs `resume()` (Previous
values over history) synchronously before the first frame. Every activation (including each return from a banner tap):
`appBecameActive` queues a backfill whose `allFinishedDescriptor()` fetch faults **every finished workout** on the main
context and `process` maps `healthWorkoutID` over all of them, even when nothing is unchecked. With Eric's imported
history this is a visible hitch exactly when the cover is animating in; under load a cold launch can approach the
watchdog (the 0x8BADF00D that 82e751c fixed for XPC). Fix: make the backfill fetch only candidates
(`#Predicate { finishedAt != nil && healthWorkoutID == nil && healthCheckedAt == nil }`), take `claimed` from a separate
fetch of `healthWorkoutID != nil` with `propertiesToFetch`, and skip the backfill entirely when the candidate count is 0
(`fetchCount`). Kit change + test in `HealthEnrichmentRunTests`; `./dev kit HealthEnrichmentRunTests`.

**P2-2. `process` reads models after an `await` before the liveness guard exists** —
`Packages/WorkoutsKit/Sources/WorkoutsKit/Health/HealthEnrichmentRun.swift:85-93`.

`await source.earliestReadableDate()` runs first; only then are `pending.filter { $0.startedAt >= earliest }`,
`all.compactMap(\.healthWorkoutID)` and `stored = pending.map { $0.modelContext != nil }` evaluated. A workout deleted and
saved (History swipe-delete, or an import that replaces rows) while that await is suspended is read detached, and worse, its
`stored` flag is computed as `false`, so the later `isLive(_, wasStored:)` guard treats it as "never stored" and reads
`finishedAt` and writes `applyHealth` on a detached model: SwiftData's "backing data could no longer be found" fatal error.
Fix: compute `stored` and snapshot `startedAt` / `healthWorkoutID` (Sendable values) before the first `await`, and filter
with `isLive` after it. Test: a fake source whose `earliestReadableDate` deletes and saves one workout; the pass must skip it.
`./dev kit HealthEnrichmentRunTests`.

**P2-3. `SystemNotificationCenter.flush()` closure is main-actor-inferred** —
`Workouts/App/Notifications/RestNotifier.swift:87-91`.

`DispatchGroup.notify` takes a non-`@Sendable` closure, so under default MainActor isolation `{ continuation.resume() }` is
`@MainActor` but runs on `Self.queue`. Harmless in Swift 5 mode, a guaranteed trap on every `syncNow()` (each notification
action, each Live Activity button) in Swift 6 mode (probe above). Also worth noting: `AGENTS.md` claims Swift 6 strict
concurrency while every target is `SWIFT_VERSION = 5.0`. Fix: `{ @Sendable in continuation.resume() }` (or mark the
class `nonisolated`, its state is all static and queue-confined); one line. Proof: `./dev test RestNotifierTests` plus a
note in the commit; correcting the AGENTS line is the orchestrator's call.

**P2-4. Notification fire time drifts by the XPC queue delay** — `RestNotifier.swift:199-215`, `56-69`.

`remaining` is computed on main at sync time, but the request goes through the serial queue introduced in 82e751c; a
`UNTimeIntervalNotificationTrigger` starts counting when the daemon receives it. When the daemon is slow (the very
condition that queue exists for) the "Rest over" alarm fires late by however long the queue was backed up, while the Island
and ring show 0:00 on time. Fix: recompute the interval inside the queue block (`plan.fireDate.timeIntervalSinceNow`,
skip if ≤ 0) by passing the fire date to `schedule` instead of a prebuilt trigger. Test with the fake center:
the request built at drain time carries the shorter interval. `./dev test RestNotifierTests`.

### P3

- **P3-1. Stale "Rest over" can outlive a skipped-then-ended rest** — `RestNotifier.swift:198-201`: a plan already in
  the past removes the pending request but not the delivered one. Harmless when it is the same rest (it did fire), but after
  `extendOrRestartRest` from a stale state a delivered banner of the old rest stays in Notification Center next to the live
  one. Fix: `removeDelivered` on every non-nil plan as well. Kit-free, one test.
- **P3-2. `currentPosition` force-unwraps `latest!`** —
  `Packages/WorkoutsKit/Sources/WorkoutsKit/Activity/WorkoutActivityState.swift:174`. Safe by short-circuit, but against
  the no-force-unwrap rule; rewrite with `if let`.
- **P3-3. `activeWorkout()` does not use `liveWorkout`** —
  `Packages/WorkoutsKit/Sources/WorkoutsKit/Session/ActiveWorkoutEngine+Support.swift:89-92`: every rest/intent mutation
  writes to `workout` without the deleted/detached check the readers use. Unreachable today (sync off, discard clears
  `workout` first); becomes reachable with CloudKit (PLAN 8.1) when a remote discard deletes the row. Fix: guard on
  `liveWorkout`, throw `noActiveWorkout`; kit test.
- **P3-4. `-uiTesting` "sync plan=nil" log** is expected, not a bug: the in-memory store has no workout at launch, so
  `observe` syncs a nil plan (remove pending + delivered). No action.

## Checked and fine

- Live Activity cleanup: `apply()` ends every activity when the engine has no workout (finish, discard), adopts a leftover
  of the same workout at launch, drops system-ended ones and respects a dismissal; container failure ends them in `init`.
- Intent buttons vs the app: all mutations hop to the main actor through `ActivityIntentRouter`; `resumeIfNeeded` covers a
  background cold launch; a stale Done set id is a no-op; `flush()` awaits both the notification queue and ActivityKit.
- Rest expiry: two wall-clock sleeps, no buzz after a late wake, cancel on `endsAt` change; relaunch clears an over rest.
- Health opt-in/opt-out ordering, cancellation and the deleted-workout guard inside the loop (outside P2-2's window).

Not covered in depth (budget): `HealthKitSource` continuation code and the widget views; the intents were read only at the
router level.
