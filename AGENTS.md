# Workouts (iOS)

Native SwiftUI rewrite of the web app in `../mac-os-compose-collection/workouts/` (Go + React +
Postgres, see its `README.md`, `PLAN.md`, `IOS.md`). Targets iPhone, with the **iPhone Duo**
(foldable) as the primary device. This file is the working contract for agents; `CLAUDE.md` is a
symlink to it.

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

## Not set up yet (deliberately)

- CI (no macOS runner decision made).
- Code signing / device builds — simulator only for now.
- App data model, persistence, sync — see the web app's `PLAN.md`; port in later tasks.
