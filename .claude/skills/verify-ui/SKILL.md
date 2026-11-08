---
name: verify-ui
description: Prove a SwiftUI change visually — render a #Preview, or run the app on the iPhone Duo simulator, screenshot it, and drive it through the accessibility tree. Use after any view change, before handing back.
---

# Verifying UI changes

Pick the cheapest proof that answers the question. Each step below is more expensive than the one
before it.

## 0. The proof of record needs no MCP

Xcode's MCP (steps 1 and 3 below) is the first shortcut; a proof must not depend on it. The fallback is the proof of
record:

- **Screens**: `./dev run -- -preview <Name>` launches the `#if DEBUG` `PreviewGallery` root, which hosts the same views as the
  `#Preview`s on the sample container (PLAN task 0.10). Dynamic Type and dark: `./dev ui-env content_size
  accessibility-extra-large`, `./dev ui-env appearance dark` (this checkout's sim, under the lock; `./dev ui-env reset` = large/light;
  tests, `ui-test` and `./dev tree` reset to large/light, so re-apply ui-env before `./dev shot`). Prefer `./dev shot <png> -- -preview <Name>`: run,
  settle and screenshot under one simulator lock, so a parallel worker cannot install its build in between. Then Read the PNG.
- **Flows**: an XCUITest in `WorkoutsUITests`, run with `./dev ui-test Suite/test()`. It navigates by accessibility
  identifier, so unlabeled controls fail it just as they stall agents.
- **Tree**: `./dev tree <Name>` prints the accessibility tree (labels, frames, identifiers) of a `-preview <Name>` screen, to
  check what an agent or VoiceOver sees without a screenshot.
- Register every new screen in the gallery in the same change.

## 1. Preview (no app launch, ~10–60s)

Every view file should carry a `#Preview`. Render it through Xcode's MCP:

1. `XcodeOpenWorkspace` with the current checkout's absolute `Workouts.xcodeproj` path (worktrees differ; never hardcode
   one) → note the `workspaceIdentifier` (it changes per Xcode launch; don't hardcode it). Opening it writes a
   `project.xcworkspace` stub under the project; it is git-ignored, leave it alone.
2. `RenderPreview` with `sourceFilePath: "Workouts/<File>.swift"`, that identifier and an iPhone Duo render destination (the
   default is an iPad). Add `previewDefinitionIndexInFile` for a second `#Preview` in the same file.
3. Look at the returned PNG yourself. A successful render does not reveal clipped or truncated
   text; check it.

`--lean` workers have no MCP tools; everyone else does.

Previews are the right tool for layout, colours, Dynamic Type (`previewVariantOverrides`), and
dark mode. They are the wrong tool for navigation flows and state.

## 2. Simulator run + screenshot (~15s warm)

```
./dev run            # boots iPhone Duo, builds, installs, launches
./dev screenshot     # .build/screenshots/<timestamp>.png — open it with Read
./dev shot <png> [-- args]   # run + settle (two identical captures, status bar pinned to 9:41) + screenshot in one lock hold: the parallel-safe proof
./dev shot --burst <png> [-- args]   # 15 lit-panel captures ~100 ms apart from launch, tiled into one labelled grid: a reviewer artifact for transitions; --settle stays the steady-state proof
```
Dark mode / text size: `./dev ui-env appearance dark`,
`./dev ui-env content_size accessibility-extra-large`; `./dev ui-env reset` afterwards (large/light). Tests and `./dev tree`
reset these too, so re-apply before `./dev shot`.
Logs: `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.ericribeiro.Workouts"'`.

## 3. Drive the UI (flows, taps, typing)

This is for exploration and hierarchy reads; a flow's proof of record is still an XCUITest. Use Apple's device-interaction tools (skill `device-interaction` has the command syntax):
`DeviceInteractionStartWorkspaceSession` (device `iPhone Duo`, pass the workspace identifier) →
`DeviceInteractionInstallAndRun` → `DeviceInteractionSynthesize` (`t x y` tap, `w 1` wait, typing,
orientation) → `DeviceInteractionEndSession`. Each synthesize returns a screenshot **and** the
accessibility hierarchy; take coordinates from the hierarchy, never from the image. Unlabeled
controls are invisible here — add `accessibilityLabel`s rather than tapping blind. End the
session as soon as you are done; it is expensive to keep open.

## 4. The Duo poses

Layout work must be checked in all four poses: closed portrait and landscape (compact width,
outer display), open tall and open wide (regular/regular, inner display, hinge in the middle).
**Simulator pool.** `./dev` gives each checkout (main, each worktree) its own simulator from the pool (`iPhone Duo`,
`iPhone Duo 2`…`iPhone Duo 5`), remembered in `.build/dev-sim-udid`, so parallel workers rarely queue. Every command in a
checkout hits that one simulator, so its fold pose and text size belong to your checkout; still leave it closed and
portrait. Each simulator has its own lock; the crash guard stays global. Booting is headless (no Simulator.app window), and
a cold boot settles 15 s before `shot` captures. `./dev sims` lists the pool. Any simulator command shuts down other pool
clones that are booted, unlocked, unused for `DEV_SIM_IDLE_MIN` (30) minutes and not running the app (`dev: shut down idle iPhone Duo 3`), so a
simulator you left booted and walked away from cold-boots again next time.

Change poses with `./dev pose closed-portrait|closed-landscape|open-wide|open-tall [png]` (fold + orient in one verified step;
open-wide is 951x669 pt, sidebar expanded; open-tall 669x951, sidebar collapsed behind its toggle) or `./dev poses <dir>`
(all four as settled PNGs under one lock, always ending closed-portrait). `./dev fold closed|half-open|open [png]` and
`./dev orient portrait|landscape-left|landscape-right [png]` are the low-level verbs under them (`Tools/duo`, our own tool: it
sends the same HID hinge and orientation events as Xcode's Device Hub from a helper inside the simulator, then proves the pose
with documented reads, hinge angle, `devicectl` orientation and the lit panel, and fails with the observed state if the pose is
not reached; an orientation event that was dropped is re-sent once, reported as `(re-sent)`). Each command is stateless: no
session to open or close, and `./dev`'s per-simulator lock is the only serialisation. The optional png captures whichever panel
is lit: 466x678 pt closed (outer), 951x669 open (PNG 2853x2007), 669x951 open rotated (PNG 2007x2853). Plain `./dev screenshot`
may capture a dark panel once the Duo is open, so use the pose/fold/orient capture there. A closed fold takes about 6 s because
the panel switch trails the hinge; half-open settles near 123 deg, not the commanded 130. Other verbs are one `./dev duo <verb>`
away: `panels` (which panel is lit, with pixel and point sizes), `hinge` (angle, pose, lit panel; `hinge --app` reads the angle
and status the app logs when launched with `./dev run -- -logHinge`, where the status, not the angle, is the truth), `settle` (waits for
two identical consecutive captures of the lit panel), `screenshot <png> --display lit|outer|inner`, `fold <degrees>` for an
explicit angle, `home`. `./dev fold --keyframes '<json>' [--record <mov>]` plays timed hinge motion at 60 Hz (one panel per
movie) for transition checks; an interrupted run needs `./dev pose closed-portrait`. Every coordinate and accessibility ref is
stale after a pose change. Finish a run with `./dev pose closed-portrait` so the next agent starts from the default pose.
Device Hub (`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`) remains the manual fallback.

**Never experiment with the simulator's displays.** `xcrun simctl io <dev> screenConfig --display=N
power off|on` (tried 2026-11-03 to fake folding) put SpringBoard into a crash loop: a "SpringBoard quit
unexpectedly" dialog on Eric's Mac every few seconds. Do not use `screenConfig`, display power, or any
undocumented simctl/defaults change to the device. `simctl io enumerate` and `screenshot --display=N`
(read-only) are fine. Use `./dev fold` for poses, never anything else.

**Preview renders are not guarded by `./dev`.** `RenderPreview` runs the view in PreviewShell; a layout bug there
(seen 2026-11-03: `LayoutSubview.place` assertion from `fixedSize`/`layoutPriority`/`maxWidth: .infinity` around a
linear `ProgressView(timerInterval:)` in a Live Activity) crashes PreviewShell and pops a dialog on Eric's Mac. Run
`command ls -t ~/Library/Logs/DiagnosticReports | head -3` before and after every render; on a new `PreviewShell-*.ips`,
stop rendering and fix the view (it would crash on device too). Never re-render the same code hoping it passes.

`./dev run|test|ui-test|screenshot|check` fail when a new `SpringBoard-*.ips` crash report appears while
they run. If that happens: stop and report it; never `simctl shutdown all` (it kills other agents' simulators) and never retry
past it. If it was a pool clone with 2+ PosterBoard/SpringBoard/backboardd reports, `dev` has already shut down and erased that
clone itself (the original is never erased automatically); the next run boots it clean.

## Live Activity on the simulator (proven 2026-11-03, task 1.5)

1. `./dev run -- -startSampleWorkout` (DEBUG: seeds sample data, starts the first template, starts a 300 s rest).
2. Background the app: `./dev home` (the MCP's `b h` / `b p` hardware buttons do nothing on this simulator).
3. Pull down the Lock Screen view with the MCP: `DeviceInteractionStartSession` on the Duo, then
   `DeviceInteractionSynthesize` `t 150 2 f 150 450 0.4` (closed pose, 466x678 pt). The Live Activity banner is there;
   the first time, the system asks "Allow Live Activities from Workouts?" inside the banner: tap Allow.
4. Tap the banner's buttons by coordinates from the screenshot (`t <x> <y> w 3`), read the screenshot after each.
   Dismiss with `t 233 670 f 233 200 0.3`, then `DeviceInteractionEndSession` (key `interactionSessionKey`).
The Dynamic Island is not drawn in simulator screenshots of the closed Duo's strip; use the Lock Screen banner.

- **Text size**: the `-UIPreferredContentSizeCategoryName` launch argument does **not** apply through `./dev shot` (Phase 3 review, 2026-11-04). Your checkout has its own pool simulator, so set it there: `./dev ui-env content_size accessibility-extra-large` (it resolves this checkout's sim itself), shoot, then `./dev ui-env reset`. Same for `./dev ui-env appearance dark|light`.
