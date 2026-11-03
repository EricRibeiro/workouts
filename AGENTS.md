# Workouts (iOS)

Native SwiftUI rewrite of the web app in `../mac-os-compose-collection/workouts/` (Go + React +
Postgres). Targets iPhone, with the **iPhone Duo** (foldable) as the primary device. This file is
the working contract for agents; `CLAUDE.md` is a symlink to it. **`docs/PLAN.md` is the roadmap**:
decisions, architecture, and the ticked/unticked task list the orchestrator works from.
`docs/port/` is the feature spec extracted from the web app.

## Toolchain (pinned by what is installed on this machine)

| Thing | Value |
|---|---|
| Xcode | 27.2 (27B52), Swift 6.4 |
| Deployment target | iOS 27.2 (Duo layout needs the 27.1+ SDK) |
| Project | `Workouts.xcodeproj` — Xcode 27 **folder-based `project.xcproj`** format (JSON-like, no pbxproj) |
| Scheme | `Workouts` |
| Simulator | `iPhone Duo` (iOS 27.2) — override with `DEV_SIM=...` |
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

## The loop

```
./dev kit [filter]      swift test for WorkoutsKit        — seconds; use this first and most
./dev build             xcodebuild, iPhone Duo sim         — ~10s warm
./dev test [filter]     unit tests on the simulator        — ~25s; filter = Suite or Suite/test()
./dev lint | format     swift-format lint --strict / format --in-place
./dev run               boot sim, install, launch the app
./dev screenshot [p]    PNG of the booted simulator (Duo has two displays; DEV_DISPLAY=primary|…)
./dev check             lint → kit → build → test; the pre-commit gate (~30s warm)
```

Rules for the loop:

- **Always go through `./dev`.** It pins scheme, destination, derived data (`.build/DerivedData`)
  and `-quiet`, and prints only failures. Raw `xcodebuild` floods context.
- **Add files, don't register them.** The three target folders and the package are synced; a new
  `.swift` file in the right folder is in the build. Never hand-edit `project.xcproj`; use
  `xcrun xcodeproj ...` then `xcrun xcprojformatter --update Workouts.xcodeproj` (skill:
  `xcode-project`).
- **Run the narrowest proof.** One failing test → `./dev kit 'Suite/test'` or `./dev test Suite/test()`,
  not `./dev check`. `check` is for the end of a task.
- **Previews and the simulator are the UI proof.** Xcode's MCP tools are available in Claude Code
  (plugin `xcode-integration`) and Codex (`xcrun agent plugin path --plugin-format codex`):
  `RenderPreview` on a file with a `#Preview` returns an image without launching the app;
  `DeviceInteraction*` taps and reads the accessibility tree. Skill: `verify-ui`. Tools need
  `workspaceIdentifier`: call `XcodeOpenWorkspace` on the absolute `.xcodeproj` path first.
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
  Activity for the active workout, notifications, widgets. When a web decision and a native idiom
  disagree, choose the native idiom and say so in the task.

- **Answered 2026-11-03 (do not re-ask):** no Strong CSV import and no `Workout.source` (a one-time
  history migration from the web app happens later through an in-app JSON import). Weights are
  `Double`. Exactly one in-progress workout, persisted across relaunch. Library exercises are
  read-only; only custom exercises get rename/unit/bar/rest. Three tabs (History, Workout,
  Exercises); Settings is a gear toolbar button on History opening a `Form` sheet, not a tab.
  Folder `collapsed` is per-device state, not synced. Weeks start Monday in the device time zone.
  Exercise media (thumbnails + videos) is wanted; delivery mechanism decided in `docs/port/media.md`.
  No widgets, Shortcuts, Control Center or HealthKit: Eric starts his Apple Fitness workout in
  Apple's own app alongside this one.

## Code conventions

- SwiftUI only, `@Observable` models, `NavigationStack`/`NavigationSplitView`, `TabView`. No
  `ObservableObject`, no `NavigationView`, no UIKit unless wrapping something SwiftUI lacks.
- **Duo-ready layout.** Never read `UIScreen.main`, device idiom, orientation, or hardcode sizes.
  Use size classes and `GeometryReader`; compact width may become regular width mid-session when
  the phone opens. Tab bars/toolbars may be placed vertically on the inner display. Consult the
  `app-resizability` skill before any top-level layout work.
- Swift 6 strict concurrency is on; everything is `MainActor` by default. Mark off-main work
  `nonisolated` explicitly and keep types that cross actors `Sendable`.
- No force unwraps, no `try!` outside tests. `OrderedImports` and the rest of `.swift-format`
  are enforced by `./dev lint`.
- Every new public function in `WorkoutsKit` gets a test in the same change.
- Accessibility labels on every interactive element — the device-interaction tools navigate by
  the accessibility tree, so unlabeled controls stall agents as well as users.
- Localize user-facing strings via the String Catalog (`STRING_CATALOG_GENERATE_SYMBOLS` is on).

## Working in bite-sized tasks

A task for a worker is one unit: one model type + its tests, one view + its preview, one
`xcodeproj` change. Give it the files, the approach, and exactly one proving command from the
loop above. Keep whole-suite runs (`./dev check`), screenshots across poses, and commits for the
orchestrator after review. Workers do not commit.

## Skills

- `.claude/skills/xcode-project` — `xcrun xcodeproj` recipes: list/add packages, link products,
  read/set build settings, add targets; always followed by `xcprojformatter`.
- `.claude/skills/verify-ui` — render a preview, run on the Duo, screenshot, drive the UI, and
  what each pose of the Duo should be checked for.
- Apple's bundled skills (`swiftui-specialist`, `app-resizability`, `device-interaction`,
  `modernize-tests`, accessibility auditors, …) come with the Xcode plugin; invoke them by name.

## Git

Commit directly to `main`, no feature branches unless asked. Commits are signed (see the
machine notes in `~/.claude/CLAUDE.md` if signing fails). `./dev check` must pass before a
commit. Remote: `git@github.com:EricRibeiro/workouts.git`.

Eric wants agents to commit and push without him present, so `.claude/settings.json` allowlists
`git add/rm/commit/push/status/diff/log`. Run them **bare** (`git push`, not `cd … && git push`
or `timeout 60 git push`): the allow rule matches the command prefix, and a wrapper drops the
command back into the permission classifier, which has refused pushes over content it mistook for
publication (the private server domain in the docs).

## Not set up yet (deliberately)

- CI (no macOS runner decision made).
- Code signing / device builds — simulator only for now. Distribution will be TestFlight (no
  direct-to-device installs); blocked on Apple Developer Program approval, then `./dev testflight`.
- App data model and screens — see `docs/port/` and the phases in `docs/PLAN.md`.
