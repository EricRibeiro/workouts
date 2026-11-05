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
| Simulator | a pool: `iPhone Duo` (iOS 27.2) plus clones `iPhone Duo 2`…`5` (`./dev sims`; `DEV_SIM_POOL` sets the size); each checkout keeps its own (`DEV_SIM=<name>` / `DEV_SIM_UDID=` override) |
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

```
./dev kit [filter]      swift test for WorkoutsKit        — ~1s; use this first and most
./dev build             xcodebuild, iPhone Duo sim         — ~2s warm
./dev test [filter]     unit tests on the simulator        — ~25s; filter = Suite or Suite/test()
SNAPSHOT_RECORD=1 ./dev test SnapshotTests   re-record the visual references (WorkoutsTests/__Snapshots__); fails once on purpose
./dev lint | format     swift-format lint --strict / format --in-place
./dev ui-test [filter]  XCUITest flows on the simulator    — Suite/test(); the flow proof of record
./dev coverage [kind]   per-target app coverage of the last passing test (default) or ui-test run (bundle kept in .build/results/latest-*)
./dev kit-coverage      swift test with coverage; prints the WorkoutsKit line-coverage TOTAL
./dev run [-- args]     boot sim, install, launch the app; args go to the app (`-- -preview <Name>` = the gallery)
./dev screenshot [p]    PNG of the booted simulator (Duo has two displays; DEV_DISPLAY=primary|…)
./dev shot <p> [-- args] run + settle + screenshot under one simulator lock: the parallel-safe screen proof
./dev fold <pose> [p]   Duo hinge closed|half-open|open, p = PNG of the lit panel; ./dev orient <o> [p] rotates
./dev check             lint → kit → build → test; the pre-commit gate (~30s warm)
./dev sims              create missing simulator clones and list the pool (who holds which lock, which is yours)
```

Every test command prints one totals line on success (`kit: Test run with 100 tests …`, `test: 2 passed, …`) and
**fails when the filter matched nothing**, so a misspelled suite can never pass. Silence means failure output
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
  accessibility-3 Dynamic Type, light and dark) and pixel-compares them with the PNGs in
  `WorkoutsTests/__Snapshots__/<File>/` (`./dev test SnapshotTests`, part of `./dev check`). A failure writes
  `<name>.actual.png` beside the reference (git-ignored): view it. Re-record only for an *intended* visual change, after
  viewing the `.actual.png`: `SNAPSHOT_RECORD=1 ./dev test SnapshotTests` (or one suite, `SnapshotTests/ExerciseRowSnapshots`),
  which fails once by design, then re-run without it and commit the PNGs with the change. Add a component by copying a
  `Snapshot*Tests.swift` file; views with `List`, `TextField` or `NavigationStack` pass `engine: .hostedFitting` or
  `.hosted(height:)`. Dates in the PNGs use the simulator's time zone.
- **Flows need the harness.** `WorkoutsUITests/SmokeUITests` is the one XCUITest to copy from; PLAN task 0.10 extends it
  with the `-preview` gallery, and every task whose proof is a preview or a flow lists 0.10 in its `Needs`.
  UI tests launch with `-uiTesting` (in-memory store, no leftover state).
- **The UI proof of record is the fallback, not the MCP.** A screen is proven by `./dev run -- -preview <Name>` (PLAN
  task 0.10; until it lands, plain `./dev run`; a `#if DEBUG` `PreviewGallery` hosting the same views as the `#Preview`s, fed by the sample container; set Dynamic Type and
  dark with `xcrun simctl ui booted ...`) followed by `./dev screenshot`; a flow is proven by an XCUITest in `WorkoutsUITests`
  (`./dev ui-test Suite/test()`), which also forces the accessibility identifiers below. Xcode's MCP tools (plugin
  `xcode-integration` in Claude Code, `xcrun agent plugin path --plugin-format codex` in Codex) are an **optional**
  shortcut when they connect: `RenderPreview` returns a preview image without launching the app, `DeviceInteraction*` taps
  and reads the accessibility tree (they need `workspaceIdentifier` from `XcodeOpenWorkspace` on the absolute `.xcodeproj`
  path first). The bridge is a stdio process that Claude Code marks failed once it drops, and nothing an agent can do
  restarts it: only Eric typing `/mcp reconnect all` (or picking Reconnect in `/mcp`) does. If the `mcp__…xcode__*`
  tools are missing, say so once and ask him to run it, then continue with the fallback proofs above; a task's proof must
  never depend on the MCP. Skill: `verify-ui`.
- **Never toggle the simulator's displays** (`simctl io … screenConfig`, display power, device defaults): it crash-loops
  SpringBoard and floods Eric's Mac with crash dialogs. `./dev` fails any simulator command during which SpringBoard
  crashed; treat that as a stop, `xcrun simctl shutdown all`, and report. Change Duo poses only with `./dev fold` /
  `./dev orient` (skill `verify-ui`), and leave the sim closed and portrait.
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
- English only: `Text("…")` literals, no String Catalog maintenance, no `String(localized:)` in the kit.

## Working in bite-sized tasks

A task for a worker is one unit: one model type + its tests, one view + its preview, one
`xcodeproj` change. Give it the files, the approach, and exactly one proving command from the
loop above. Keep whole-suite runs (`./dev check`), screenshots across poses, and commits for the
orchestrator after review. Workers do not commit.

## Skills

- `.claude/skills/xcode-project` — `xcrun xcodeproj` recipes: list/add packages, link products,
  read/set build settings, add targets; always followed by `xcprojformatter`.
- `.claude/skills/design-review` — the read-only critique at the end of each UI phase (slop test, five scored
  dimensions, state inventory, P0–P3 findings → worker tasks, taste → Eric). HIG and `DECISIONS.md` are its authority.
- `.claude/skills/verify-ui` — render a preview, run on the Duo, screenshot, drive the UI, and
  what each pose of the Duo should be checked for.
- Apple's bundled skills (`swiftui-specialist`, `app-resizability`, `device-interaction`,
  `modernize-tests`, accessibility auditors, …) come with the Xcode plugin; invoke them by name.

## TestFlight cadence

After **every push to `main` that changes the app** (any fix, not only milestones; Eric, 2026-11-04: "we can update with
far more frequency"), the orchestrator runs `./dev testflight --upload` in the background from the main checkout. The
commit gate is unchanged: `./dev check` plus the UI suites the change touches; the full `./dev ui-test` still runs before
a milestone (a PLAN task or a review's fix batch). Never from a worktree, never with uncommitted changes,
never by workers. It takes no simulator lock (own DerivedData under `.build/testflight/`). Log each upload's build number
and commit in `docs/testflight.md`. `--upload` is gated: it refuses unless a full unfiltered `./dev ui-test` passed on HEAD
with a clean tree (`.build/ui-test.stamp`); `DEV_SKIP_UI_GATE=1` overrides with a warning. A failed upload is reported, not retried in a loop.

## Secrets (App Store Connect key)

The App Store Connect API key lives only in 1Password (`op://Homelab/Apple App Store Connect API/…`). The **only** code that
touches it is `./dev testflight`, which pipes `op read` into a mode-600 file in a fresh `mktemp -d` that a trap deletes
on exit. Never `op read` the key yourself, echo or `cat` it, put it in a variable, env var, argument, log, scratch file,
commit, PR or chat, or copy a `.p8` anywhere. Key ID and Issuer ID are not secret. If a task seems to need the key some
other way, stop and ask Eric.

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
