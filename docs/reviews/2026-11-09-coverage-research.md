# Covering the remaining test gaps (research, 2026-11-09)

Seven read-only research workers (one per gap) plus Apple-docs checks. The per-gap reports with code sketches and
sources are in `2026-11-09-coverage-research/`. Numbers come from `.build/results/latest-test.xcresult` and
`latest-ui-test.xcresult` on 12f5649 (kit 97.6 % lines, app 80 % under the UI suite, 33 % under unit tests by design).

Two findings from the first survey were wrong and are corrected here: the Duo placement logic is already unit-tested
(`FoldPlacement`, 26 kit tests; only the SwiftUI glue is at 0 %), and the 2026-11-07 gate table's claim that a
`-liveActivity` fixture test exists is false (no UI test passes the flag).

## Plan at a glance

| # | Gap | Do now | Do next | Keep manual |
|---|---|---|---|---|
| 1 | Duo open poses | `ImageRenderer` placement snapshots of `ArrangementView` at 951×669 and 669×951 (1 h) | `DEV_POSE` in `dev` + `OpenPoseUITests` with an in-pose rotation (3–4 h) | hinge fold itself; `./dev poses` stays the reviewer proof |
| 2 | Rest timer picker | template-editor UI test (caption changes, Cancel) (1 h) | logging-cover test: pick 30 s, check a set, ring reads ≤ 30 (2 h) | — |
| 3 | HealthKit real store | gate on change: `testflight --upload` blocks when Health files changed since the last real-store pass, run on a dedicated non-pool sim (2 h) | helpers-only unit seam in `HealthKitSource` (2–3 h) | sheet driver survival across iOS versions; Watch data |
| 4 | CloudKit sync | two on-disk containers + history author filter test in the kit (3–4 h); `CKDatabase` seam for `CloudKitMediaSource` (1.5 h) | offline `NSPersistentCloudKitContainer` load + `initializeCloudKitSchema(.dryRun)` spike (1–2 h); exempt the iCloud sims from auto-erase | push-driven merge, Production, `./dev sync-check` as a human-run script |
| 5 | Live Activity | ring seam + 5 snapshots for `DynamicIslandViews` (2 h); `RenderPreview` spike on `ActivityPreviews` (1 h) | factor the `ActivityConfiguration` builder closures (1.5 h) | Island on the closed Duo, StandBy; SpringBoard XCUITest only after a spike |
| 6 | Flakiness | view the audit failure's element screenshot; settle anchors + 15 s rest budget; failure text into `ui-flaky.log` (2 h) | replace the 4 sleeps with predicates (2–3 h); suite-level flake-trend gate (2 h) | — |
| 7 | SettingsFlow, gates, link router | `turnOffFitness` seam, `WorkoutLinkRouter` unit test (0.8 h); update the gate table (15 min) | `runImport` awaitable + `refreshAfterImport` test (1.5 h) | file picker, notification tap on device |

Roughly 20 h of "now" work and 15 h of "next"; everything in "now" runs inside `./dev check` or is a one-off script
change, nothing adds a simulator pose or a network call to the gate.

## 1. Duo open poses

**What is really uncovered.** `FoldPlacement.placement(size:divisions:axes:)` and `frames(for:in:headerHeight:)` are in
the kit with 26 tests (wide, tall, square, book, laptop, keyboard-up, clamping). `BenchArrangement.swift` (0 %) is the
glue: `BenchArrangementBody` reads `GeometryReader` size and `reservedRegions(kind: .division)`; the size class is read
one level up (`ActiveWorkoutCover` passes both axes only when `horizontalSizeClass == .regular`). So open-wide and
open-tall are reproducible from geometry alone (951×669 → side by side, 669×951 → stacked); bench (half-open) needs a
real division and cannot be faked in a snapshot.

**Facts that bound the options.** `XCUIDevice` has orientation and appearance, no hinge or fold API (Apple docs); there
is no `simctl` hinge verb; the hinge is driven only by `Tools/duo` through a private HID path from the host. Hosted
snapshot windows cannot be wider than the sim's scene, which is why the dashboard and heart-rate wide snapshots use the
`ImageRenderer` engine at 700–800 pt.

**Options, ranked.**

- **A. `ImageRenderer` placement snapshot** of `ArrangementView` with coloured placeholders under `BenchArrangementStyle`
  at both open sizes (and axes `[]` for single). Proves the glue applies `FoldPlacement`; covers the 0 % file inside
  `./dev check`. Needs a 15-minute spike that `ArrangementView` renders under `ImageRenderer`. 1 h, deterministic.
- **B. `DEV_POSE`.** `run_tests` poses the sim after `sim_reset_ui` under the same lock, exports `TEST_RUNNER_DUO_POSE`,
  and always restores closed-portrait on exit. A new `OpenPoseUITests` skips without the env (the `TreeDumpUITests`
  pattern), asserts the window is 951×669 and the exercise pane sits in the right half, then sets
  `XCUIDevice.shared.orientation = .landscapeLeft` and asserts the focused cell, its typed draft and the scroll position
  survive the side-by-side → stacked change. That is the identity claim BenchArrangement exists for, proven with
  documented APIs only. The same env lets a hosted full-cover snapshot run at 951 wide. 3–4 h; excluded from the sharded
  full run, run before TestFlight.
- **C. Mid-test fold handshake.** The test logs `fold-request open-wide`; a host watcher under the lock streams the sim's
  log and runs `duo pose`; the test waits on the window width. The only way to prove closed → open → half-open (bench).
  6–10 h, medium-high flakiness (private HID path, SpringBoard guards), single sim, opt-in. Only if the fold itself must
  be gated.

**Eric decides:** whether rotation-in-open (B) is enough proof of "focus and scroll survive a pose change", or C is
wanted; whether posed suites join the upload gate or stay opt-in.

## 2. Rest timer picker

`RestTimerPickerSheet` (0 %) is a `NavigationStack` + `List` over `[default, 0, 30, 60, 90, 120, 180, 300]` plus the
current custom value; ids `restTimer.sheet`, `restTimer.option.<seconds|default>`, `restTimer.cancel`. It opens from
`settable.menu.rest` ("Update Rest Timer…") in the logging cover and the template editor only; the past editor hides
the entry and `PastEditorUITests.testBlockMenuOffersOnlyTheNotes` already asserts that.

- **Template editor test (first).** The block header caption changes immediately (`Rest 1:30`, `Rest off`,
  `Rest 1:00 (default)` from `SetTableLayout.restCaption`), so one test covers open, current-row `.isSelected`, every
  option branch, dismiss and `draft.updateRestTimers`; a second covers Cancel. No new identifiers needed; an optional
  `settable.restCaption.<id>` avoids label-prefix matching. 1 h, low flakiness. Read the caption first: seeded blocks may
  already carry a rest from `SampleData`.
- **Logging cover test (second).** Skip the launch rest, pick 30, check the first unchecked set, read `rest.ring` and
  assert 16…30 s. The only test of the engine-fed path (`engine.setRest` → `startRest(afterChecking:)`). Move the
  `private` ring helpers from `RestRingUITests` into `Support/` first. 2 h, medium flakiness (ticking ring, bounded as
  `RestRingUITests` does).
- **Kit:** no test exists for `engine.setRest` followed by a check; add one (15 min) so the UI test asserts wiring only.
- **Skip** a snapshot of the sheet. **Optional:** spoken labels "30 seconds" instead of "0:30".

## 3. HealthKit real store

`HealthKitSource.swift` is 0 % because only `HealthKitIntegrationUITests` reaches it, and that test skips unless
`HEALTH_INTEGRATION` is set. The reason is the Health Access sheet: a separate process (`com.apple.HealthPrivacyService`),
private identifiers, an iOS 27 data-range page, Allow hidden until a swipe. Runtime is about a minute; shared-state risk
is small (the seeder deletes only its own tagged objects). `simctl privacy` has no `health` service, so pre-granting is
out; an interruption monitor does not fire for another process's sheet. A filtered run also overwrites
`latest-ui-test.xcresult`, clobbering the full-run coverage bundle.

- **Gate on change, not on a clock (recommended cadence).** A `.build/health-test.stamp` written only when the filtered
  run passes with zero skips; `tf_ui_gate` fails when `HealthKitSource.swift`, `HealthSeeder.swift`, the entitlements or
  the test changed since the stamped commit (override as today with `DEV_SKIP_UI_GATE=1`). Pin the run to a dedicated
  clone outside `sim_pool_names` ("iPhone Duo Health") so the grant and seed persist, and save its xcresult under its own
  name. 2 h. A weekly or every-run cadence was rejected: unattended sheet flakes, or a stale commit unrelated to uploads.
- **Ten-minute check first:** run the filtered test twice on one clone and read the `answered` count. If the second run
  answers 0, the sheet is a first-run cost and the 90 s deadline can drop to 30 s.
- **Unit seam, helpers only.** Make `map`, `kind(of:)`, `quantity(_:in:)`, `text(_:)`, the unit choice in `statistic`
  and the summary arithmetic (active + basal, HR offset, humidity ×100, rated-over-estimated effort) internal and test
  them in `WorkoutsTests`. About 100–120 of 288 lines, 2–3 h. A full `HKHealthStore` protocol (6–8 h) was rejected: the
  high-risk lines (predicates, `statistics(for:)`, activities, routes) have no public constructors and need the real
  store anyway.

**Eric decides:** hard block on upload vs warning; a sixth non-pool clone (disk) vs reusing "iPhone Duo 5".

## 4. CloudKit sync

**Current state.** Every kit test builds `inMemory: true, cloudKit: false`. The remote-change wiring and the P8-04
author filter (`ForeignHistoryCheck`, private in `WorkoutsApp.swift`) have no test; kit tests call
`engine.reloadAfterRemoteChange()` by hand. `CloudSyncMonitor` already maps `NSPersistentCloudKitContainer.Event` to a
kit value, so only the 15-line map is untested. `CloudKitMediaSource` is 12 %. The pool is hostile to signed-in sims:
`sim_heal` and `sims --prune` erase clones, which signs them out of iCloud.

- **B. Two on-disk containers + persistent history (do first, high confidence).** Move `ForeignHistoryCheck` into the
  kit; add a test-only `ModelContainer.workouts(at: URL)`. Open two containers on the same sqlite file, author `"app"` on
  one and `"NSCloudKitMirroringDelegate.import"` on the other; a save on the mirror posts a real
  `NSPersistentStoreRemoteChange`, the observer debounces (manual clock), the filter passes, the engine adopts the
  workout; a local save does not fire. Proves P8-01/02/03/04 through the real notification path. 3–4 h.
- **A. Offline model validation (spike 30 min, then 1–2 h).** Load the SwiftData-generated `NSManagedObjectModel` into an
  `NSPersistentCloudKitContainer` on a temp store with `cloudKitContainerOptions`; the mirroring delegate rejects a
  CloudKit-incompatible model at load. Then `initializeCloudKitSchema(options: .dryRun)`; it may need an account under
  `swift test`, in which case keep only the load assertion. Catches what the metadata walk in `CloudKitSchemaRulesTests`
  cannot (SwiftData's transformed attribute types, Codable attributes, inverse mapping).
- **D + C. `CKDatabase` seam and event-map seam (cheap).** A `RecordFetching` protocol lets a fake exercise dark → light
  fallback, `.unknownItem` → nil, rethrow and cancellation (~90 % of the file). A read-only `cktool query-records` probe
  under `op run` checks the record type and field names against the Console; add it to `./dev ck-schema` as a manual
  step. `CloudSyncMonitor.map` takes plain fields so three more `CloudSyncStatusTests` cover it. 2 h.
- **E. `./dev sync-check` (human-run, not a gate).** Two reserved sims exempt from heal/prune, a `-syncProbe <uuid>`
  insert on A, `xcrun simctl icloud_sync` plus relaunch on B, poll B's unified log for `SyncProbe seen <uuid>` for 180 s,
  fail fast on `accountStatus` lapses. 4–6 h, high flakiness (forum reports: simulator pushes unreliable, sync happens
  on relaunch). The pool exemption is worth doing on its own: it is the likeliest cause of a surprise "Not signed in".
- **Leave manual:** push-driven live merge, Production deploys, phone + second device.

**Eric decides:** kit takes over `ForeignHistoryCheck` and gains a URL overload; which sims leave the auto-erase pool;
whether the 3-minute script is worth it before a second real device exists; does the test account have 2FA (the usual
cause of lapses).

## 5. Live Activity

**Current state.** `SnapshotLiveActivityTests` renders the extension's views as plain SwiftUI (`.hostedFitting`) inside a
fake Island frame; it skips every case that draws the ring because `ProgressView(timerInterval:)` renders a spinner
outside WidgetKit. That is the whole 60 % of `DynamicIslandViews` (`ActivityRing` restOver and running, compact leading
with ring, compact trailing resting/restOver). `WorkoutLiveActivity.swift` (0 %) is the `ActivityConfiguration` +
`DynamicIsland` builder, which only the WidgetKit host instantiates; no documented test path exists. No UI test passes
`-liveActivity`. The leftover-activity crash (JC20) needs an activity alive across a reinstall.

- **A. Ring seam + snapshots (first).** Split `ActivityRing` into a pure `ActivityRingContent(kind:)` with a DEBUG
  `drawsSystemRing` flag; under test it draws a static `Circle().trim`. Five new snapshots take the file to ~90 %. 2 h.
- **E. `RenderPreview` spike (1 h).** `ActivityPreviews.swift` already has `#Preview(as: .dynamicIsland(.expanded /
  .compact / .minimal))` and `.content`. If the Xcode MCP renders them, Eric gets reviewable PNGs per region and Dynamic
  Type without a device. The narrow Duo Island cannot be previewed (`isDynamicIslandLimitedInWidth` is get-only).
- **B. Factor the builder closures** into `lockScreen(state:isStale:)` / `islandRegions(...)` functions; the file's
  honest ceiling is ~50 %, and the remainder should be recorded as uncoverable rather than chased.
- **C + D. SpringBoard XCUITest** (launch `-liveActivity`, start a rest, press home, find the Lock Screen banner's
  "Add 30 seconds of rest" button in `XCUIApplication(bundleIdentifier: "com.apple.springboard")`, tap, compare the
  ring), with teardown ending every activity. One public project does this for a Stop button; nothing confirms the Island
  itself is in the accessibility tree, and nothing covers the Duo. 4–8 h after a 1 h spike, high flakiness, opt-in and
  single-sim only.
- **Stays with Eric:** narrow Island on the closed Duo during a rest; buttons in StandBy night (PLAN device checks).

**Eric decides:** a reviewable PNG (E) or an automated pass/fail (C); accept the DEBUG seam in `ActivityRing`; accept
`WorkoutLiveActivity.swift` below 100 %.

## 6. Flakiness

**Diagnoses** (only the 12f5649 bundles survive; the 11-06 and 11-08 messages are gone, which is itself a finding):

| Test | What the bundle says | Side |
|---|---|---|
| `AccessibilityAuditUITests/testActiveWorkoutLogging` | "Hit area is too small" with an element screenshot; audit runs the instant `screen.activeWorkout` appears, cover still presenting, 300 s ring live | test-side settle, **but view the screenshot first**: a real undersized control in a transient state would hide here |
| `RestRingUITests/testRestEndsWhileSetFieldHasFocus` | `label BEGINSWITH 'Rest timer, '` timed out at 5 s; the test took 256 s, its shard 24 min vs 20 for the others | environmental stall plus a 5 s budget; suspect (unverified) the 0.25 s `TimelineView` in `RestStateProbe` keeps the app from going idle under `-uiTesting` |
| `ExerciseListUITests/testBestSetFollowsUnitChange` | message lost | long chain with un-anchored steps (Settings alert OK, unit segment tap) before a 10 s predicate |
| `FirstFrameUITests/testTemplatePreviewChromeBeforeLastPerformed` | message lost; the file already documents an earlier flake | the absence assertion races the `-slowLoads` hold; tap + 5 s wait burn the slack before `.exists` |

**Sleeps.** `CoverTimerUITests:17` (2.5 s for a subtitle tick) → predicate `label != before`. The three
`SetTableKeyboardRevealUITests` 1 s sleeps → `waitUntil` on frame equality across two reads. `LoggingBlockMenuUITests:124`
("did not move") legitimately keeps a settle. `PerfDriverUITests` skips itself without `PERF_DRIVER`; leave it.
`XCUIElement+Waiting.swift` already has `waitUntilGone`, `assertStaysAbsent`, `waitUntil`; the Darwin seam
(`expireRestNow`, `debug.restState`) exists.

**Policy.** The "flaky twice in a row" rule compares the same test id against the previous stamp only, so four different
tests in four runs never trips it, and `ui-flaky.log` records no message, duration or shard. Recommended: write the first
attempt's `failureText`, shard and seconds into the log line (it is read already in `ui_shard_retry`); add a suite-level
trigger (≥ 2 flakes of one test, or ≥ 3 of one suite, in the last 8 full runs) once the history has ~10 entries; a
`./dev ui-flaky` summary. `xcodebuild -retry-tests-on-failure` was considered and rejected: dev's retry already adds the
trend rule the flags lack.

**Eric decides:** accept a gate that fails on a retry-passed flake (blocks uploads more often); was the Mac busy at
04:5x UTC on 11-09; may the probe's `TimelineView` be swapped for a one-shot timer.

## 7. SettingsFlow, the gate table, WorkoutLinkRouter

- **SettingsFlow.** Never run in either suite: `runImport` (46–58), `refreshAfterImport` (99–102, `exerciseStore.setCustom`
  + `engine.resume()` when nothing is running) and the `turnOffFitness` catch (165–168, "Could Not Remove Fitness Data").
  The import UI has no XCUITest by design (the file picker cannot be driven; `SettingsUITests:178`). Fixes: a
  `performTurnOff(_:)` closure seam like `performImport(refresh:)`; make `runImport` return its `Task` so a test awaits
  the `isImporting` lifecycle; drop `private` on `refreshAfterImport` and test it with a real engine and store on an
  in-memory container (imported unfinished workout shows at once; a running one is untouched). ~2.3 h total. A DEBUG
  `-importFile <fixture>` UI seam (2 h) is possible but only adds alert wiring; defer. Moving `DataTransfer` to the kit
  only if it changes again.
- **WorkoutLinkRouter** (17 %): `OpenWorkoutURLUITests` goes through `.onOpenURL` directly; the router is fed only by the
  rest notification's body tap (`notifier.openWorkout = { links.request() }`) and consumed by `RootView`. A unit test of
  `request()`/`consume()` plus a `RestNotifierTests` case for `didReceive` → `openWorkout` (0.3 h). The cold-launch
  consumption stays a device check: a delivered notification cannot be tapped reliably in XCUITest.
- **Gate table.** Eleven `-uiTesting` checks now, in two kinds: eight turn a feature or state off (line numbers all
  drifted) and three turn a test seam on (`HealthLookupProbe.swift:9`, `RestExpirySeam.swift:22` and `:47`). Section 2C
  of the 2026-11-07 review says six. The `WorkoutsApp.swift` Live Activity row must change: no test passes
  `-liveActivity`; coverage is `LiveActivityControllerTests` and device runs. The drafted replacement table is in the
  appendix report.

## Cross-cutting

- **Pin a date on evidence.** Only the latest run's xcresult bundles survive, so two of four flake causes are
  unrecoverable. Keeping the last N shard bundles (or the failure text in the log) is cheap and would have answered this.
- **"Off under the harness" now has a third kind.** Besides feature gates and isolation, three seams turn test-only
  machinery on. The gate table should carry a "kind" column so a reviewer can see which green means "correct", which
  means "off", and which means "the seam fired".
- **Dedicated non-pool sims** solve two gaps at once (Health grant persistence, iCloud sign-in survival) and remove the
  likeliest cause of surprise "Not signed in" during the manual sync check.
- **Honest ceilings.** `WorkoutLiveActivity.swift` (`ActivityConfiguration`), the Health predicates and statistics, and
  `NSPersistentCloudKitContainer` behaviour are uncoverable in automation; record them as such in PLAN rather than chase
  the number.

## Appendix

Per-gap worker reports, with code sketches, line references and sources:
`2026-11-09-coverage-research/{duo,restpicker,health,cloudkit,liveactivity,flaky,settings-gates}.md`.
