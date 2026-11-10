# Covering the remaining test gaps (research, 2026-11-09)

Seven read-only research workers (one per gap), Apple-docs checks, and a Fable review that spot-checked 34 claims against
the code and the result bundles (25 confirmed, 6 line drifts, 3 wrong in a way that changed a recommendation; all folded in
below). The per-gap reports with code sketches and sources, and the review, are in `2026-11-09-coverage-research/`.
Coverage numbers: `latest-ui-test.xcresult` is the full run on 12f5649; `latest-test.xcresult` is an earlier 11-08 build
(the unit bundle carries no stamp, see Cross-cutting). Kit 97.6 % lines, app 80 % under the UI suite, 33 % under unit tests
by design.

Two findings from the first survey were wrong: the Duo placement logic is already unit-tested (`FoldPlacement`, 26 kit
tests; `BenchArrangement.swift` is 0 % under unit tests but 29 % under the UI suite, with only the open and bench branches
dark), and the 2026-11-07 gate table's claim that a `-liveActivity` fixture test exists is false (no UI test passes the flag).

## Plan at a glance

| # | Gap | Do now | Do next | Keep manual |
|---|---|---|---|---|
| 1 | Duo open poses | `ImageRenderer` placement snapshot of `ArrangementView` at 951×669 and 669×951 (1 h, after a 15-min render spike) | `DEV_POSE` in `run_tests` + `OpenPoseUITests`, only after two spikes: posing under the lock, and whether XCUITest rotation re-lays out the inner display (3–4 h if both pass) | hinge fold and bench; `./dev poses` stays the reviewer proof |
| 2 | Rest timer picker | kit `setRest → check` test (15 min); template-editor UI test with Cancel (1 h) | logging-cover test: pick 30 s, check a set, ring reads 16–30 s (1.5 h) | — |
| 3 | HealthKit real store | helpers-only unit seam in `HealthKitSource` (2–3 h); the "answered count" check, twice on one clone (orchestrator, 10 min) | `tf_health_gate` on every `--upload`, outside `DEV_SKIP_UI_GATE`, with its own override, on a dedicated non-pool clone (2 h) | sheet-driver survival across iOS versions; Watch data |
| 4 | CloudKit sync | 30-min spike: does a second in-process container's save post `NSPersistentStoreRemoteChange`; then the two-container history test (3–4 h) or its hand-posted fallback; `CKDatabase` seam + `CloudSyncMonitor.map` seam (2 h) | offline `NSPersistentCloudKitContainer` load check in `WorkoutsTests` (1–2 h); exempt the iCloud sims from auto-erase | push-driven merge, Production, `./dev sync-check` (defer until a second device) |
| 5 | Live Activity | `RingKind` value + unit test (0.5 h); `RenderPreview` spike on `ActivityPreviews` (1 h) | factor the `ActivityConfiguration` builder closures (1.5 h); record the ceiling | Island on the closed Duo, StandBy; SpringBoard XCUITest only if `RenderPreview` fails |
| 6 | Flakiness | extend the audit `.hitRegion` rule to the title label (15 min); failure text, shard and seconds into `ui-flaky.log` + `./dev ui-flaky` (1.5 h); `startRest` budget 5 → 15 s | replace the 4 sleeps with predicates (2–3 h) | trend gate until the log has ~10 entries and the full run is back on the upload path |
| 7 | SettingsFlow, gates, link router | `performTurnOff` seam + `WorkoutLinkRouter` unit test (0.65 h); update the gate table (15 min) | `runImport` awaitable + `refreshAfterImport` test (1.5 h) | file picker, notification tap on device |

About 16 h of "now" work and 14 h of "next". Nothing in "now" adds a simulator pose or a network call to the gate, and the
two `dev` gates were moved off the `tf_ui_gate` path, where `DEV_SKIP_UI_GATE=1` (the routine upload mode since 11-08) would
have made them dead code.

## 1. Duo open poses

**What is really uncovered.** `FoldPlacement.placement(size:divisions:axes:)` and `frames(for:in:headerHeight:)` are in
the kit with 26 tests (wide, tall, square, book, laptop, keyboard-up, clamping). `BenchArrangement.swift` is the glue:
`BenchArrangementBody` reads `GeometryReader` size and `reservedRegions(kind: .division)`; the size class is read one level
up (`ActiveWorkoutCover` passes both axes only when `horizontalSizeClass == .regular`). The closed-pose path runs under
every cover UI test (29 %); the open and bench branches never run. Open-wide and open-tall are reproducible from geometry
alone (951×669 → side by side, 669×951 → stacked); bench (half-open) needs a real division and cannot be faked.

**Facts that bound the options.** `XCUIDevice` has orientation and appearance, no hinge or fold API (Apple docs); there is
no `simctl` hinge verb; the hinge is driven only by `Tools/duo` through a private HID path from the host. Hosted snapshot
windows cannot be wider than the sim's scene, which is why the dashboard and heart-rate wide snapshots use the
`ImageRenderer` engine at 700–800 pt. `docs/port/duo-layout.md` says the inner display does not honour supported interface
orientations and the app scales there, so whether an XCUITest rotation re-lays out the open Duo is unknown.

**Options, ranked.**

- **A. `ImageRenderer` placement snapshot** of `ArrangementView` with coloured placeholders under `BenchArrangementStyle`
  at both open sizes (and axes `[]` for single). Proves the glue applies `FoldPlacement` for the open branches, inside
  `./dev check`. Spike first (15 min): does `ArrangementView` render under `ImageRenderer`. 1 h, deterministic.
- **B. `DEV_POSE`.** `run_tests` poses the sim after `sim_reset_ui` under the same lock, exports `TEST_RUNNER_DUO_POSE`, and
  always restores closed-portrait on exit. A new `OpenPoseUITests` skips without the env (the `TreeDumpUITests` pattern),
  asserts the window is 951×669 and the exercise pane sits in the right half, then sets
  `XCUIDevice.shared.orientation = .landscapeLeft` and asserts the focused cell, its typed draft and the scroll position
  survive side-by-side → stacked. Two spikes before the estimate stands: posing from `run_tests`, and the inner-display
  rotation question above. 3–4 h; excluded from the sharded full run, run before TestFlight.
- **C. Mid-test fold handshake.** The test logs `fold-request open-wide`; a host watcher under the lock streams the sim's
  log and runs `duo pose`; the test waits on the window width. The only way to prove closed → open → half-open (bench).
  6–10 h, medium-high flakiness (private HID path, SpringBoard guards), single sim, opt-in. Only if the fold itself must be
  gated.

**Eric decides:** whether rotation-in-open (B) is enough proof of "focus and scroll survive a pose change", or C is wanted;
whether posed suites join the upload gate or stay opt-in.

## 2. Rest timer picker

`RestTimerPickerSheet` (0 %) is a `NavigationStack` + `List` over `[default, 0, 30, 60, 90, 120, 180, 300]` plus the current
custom value; ids `restTimer.sheet`, `restTimer.option.<seconds|default>`, `restTimer.cancel`. It opens from
`settable.menu.rest` ("Update Rest Timer…") in the logging cover and the template editor only; the past editor hides the
entry and `PastEditorUITests.testBlockMenuOffersOnlyTheNotes` already asserts that. In the cover, `engine.setRest` writes
`row.restSeconds`, and the next check starts a rest of that length and replaces any running rest; only Off (0) leaves a
running rest alone.

- **Kit first (15 min).** No test covers `engine.setRest` followed by a check; add one so the UI tests assert wiring only.
- **Template editor test.** The block header caption changes immediately (`Rest 1:30`, `Rest off`, `Rest 1:00 (default)`
  from `SetTableLayout.restCaption`), so one test covers open, current-row `.isSelected`, every option branch, dismiss and
  `draft.updateRestTimers`; a second covers Cancel. No new identifiers needed; an optional `settable.restCaption.<id>`
  avoids label-prefix matching. The seeded first block carries 150 s (`SampleData`), so the caption starts at `Rest 2:30`.
  1 h, low flakiness.
- **Logging cover test.** Pick 30, check the first unchecked set, read `rest.ring` and assert 16…30 s. No "skip the launch
  rest" step: the check replaces it. Move the `private` ring helpers from `RestRingUITests` into `Support/` first. 1.5 h,
  medium flakiness (ticking ring, bounded as `RestRingUITests` does).
- **Skip** a snapshot of the sheet. **Optional:** spoken labels "30 seconds" instead of "0:30".

## 3. HealthKit real store

`HealthKitSource.swift` is 0 % because only `HealthKitIntegrationUITests` reaches it, and that test skips unless
`HEALTH_INTEGRATION` is set. The reason is the Health Access sheet: a separate process (`com.apple.HealthPrivacyService`),
private identifiers, an iOS 27 data-range page, Allow hidden until a swipe. Runtime is about a minute; shared-state risk is
small (the seeder deletes only its own tagged objects). `simctl privacy` has no `health` service, so pre-granting is out; an
interruption monitor does not fire for another process's sheet. A filtered run also overwrites `latest-ui-test.xcresult`,
clobbering the full-run coverage bundle.

- **Unit seam, helpers only (first).** Make `map`, `kind(of:)`, `quantity(_:in:)`, `text(_:)`, the unit choice in
  `statistic` and the summary arithmetic (active + basal, HR offset, humidity ×100, rated-over-estimated effort) internal and
  test them in `WorkoutsTests`. About 100–120 of 288 lines, 2–3 h. A full `HKHealthStore` protocol (6–8 h) was rejected: the
  high-risk lines (predicates, `statistics(for:)`, activities, routes) have no public constructors and need the real store.
- **Ten-minute check (orchestrator):** run the filtered test twice on one clone and read the `answered` count. If the second
  run answers 0, the sheet is a first-run cost and the 90 s deadline can drop to 30 s.
- **Gate on change, not on a clock (recommended cadence).** A `.build/health-test.stamp` written only when the filtered run
  passes with zero skips. A new `tf_health_gate`, called on every `--upload` and independent of `tf_ui_gate` (which returns
  before any check under `DEV_SKIP_UI_GATE=1`), fails when `HealthKitSource.swift`, `HealthSeeder.swift`, the entitlements
  or the test changed since the stamped commit, with its own `DEV_SKIP_HEALTH_GATE=1` override. Pin the run to a dedicated
  clone outside `sim_pool_names` ("iPhone Duo Health") so the grant and seed persist, and save its xcresult under its own
  name. 2 h. A weekly or every-run cadence was rejected: unattended sheet flakes, or a stale commit unrelated to uploads.

**Eric decides:** hard block on upload vs warning; a sixth non-pool clone (disk) vs reusing "iPhone Duo 5".

## 4. CloudKit sync

**Current state.** Every kit test builds `inMemory: true, cloudKit: false`. The remote-change wiring and the P8-04 author
filter (`ForeignHistoryCheck`, private in `WorkoutsApp.swift`) have no test; kit tests call
`engine.reloadAfterRemoteChange()` by hand, and the only `RemoteChangeObserver` test posts `NSPersistentStoreRemoteChange`
itself. `CloudSyncMonitor` already maps `NSPersistentCloudKitContainer.Event` to a kit value, so only the 15-line map is
untested. `CloudKitMediaSource` is 12 %. The pool is hostile to signed-in sims: `sim_heal` and `sims --prune` erase clones,
which signs them out of iCloud.

- **B. Two on-disk containers + persistent history (first, after a 30-min spike).** Move `ForeignHistoryCheck` into the
  kit; add a test-only `ModelContainer.workouts(at: URL)`. Open two containers on the same sqlite file, author `"app"` on one
  and `"NSCloudKitMirroringDelegate.import"` on the other; a save on the mirror should post a real
  `NSPersistentStoreRemoteChange`, the observer debounces (manual clock), the filter passes, the engine adopts the workout; a
  local save does not fire. Whether SwiftData sets the remote-change post option on a second in-process container is
  unverified: spike it first. Fallback keeps most of the value: post the notification from the test and keep the
  history-author assertions. Also the natural place to drive `InProgressResolution` through the mirror author and prove a
  recent remote in-progress row is never settled or deleted. 3–4 h.
- **D + C. `CKDatabase` seam and event-map seam (cheap).** A `RecordFetching` protocol lets a fake exercise dark → light
  fallback, `.unknownItem` → nil, rethrow and cancellation (~90 % of the file). `CloudSyncMonitor.map` takes plain fields so
  three more `CloudSyncStatusTests` cover it. A read-only `cktool query-records` probe against the public database would
  check record type and field names against the Console; whether a management token may query records is unverified
  (`man cktool`). 2 h.
- **A. Offline model validation in `WorkoutsTests` (spike 30 min, then 1–2 h).** Load the SwiftData-generated
  `NSManagedObjectModel` into an `NSPersistentCloudKitContainer` on a temp store with `cloudKitContainerOptions`; the
  mirroring delegate rejects a CloudKit-incompatible model at load. Then `initializeCloudKitSchema(options: .dryRun)`; it may
  need an account, in which case keep only the load assertion. It stays in the app test target: the kit's contract is
  Foundation-only and the app already imports CoreData. Catches what the metadata walk in `CloudKitSchemaRulesTests` cannot
  (SwiftData's transformed attribute types, Codable attributes, inverse mapping).
- **E. `./dev sync-check` (human-run, not a gate).** Two reserved sims exempt from heal/prune, a `-syncProbe <uuid>` insert on
  A, `xcrun simctl icloud_sync` plus relaunch on B, poll B's unified log for `SyncProbe seen <uuid>` for 180 s, fail fast on
  `accountStatus` lapses. 4–6 h, high flakiness (forum reports: simulator pushes unreliable, sync happens on relaunch).
  Defer until a second real device exists. The pool exemption is worth doing on its own: it is the likeliest cause of a
  surprise "Not signed in".
- **Leave manual:** push-driven live merge, Production deploys, phone + second device.

**Eric decides:** which sims leave the auto-erase pool (or a third dedicated iCloud sim). The kit URL overload and taking
over `ForeignHistoryCheck` are routine design calls (yes, test-only).

## 5. Live Activity

**Current state.** `SnapshotLiveActivityTests` renders the extension's views as plain SwiftUI (`.hostedFitting`) inside a
fake Island frame; it skips every case that draws the ring because `ProgressView(timerInterval:)` renders a spinner outside
WidgetKit. That is the whole 60 % of `DynamicIslandViews` (`ActivityRing` restOver and running, compact leading with ring,
compact trailing resting/restOver). `WorkoutLiveActivity.swift` (0 %) is the `ActivityConfiguration` + `DynamicIsland`
builder, which only the WidgetKit host instantiates; no documented test path exists. No UI test passes `-liveActivity`. The
leftover-activity crash (JC20) needs an activity alive across a reinstall.

- **`RingKind` value + unit test (first, 0.5 h).** Extract the branch selection (`.over` / `.running(range)` / `.idle`,
  limited vs full) into a value the views switch on, and test it directly. A DEBUG stand-in ring with five snapshots was
  considered and rejected: it proves the same selection, puts a DEBUG flag in a file compiled into the appex, and its PNGs
  show nothing the user sees.
- **`RenderPreview` spike (1 h).** `ActivityPreviews.swift` already has `#Preview(as: .dynamicIsland(.expanded / .compact /
  .minimal))` and `.content`, Apple's documented render path. If the Xcode MCP renders them, Eric gets reviewable PNGs per
  region and Dynamic Type without a device. The narrow Duo Island cannot be previewed (`isDynamicIslandLimitedInWidth` is
  get-only).
- **Factor the builder closures** into `lockScreen(state:isStale:)` / `islandRegions(...)` functions; the file's honest
  ceiling is ~50 %, and the remainder should be recorded as uncoverable rather than chased.
- **SpringBoard XCUITest** (launch `-liveActivity`, start a rest, press home, find the Lock Screen banner's "Add 30 seconds of
  rest" button in `XCUIApplication(bundleIdentifier: "com.apple.springboard")`, tap, compare the ring), with teardown ending
  every activity. One public project does this for a Stop button; nothing confirms the Island itself is in the accessibility
  tree, and nothing covers the Duo. 4–8 h after a 1 h spike, high flakiness, opt-in and single-sim only; only if
  `RenderPreview` fails.
- **Stays with Eric:** narrow Island on the closed Duo during a rest; buttons in StandBy night (PLAN device checks).

**Eric decides:** a reviewable PNG or an automated pass/fail as the "repeatable Island check"; accept
`WorkoutLiveActivity.swift` below 100 %.

## 6. Flakiness

**Diagnoses** (the 12f5649 shard bundles survive; the 11-06 and 11-08 messages are gone, which is itself a finding):

| Test | What the bundle says | Side |
|---|---|---|
| `AccessibilityAuditUITests/testActiveWorkoutLogging` | "The size of this UILabel is too small"; the element screenshot is the title-menu label "Push" on a settled cover (elapsed 0:06, ring running) | **test-side rule gap, deterministic**: the `.hitRegion` known-issue rule exempts the system title menu only when `elementType == .button`; the `UILabel` variant falls through. Extend the rule to a `.staticText` whose label equals a `navigationBars.buttons` title (15 min). Not a settle problem. |
| `RestRingUITests/testRestEndsWhileSetFieldHasFocus` | `label BEGINSWITH 'Rest timer, '` timed out at 5 s; the shard took 24 min vs 20 for the others on a 4-sim run | load, as the `ui_shard` comment already says, plus a 5 s budget; raise to 15 s. Suspect (unverified) the 0.25 s `TimelineView` in `RestStateProbe` keeps the app from going idle under `-uiTesting`; try a one-shot timer |
| `ExerciseListUITests/testBestSetFollowsUnitChange` | message lost | long chain with un-anchored steps (Settings alert OK, unit segment tap) before a 10 s predicate |
| `FirstFrameUITests/testTemplatePreviewChromeBeforeLastPerformed` | message lost; the file documents an earlier flake and its fix (`.exists` right after the push, 10 s hold) | already fixed; if it flakes again the richer log is the tool |

**Sleeps.** `CoverTimerUITests:17` (2.5 s for a subtitle tick) → predicate `label != before`. The three
`SetTableKeyboardRevealUITests` 1 s sleeps → `waitUntil` on frame equality across two reads. `LoggingBlockMenuUITests:124`
("did not move") legitimately keeps a settle. `PerfDriverUITests` skips itself without `PERF_DRIVER`; leave it.
`XCUIElement+Waiting.swift` already has `waitUntilGone`, `assertStaysAbsent`, `waitUntil`; the Darwin seam
(`expireRestNow`, `debug.restState`) exists.

**Policy.** The "flaky twice in a row" rule compares the same test id against the previous stamp only, so four different
tests in four runs never trips it, and `ui-flaky.log` records no message, duration or shard. Now: write the first attempt's
`failureText`, shard and seconds into the log line (already read in `ui_shard_retry`) and add a `./dev ui-flaky` summary.
Later: a suite-level trigger (≥ 2 flakes of one test, or ≥ 3 of one suite, in the last 8 full runs), but only once the log
has ~10 entries and the full run is back on the upload path; today the full run happens after the upload, so a gate there
fires on nothing. `xcodebuild -retry-tests-on-failure` was considered and rejected: dev's retry already adds the trend rule
the flags lack.

**Eric decides:** whether a retry-passed flake may ever fail a run once the trend gate becomes possible.

## 7. SettingsFlow, the gate table, WorkoutLinkRouter

- **SettingsFlow.** Never run in either suite: `runImport` (47–57), `refreshAfterImport` (100–101, `exerciseStore.setCustom`
  + `engine.resume()` when nothing is running) and the `turnOffFitness` catch (164–168, "Could Not Remove Fitness Data"). The
  import UI has no XCUITest by design (the file picker cannot be driven; `SettingsUITests:202`). Fixes: a
  `performTurnOff(_:)` closure seam like `performImport(refresh:)`; make `runImport` return its `Task` so a test awaits the
  `isImporting` lifecycle; drop `private` on `refreshAfterImport` and test it with a real engine and store on an in-memory
  container (imported unfinished workout shows at once; a running one is untouched). ~2.2 h total. A DEBUG `-importFile
  <fixture>` UI seam (2 h) is possible but only adds alert wiring; defer. Moving `DataTransfer` to the kit only if it changes
  again.
- **WorkoutLinkRouter** (17 %): `OpenWorkoutURLUITests` goes through `.onOpenURL` directly; the router is fed only by the
  rest notification's body tap (`notifier.openWorkout = { links.request() }`) and consumed by `RootView`. A unit test of
  `request()`/`consume()` (0.15 h); `RestNotifierTests` already covers `didReceive` → `openWorkout`. The cold-launch
  consumption stays a device check: a delivered notification cannot be tapped reliably in XCUITest.
- **Gate table.** Eleven `-uiTesting` checks now, in two kinds: eight turn a feature or state off (line numbers all
  drifted) and three turn a test seam on (`HealthLookupProbe.swift:9`, `RestExpirySeam.swift:22` and `:47`). Section 2C of
  the 2026-11-07 review says six. The `WorkoutsApp.swift` Live Activity row must change: no test passes `-liveActivity`;
  coverage is `LiveActivityControllerTests` and device runs. The drafted replacement table is in the appendix report.

## Cross-cutting

- **The gate plumbing has no tests.** `dev` is ~1500 lines of bash and `duo-test` covers `Tools/duo` only. This plan adds a
  stamp, a path diff and a log format to it, and the review found that both gates as first drafted would never have fired
  under `DEV_SKIP_UI_GATE=1`. One `./dev selftest` over stamp and gate parsing (fixture files, no sim) is cheaper than the
  first silent mis-gate.
- **Field-level schema drift.** `./dev ck-schema diff` compares record types between environments. A new optional attribute
  (the additive change the rules allow) deploys nothing to Production and the diff stays green; TestFlight then logs a schema
  error on the first record that sets it. Compare the exported `.ckdb` field list with the current schema's attributes.
- **The unit-test bundle is unstamped**, so `./dev coverage` can report numbers from a stale build without saying so. Have
  `./dev test` write a stamp like `ui-test.stamp`.
- **Pin a date on evidence.** Only the latest run's xcresult bundles survive, so two of four flake causes are unrecoverable.
  The failure text in the log closes most of this.
- **"Off under the harness" has a third kind.** Besides feature gates and isolation, three seams turn test-only machinery on.
  The gate table should carry a "kind" column so a reviewer can see which green means "correct", which "off", and which "the
  seam fired".
- **Dedicated non-pool sims** solve two gaps at once (Health grant persistence, iCloud sign-in survival).
- **Time zone of snapshot references** follows the host Mac; `sim_reset_ui` pins size and appearance, not the zone. A travelling
  Mac or a clone created under another zone fails `SnapshotTests`.
- **No flow runs dark.** Snapshots cover AX3 and dark per component; only the audit suite launches at AX sizes. One dark run of
  `SmokeUITests` would catch a `.white` literal cheaply.
- **Extension plist keys.** The appex needs no entitlements, but `AppBundleTests` could assert `NSSupportsLiveActivities` and the
  time-sensitive entitlement so a project-file edit cannot drop them.
- **Covered already, left out on purpose:** migrations (`OnDiskStoreMigrationTests`), import/export round trips
  (`ImportExportFlowTests`, `WebExportTests`), notification `didReceive`.
- **Honest ceilings.** `WorkoutLiveActivity.swift` (`ActivityConfiguration`), the Health predicates and statistics, and
  `NSPersistentCloudKitContainer` behaviour are uncoverable in automation; record them as such in PLAN rather than chase the
  number.

## Appendix

Per-gap worker reports, with code sketches, line references and sources, and the Fable review with its 34-claim spot-check
log: `2026-11-09-coverage-research/{duo,restpicker,health,cloudkit,liveactivity,flaky,settings-gates,fable-review}.md`.
