# Review of the coverage research (b7263b4), Fable, 2026-11-09

Read-only. Evidence: the repo at b7263b4, `.build/results/latest-{test,ui-test}.xcresult` and the shard bundles via `xccov` /
`xcresulttool`, `xcrun simctl` help, `.build/ui-test.stamp`, `.build/ui-flaky.log`, `docs/testflight.md`. No simulator was used.

## Verdict

The research is largely accurate: of 34 spot-checked claims, 25 are confirmed, 6 are line drifts or off-by-one, and 3 are
wrong in a way that changes a recommendation. The plan's shape (snapshots and kit seams now, posed and SpringBoard XCUITests
later, the fold and the Island on the device) is right, and the hour estimates are plausible for Sonnet workers except where
a recommendation is already implemented or already exists. The two problems that matter: (1) both proposed `dev` gates (the
Health "changed since last real-store pass" check and the flake-trend rule) hang off `tf_ui_gate` / the full-run path, but
every upload since 2026-11-08 used `DEV_SKIP_UI_GATE=1`, which returns from `tf_ui_gate` before any check (`dev:1165-1168`),
so as drafted neither gate would ever fire; and (2) the accessibility-audit flake is misdiagnosed: the shard-1 bundle's element
screenshot is the title-menu `UILabel` "Push" on a settled screen, which the existing `.hitRegion` known-issue rule misses
only because it exempts `.button` elements (`AccessibilityAuditUITests.swift:98-100`). That is a five-minute rule fix, not a
settle anchor. Smaller corrections: `BenchArrangement.swift` is 28.6 %, not 0 %, under the UI suite; `latest-test.xcresult`
predates 12f5649; the FirstFrame fix is already in the code; the rest-picker logging test needs no "skip the launch rest" step
because a check replaces a running rest; the RestNotifier `didReceive → openWorkout` test already exists.

## Findings

| id | sev | gap | claim / recommendation | what is wrong or missing | evidence | suggested change |
|---|---|---|---|---|---|---|
| F1 | P1 | 3, 6 | Health path-scoped stamp in `tf_ui_gate`; flake-trend gate after a full pass | `tf_ui_gate` returns before any check when `DEV_SKIP_UI_GATE=1`; that is the routine upload path (CLAUDE.md "Upload sooner"; all 6 recent rows in `docs/testflight.md` carry it). Full runs are post-upload. Both gates would be dead code. | `dev:1165-1168`; `docs/testflight.md` tail; CLAUDE.md TestFlight cadence | A separate `tf_health_gate` with its own override (`DEV_SKIP_HEALTH_GATE=1`) that runs on every `--upload`; the flake trend becomes `./dev ui-flaky` (report) now and a gate only once the full run is in the upload path again |
| F2 | P1 | 6 | Audit flake = unsettled UI; "view the screenshot first", then settle anchors + element text (2 h) | The element is the `UILabel` "Push" (the `.toolbarTitleMenu` title) on a settled cover (elapsed 0:06, ring running). The known-issue rule for exactly this control requires `elementType == .button`, so the label variant falls through. Deterministic rule gap, not load. | shard-1 attachments "Element Screenshot" and "Complete Issue Description" ("The size of this UILabel is too small"); `AccessibilityAuditUITests.swift:95-100`; `ActiveWorkoutCover.swift:177,185` | Extend the `.hitRegion` rule: a `.staticText` whose label equals a `navigationBars.buttons` title is also system-owned. 15 min. Keep the `debugDescription` in the failure text |
| F3 | P2 | 6 | "Reorder FirstFrame: `.exists` first; raise the hold to 20 s" | Already done: the absence check runs right after the push (`:88`), the doc comment says so (`:78`), and the hold is 10 s (`-slowLoads 10000`). | `FirstFrameUITests.swift:74-90` | Drop. If it flakes again, the richer log (F1's `ui-flaky`) is the fix |
| F4 | P2 | 4 | Option B "a save on the mirror posts a real `NSPersistentStoreRemoteChange`" (3–4 h, "high confidence") | No test or doc in the repo shows SwiftData posting that notification for a second in-process container; the only kit test posts it by hand. Whether SwiftData sets the remote-change post option on an on-disk store is unverified. | `CloudKitReadinessTests.swift:262-275` (`center.post(name: .NSPersistentStoreRemoteChange)`) | 30-min spike first (two containers, one save, observe). Fallback keeps most of the value: post the notification from the test and keep the history/author assertions |
| F5 | P2 | 4 | Option A in the kit (`NSPersistentCloudKitContainer` load + `.dryRun`) | Adds CoreData to a kit whose contract is Foundation-only (`docs/port/healthkit.md` §6). The app target already imports CoreData (`CloudSyncMonitor`). `.dryRun` under unsigned `swift test` is the worker's own open question. | `healthkit.md:118-128`; `CloudSyncMonitor.swift:30,73` | Put A in `WorkoutsTests`; keep only the load-time assertion unless the spike shows `.dryRun` works without an account |
| F6 | P2 | 1 | `BenchArrangement.swift` "0 %" | 0 % in the unit bundle, 28.57 % (38/133) in the UI bundle: the closed-pose glue runs under every cover test; only the open/bench branches are dark. | `xccov --files-for-target Workouts.app latest-ui-test.xcresult` | Reword; option A still right, its claim is "the open branches", not "the file" |
| F7 | P2 | 5 | Option A: DEBUG `drawsSystemRing` seam + 5 stand-in snapshots (2 h) | The stand-in ring proves branch selection, which a pure value test proves for free; 5 PNGs that look like nothing the user sees must be re-recorded on every style tweak. The DEBUG flag sits in a view file compiled into the appex. | `DynamicIslandViews.swift:14-31`; CLAUDE.md "change the design instead of hacking" | Extract `RingKind` (`.over` / `.running(range)` / `.idle`) and unit-test it; promote E (`#Preview(as: .dynamicIsland)` via `RenderPreview`, Apple's documented path) to "now"; no seam |
| F8 | P2 | 2 | Logging-cover test B: "skip the 300 s launch rest first" and "a running rest is left alone" (§1 table) | A check replaces any running rest; only Off (0) leaves it alone. The skip step is wasted time and a flake source; the §1 table is ambiguous. | `RestTimer.swift` `startRest(afterChecking:)` doc comment | Pick 30, check a set, read the ring. 1.5 h, not 2 |
| F9 | P2 | all | "Numbers come from … on 12f5649" | `latest-ui-test` is 12f5649 (stamp). `latest-test.xcresult` is from 19:02 on 11-08, before 12f5649 (23:25); its app line total is 20367 vs 20495. The synthesis's own "pin a date on evidence" rule. | `ls --time-style` on `.build/results`; `git log`; `xccov --only-targets` | Say "latest-test from an earlier 11-08 build"; have `./dev test` write a stamp like `ui-test.stamp` |
| F10 | P2 | 1 | Option B: mid-test `XCUIDevice.shared.orientation = .landscapeLeft` on the open Duo | duo-layout.md:20: the inner display "does not honor supported interface orientations; the app scales there". Whether XCUITest rotation re-lays out the inner display is unverified; the worker did not flag it. | `docs/port/duo-layout.md:20` | Add a 15-min spike to B before estimating 3–4 h |
| F11 | P3 | 7 | "Add a `RestNotifierTests` case for `didReceive` → `openWorkout` if one is missing" | It exists. | `RestNotifierTests.swift:313, 562-574` | A5 is the router test only (0.15 h) |
| F12 | P3 | 2, 5, 7 | Line references | `RestTimerPickerSheet` ids are at :58/:49/:54 (not :63/:50/:56); the picker comment is `SettingsUITests.swift:202` (not :178); `ActivityControls.swift:28` (not :29); `FoldPlacementTests` has 26 tests (duo report says 24). | grep | Cosmetic; fix when the docs are next touched |
| F13 | P3 | 4 | `cktool query-records` with the management token as a manual probe | Unverified that a management token may query records (JC128 only used it for schema export). | `docs/cloudkit.md` step 3 | Keep as "verify with `man cktool`" |
| F14 | P3 | 3 | "Ten-minute check first… of Eric's time" | A filtered `./dev ui-test HealthKitIntegrationUITests` run twice on one clone is orchestrator work, not Eric's. | brief hard rules apply to this worker only | Move from "Eric decides" to the task list |

## Reordered plan

| # | Gap | Do now | Do next | Keep manual |
|---|---|---|---|---|
| 1 | Duo | A `ImageRenderer` placement snapshot (1 h, after the 15-min render spike) | B only after two spikes: `DEV_POSE` in `run_tests` and rotation on the inner display (F10); 3–4 h stands if both pass | fold / bench; `./dev poses` |
| 2 | Rest picker | kit `setRest → check` (15 min); template-editor test + Cancel (1 h) | logging-cover test without the skip step (1.5 h) | — |
| 3 | Health | helpers-only unit seam (2–3 h); the 10-min "answered" check by the orchestrator | `tf_health_gate` outside `DEV_SKIP_UI_GATE` with a dedicated non-pool clone (2 h) | sheet survival; Watch data |
| 4 | CloudKit | 30-min notification spike, then B (3–4 h) or its fallback; `CKDatabase` seam + `CloudSyncMonitor.map` seam (2 h) | A in `WorkoutsTests`, load assertion first (1–2 h); pool exemption for the two iCloud sims | push merge; Production; sync-check script (defer until a second device) |
| 5 | Live Activity | `RingKind` unit test (0.5 h); E `RenderPreview` spike (1 h) | B factor the builder (1.5 h); record the `ActivityConfiguration` ceiling | Island on the closed Duo; StandBy; C/D only if E fails |
| 6 | Flakiness | F2's rule fix (15 min); failure text + shard + seconds into `ui-flaky.log` and `./dev ui-flaky` (1.5 h); `startRest` budget 5 → 15 s | replace the 4 sleeps with predicates (2–3 h) | trend gate until the log has ~10 entries and the full run is back on the upload path |
| 7 | Settings / gates | A3 `performTurnOff` seam + router test (0.65 h); gate table update (15 min) | A1 + A2 (1.5 h) | file picker; notification tap |

Net: about 16 h "now" (down from 20), with two items moved from gates that would not have fired into checks that run on every
upload.

## Blind spots

- **The gate plumbing itself.** `dev` is ~1500 lines of bash with no tests (`duo-test` covers `Tools/duo` only). The research adds
  stamps, path diffs and an `awk` trend rule to it. One `./dev selftest` over the stamp/gate parsing (fixture files, no sim) is
  cheaper than the first silent mis-gate. F1 is an instance.
- **Field-level schema drift.** `./dev ck-schema diff` compares record *types* between environments (`dev:1473`). A new optional
  attribute (the additive change the rules allow) deploys nothing to Production and the diff stays green; TestFlight then logs a
  schema error on the first record that sets it. A test or script that compares the exported `.ckdb` field list with
  `SchemaV2`'s attributes closes it.
- **The unit-test bundle is unstamped**, so `./dev coverage` can report numbers from a stale build without saying so (F9).
- **Sync data-loss paths.** `InProgressResolution` (settle or delete an in-progress row untouched for 6 h) is tested with hand-made
  rows; the research's two-container test is the natural place to drive it through the mirror author and prove a *recent* remote
  row is never deleted. Not mentioned by the CloudKit report.
- **Time zone of the snapshot references.** CLAUDE.md notes the PNG dates use the simulator's zone, which follows the host; a Mac
  travelling or a sim created under another zone fails `SnapshotTests`. `sim_reset_ui` pins size and appearance, not the zone.
- **Dark and accessibility sizes in flows.** Only two UI files launch with a non-default style or size (the audit suite's four AX
  tests). Snapshots cover AX3 and dark per component, so this is a known trade, but no flow test runs dark; one dark run of
  `SmokeUITests` would catch a `.white` literal cheaply.
- **Migrations and import/export are covered** (`OnDiskStoreMigrationTests`, `ImportExportFlowTests`, `WebExportTests`); the
  research correctly left them out. Notifications: the delivered-tap path is device-only as stated; `didReceive` is tested (F11).
- **Extension entitlements.** Only the app has an `.entitlements`; the appex has none and needs none for Live Activities. Fine, but
  `AppBundleTests` could assert `NSSupportsLiveActivities` and the time-sensitive entitlement so a project-file edit cannot drop them.

## Decisions for Eric (trimmed)

Keep for Eric: (a) a hard block vs warning for the Health gate on upload, and whether a sixth non-pool clone may be created;
(b) whether `iPhone Duo` / `iPhone Duo 2` leave the auto-erase pool or a third iCloud sim is created; (c) whether a reviewable
PNG (RenderPreview) is the "repeatable Island check" or an automated SpringBoard test is wanted; (d) whether the posed suites
(B) join the upload gate; (e) the spoken labels for the rest picker ("30 seconds").

Answerable by the research or the orchestrator, not Eric: the seeded template's rest (150 s → "Rest 2:30",
`SampleData.swift:131`); whether `ArrangementView` renders under `ImageRenderer` (a spike); the "answered count" check (a
filtered run); whether the kit may gain a URL overload (a routine design call; yes, test-only); whether `refreshAfterImport`
goes internal (routine); whether the audit element was real (it was the title label, F2); whether the Mac was busy at
04:5x UTC (the shard took 24 m vs 19 m on a 4-sim run: load, as the dev comment at `ui_shard` already says); whether
`RestStateProbe`'s `TimelineView` may be swapped (a `-uiTesting`-only seam; try it); a 2FA question about the test account
(check the account, do not ask).

## Spot-check log

| # | claim (report) | result | evidence |
|---|---|---|---|
| 1 | `FoldPlacement` has 26 kit tests (synthesis) / 24 (duo) | confirmed 26; duo wrong | `grep -c @Test FoldPlacementTests.swift` = 26 |
| 2 | `FoldPlacement.swift:50,78` placement / frames | confirmed | lines 50, 78 |
| 3 | `BenchArrangement.swift:41-58` reads `GeometryReader` + `reservedRegions(kind: .division)` | confirmed | lines 41-57 |
| 4 | `ActiveWorkoutCover.swift:240,257-261` axes only when regular | confirmed | lines 240, 257-261 |
| 5 | `BenchArrangement.swift` is 0 % | wrong for the UI bundle (28.57 %, 38/133); true for unit | xccov |
| 6 | both bundles are on 12f5649 | half wrong: `latest-test` predates it | mtimes 19:02 vs 23:52; totals 20367 vs 20495 |
| 7 | picker ids at `:63/:50/:56`; options `[nil,0]+fixed` | ids drifted (:58/:49/:54); options confirmed | `RestTimerPickerSheet.swift` |
| 8 | "Default (1:00)", default 60 | confirmed (`SettingsStore.swift:30`); DECISIONS.md says 90 (doc inconsistency, not the research's) | |
| 9 | `SampleData` rest 131-218 | confirmed (kit `Sample/SampleData.swift`; first block 150) | |
| 10 | `PastEditorUITests` 111-117 asserts `settable.menu.rest` absent | confirmed | |
| 11 | eleven `-uiTesting` checks at the drafted lines | confirmed, all 11 lines match | grep |
| 12 | `SettingsUITests:178-179` "pickers cannot be driven" | wrong line (:202) | |
| 13 | `SettingsFlow` 46-58, 99-102, 165-168 never run | confirmed within a line (47-57, 100-101, 164-168) | |
| 14 | `WorkoutLinkRouter` 17 % = line 14 only | confirmed (1/6) | xccov |
| 15 | `RootView.swift:72-78`, `WorkoutsApp.swift:79` router wiring | confirmed | |
| 16 | `RestNotifierTests` lacks `didReceive → openWorkout` ("if missing") | exists | `:313, :562-574` |
| 17 | `HealthKitSource` 0/288 UI; helpers at 163/234-249/263/298/307 | confirmed (statistic at 247-248) | xccov, grep |
| 18 | `simctl privacy` has no `health` service | confirmed | `xcrun simctl privacy` help |
| 19 | `xcrun simctl icloud_sync` exists | confirmed | `simctl help icloud_sync` |
| 20 | `dev:304` sets `TEST_RUNNER_HEALTH_INTEGRATION`; 316-320 stamp; 1166 gate; 270 removes `latest-*` | confirmed | sed |
| 21 | flaky rule compares the same id with the previous stamp only; log has no message | confirmed | `dev:458-460, :331` |
| 22 | `CloudKitMediaSource` 11.8 % (6/51) | confirmed (unit); 0 % UI | xccov |
| 23 | `WorkoutsApp.swift` 43 % (130/302) | confirmed for unit; 59 % (254/430) under UI, unstated | xccov |
| 24 | `DynamicIslandViews` 59.6 % (56/94), `WorkoutLiveActivity` 0/82, `LiveActivityController` 92 % / 11.7 %, intent handler 16.7 % | confirmed | xccov both bundles |
| 25 | no UI test passes `-liveActivity`; gate at `WorkoutsApp.swift:274` | confirmed | grep empty; line 274 |
| 26 | `ActivityControls.swift:29`; `ActivityPreviews.swift:118-120` | off by one / three (:28; :121-123) | |
| 27 | sleeps at `CoverTimer:17`, `KeyboardReveal:38,106,115`, `LoggingBlockMenu:124`; `RestRing:122` 5 s | confirmed | |
| 28 | FirstFrame needs `.exists` first and a 20 s hold | already so (`:78, :88`; `-slowLoads 10000`) | |
| 29 | audit failure "Hit area is too small" with an element screenshot | confirmed; element = title `UILabel` "Push", settled screen | shard-1 attachments |
| 30 | shard 3 took 24m12 vs 19m49 / 19m41; the RestRing test took 256 s | shard times confirmed (`summary.tsv`); 256 s not checked | |
| 31 | `RemoteChangeObserver` tested only with a hand-posted notification | confirmed (so B's premise is unverified) | `CloudKitReadinessTests.swift:262-275` |
| 32 | surviving bundles: shard-1, shard-3, retry-1, retry-3 | shard-2.xcresult also exists | `ls ui-test-shards` |
| 33 | `sim_heal` (931-938) and `sims --prune` (1105-1121) erase clones; `simctl clone` at 1139 | confirmed | sed |
| 34 | `isDynamicIslandLimitedInWidth` is get-only; no `XCUIDevice` fold API | unverifiable here (no web used); consistent with the repo's own comment and the iOS 27 SDK compiling it | `ActivityPreviews.swift:121` |
