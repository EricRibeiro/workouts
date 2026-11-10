# Independent review of the coverage research and plan (HEAD 643c067)

Read-only. Verified against `dev`, the result bundles, the code and the docs; the earlier Fable review and the synthesis file's git history were not read.

## Verdict

The synthesis is accurate where it counts: 24 of the 27 claims I checked hold, the coverage numbers match both bundles, the gate semantics (`tf_ui_gate` returns before any check under `DEV_SKIP_UI_GATE=1`, which is the routine upload mode in `docs/testflight.md`) are described correctly, and the "do now" column is mostly cheap, deterministic work inside `./dev check`. Three things are wrong or under-weighted. First, the plan treats the two flaky tests as research items when the repo is already armed against them: the stamp on 12f5649 lists both, and `ui_shard_retry` refuses a second retry for a test named in the previous stamp, so the next full run fails on either flake and blocks the next milestone gate. The audit rule fix and the `startRest` budget belong in one small commit before anything else, not inside a 16-hour "now" bucket. Second, the audit flake is labelled deterministic, but it passed alone on retry; the `.button`-only rule is the gap, the trigger is a transient (title exposed as `UILabel` while the bar settles). Third, two "now" items are padding: the kit `setRest → check` test duplicates `RestTimerTests`, and the `RestStateProbe` timer is filed as a one-test suspect when it ticks 4×/s on every screen of every UI test. The CloudKit two-container test and the Health gate are sound in intent but each needs its stated spike, and the Health clone is not safe from `sim_heal`. Nothing in "now" leaks into release builds or changes product behaviour.

## Findings

| id | sev | gap | claim or recommendation | what is wrong or missing | evidence | suggested change |
|---|---|---|---|---|---|---|
| F1 | P0 | 6 | Audit rule fix (15 min) and `startRest` 5→15 s are "do now" items | The current stamp names both tests as flaky; `ui_shard_retry` skips the retry for a test in the previous stamp's `flaky=`, so the next unfiltered run fails hard if either flakes again, and that run gates the next milestone | `.build/ui-test.stamp` `flaky=AccessibilityAudit…,RestRing…`; `dev:458-460`; `dev:1177` | Land both fixes first, in one commit, before the next `./dev ui-test`; then the rest of the plan |
| F2 | P2 | 6 | Audit flake is a "deterministic rule gap" | It passed alone on retry (10 s fail, 12 s pass); the rule gap is real but the trigger is transient. Also "4-sim run" is wrong: 3 shards (Duo 4, 3, 5) | `shard-1.xcresult` failure text "The size of this UILabel is too small"; element screenshot "Push"; `AccessibilityAuditUITests.swift:99`; `summary.tsv` | Keep the rule fix; add `issue.element?.debugDescription` to the failure text as the flaky worker proposed; say "intermittent" |
| F3 | P1 | 6 | `RestStateProbe` 0.25 s `TimelineView` is a suspect for one RestRing stall | The probe mounts under `-uiTesting` on every screen and ticks regardless of rest state, so it is a suite-wide quiescence cost, not a rest-only one. Cheap to test (mount only when `engine.restTimer.isActive`, or a one-shot timer) | `Workouts/Debug/RestExpirySeam.swift:47-58` | Move to "now": one commit, compare shard wall times (19m49/19m41/24m12 today) |
| F4 | P3 | 2 | "No test covers `engine.setRest` followed by a check" (15 min kit test) | Literally true, but both halves are tested: `setRestChangesOnlyThatRowAndPersists` writes `row.restSeconds`; `RestTimerTests` sets `restSeconds` on a row and asserts `check` starts that length, including 0 | `ActiveWorkoutEngineSupersetTests.swift:361-368`; `RestTimerTests.swift:25,228-238,262` | Drop it, or add only the "Off leaves a running rest alone" case if `:262` does not already cover it |
| F5 | P3 | 2 | Logging-cover test: "no skip step, the check replaces the launch rest" | A cleaner fixture exists and the research missed it: `-sampleNoRest` starts the workout idle, already used by `RestRingUITests`. The restpicker worker asked Eric about `-sampleRestSeconds` instead | `WorkoutsApp.swift:395`; `RestRingUITests.swift:127` | Launch with `-sampleNoRest`; the 16…30 s bound then needs no "replaced" reasoning. Not a decision for Eric |
| F6 | P1 | 3 | Pin the Health run to a dedicated non-pool clone "so the grant and seed persist" | `sim_heal` erases any clone (`sim_is_clone`), pool or not, after 2 SpringBoard/PosterBoard crashes during a command; a sheet-driver crash loop on the Health clone wipes the grant the plan relies on. Prune and the reaper do skip it (they iterate `sim_pool_names`) | `dev:996-998`, `dev:931-940`, `dev:1105-1121` | Exempt named non-pool sims from `sim_heal` (same exemption the iCloud sims need in gap 4); one change serves both |
| F7 | P2 | 3 | `tf_health_gate` on every `--upload` with a path diff | Sound, but the stamp writer must read `skippedTests` (a skipped run exits 0) and the filtered run must stop overwriting `latest-ui-test.xcresult`; both are `run_tests` changes to an untested 1500-line script, and every `dev` edit forces a full `./dev check` before commit | `dev:270-271`, `dev:280-291`; `.claude/hooks/require-check.sh` | Do `./dev selftest` (fixture stamp + gate parsing) in the same change, as the cross-cutting section proposes, not later |
| F8 | P2 | 3 | `simctl privacy` has no `health` service, so pre-granting is out | Confirmed. But `docs/port/healthkit.md:147` still tells agents to `simctl privacy … reset all` to re-exercise the sheet; that resets nothing for Health | `xcrun simctl privacy` service list (no health); `healthkit.md:147` | Fix the doc line when the gate table is updated |
| F9 | P2 | 4 | Option A stays in `WorkoutsTests` because "the kit's contract is Foundation-only" | Wrong reason: the kit already imports CoreData and SwiftData. The right reason is signing: `swift test` on macOS runs unsigned with no iCloud entitlement | `Packages/WorkoutsKit/Sources/WorkoutsKit/Model/RemoteChangeObserver.swift` (`import CoreData`) | Correct the sentence; the placement stands |
| F10 | P2 | 4 | `cktool query-records` probe "under `./dev ck-schema` style `op run`"; management-token question unverified | The verb and flags exist (`--database-type`, `--environment`, `--record-type`, `--token`). `cktool` distinguishes management and user tokens (`save-token --type management\|user`); Apple assigns record operations to user tokens, so the probe needs a second secret and a 1Password item that does not exist | `xcrun cktool query-records --help`; `xcrun cktool save-token --help` | Treat as a spike with a new secret, or drop; the `CKDatabase` seam is the real "now" |
| F11 | P2 | 4 | Two-container test, 3–4 h | The unknown (does SwiftData set the remote-change post option on a second in-process container) decides most of the value; the fallback (post the notification, keep the history-author assertions) is the likely outcome and costs about 2 h | `Schema.swift:65-85` (no `url:` overload, no store options exposed); `CloudKitReadinessTests.swift:262-271` already posts `.NSPersistentStoreRemoteChange` by hand | Estimate 2 h + 30 min spike; book the extra 2 h only if the spike passes |
| F12 | P3 | 5 | `RingKind` value in the appex view file + unit test in `WorkoutsTests` | The selection depends only on `restOver` and `WorkoutActivityState.restRange()`, both kit values. A `ringKind(restOver:)` on `WorkoutActivityState` in the kit is tested by `./dev kit` in 1 s and keeps the appex file free of test-shaped types | `WorkoutsLiveActivity/DynamicIslandViews.swift:9-38` | Put the value in the kit |
| F13 | P3 | 1 | Option B sketch installs an EXIT trap inside `run_tests` | Bash has one EXIT trap; `sim_lock` already set `trap sim_release EXIT` and the sharded path layers `ui_cleanup` then clears it. The sketch calls `sim_release` itself, but `./dev tree` also goes through `run_tests` and would pose too | `dev:847`, `dev:540,557`, `dev:1412` | Pose in a wrapper around `run_tests`, restore in `sim_release`'s caller; spike as the plan says |
| F14 | P3 | 1 | Rotation in the open pose gives sideBySide → stacked | `docs/port/duo-layout.md:20` says the inner display does not honour supported orientations and the app scales there, while `NamedPose` makes open-tall = open + landscape-left. The two statements cannot both describe a relayout; the plan's spike is required, not optional | `duo-layout.md:20`; synthesis §1 | Keep B behind the spike; A is the only "now" item |
| F15 | P3 | 7 | Gate table: eleven checks, three seams | Confirmed exactly (8 off-switches, `HealthLookupProbe.swift:9`, `RestExpirySeam.swift:22,47`); the 2026-11-07 table's "six" and all its line numbers are stale | `grep -rn '"-uiTesting"' Workouts` → 11 | None; do the 15-min update |
| F16 | P3 | 5 | "`WorkoutLiveActivity.swift` (0 %)" | Correct, but it is reported under the `WorkoutsLiveActivity.appex` target (0/82), not `Workouts.app`; `./dev coverage` output lists the appex separately. The appex is 0/655 under the UI suite and 64.9 % under unit tests | `xccov --files-for-target WorkoutsLiveActivity.appex` | Say which target the number comes from when recording the ceiling in PLAN |

## My plan (where it differs)

| # | Gap | Do first (this week, small commits) | Do now | Do next | Keep manual |
|---|---|---|---|---|---|
| 0 | 6 | Audit `.hitRegion` rule for `.staticText` titles + element description in the failure text; `startRest` budget 15 s; **then one full `./dev ui-test`** to clear the stamp's `flaky=` (1 h total) | `RestStateProbe` mounts only while a rest is active, measure shard times (1 h); `ui-flaky.log` gets failure text, shard, seconds + `./dev ui-flaky` (1.5 h) | predicates for the 4 sleeps (2–3 h); trend gate when the log has ~10 entries | — |
| 1 | 1 | — | `ImageRenderer` placement snapshot after the 15-min render spike (1 h) | B only after both spikes (3–4 h) | hinge fold, bench; `./dev poses` |
| 2 | 2 | — | template-editor test + Cancel (1 h); logging-cover test launched with `-sampleNoRest` (1 h, not 1.5) | — | — |
| 3 | 3 | — | helpers-only unit seam (2–3 h); the twice-on-one-clone "answered" check (10 min) | `tf_health_gate` + stamp + own xcresult name + `sim_heal` exemption for named non-pool sims + `./dev selftest` fixtures, in one change (3 h, not 2) | sheet driver survival; Watch data |
| 4 | 4 | — | `CKDatabase` seam + `CloudSyncMonitor.map` seam (2 h); 30-min remote-change spike, then fallback test (2 h) or full (4 h) | offline `NSPersistentCloudKitContainer` load check (1–2 h) | `cktool` record probe (needs a user token), `sync-check`, push merge, Production |
| 5 | 5 | — | `ringKind` on `WorkoutActivityState` in the kit + kit test (0.5 h); `RenderPreview` spike (1 h) | factor builder closures (1.5 h); record the appex ceiling per target | Island on the closed Duo; StandBy |
| 6 | 7 | — | `performTurnOff` seam + router test (0.65 h); gate table + `healthkit.md:147` fix (20 min) | `runImport` awaitable + `refreshAfterImport` (1.5 h) | picker; notification tap |

"Now" drops to about 14 h with the two duplicates removed and the flake fixes pulled forward; "next" grows by about 1 h for the gate self-test.

## Blind spots

- **No per-test timeout.** `xcodebuild` supports `-test-timeouts-enabled YES -default-test-execution-time-allowance <s>`; a stalled test then fails with a spindump instead of eating 4 min 15 s of a shard silently. Cheaper than any log format change and never mentioned.
- **The skip count is unasserted.** Every full run reports exactly 5 skipped (PerfDriver 3, HealthKitIntegration 1, TreeDump 1). A new accidental `XCTSkip` would pass unnoticed; `cmd_ui_test` could refuse to stamp when `skippedTests != 5`.
- **The open Duo is never audited.** `AccessibilityAuditUITests` runs closed only, so the pane layout, bench rest and the side-by-side table have no audit at all; option B would be the first chance to run one.
- **`sim_heal` erases any clone**, which is the same hazard for the proposed Health clone and the iCloud sims; the research treats them as two problems.
- **`./dev coverage` reads a merged bundle that contains the shard failures** (`failedTests: 2` in `latest-ui-test.xcresult`), so "coverage of the last passing run" includes a failing first attempt and the retry. Harmless for lines, misleading as evidence.
- **A failed filtered run leaves its bundle** (`ui-test-60677.xcresult` from 11-08 19:07) until a later run's 240-min sweep; not a gap, but the "only the latest bundle survives" story is slightly off.

## Decisions for Eric (trimmed)

Real decisions: whether a flake that passed on retry may ever fail a run once a trend gate exists; whether posed suites join any gate or stay opt-in; whether the Health gate hard-blocks or warns; disk for a sixth clone. Everything else the research should have settled itself: `-sampleNoRest` vs skipping the launch rest (fixture exists), the kit `workouts(at:)` overload and moving `ForeignHistoryCheck` (routine, test-only), label matching vs a caption id (add the id, it is one line), `refreshAfterImport` visibility (closure seams are the file's existing style), accepting `WorkoutLiveActivity.swift` below 100 % (there is no documented path; record it), and the `RestStateProbe` experiment (a `-uiTesting`-only change with no product effect).

## Spot-check log

| # | Claim | Result | Evidence |
|---|---|---|---|
| 1 | Kit 97.6 %, app 80 % under UI, 33 % under unit | confirmed (80.24 %, 32.97 %; kit not re-run) | `xccov --report` on both bundles |
| 2 | `HealthKitSource.swift` 0/288 under the UI suite | confirmed | `xccov --files-for-target Workouts.app latest-ui-test` |
| 3 | `BenchArrangement.swift` 0 % unit, 29 % UI | confirmed (28.57 %, 38/133) | same |
| 4 | `DynamicIslandViews.swift` 59.6 % (56/94) | confirmed | `latest-test`, appex target |
| 5 | `WorkoutLiveActivity.swift` 0/82 | confirmed, appex target not app | `--files-for-target WorkoutsLiveActivity.appex` |
| 6 | `WorkoutLinkRouter` 17 % = `isPending` only | confirmed (1/6) | `WorkoutLinkRouter.swift:14-22` |
| 7 | `CloudKitMediaSource` 12 % | confirmed (11.76 % unit; 0 % UI) | both bundles |
| 8 | `RestTimerPickerSheet` 0 % | confirmed | both bundles |
| 9 | `SettingsFlow` never-run lines 46-58, 99-102, 165-168 | confirmed (plus 70-91 unit-only) | `xccov --archive --file` on both bundles |
| 10 | `FoldPlacement` has 26 kit tests | confirmed (worker said 24) | `grep -c @Test FoldPlacementTests.swift` |
| 11 | Eleven `-uiTesting` checks, three are seams | confirmed | `grep -rn '"-uiTesting"' Workouts` |
| 12 | No UI test passes `-liveActivity`; test-gaps.md:113 says one exists | confirmed | grep of `WorkoutsUITests`, `dev`; `test-gaps.md:113` |
| 13 | Audit flake: UILabel "Push" title, `.button`-only rule | confirmed (but passed on retry: intermittent) | shard-1 issue text + element PNG; `AccessibilityAuditUITests.swift:99` |
| 14 | RestRing: 5 s `BEGINSWITH 'Rest timer, '`, ~256 s test, 24 vs 20 min shards | confirmed (4m15s; 24m12s vs 19m49s/19m41s); "4-sim" wrong, 3 shards | shard-3 summary; `summary.tsv`; `RestRingUITests.swift:121-122` |
| 15 | `ui-flaky.log` has time, commit, id only; 4 entries | confirmed | `.build/ui-flaky.log` |
| 16 | "Flaky twice" compares the same id to the previous stamp only | confirmed | `dev:458-460` |
| 17 | `tf_ui_gate` returns before any check under `DEV_SKIP_UI_GATE=1`; routine mode | confirmed | `dev:1165-1168`; `docs/testflight.md` rows 11-08/09 |
| 18 | Filtered run overwrites `latest-ui-test.xcresult`; unit bundle unstamped | confirmed | `dev:270-271`, `dev:296-299` |
| 19 | `simctl privacy` has no health service | confirmed | `xcrun simctl privacy` help |
| 20 | `simctl icloud_sync` exists | confirmed | `xcrun simctl help icloud_sync` |
| 21 | `cktool query-records` exists; management-token question open | confirmed verb; token type needs a user token (likely) | `cktool --help`, `save-token --type` |
| 22 | `ck-schema diff` compares record types only | confirmed | `dev:1378-1384` |
| 23 | `XCUIDevice` has orientation and appearance, no hinge | confirmed | `XCUIDevice.h:55,124` |
| 24 | `xcodebuild -retry-tests-on-failure` exists | confirmed | `xcodebuild -help` |
| 25 | Seeded first block carries 150 s → "Rest 2:30" | confirmed for Push/Barbell Bench Press | `Sample/SampleData.swift:119-131` |
| 26 | `startRest(afterChecking:)`: replaces a running rest; 0 leaves it alone | confirmed | `RestTimer.swift:260-268` |
| 27 | Kit contract is "Foundation-only" | wrong: kit imports CoreData and SwiftData | `RemoteChangeObserver.swift` |
| 28 | Whether SwiftData posts remote-change for a second in-process container | unverifiable here | — |
| 29 | `initializeCloudKitSchema(.dryRun)` works without an account | unverifiable; Apple docs silent, forum reports say device/account needed | https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/initializecloudkitschema(options:), https://developer.apple.com/forums/thread/121617 |
