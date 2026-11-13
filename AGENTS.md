# Workouts (iOS)

Native SwiftUI rewrite of the web app in `../mac-os-compose-collection/workouts/` (Go + React +
Postgres). Targets iPhone, with the **iPhone Duo** (foldable) as the primary device. This file is
the working contract for agents; `CLAUDE.md` is a symlink to it. **`docs/PLAN.md` is the roadmap**:
architecture and the ticked/unticked task list the orchestrator works from. **`docs/DECISIONS.md`** holds
the settled technical decisions (read the heading a task cites; never re-litigate). `docs/port/` is the
feature spec extracted from the web app.

## Toolchain (pinned by what is installed on this machine)

| Thing | Value |
|---|---|
| Xcode | 27.2 (27B52), Swift 6.4 |
| Deployment target | iOS 27.2 (Duo layout needs the 27.1+ SDK) |
| Project | `Workouts.xcodeproj` — Xcode 27 **folder-based `project.xcproj`** format (JSON-like, no pbxproj) |
| Scheme | `Workouts` |
| Simulator | simkit's pool of `iPhone Duo` simulators (iOS 27.2), shared with every other project by simkit's queue (`./dev sims` = `sim status`; `simkit.json` names the app, its own processes and the test targets) |
| Bundle id | `com.ericribeiro.Workouts` |
| Tests | Swift Testing (`import Testing`, `@Test`, `#expect`) everywhere; XCUITest only in `WorkoutsUITests` |
| Formatter | `xcrun swift-format` (bundled), config in `.swift-format` |
| Language mode | `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, approachable concurrency, `MemberImportVisibility` |

## Layout

```
Workouts/              app target: App entry, root views, assets. Synced folder — just add files.
WorkoutsTests/         app unit tests (run on the simulator, ~45s). Synced folder.
WorkoutsUITests/       XCUITest. Synced folder.
Packages/WorkoutsKit/  local SwiftPM package: domain logic, no UIKit/SwiftUI. `swift test` on macOS in seconds.
dev                    the only build/test entry point agents should use.
.claude/skills/        repo-local procedures (see "Skills").
```

**Put logic in `WorkoutsKit`, views in `Workouts/`.** Everything that can be tested without a
simulator (models, calculations, formatting, persistence rules, sync logic) belongs in the package
so its tests run via `./dev kit` in seconds. The app target stays a thin SwiftUI shell. A second
package (e.g. `WorkoutsUI` for shared view components) is fine when the need appears; add it the
same way (`xcrun xcodeproj pkg add-local`, see the `xcode-project` skill).

**The kit must compile for macOS** (`swift test` runs there). Anything that imports ActivityKit, UIKit, WidgetKit, or
AppIntents' Live Activity types (`ActivityAttributes`, `LiveActivityIntent`) stays in the app target; the kit holds the
Codable/Sendable state those types wrap and the logic behind them.

## The loop

Every simulator verb of `./dev` calls simkit's `sim` CLI (`$SIMKIT_HOME/bin/sim`, default `~/Projects/simkit`); `./dev` dies with
one line naming that path when it is missing, and passes simkit's exit code on unchanged. simkit owns the pool, the queue and
leases, the crash guard, the Duo poses and the test jobs: its `AGENTS.md` ("The loop"), `docs/project-file.md` (`simkit.json`) and
`docs/test-result.md` (`result.json`) are the manual, and the `simkit:simulator` skill covers touches and pictures. `simkit.json`
holds what is Workouts': the scheme and bundle id, `own_processes` (a crash of one fails the run), and per test target the workers,
retry, per-test allowance and expected skips of `WorkoutsUITests` and the Health suite's own simulator and environment.

```
./dev kit [filter]      swift test for WorkoutsKit        — ~1s; use this first and most
./dev build             xcodebuild for the simulator       — ~2s warm (leased)
./dev test [filter]     unit tests on the simulator        — ~25s; filter = Suite or Suite/test(); a simkit job (`sim test WorkoutsTests`)
SNAPSHOT_RECORD=1 ./dev test SnapshotTests   re-record the visual references (WorkoutsTests/__Snapshots__); fails once on purpose
./dev lint | format     swift-format lint --strict / format --in-place
./dev ui-test [filter]  XCUITest flows on the simulator    — Suite/test(); the flow proof of record. No filter = the full suite, a simkit job over the workers,
                        retry, allowance and expected skips that `simkit.json` sets for `WorkoutsUITests` (one combined totals line; the run's
                        files under `.build/simkit/test/WorkoutsUITests/`; a filtered run goes to `filtered/` there and never replaces the full
                        run's `result.json`). A test that fails and passes alone on retry is reported as flaky; a test whose first attempt
                        crashed the app fails the run even when its retry passes. A filter starting `HealthKitIntegration` runs on the Health
                        simulator with its environment and writes to `.build/simkit/test/WorkoutsUITests-health/` (`simkit.json` `suites`).
                        The queue decides when it starts: exit 75 = wait (see "Keep the machine usable")
DEV_POSE=open-wide ./dev ui-test OpenPoseUITests   a filtered ui-test with the Duo posed first (closed-portrait|closed-landscape|open-wide|open-tall,
                        verified); closed-portrait restored afterwards, also on failure; the runner sees DUO_POSE. Opt-in, before a phase's TestFlight.
                        closed-landscape needs the app in front first (`./dev run`, then the posed test): the closed Home screen does not rotate
./dev ui-status         progress of a running ui-test, or the last run's final line (`sim test status`)
./dev ui-flaky [--since <days>]  per-test summary of the tests that failed, then passed on retry (`sim test flaky`): count, last date and commit, last failure text; read-only
./dev tree <Name>       accessibility tree (XCUIApplication.debugDescription) of the `-preview <Name>` screen via TreeDumpUITests (one sim, ~30s)
./dev coverage [kind]   per-target app coverage of the last passing test (default) or ui-test run (`sim test coverage` on `.build/simkit/test/<target>`)
./dev kit-coverage      swift test with coverage; prints the WorkoutsKit line-coverage TOTAL
./dev thumb-crops       regenerate `Resources/Library/thumbs/thumb-crops.json` (per-exercise figure crop rectangle, `Tools/thumb-crops.swift`); deterministic, run by hand, commit the result
./dev run [-- args]     boot sim, install, launch the app; args go to the app (`-- -preview <Name>` = the gallery)
./dev screenshot [p]    PNG of the booted simulator (Duo has two displays; DEV_DISPLAY=primary|…)
./dev shot <p> [-- args] run + settle + screenshot as one simkit job: the parallel-safe screen proof
./dev shot --burst [CxMS] <p> [-- args]  launch and capture the lit panel from the first frame (default 15x100), tiled into one labelled PNG grid: a
                        reviewer artifact for transitions, not a proof (no touches; `sim tap` of the `simkit:simulator` skill sends them)
./dev fold <pose> [p]   Duo hinge closed|half-open|open, verified by hinge reads + lit panel; p = PNG of the lit panel
./dev fold --keyframes '<json>' [--record <mov>]  timed hinge motion [{"atMs":0,"angle":0},{"atMs":3000,"angle":180}] at 60 Hz, final pose verified;
                        --record = simctl io recordVideo around it (read-only on the display); finish with `./dev pose closed-portrait`
./dev orient <o> [p]    rotate portrait|landscape-left|landscape-right, verified by devicectl + lit panel; p as for fold
./dev pose <name> [p]   closed-portrait|closed-landscape|open-wide (951x669 pt)|open-tall (669x951 pt) = fold + orient, verified; p as for fold
./dev poses <dir> [-- args]  run, then all four poses as settled PNGs <dir>/<name>.png as one simkit job; always ends closed-portrait
./dev ui-env [content_size <size>] [appearance light|dark] | reset   text size / appearance of this session's simulator (no args = print; reset = large/light). The app is
                        always dark whatever the sim says; `appearance` only changes the system surfaces around it.
                        test, ui-test and tree reset it to large/light first: re-apply before `./dev shot`
./dev home [p]          Home screen (the app keeps running); ./dev duo <verb> = pass-through to `sim <verb>` (panels, hinge [--app = the app's own status, launch with `-- -logHinge`], settle, screenshot, fold, orient, pose, home)
./dev probe [dir]       launch the app with `-uiTesting`, then answer `sim/probes.json` (screen probes: pixels, lines, poses) into <dir> (default .build/probe)
./dev selftest          the upload gates on result.json fixtures, the swift test totals and ck-schema parsing; no simulator or xcodebuild, ~2s; not part of check
./dev check             lint → kit → test; the pre-commit gate (~30s warm; `test` builds the app, so there is no separate build step)
./dev sims              `sim status`: the slots, who holds which simulator, who waits, which are booted; read-only
./dev release           end this session's simulator lease (simkit also drops it after ten minutes with no verb)
```

Every test command prints its totals on success (`kit: Test run with 100 tests …`; simkit's `tests:`, `passed:`, `failed:`,
`skipped:` lines and `result: <result.json>`) and **fails when the filter matched nothing** (or a filtered run skipped every
test it ran), so a misspelled suite can never pass. Silence means failure output
only; read it.

Rules for the loop:

- **Always go through `./dev`.** It pins scheme, destination, derived data (`.build/DerivedData`)
  and `-quiet`, and prints only failures. Raw `xcodebuild` floods context.
- **Add files, don't register them.** The three target folders and the package are synced; a new
  `.swift` file in the right folder is in the build. Never hand-edit `project.xcproj`; use
  `xcrun xcodeproj ...` then `xcrun xcprojformatter --update Workouts.xcodeproj` (skill:
  `xcode-project`).
- **Run the narrowest proof.** One failing test → `./dev kit 'Suite/test'` or `./dev test Suite/test()`,
  not `./dev check`. `check` is for the end of a task.
- **Visual regressions are caught by snapshot tests.** `WorkoutsTests/Snapshot` renders components (default and
  accessibility-3 Dynamic Type, dark; the Live Activity's Lock Screen banner also in light, since the system draws it in the
  device's appearance) and pixel-compares them with the PNGs in
  `WorkoutsTests/__Snapshots__/<File>/` (`./dev test SnapshotTests`, part of `./dev check`). A failure writes
  `<name>.actual.png` beside the reference (git-ignored): view it. Re-record only for an *intended* visual change, after
  viewing the `.actual.png`: `SNAPSHOT_RECORD=1 ./dev test SnapshotTests` (or one suite, `SnapshotTests/ExerciseRowSnapshots`),
  which fails once by design, then re-run without it and commit the PNGs with the change. Add a component by copying a
  `Snapshot*Tests.swift` file; views with `List`, `TextField` or `NavigationStack` pass `engine: .hostedFitting` or
  `.hosted(height:)`. Dates in the PNGs use the simulator's time zone.
- **Flows need the harness.** `WorkoutsUITests/SmokeUITests` is the one XCUITest to copy from; PLAN task 0.10 extends it
  with the `-preview` gallery, and every task whose proof is a preview or a flow lists 0.10 in its `Needs`.
  UI tests launch with `-uiTesting` (in-memory store, no leftover state).
- **The UI proof of record is `./dev`; the Xcode MCP is the first shortcut.** A screen is proven by `./dev run -- -preview <Name>` (PLAN
  task 0.10; until it lands, plain `./dev run`; a `#if DEBUG` `PreviewGallery` hosting the same views as the `#Preview`s, fed by the sample container; set Dynamic Type
  with `./dev ui-env content_size <size>` (previews and screenshots are rendered dark: the app is dark-only; `ui-env appearance` changes the simulator, not the app), never `simctl ui booted`: that hits an arbitrary sim) followed by `./dev screenshot`; a flow is proven by an XCUITest in `WorkoutsUITests`
  (`./dev ui-test Suite/test()`), which also forces the accessibility identifiers below. Xcode's MCP tools (plugin
  `xcode-integration` in Claude Code, `xcrun agent plugin path --plugin-format codex` in Codex) connect by default; reach
  for them first. `RenderPreview` checks layout, Dynamic Type and dark without a simulator (`XcodeOpenWorkspace` on this
  checkout's absolute `.xcodeproj` path first, then pass an iPhone Duo render destination: the default is an iPad);
  `DeviceInteraction*` drives the UI and reads the accessibility tree for exploration. If the `mcp__…xcode__*` tools are
  missing, say so once and fall back to the proofs above (only Eric can reconnect, with `/mcp reconnect all`). A task's
  proof never depends on the MCP, and its `BuildProject`/`RunSomeTests` tools never count as the gate (Xcode's own
  DerivedData, no `.build/check.stamp`). Workers have the MCP tools too; `--lean` workers have none. Skill: `verify-ui`.
- **Never toggle the simulator's displays** (`simctl io … screenConfig`, display power, device defaults): it crash-loops
  SpringBoard and floods Eric's Mac with crash dialogs. simkit's crash guard fails any verb during which SpringBoard,
  PosterBoard, backboardd or one of this app's own processes (`own_processes` in `simkit.json`) crashed; treat that as a stop and
  report (never `simctl shutdown all`: it kills other agents' simulators, and never erase a simulator by hand). Change Duo poses only with
  `./dev pose` / `poses` (or the low-level `fold` / `orient`; skills `verify-ui` and `simkit:simulator`), and leave the sim closed
  and portrait (`./dev pose closed-portrait`, then `./dev release`).
- **Do not change** the deployment target, supported platforms, signing, or add a remote package
  without being asked.

## Product decisions (2026-11-03)

- **Local-first.** SwiftData with CloudKit sync. No backend, no API client, no auth. Design models
  CloudKit-compatible: optional relationships, default values, no `@Attribute(.unique)`.
- **The web app is reference only.** It keeps running untouched and will be retired later; there is
  no data sync or migration between the two. Read its `PLAN.md`/`docs/` for *what* the product does,
  not for *how* to build it.
- **Parity is the floor.** Keep the streamlined workout-tracking flow, but the point of going native
  is the iPhone Duo and what a PWA cannot do: sidebar on the inner display, Dynamic Island / Live
  Activity for the active workout, notifications. When a web decision and a native idiom
  disagree, choose the native idiom and say so in the task.

- **Answered 2026-11-03 (do not re-ask):** no Strong CSV import and no `Workout.source` (Eric's
  history comes over once through the in-app JSON import, task 1.7, as soon as it exists). Weights are
  `Double`. Exactly one in-progress workout, persisted across relaunch. Library exercises are
  read-only; only custom exercises get rename/unit/bar/rest. Three tabs in the web's order
  (History · Workout · Exercises) with **Workout the default tab**; Settings is a gear toolbar
  button on the Workout tab (and in the sidebar's bottom) opening a `Form` sheet, not a tab.
  Folder `collapsed` is per-device state, not synced. Weeks start Monday in the device time zone.
  Exercise media (thumbnails + videos) is wanted; delivery mechanism decided in `docs/port/media.md`.
  No widgets, Shortcuts or Control Center. Eric starts his Apple Fitness workout in Apple's own app alongside this one;
  **HealthKit is read-only enrichment** (Eric, 2026-11-04): after both finish, the app reads the overlapping Fitness
  workout (calories, heart rate) into the history. Opt-in: a Settings toggle, off by default; turning it off offers to keep or remove the data. It never writes to Health and never starts a workout (PLAN 7.1b).

## Code conventions

- SwiftUI only, `@Observable` models, `NavigationStack`/`NavigationSplitView`, `TabView`. No
  `ObservableObject`, no `NavigationView`, no UIKit unless wrapping something SwiftUI lacks.
- **Duo-ready layout.** Never read `UIScreen.main`, device idiom, orientation, or hardcode sizes.
  Use size classes and `GeometryReader`; compact width may become regular width mid-session when
  the phone opens. On the closed display the system puts the Dynamic Island, status bar, toolbar
  and tab bar in a vertical strip on the trailing edge; never override bar placement, give every
  toolbar item a symbol. Read `docs/port/duo-layout.md` (Apple's rules) before any layout work and
  use the `app-resizability` skill for migrations.
- Swift 6 strict concurrency is on; everything is `MainActor` by default. Mark off-main work
  `nonisolated` explicitly and keep types that cross actors `Sendable`.
- No force unwraps, no `try!` outside tests. `OrderedImports` and the rest of `.swift-format`
  are enforced by `./dev lint`.
- Every new public function in `WorkoutsKit` gets a test in the same change.
- Accessibility labels on every interactive element — the device-interaction tools navigate by
  the accessibility tree, so unlabeled controls stall agents as well as users.
- **Load the Apple skill before the work, not after.** Writing or changing a SwiftUI view →
  `xcode-integration:swiftui-specialist`; any layout, size-class or window-size work →
  `xcode-integration:app-resizability`; toolbar, `@State`, reorderable lists or any API new in iOS 27 →
  `xcode-integration:swiftui-whats-new-27`; the Live Activity / rest intents (Skip, +30 s, Done) →
  `xcode-integration:app-intents-specialist`; an API question → the MCP `DocumentationSearch` tool (workers have no
  web). One skill per concern; load it with the Skill tool, read the relevant reference, then edit.
- English only: `Text("…")` literals, no String Catalog maintenance, no `String(localized:)` in the kit.

## Working in bite-sized tasks

A task for a worker is one unit: one model type + its tests, one view + its preview, one
`xcodeproj` change. Give it the files, the approach, and exactly one proving command from the
loop above. Keep whole-suite runs (`./dev check`), screenshots across poses, and commits for the
orchestrator after review. Workers do not commit. A brief names the Apple skill the worker must load when the task
touches a view, layout, iOS 27 API or intent.

**Keep the machine usable: one heavy thing at a time.** A booted simulator is about 260 processes, and a build plus a UI
test per worker multiplies fast (2026-11-11: a full `./dev ui-test` beside four simulator workers drove the load average
past 140; workers crawled for an hour or stalled, and audit tests fail with `-902` under that load). simkit's queue
enforces the count (its `AGENTS.md`, "Rules" and "The loop"); what stays here is how to plan around it.
- **Leases.** A simulator is used only under a lease. Every `./dev` call in a checkout shares one session lease (the session is
  the git worktree root); the leased verbs (`build`, `run`, `pose`, `fold`, `orient`, `screenshot`, `home`, `duo`, `ui-env`, `probe`)
  take it on first use, and simkit drops it after ten minutes with no verb. `./dev release` ends it at once: run it when
  you are done with the simulator. `test`, `ui-test`, `tree`, `shot` and `poses` are whole jobs that use the session's lease
  when one is held and otherwise take a lease of their own for the job. Workers do not pick a simulator.
- **Exit 75 means wait**: no lease came within the wait. The `busy:`, `position:` and `holder:` lines say who is in the way.
  Never retry it in a loop or override it. `./dev sims` (`sim status`) lists the slots, the leases and the queue; run it
  and `uptime` before dispatching simulator workers.
- A full `./dev ui-test` is the heaviest thing (`simkit.json` gives it three workers, so it holds three simulators) and runs
  alone. While it runs, dispatch only work that needs no simulator (kit changes with `./dev kit`, docs, read-only reviews);
  start simulator workers after `./dev ui-status` reports it finished.
- At most two simulator-using workers at once, and never beside the full run.
- Order a batch so kit and docs work goes first and simulator proofs come last, instead of starting everything at once.
- A simulator boot is the heaviest minute (two workers booting and building at once took the load average to 160 on
  2026-11-11). Start the second simulator worker a couple of minutes after the first; simkit spaces boots itself, and
  a lease's end shuts its simulator down unless the next in the queue takes it over booted.
- Shut down simulators you booted outside simkit's queue when you are done with them (`xcrun simctl shutdown <udid>`
  for that one device, e.g. a clone used for Fitness captures); check with `./dev sims` and `uptime` before dispatching.
- A worker is stopped after about 30 tool calls: size a brief for that (one change, named files, batched commands) and tell
  the worker to report before it runs out.
- A "flaky" line in a full run is a claim to check, not a pass: read the first failure in `./dev ui-flaky`. An app crash on
  the first attempt fails the run by itself; a timeout or an audit failure that recurs on the same test is a defect too.

**Record process failures in `docs/incidents/`** (one file per incident, `YYYY-MM-DD-slug.md`, format in its README): a rule
that existed and was not followed, a skipped check, damage to the machine or to a build that reached Eric. Write it in the
same session, with the numbers, the cause, why the safeguard did not hold and what now carries the rule.

## Skills

- `.claude/skills/xcode-project` — `xcrun xcodeproj` recipes: list/add packages, link products,
  read/set build settings, add targets; always followed by `xcprojformatter`.
- `.claude/skills/design-review` — the read-only critique at the end of each UI phase (slop test, five scored
  dimensions, state inventory, P0–P3 findings → worker tasks, taste → Eric). HIG and `DECISIONS.md` are its authority.
- `docs/fitness-reference.md` (not a skill) — fill a simulator's Health store with `-seedHealthHistory` and drive Apple's
  Fitness app there as the visual reference; what populates, what cannot, and the look worth copying.
- `.claude/skills/verify-ui` — render a preview, run on the Duo, screenshot, drive the UI, and
  what each pose of the Duo should be checked for.
- Apple's bundled skills come with the Xcode plugin (`xcode-integration:<name>`). The ones that matter here:
  `swiftui-specialist`, `swiftui-whats-new-27`, `app-resizability`, `device-interaction`, `app-intents-specialist`, and
  the three `accessibility-*-specialist` auditors (dynamic-type, sufficient-contrast, voiceover) used by `design-review`
  and PLAN 6.3. The rest of the plugin (translation, String Catalog, modernize-tests, C bounds safety, document apps)
  does not apply to this project.

## TestFlight cadence

After **every push to `main` that changes the app** (any fix, not only milestones; Eric, 2026-11-04: "we can update with
far more frequency"), the orchestrator runs `./dev testflight --upload` in the background from the main checkout. The
commit gate is unchanged: `./dev check` plus the UI suites the change touches; the full `./dev ui-test` (a simkit job over
the workers `simkit.json` sets, so wall time is roughly a third) still runs before
a milestone (a PLAN task or a review's fix batch). Never from a worktree, never with uncommitted changes,
never by workers. It takes no simulator lease (own DerivedData under `.build/testflight/`). Log each upload's build number
and commit in `docs/testflight.md`. `--upload` is gated: it refuses unless the last full unfiltered `./dev ui-test` passed on HEAD
with a clean tree, which it reads from `.build/simkit/test/WorkoutsUITests/result.json` (no filter, exit code 0, `commit` =
HEAD, `clean` true; it prints the run's flaky list). `DEV_SKIP_UI_GATE=1` overrides with a warning. A failed upload is reported, not retried in a loop.
**Upload sooner (Eric, 2026-11-07: "more frequent uploads so I can test the changes quicker"):** a fix needs only `./dev check` plus
its touched UI suites green, then `DEV_SKIP_UI_GATE=1 ./dev testflight --upload` right away; do not hold an upload for a full
run, and batch nothing just to save uploads. The full run still gates milestones (a PLAN phase, a review round's batch)
and runs in the background; the `docs/testflight.md` row says which gate it passed (`Gated (full …)` or `Touched suites: …`).
The Health suite has its own gate: `.build/simkit/test/WorkoutsUITests-health/result.json` with exit code 0 and nothing
skipped (`DEV_SKIP_HEALTH_GATE=1` overrides).

## Secrets

The App Store Connect API key lives only in 1Password (`op://Homelab/Apple App Store Connect API/…`). The **only** code that
touches it is `./dev testflight`, which pipes `op read` into a mode-600 file in a fresh `mktemp -d` that a trap deletes
on exit. Never `op read` the key yourself, echo or `cat` it, put it in a variable, env var, argument, log, scratch file,
commit, PR or chat, or copy a `.p8` anywhere. Key ID and Issuer ID are not secret. If a task seems to need the key some
other way, stop and ask Eric.

The CloudKit server-to-server key (`./dev media-upload`) follows the same rules: `op read` into a mode-600 file in a trapped
`mktemp -d`, never echoed, stored in a variable, logged or copied.

The CloudKit management token (`./dev ck-schema`) is never read at all: the `op://` reference goes into the child's environment
through `op run`, so the value exists only inside `cktool`. Never `op read` it, and never put it in a variable, file or log.

## Git

Commit directly to `main`, no feature branches unless asked. Commits are signed (see the
machine notes in `~/.claude/CLAUDE.md` if signing fails). `./dev check` must pass before a
commit, and this is enforced: `check` touches `.build/check.stamp` on success and the PreToolUse hook
`.claude/hooks/require-check.sh` refuses `git commit` while any non-doc file is newer than that stamp
(docs-only commits pass). Remote: `git@github.com:EricRibeiro/workouts.git`.

Eric wants agents to commit and push without him present, so `.claude/settings.json` allowlists
`git add/rm/commit/push/status/diff/log`. Run them **bare** (`git push`, not `cd … && git push`
or `timeout 60 git push`): the allow rule matches the command prefix, and a wrapper drops the
command back into the permission classifier, which has refused pushes over content it mistook for
publication (the private server domain in the docs).

## Not set up yet (deliberately)

- CI (no macOS runner decision made).
- Code signing / device builds — simulator only for now. Distribution will be TestFlight (no
  direct-to-device installs); `./dev testflight [--upload]` archives and exports a signed App Store build to
  `.build/testflight/export` (key read from 1Password with `op`; build number is the UTC timestamp; export only unless `--upload`).
- App data model and screens — see `docs/port/` and the phases in `docs/PLAN.md`.
