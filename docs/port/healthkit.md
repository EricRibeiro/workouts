# HealthKit read-only enrichment: how to test it (PLAN 7.1b-a)

Feature: after Eric finishes a workout, read the overlapping Apple Fitness "Functional Strength Training" `HKWorkout`
(written by his Apple Watch) and store active/total energy, average/max heart rate and duration on our `Workout`.
Read-only.

Note: `docs/PLAN.md` section 1 and `CLAUDE.md` currently list HealthKit as a non-goal ("Eric starts his Fitness workouts in
Apple's app"). This feature reverses that; both need updating when 7.1b is accepted.

Legend: **[observed]** = I ran it on the iPhone Duo simulator (iOS 27.2, Xcode 27.2) with a throwaway spike
(reverted). **[doc]** = Apple documentation or SDK header quote. **[inference]** = reasoned, not run.

## 1. Availability on the simulator

- `HKHealthStore.isHealthDataAvailable()` returns `true` on the Duo simulator **[observed]**, even without the HealthKit
  entitlement. Every other call without the entitlement fails with `HKError` code 4 "Missing com.apple.developer.healthkit
  entitlement." **[observed]**, so the entitlement is enforced on the simulator too.
- The Health app (`com.apple.Health`) and Fitness (`com.apple.Fitness`) are installed on the Duo simulator
  (`xcrun simctl listapps`) **[observed]**. The Health daemons (`healthd`, `healthappd`) run.
- Before the user answers the prompt, queries throw `HKError` code 5 "Authorization not determined" **[observed]**.
  After a read grant, `authorizationStatus(for:)` is meaningless for read access (it reports sharing only; [doc]
  `authorizationStatus(for:)`: "your app cannot determine whether or not a user has granted permission to read data");
  a denied read looks like "no data".

## 2. Granting authorization in tests

- **`simctl privacy` cannot grant Health.** The service list is: all, calendar, contacts-limited, contacts, location,
  location-always, photos-add, photos, media-library, microphone, motion, reminders, siri **[observed, `xcrun simctl
  privacy` help]**. `grant health` fails with "Failed to create TCC authorization record / Operation not permitted", and so
  does any bogus service name, so `health` is simply not a service **[observed]**. No `HKHealthStore` test hook exists
  that I found (nothing in the SDK interface or docs search).
- **The prompt is drivable by XCUITest.** The sheet is a separate process, bundle id `com.apple.HealthPrivacyService`
  (window title "Health Access"). `XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")` sees it
  directly **[observed]**; I did not try `addUIInterruptionMonitor` (not needed, and the sheet is not a SpringBoard alert).
  It has two pages **[observed]**:
  1. Topics page. Identifiers: `UIA.Health.AuthSheet.AllCategoryButton` (cell, label "Select All N Topics"; N = 4 for our
     read-only set, 7 with write types; tap its inner `staticTexts.firstMatch`, the label flips to "Deselect N Topics"),
     per-type `UIA.Health.Read.<Type>.SwitchCell(.Switch)`, `UIA.Health.Write.<Type>...`, `UIA.Health.DoNotAllow.Button`,
     `UIA.Health.Allow.Button`. The Allow button is **below the fold and absent from the accessibility tree until the table
     is scrolled**: `sheet.tables.firstMatch.swipeUp()` once, then tap it.
  2. iOS 27 data-range page: "Past 30 Days and Future Data" vs "All Recorded Data and Future Data" (no identifiers; match
     `staticTexts` by label prefix). **Allow is disabled until one is picked**, then tap `buttons["Allow"]`.
  After page 2 the `requestAuthorization` call returns, the status is `unnecessary` (no further prompt) and queries work.
- Behaviours that shape the harness **[observed]**: uninstalling the app resets the grant (status back to
  `shouldRequest`); the data written to the store survives the uninstall. So the XCUITest must handle the sheet
  idempotently (`waitForExistence(timeout: 3)`, skip if absent). Whether `xcodebuild test`'s own reinstall resets the grant
  between runs I did not verify.
- [doc] iOS 27 adds "Past 30 Days and Future Data" as the default scope and
  `HKHealthStore.getEarliestAuthorizedSampleDateForTypes(_:completion:)` (iOS 27, SDK header) to read the lower bound.
  Irrelevant for a just-finished workout; relevant if we ever backfill older workouts.
- Purpose-string trap **[observed]**: `requestAuthorization` throws an uncaught `NSInvalidArgumentException` (SIGABRT) from
  `_validateHealthDataPurposeStringsForSharingTypes:readingTypes:` when a needed usage string is missing or invalid.
  `The string "Spike write" is an invalid value for NSHealthUpdateUsageDescription` (an 11-character placeholder);
  a one-sentence 60+ character string was accepted. Use real sentences, never placeholders.

## 3. Seeding sample data in a DEBUG build

Verified end to end **[observed]** with `HKWorkoutBuilder(healthStore:configuration:device:)`,
`configuration.activityType = .functionalStrengthTraining`:

```swift
try await builder.beginCollection(at: start)
try await builder.addSamples([hrSamples..., activeEnergySample])   // HKQuantitySample(type:quantity:start:end:)
try await builder.endCollection(at: end)
let workout = try await builder.finishWorkout()                    // HKWorkout?
```

Afterwards the workout is found by a workout query, `workout.duration == 2700`, `statistics(for: activeEnergyBurned)`
sum 210 kcal, `statistics(for: heartRate)` avg 132 / max 164 bpm, and a window query returns the 9 heart-rate samples.
Samples added through the builder are associated with the workout automatically.

- **Share authorization needed:** `toShare: [workoutType, heartRate, activeEnergyBurned]` (plus the read types), which makes
  the sheet show 7 topics (3 write + 4 read). Needs `NSHealthUpdateUsageDescription`.
- **DEBUG-only strings are possible:** `xcrun xcodeproj setting set INFOPLIST_KEY_NSHealthUpdateUsageDescription "<sentence>"
  --target Workouts --config Debug` (`--config` scopes to one configuration) **[doc: xcodeproj help]**. The entitlement
  cannot be split by read/write (`com.apple.developer.healthkit` covers both), so one entitlements file serves both
  configurations. Guard: Release code must never request `toShare` non-empty, or it aborts (see the purpose-string trap).
- **Seeded data accumulates** across runs and reinstalls **[observed]** (the workout survived an uninstall). Tag seeds with
  custom metadata (e.g. `"WorkoutsSeed": true`) and delete by predicate before seeding (`deleteObjects`, needs write auth),
  or give each run a unique window and match on it.
- Series from real watch workouts: [doc] ("Accessing condensed workout samples") HealthKit condenses/coalesces heart-rate and
  energy samples of workouts older than a few months; a chart of old workouts needs `HKQuantitySeriesSampleQueryDescriptor`.
  Not an issue for a workout read minutes after it ends.

## 4. Reading

All async/await, all run on the simulator **[observed]** unless noted:

| Need | API | Notes |
|---|---|---|
| Overlapping Fitness workout | `HKSampleQueryDescriptor(predicates: [.workout(p)], sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 5).result(for: store)` with `p = AND(HKQuery.predicateForSamples(withStart:end:), HKQuery.predicateForWorkouts(with: .functionalStrengthTraining))` | Widen the window by some slack (Watch start/stop differs from ours) and pick the best overlap in kit logic. |
| Energy, HR | `workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()`, `statistics(for: .heartRate)?.averageQuantity()/maximumQuantity()` | Works for builder-written workouts; for Watch workouts it is the documented path (iOS 16+; `HKWorkout.totalEnergyBurned` still exists). Heart-rate unit `count().unitDivided(by: .minute())`. |
| Duration | `workout.duration` (2700 s observed) | |
| Avg/max HR over a window | `HKStatisticsQueryDescriptor(predicate: .quantitySample(type:, predicate: window), options: [.discreteAverage, .discreteMax]).result(for:)` | Matched `workout.statistics` (132 / 164). `predicateForObjects(from: workout)` also worked. Use the window form when the Watch did not associate samples with the workout. |
| HR series for a chart | `HKSampleQueryDescriptor(predicates: [.quantitySample(type: heartRate, predicate: window)], sortDescriptors: [SortDescriptor(\.startDate)])` | 9 samples returned. |
| Resting energy (for "total") | same pattern with `.basalEnergyBurned` | **[inference]** not run; total = active + basal over the window; adds "Resting Energy" to the read topics (it is already in the 4-topic set above). |
| Wait for the Watch workout to sync | `HKAnchoredObjectQueryDescriptor(...).results(for:)` (AsyncSequence) | [doc]; not run. Needed if the workout arrives after Finish; a short retry loop is the simpler alternative. |

## 5. Entitlement, Info.plist, signing

- Entitlement **[doc]**: `com.apple.developer.healthkit` = `true` ("enable the HealthKit capability in Xcode"). The
  `com.apple.developer.healthkit.access` array is **not needed**: it is for extra-sensitive types (e.g. `health-records`);
  heart rate, energy and workouts are covered by the base entitlement. Background delivery entitlement not needed.
- Info.plist: `NSHealthShareUsageDescription` (read). **Read-only works with only that key** **[observed]**: a
  `toShare: []` request with no `NSHealthUpdateUsageDescription` showed the 4-topic sheet and succeeded.
  `NSHealthUpdateUsageDescription` only for the DEBUG seeding (section 3). The project generates its Info.plist, so these are
  `INFOPLIST_KEY_NSHealthShareUsageDescription` build settings (verified they land in the built Info.plist).
- Project changes: `xcrun xcodeproj setting set ...` for the keys, `com.apple.developer.healthkit` added to
  `Workouts/Workouts.entitlements` (a plain plist edit; no project change).
- Signing **[inference, not testable here]**: HealthKit is a capability Xcode enables on the App ID itself under automatic
  signing with the signed-in account (the same way it already handled iCloud/push for 7.1), so
  `-allowProvisioningUpdates` should regenerate the profile. If the archive reports a profile without HealthKit, Eric enables
  it once at developer.apple.com > Certificates, IDs & Profiles > Identifiers > `com.ericribeiro.Workouts` > HealthKit
  (no Apple approval is needed for this capability; only research/clinical variants need a request). Simulator builds need
  no profile (verified they run with the entitlement). TestFlight/App Store Connect rejects an app that has the entitlement
  but no `NSHealthShareUsageDescription`.

## 6. `swift test` on macOS and the kit

**[observed]** A scratch SwiftPM package (macOS 14 and iOS 17 platforms, outside the repo) importing `HealthKit` built and ran under
`swift test`. HealthKit has macOS slices in the macOS 27.2 SDK (headers mark `macos(13.0)`). But at runtime
`HKHealthStore.isHealthDataAvailable()` is `false` on the Mac and a `HKSampleQueryDescriptor.result(for:)` throws
`HKError` code 1 "Health data is unavailable on this device". So it compiles but cannot do anything useful.

**Recommendation: keep `WorkoutsKit` HealthKit-free.** It would compile, but (a) no real query can run in `swift test`,
(b) `HKWorkout`/`HKQuantitySample` are awkward to construct in tests (the convenience inits are deprecated; real ones need a
store), (c) the kit contract is "no Apple-platform frameworks beyond Foundation" and this keeps it that way. HealthKit lives
in the app target behind a small adapter.

## 7. Recommended testing architecture

1. **Kit (`./dev kit`, seconds):** `WorkoutHealthMetrics` (Codable, Sendable: activeKcal, totalKcal?, avgHR, maxHR, duration),
   `HealthWorkoutCandidate` (start, end, activity type, optional metrics) and the pure logic: widen the window, choose the
   best-overlapping candidate, reject low overlap, merge fields, units. `protocol HealthMetricsProvider: Sendable { func
   metrics(overlapping: DateInterval) async throws -> WorkoutHealthMetrics? }` plus `FakeHealthMetricsProvider`
   (canned result, `.denied`, `.empty`, `.error`, delayed). All persistence of the stored fields is tested with the fake.
2. **App target:** `HealthKitMetricsProvider` (the only file importing HealthKit; maps `HKWorkout`/statistics to the kit
   values). Authorization request lives here (read-only set: workout, heart rate, active + basal energy).
3. **App UI fixtures:** a `-healthFixture <name>` DEBUG launch argument swaps in the fake provider (`full`, `none`,
   `denied`, `slow`), so Finish-summary, History detail and the preview gallery are proven without HealthKit or any prompt
   (`./dev ui-test` stays hermetic and fast).
4. **Real-store integration test (feasible, keep out of `./dev check`):** one XCUITest `HealthKitIntegrationUITests`, launched
   with `-healthSeed` (DEBUG build: requests write+read, seeds a tagged Functional Strength workout with HR and energy samples
   via the builder, after deleting earlier tagged seeds), that drives the Health Access sheet with the identifiers in section 2,
   then asserts the Finish/History UI shows the seeded avg/max HR and energy. Run on demand (`./dev ui-test
   HealthKitIntegration`), serialized on one simulator; it is the proof that predicates, units and `statistics(for:)` match.
   Run it with `DEV_SIM_UDID=<udid> ./dev ui-test HealthKitIntegrationUITests` (that filter sets `TEST_RUNNER_HEALTH_INTEGRATION=1`; without it the test skips, so the full `./dev ui-test` and `check` never run it); `xcrun simctl privacy <udid> reset all com.ericribeiro.Workouts` first exercises the sheet path.
5. **Only on Eric's device:** that his Apple Watch workout associates heart-rate/energy samples with the `HKWorkout`
   and arrives in time; real overlap behaviour (Watch start/stop vs. ours); the signing/provisioning with the HealthKit
   capability and TestFlight upload; the real read prompt wording and the "Past 30 Days" default; basal-energy "total"
   numbers; permission-denied behaviour in Settings > Health > Data Access.

## Spike hygiene

All spike code (a `HealthSpike.swift` driven by a `-healthSpike` launch arg, a temporary XCUITest, a
`com.apple.developer.healthkit` entitlement and Info.plist keys) was reverted; `git status` is clean apart from this file. The
simulator "iPhone Duo 3" retains one seeded Functional Strength workout in its Health store (harmless; `simctl erase` clears it).
