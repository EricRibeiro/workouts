# Covering the remaining test gaps (research, 2026-11-09)

Seven read-only research workers (one per gap), Apple-docs checks, and two independent Fable reviews (the second did not
read the first): 34 and 27 claims spot-checked, 25 and 24 confirmed, the rest line drifts or three substantive errors each,
all folded in below. The per-gap reports with code sketches and sources, and both reviews, are in
`2026-11-09-coverage-research/`. Coverage numbers: `latest-ui-test.xcresult` is the full run on 12f5649 (its merged bundle
includes the two failed first attempts and their retries); `latest-test.xcresult` is an earlier 11-08 build (the unit bundle
carries no stamp, see Cross-cutting). Kit 97.6 % lines, `Workouts.app` 80 % under the UI suite and 33 % under unit tests by
design; `WorkoutsLiveActivity.appex` 65 % under unit tests and 0 % under the UI suite, which never launches the extension.

Two findings from the first survey were wrong: the Duo placement logic is already unit-tested (`FoldPlacement`, 26 kit
tests; `BenchArrangement.swift` is 0 % under unit tests but 29 % under the UI suite, with only the open and bench branches
dark), and the 2026-11-07 gate table's claim that a `-liveActivity` fixture test exists is false (no UI test passes the flag).

## Plan at a glance

| # | Gap | Do first (one small commit, this week) | Do now | Do next | Keep manual |
|---|---|---|---|---|---|
| 0 | Flakiness | audit `.hitRegion` rule for `.staticText` titles + element description in the failure text; `startRest` budget 5 → 15 s; then one full `./dev ui-test` to clear the stamp's `flaky=` (1 h) | `RestStateProbe` mounts only while a rest is active, compare shard wall times (1 h); failure text, shard and seconds into `ui-flaky.log` + `./dev ui-flaky` (1.5 h) | replace the 4 sleeps with predicates (2–3 h); trend gate once the log has ~10 entries and the full run is back in front of uploads | — |
| 1 | Duo open poses | — | `ImageRenderer` placement snapshot of `ArrangementView` at 951×669 and 669×951, after a 15-min render spike (1 h) | `DEV_POSE` + `OpenPoseUITests`, only after two spikes: posing around `run_tests` without breaking its EXIT trap, and whether XCUITest rotation re-lays out the inner display (3–4 h if both pass) | hinge fold and bench; `./dev poses` stays the reviewer proof |
| 2 | Rest timer picker | — | template-editor UI test with Cancel (1 h); logging-cover test launched with `-sampleNoRest`: pick 30 s, check a set, ring reads 16–30 s (1 h) | — | — |
| 3 | HealthKit real store | — | helpers-only unit seam in `HealthKitSource` (2–3 h); the "answered count" check, twice on one clone (orchestrator, 10 min) | `tf_health_gate` on every `--upload` with its own override, a stamp that refuses skipped runs, its own xcresult name, a `sim_heal` exemption for named non-pool sims, and `./dev selftest` fixtures for the stamp and gate parsing, in one change (3 h) | sheet-driver survival across iOS versions; Watch data |
| 4 | CloudKit sync | — | `CKDatabase` seam + `CloudSyncMonitor.map` seam (2 h); 30-min spike on whether a second in-process container's save posts `NSPersistentStoreRemoteChange`, then the two-container history test with a hand-posted fallback (2 h, 4 h if the spike passes) | offline `NSPersistentCloudKitContainer` load check in `WorkoutsTests` (1–2 h); exempt the iCloud sims from `sim_heal` and prune | `cktool` record probe (needs a user token that does not exist), push-driven merge, Production, `./dev sync-check` until a second device |
| 5 | Live Activity | — | `ringKind(restOver:)` on `WorkoutActivityState` in the kit + kit test (0.5 h); `RenderPreview` spike on `ActivityPreviews` (1 h) | factor the `ActivityConfiguration` builder closures (1.5 h); record the appex ceiling per target | Island on the closed Duo, StandBy; SpringBoard XCUITest only if `RenderPreview` fails |
| 6 | SettingsFlow, gates, link router | — | `performTurnOff` seam + `WorkoutLinkRouter` unit test (0.65 h); gate table update + the `simctl privacy … reset all` line in `docs/port/healthkit.md` (20 min) | `runImport` awaitable + `refreshAfterImport` test (1.5 h) | file picker, notification tap on device |

About 14 h of "now" work and 15 h of "next". Nothing in "now" adds a simulator pose or a network call to the gate, no seam
leaks into a release build, and the two `dev` gates sit off the `tf_ui_gate` path, where `DEV_SKIP_UI_GATE=1` (the routine
upload mode since 11-08) would have made them dead code.

**Why gap 0 comes first.** The stamp on 12f5649 lists both flaky tests, and `ui_shard_retry` refuses a second retry for a
test named in the previous stamp. The next unfiltered run therefore fails hard if either flakes again, and that run gates
the next milestone. Land the two fixes, then one full run, before anything else.

## 1. Duo open poses

**What is really uncovered.** `FoldPlacement.placement(size:divisions:axes:)` and `frames(for:in:headerHeight:)` are in
the kit with 26 tests (wide, tall, square, book, laptop, keyboard-up, clamping). `BenchArrangement.swift` is the glue:
`BenchArrangementBody` reads `GeometryReader` size and `reservedRegions(kind: .division)`; the size class is read one level
up (`ActiveWorkoutCover` passes both axes only when `horizontalSizeClass == .regular`). The closed-pose path runs under
every cover UI test (29 %); the open and bench branches never run. Open-wide and open-tall are reproducible from geometry
alone (951×669 → side by side, 669×951 → stacked); bench (half-open) needs a real division and cannot be faked. The
accessibility audit also runs closed only, so the pane, the bench rest and the side-by-side table have never been audited.

**Facts that bound the options.** `XCUIDevice` has orientation and appearance, no hinge or fold API (Apple docs); there is
no `simctl` hinge verb; the hinge is driven only by `Tools/duo` through a private HID path from the host. Hosted snapshot
windows cannot be wider than the sim's scene, which is why the dashboard and heart-rate wide snapshots use the
`ImageRenderer` engine at 700–800 pt. `docs/port/duo-layout.md` says the inner display does not honour supported interface
orientations and the app scales there, while `NamedPose` defines open-tall as open + landscape-left; both cannot describe a
relayout, so whether an XCUITest rotation re-lays out the open Duo is unknown. Bash has one EXIT trap and `sim_lock` already
owns it; `./dev tree` also goes through `run_tests`.

**Options, ranked.**

- **A. `ImageRenderer` placement snapshot** of `ArrangementView` with coloured placeholders under `BenchArrangementStyle`
  at both open sizes (and axes `[]` for single). Proves the glue applies `FoldPlacement` for the open branches, inside
  `./dev check`. Spike first (15 min): does `ArrangementView` render under `ImageRenderer`. 1 h, deterministic.
- **B. `DEV_POSE`.** A wrapper around `run_tests` poses the sim under the lock, exports `TEST_RUNNER_DUO_POSE`, and the
  lock's own release path restores closed-portrait. A new `OpenPoseUITests` skips without the env (the `TreeDumpUITests`
  pattern), asserts the window is 951×669 and the exercise pane sits in the right half, then sets
  `XCUIDevice.shared.orientation = .landscapeLeft` and asserts the focused cell, its typed draft and the scroll position
  survive side-by-side → stacked. It would also be the first audit of the open layout. Two spikes before the estimate
  stands: the pose wrapper, and the inner-display rotation question above. 3–4 h; excluded from the sharded full run, run
  before TestFlight.
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
entry and `PastEditorUITests.testBlockMenuOffersOnlyTheNotes` already asserts that. The kit already covers both halves of
the cover path: `setRestChangesOnlyThatRowAndPersists` writes `row.restSeconds`, and `RestTimerTests` proves a check starts
a rest of the row's length, replaces a running rest, and that Off leaves one alone. The UI tests assert wiring only.

- **Template editor test.** The block header caption changes immediately (`Rest 1:30`, `Rest off`, `Rest 1:00 (default)`
  from `SetTableLayout.restCaption`), so one test covers open, current-row `.isSelected`, every option branch, dismiss and
  `draft.updateRestTimers`; a second covers Cancel. Add a `settable.restCaption.<id>` identifier (one line) instead of
  label-prefix matching. The seeded first block carries 150 s (`SampleData`), so the caption starts at `Rest 2:30`. 1 h,
  low flakiness.
- **Logging cover test.** Launch with `-sampleNoRest` (the existing fixture `RestRingUITests` uses, so the workout starts
  idle), pick 30, check the first unchecked set, read `rest.ring` and assert 16…30 s. Move the `private` ring helpers from
  `RestRingUITests` into `Support/` first. 1 h, medium flakiness (ticking ring, bounded as `RestRingUITests` does).
- **Skip** a snapshot of the sheet. **Optional:** spoken labels "30 seconds" instead of "0:30".

## 3. HealthKit real store

`HealthKitSource.swift` is 0 % because only `HealthKitIntegrationUITests` reaches it, and that test skips unless
`HEALTH_INTEGRATION` is set. The reason is the Health Access sheet: a separate process (`com.apple.HealthPrivacyService`),
private identifiers, an iOS 27 data-range page, Allow hidden until a swipe. Runtime is about a minute; shared-state risk is
small (the seeder deletes only its own tagged objects). `simctl privacy` has no `health` service, so pre-granting is out
(and the `simctl privacy … reset all` advice in `docs/port/healthkit.md` resets nothing for Health); an interruption monitor
does not fire for another process's sheet. A filtered run also overwrites `latest-ui-test.xcresult`, clobbering the
full-run coverage bundle, and a skipped run exits 0.

- **Unit seam, helpers only (first).** Make `map`, `kind(of:)`, `quantity(_:in:)`, `text(_:)`, the unit choice in
  `statistic` and the summary arithmetic (active + basal, HR offset, humidity ×100, rated-over-estimated effort) internal and
  test them in `WorkoutsTests`. About 100–120 of 288 lines, 2–3 h. A full `HKHealthStore` protocol (6–8 h) was rejected: the
  high-risk lines (predicates, `statistics(for:)`, activities, routes) have no public constructors and need the real store.
- **Ten-minute check (orchestrator):** run the filtered test twice on one clone and read the `answered` count. If the second
  run answers 0, the sheet is a first-run cost and the 90 s deadline can drop to 30 s.
- **Gate on change, not on a clock (recommended cadence).** A `.build/health-test.stamp` written only when the filtered run
  passes with `skippedTests == 0`. A new `tf_health_gate`, called on every `--upload` and independent of `tf_ui_gate` (which
  returns before any check under `DEV_SKIP_UI_GATE=1`), fails when `HealthKitSource.swift`, `HealthSeeder.swift`, the
  entitlements or the test changed since the stamped commit, with its own `DEV_SKIP_HEALTH_GATE=1` override. Pin the run
  to a dedicated clone outside `sim_pool_names` ("iPhone Duo Health") so the grant and seed persist, save its xcresult under
  its own name, and exempt named non-pool sims from `sim_heal`, which today erases any held clone after two system-process
  crashes regardless of pool membership (the same exemption the iCloud sims need). Every `dev` edit forces a full
  `./dev check` before commit and the script has no tests, so ship `./dev selftest` (fixture stamps, gate parsing) in the
  same change. 3 h. A weekly or every-run cadence was rejected: unattended sheet flakes, or a stale commit unrelated to
  uploads.

**Eric decides:** hard block on upload vs warning; a sixth non-pool clone (disk) vs reusing "iPhone Duo 5".

## 4. CloudKit sync

**Current state.** Every kit test builds `inMemory: true, cloudKit: false`; `ModelContainer.workouts` exposes no URL or
store options. The remote-change wiring and the P8-04 author filter (`ForeignHistoryCheck`, private in `WorkoutsApp.swift`)
have no test; kit tests call `engine.reloadAfterRemoteChange()` by hand, and the only `RemoteChangeObserver` test posts
`NSPersistentStoreRemoteChange` itself. `CloudSyncMonitor` already maps `NSPersistentCloudKitContainer.Event` to a kit value,
so only the 15-line map is untested. `CloudKitMediaSource` is 12 %. The pool is hostile to signed-in sims: `sim_heal` and
`sims --prune` erase clones, which signs them out of iCloud.

- **D + C. `CKDatabase` seam and event-map seam (first, cheap).** A `RecordFetching` protocol lets a fake exercise
  dark → light fallback, `.unknownItem` → nil, rethrow and cancellation (~90 % of the file). `CloudSyncMonitor.map` takes
  plain fields so three more `CloudSyncStatusTests` cover it. 2 h. A `cktool query-records` probe against the public
  database would check record type and field names against the Console, but `cktool` assigns record operations to user
  tokens, not the management token in 1Password; a new secret for a manual probe is not worth it.
- **B. Two on-disk containers + persistent history (after a 30-min spike).** Move `ForeignHistoryCheck` into the kit; add a
  test-only `ModelContainer.workouts(at: URL)`. Open two containers on the same sqlite file, author `"app"` on one and
  `"NSCloudKitMirroringDelegate.import"` on the other; if a save on the mirror posts a real `NSPersistentStoreRemoteChange`,
  the observer debounces (manual clock), the filter passes, the engine adopts the workout, and a local save does not fire.
  Whether SwiftData sets the remote-change post option on a second in-process container is unverified and decides most of
  the value: spike it first. The likely outcome is the fallback (post the notification from the test, keep the
  history-author assertions), about 2 h; the full version is 4 h. Either way it is the natural place to drive
  `InProgressResolution` through the mirror author and prove a recent remote in-progress row is never settled or deleted.
- **A. Offline model validation in `WorkoutsTests` (spike 30 min, then 1–2 h).** Load the SwiftData-generated
  `NSManagedObjectModel` into an `NSPersistentCloudKitContainer` on a temp store with `cloudKitContainerOptions`; the
  mirroring delegate rejects a CloudKit-incompatible model at load. Then `initializeCloudKitSchema(options: .dryRun)`; Apple's
  docs are silent and forum reports say it needs an account, in which case keep only the load assertion. It stays in the app
  test target because `swift test` on macOS runs unsigned with no iCloud entitlement (the kit itself already imports CoreData
  and SwiftData). Catches what the metadata walk in `CloudKitSchemaRulesTests` cannot (SwiftData's transformed attribute
  types, Codable attributes, inverse mapping).
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
compact trailing resting/restOver). `WorkoutLiveActivity.swift` (0/82, appex target) is the `ActivityConfiguration` +
`DynamicIsland` builder, which only the WidgetKit host instantiates; no documented test path exists. No UI test passes
`-liveActivity`. The leftover-activity crash (JC20) needs an activity alive across a reinstall.

- **`ringKind(restOver:)` on `WorkoutActivityState` in the kit (first, 0.5 h).** The ring's branch selection
  (`.over` / `.running(range)` / `.idle`, limited vs full) depends only on `restOver` and `restRange()`, both kit values, so
  the value lives in the kit, runs under `./dev kit` in a second, and keeps the appex view file free of test-shaped types.
  A DEBUG stand-in ring with five snapshots was considered and rejected: it proves the same selection, puts a DEBUG flag in
  a file compiled into the appex, and its PNGs show nothing the user sees.
- **`RenderPreview` spike (1 h).** `ActivityPreviews.swift` already has `#Preview(as: .dynamicIsland(.expanded / .compact /
  .minimal))` and `.content`, Apple's documented render path. If the Xcode MCP renders them, Eric gets reviewable PNGs per
  region and Dynamic Type without a device. The narrow Duo Island cannot be previewed (`isDynamicIslandLimitedInWidth` is
  get-only).
- **Factor the builder closures** into `lockScreen(state:isStale:)` / `islandRegions(...)` functions; the file's honest
  ceiling is ~50 %, and the remainder is recorded as uncoverable, per target, rather than chased.
- **SpringBoard XCUITest** (launch `-liveActivity`, start a rest, press home, find the Lock Screen banner's "Add 30 seconds of
  rest" button in `XCUIApplication(bundleIdentifier: "com.apple.springboard")`, tap, compare the ring), with teardown ending
  every activity. One public project does this for a Stop button; nothing confirms the Island itself is in the accessibility
  tree, and nothing covers the Duo. 4–8 h after a 1 h spike, high flakiness, opt-in and single-sim only; only if
  `RenderPreview` fails.
- **Stays with Eric:** narrow Island on the closed Duo during a rest; buttons in StandBy night (PLAN device checks).

**Eric decides:** a reviewable PNG or an automated pass/fail as the "repeatable Island check".

## 6. Flakiness

**Diagnoses** (the 12f5649 shard bundles survive, three shards on Duo 3, 4 and 5; the 11-06 and 11-08 messages are gone,
which is itself a finding):

| Test | What the bundle says | Side |
|---|---|---|
| `AccessibilityAuditUITests/testActiveWorkoutLogging` | "The size of this UILabel is too small"; the element screenshot is the title-menu label "Push" on a settled cover (elapsed 0:06, ring running); passed alone on retry | **test-side rule gap, intermittent trigger**: the `.hitRegion` known-issue rule exempts the system title menu only when `elementType == .button`; while the bar settles the title is exposed as a `UILabel` and falls through. Extend the rule to a `.staticText` whose label equals a `navigationBars.buttons` title, and put `issue.element?.debugDescription` in the failure text (15 min). |
| `RestRingUITests/testRestEndsWhileSetFieldHasFocus` | `label BEGINSWITH 'Rest timer, '` timed out at 5 s; the test took 4 min 15 s; its shard took 24 min vs 20 for the others | load, as the `ui_shard` comment already says, plus a 5 s budget; raise to 15 s. The `RestStateProbe` mounted in `RootView` under `-uiTesting` ticks a 0.25 s `TimelineView` on every screen of every UI test, rest or no rest: a suite-wide quiescence cost, not a rest-only suspect. Mount it only while a rest is active (or a one-shot timer) and compare shard wall times. |
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
the flags lack. Separately, `-test-timeouts-enabled YES -default-test-execution-time-allowance <s>` would turn a stalled test
into a fast failure with a spindump instead of a silent four-minute shard tax; cheaper than any log change.

**Eric decides:** whether a retry-passed flake may ever fail a run once the trend gate becomes possible.

## 7. SettingsFlow, the gate table, WorkoutLinkRouter

- **SettingsFlow.** Never run in either suite: `runImport` (47–57), `refreshAfterImport` (100–101, `exerciseStore.setCustom`
  + `engine.resume()` when nothing is running) and the `turnOffFitness` catch (164–168, "Could Not Remove Fitness Data"). The
  import UI has no XCUITest by design (the file picker cannot be driven; `SettingsUITests:202`). Fixes, in the file's
  existing closure-seam style: a `performTurnOff(_:)` seam like `performImport(refresh:)`; make `runImport` return its `Task`
  so a test awaits the `isImporting` lifecycle; test `refreshAfterImport` with a real engine and store on an in-memory
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
  coverage is `LiveActivityControllerTests` and device runs. The drafted replacement table is in the appendix report. Fix
  the `simctl privacy … reset all` line in `docs/port/healthkit.md` in the same pass.

## Cross-cutting

- **The gate plumbing has no tests.** `dev` is ~1500 lines of bash and `duo-test` covers `Tools/duo` only. This plan adds a
  stamp, a path diff and a log format to it, and the first review found that both gates as first drafted would never have
  fired under `DEV_SKIP_UI_GATE=1`. `./dev selftest` over stamp and gate parsing (fixture files, no sim) ships with the first
  gate change.
- **The skip count is unasserted.** Every full run reports exactly 5 skipped (PerfDriver 3, HealthKitIntegration 1,
  TreeDump 1). An accidental `XCTSkip` would pass unnoticed; `cmd_ui_test` should refuse to stamp when `skippedTests != 5`.
- **No per-test timeout.** See gap 6; one `xcodebuild` flag.
- **Field-level schema drift.** `./dev ck-schema diff` compares record types between environments. A new optional attribute
  (the additive change the rules allow) deploys nothing to Production and the diff stays green; TestFlight then logs a schema
  error on the first record that sets it. Compare the exported `.ckdb` field list with the current schema's attributes.
- **The unit-test bundle is unstamped**, so `./dev coverage` can report numbers from a stale build without saying so; and the
  merged UI bundle includes failed first attempts, so "coverage of the last passing run" is a slight misnomer. Have
  `./dev test` write a stamp like `ui-test.stamp`.
- **Pin a date on evidence.** Only the latest run's xcresult bundles survive (plus any failed filtered run's until the sweep),
  so two of four flake causes are unrecoverable. The failure text in the log closes most of this.
- **"Off under the harness" has a third kind.** Besides feature gates and isolation, three seams turn test-only machinery on.
  The gate table should carry a "kind" column so a reviewer can see which green means "correct", which "off", and which "the
  seam fired".
- **`sim_heal` erases any held clone**, pool or not, after two system-process crashes. The Health clone and the iCloud sims
  need the same exemption; one change serves both.
- **Time zone of snapshot references** follows the host Mac; `sim_reset_ui` pins size and appearance, not the zone. A travelling
  Mac or a clone created under another zone fails `SnapshotTests`.
- **No flow runs dark, and the open Duo is never audited.** Snapshots cover AX3 and dark per component; only the audit suite
  launches at AX sizes, closed. One dark run of `SmokeUITests` would catch a `.white` literal cheaply; the posed suite (gap 1
  B) is the first chance to audit the open layout.
- **Extension plist keys.** The appex needs no entitlements, but `AppBundleTests` could assert `NSSupportsLiveActivities` and the
  time-sensitive entitlement so a project-file edit cannot drop them.
- **Covered already, left out on purpose:** migrations (`OnDiskStoreMigrationTests`), import/export round trips
  (`ImportExportFlowTests`, `WebExportTests`), notification `didReceive`.
- **Honest ceilings.** `WorkoutLiveActivity.swift` (`ActivityConfiguration`), the Health predicates and statistics, and
  `NSPersistentCloudKitContainer` behaviour are uncoverable in automation; record them as such in PLAN, naming the target
  the number comes from, rather than chase the number.

## Appendix

Per-gap worker reports, with code sketches, line references and sources, and the two independent Fable reviews with their
spot-check logs: `2026-11-09-coverage-research/{duo,restpicker,health,cloudkit,liveactivity,flaky,settings-gates,fable-review,fable-review-2}.md`.
