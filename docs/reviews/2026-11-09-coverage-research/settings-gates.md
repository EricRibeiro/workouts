# Settings coverage and `-uiTesting` gates (read-only research)

Method: `xcrun xccov view --archive --file <path> .build/results/latest-{ui-test,test}.xcresult` (note `--archive`; without it the bundle is "unrecognized file format"). Bundles are from 8 Nov; `SettingsFlow.swift` last changed 6 Nov, so line numbers match.

## 1 Current state

### Gap A: `SettingsFlow.swift`
Uncovered in the UI run (count 0), by behaviour:

| Lines | Behaviour | Unit run | Reached by |
|---|---|---|---|
| 46-58 | `runImport`: sets `isImporting`, wraps `performImport` in a `Task` | 0 | Import button after the file picker returns |
| 70-91 | `performImport`: read/apply failure → "Could Not Import"; success → bump generation, summary, backfill; refresh failure → note appended | covered (`SettingsFlowTests`, 3 tests) | `runImport` |
| 99-102 | `refreshAfterImport`: `exerciseStore.setCustom`, `engine.resume()` when no workout is running | **0** | only `runImport` (the tests pass `refresh:` closures) |
| 165-168 | `turnOffFitness` catch → "Could Not Remove Fitness Data" | **0** | `HealthEnrichmentService.turnOff` throwing, i.e. `HealthEnrichmentRun.clearAll` failing a SwiftData save |

- Everything else is covered by the UI run: the video alert paths (117-133, 143-151), `requestAuthorization` (154-156) and the Fitness turn-off (160-164, 169-171). The unit run covers only `performImport`.
- Not in this file: iCloud states (the row is a separate view; `SettingsUITests.swift:76-79` checks only that the row exists), the file-picker `.failure` branch (`SettingsView.swift:66-70`), and the export (a `ShareLink`; `SettingsUITests.swift:~200` opens the sheet).
- `SettingsUITests` (`WorkoutsUITests/SettingsUITests.swift:178-179`) says outright that the file pickers cannot be driven reliably, so import has no UI test by design. `ImportExportFlowTests` in the kit covers the data round trip.
- Combined unit + UI, still never run: `runImport` (46-58), `refreshAfterImport` (99-102) and the `turnOffFitness` catch (165-168). That is about 21 lines. `DataTransfer` lives in the app target (`Workouts/Features/Settings/DataTransfer.swift`); `ImportReport`, `MediaStore`, `ExerciseStore` and `ActiveWorkoutEngine` are in the kit.

### Gap C: `WorkoutLinkRouter.swift`
- 17% = only line 14 (the `isPending` property). `request()` (line 16) and `consume()` (lines 19-22) are 0 in both runs.
- `OpenWorkoutURLUITests` goes through `RootView.swift:72-74`: `.onOpenURL` → `openWorkoutLink()` directly, bypassing the router.
- The router is fed only by `notifier.openWorkout = { links.request() }` (`WorkoutsApp.swift:79`), i.e. a tap on the rest notification body, consumed at `RootView.swift:76-78`.
- So the uncovered branch is the notification-tap and cold-launch-pending path, which is the router's reason to exist.

### Gap B: gates
`grep` finds eleven `"-uiTesting"` checks. The doc table has eight, and all eight line numbers have drifted. The new ones are `HealthLookupProbe.swift:9`, `RestExpirySeam.swift:22` and `RestExpirySeam.swift:47`.

## 2 Options (Gap A, per behaviour)

**A1. Make `runImport` awaitable** (`@discardableResult … -> Task<Void, Never>`). Test: `flow.runImport(file, …)` → `#expect(flow.isImporting)`, `await task.value`, `#expect(!flow.isImporting)` and the outcome. Proves the flag lifecycle (the Import button's disabled state); cannot prove the button itself. ~0.5 h, no flakiness. Pattern: `HealthEnrichmentService.followUp` is already exposed so tests await it.

**A2. Test `refreshAfterImport` directly.** Drop `private`. Test: import an export holding an unfinished workout and a custom exercise into an in-memory container with a real `ActiveWorkoutEngine` and `ExerciseStore` (as other WorkoutsTests do), then assert `exerciseStore` has the exercise and `engine.workout != nil`; run it a second time with a workout already running and assert it is untouched. ~1 h. Proves the "imported unfinished workout shows at once" rule from the comment at lines 93-94.

**A3. Seam for the removal-failure alert**, in the style of `performImport(refresh:)`:
```swift
func turnOffFitness(removeData: Bool, health: HealthEnrichmentService, context: ModelContext) {
    Task { await performTurnOff { try await health.turnOff(remove: removeData, context: context) } }
}
func performTurnOff(_ work: () async throws -> Void) async {
    do { try await work() } catch { outcome = .init(title: "Could Not Remove Fitness Data", message: error.localizedDescription) }
}
```
Test: a throwing closure sets the outcome; a succeeding one leaves it nil. ~0.5 h. It cannot prove that `turnOff` really throws on a failed save, because forcing a SwiftData save failure is not worth building.

**A4. UI proof of the import wiring** (optional): a DEBUG `-importFile <fixture>` argument that feeds a bundled JSON to the same `runImport` the picker calls. A `SettingsUITests` test then asserts alert "Import Complete", `settings.transferOK` and the Import button's disabled state. It also proves the backfill, since `debug.health.lookups` increments with `-healthFixture full -healthEnrichmentEnabled YES`. It bypasses the picker, which is the one part that stays manual. ~2 h; low flakiness. The gain over A1+A2 is only the alert and view wiring, so I would defer it.

**A5. Router unit test** (Gap C): `request()` then `consume()` is true and then false; `consume()` alone is false; `request()` twice then one `consume()` is true then false. Add a RestNotifierTests case that `didReceive` calls `openWorkout`, if one is missing. ~0.3 h. A UI test cannot tap a delivered notification on the simulator reliably, so unit is the right level. It does not prove the `RootView` cold-launch consumption (lines 76-78); that needs a manual device check.

**Kit move:** `SettingsFlow` itself should stay in the app (it needs `BulkVideoDownload` and `HealthEnrichmentService`, both app-side). Moving `DataTransfer` (read, apply, error message) and the "bytes == 0 → just turn off, else confirm" decision (lines 119-131) into WorkoutsKit would make them `./dev kit` tests (~1 s). It is a refactor of ~100 lines for little new coverage, so I would only do it if `DataTransfer` changes again.

## 2b Gap B: draft of the updated section 6 table
(rows renumbered to current lines; the "Proves" column is new)

| file:line | What it does | Fixture / launch arg | UI suite proves | Status |
|---|---|---|---|---|
| `WorkoutsApp.swift:58` | Clears the app's UserDefaults domain at launch | args override the cleared defaults | n/a | Test isolation, not a feature gate. |
| `WorkoutsApp.swift:158` | In-memory store instead of the CloudKit-capable one (also for `-preview`) | none | "off" | Manual-only (persistence/sync: kit tests, device runs). |
| `WorkoutsApp.swift:274` | No Live Activity unless `-liveActivity` | `-liveActivity` exists, **but no UI test passes it** | "off" | Change: the old "fixture exists for the one test that needs it" is wrong. Say Live Activity is covered only by `LiveActivityControllerTests` and device runs. |
| `RootView.swift:224` | Ignores the stored "cover was open" flag at launch | `-openWorkoutCover` (2 UI files) | correct (forced open) | Kept on purpose. |
| `HealthEnrichmentService.swift:73` | No real HealthKit (nil source) | `-healthFixture <name>` (6 suites) | correct via fixture | Real `HealthKitSource` manual-only. |
| `ExerciseMedia.swift:23` | No video fetching | `-mediaSource fixture[:ms]` + `-videoCache …` | correct for progress and turn-off (`SettingsUITests`) | CloudKit source manual-only. |
| `ExerciseMedia.swift:178` | Hero start/end cross-fade off | none | "off" | Manual-only. |
| `ExerciseRow.swift:116` | List-row thumbnail cross-fade off | none | "off" | Manual-only. |
| **new** `HealthLookupProbe.swift:9` | **Adds** a zero-size `debug.health.lookups` element (fixture lookup count) | read by `HealthEnrichmentUITests` | proves "no lookup ran when off" (asserts `0`) | Test seam (turns something on); only that one suite reads it. |
| **new** `RestExpirySeam.swift:22` | **Adds** a Darwin-notification listener that expires the running rest | `XCUIApplication.expireRestNow()` (ResumeControl, RestRing) | correct for the over/grace/forget path with the real watchers | Test seam; wall-clock expiry itself is not exercised. |
| **new** `RestExpirySeam.swift:47` | **Adds** the `debug.restState` probe (`none`/`running`/`over`) | read by `ResumeControlUITests` | state machine | Test seam. |

Also update: Section 2C says "six gates" (now eleven, in three kinds: 8 features/isolation turned off, plus 3 seams that turn something on), and the section 6 intro should say "line numbers as of <date>".

## 3 Recommendation
1. A3 + A5 first (about 0.8 h): they close the two silent error/launch paths, and Gap C is a pure unit target.
2. A1 + A2 (about 1.5 h): they cover the rest of `SettingsFlow` that UI cannot reach. Expected result: 0-lines in the file drop to nothing but the `Task {}` bodies.
3. Update the doc table above (15 min), including the `-liveActivity` correction.
4. Defer A4 and the kit move. UI proof of import is mostly alert wiring, and the picker stays manual either way.
5. Gap C does not matter for the Live Activity link (that path is covered by `OpenWorkoutURLUITests`); it matters only for notification taps, so A5 is enough.

## 4 Open questions for Eric
- Is a DEBUG `-importFile` seam acceptable, or does the rule "the picker stays manual-only" mean you want the import UI left unproven?
- Should Live Activity get one UI test using `-liveActivity`, or is it intentionally device-only? The doc currently implies a test exists.
- OK to make `refreshAfterImport` and `runImport`'s return value internal for tests, or do you prefer closure seams everywhere (as `performImport(refresh:)` does)?
- Is a notification-tap check on a device before release enough for `RootView.swift:76-78`?
