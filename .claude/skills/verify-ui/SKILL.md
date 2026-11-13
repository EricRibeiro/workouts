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
  `#Preview`s on the sample container (PLAN task 0.10). Dynamic Type: `./dev ui-env content_size
  accessibility-extra-large` (the app is dark-only, so screenshots are dark whatever `ui-env appearance` says; this session's simulator; `./dev ui-env reset` = large/light;
  tests, `ui-test` and `./dev tree` reset to large/light, so re-apply ui-env before `./dev shot`). Prefer `./dev shot <png> -- -preview <Name>`: run,
  settle and screenshot as one simkit job, so a parallel worker cannot install its build in between. Then Read the PNG.
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
./dev run            # takes a simulator lease, boots, builds, installs, launches
./dev screenshot     # .build/screenshots/<timestamp>.png — open it with Read
./dev shot <png> [-- args]   # run + settle (two identical captures, status bar pinned to 9:41) + screenshot as one job: the parallel-safe proof
./dev shot --burst <png> [-- args]   # 15 lit-panel captures ~100 ms apart from launch, tiled into one labelled grid: a reviewer artifact for transitions; plain `shot` stays the steady-state proof
./dev release        # when you are done: ends this session's lease
```
Text size (the app is always dark): `./dev ui-env content_size accessibility-extra-large`; `./dev ui-env reset` afterwards (large/light). Tests and `./dev tree`
reset these too, so re-apply before `./dev shot`.
Logs: `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.ericribeiro.Workouts"'` (`booted` is whichever simulator is up; with more than one booted, take the udid from `./dev sims`).

The simulator is simkit's: a lease from its queue, shared with other projects (`./dev sims` = `sim status`). Exit 75 means wait, never retry it
in a loop. The `simkit:simulator` skill covers the rest: real touches (`sim tap --changed` says whether the screen changed), pictures, text size,
pixel probes. `./dev probe` runs this repo's `sim/probes.json` on the app launched with `-uiTesting`.

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

Change poses with `./dev pose closed-portrait|closed-landscape|open-wide|open-tall [png]` (fold + orient in one verified step;
open-wide is 951x669 pt, sidebar expanded; open-tall 669x951, sidebar collapsed behind its toggle) or `./dev poses <dir> [-- args]`
(runs the app, then all four as settled PNGs, always ending closed-portrait). `./dev fold closed|half-open|open [png]` and
`./dev orient portrait|landscape-left|landscape-right [png]` are the low-level verbs under them, and `./dev duo <verb>` passes
`panels`, `hinge`, `settle`, `screenshot`, `home` to simkit (`hinge --app` reads the angle and status the app logs when launched
with `./dev run -- -logHinge`; the status, not the angle, is the truth). `./dev fold --keyframes '<json>' [--record <mov>]` plays
timed hinge motion for transition checks; an interrupted run needs `./dev pose closed-portrait`. How the poses are set and proven,
what each verb prints and the pose timings are simkit's (its `AGENTS.md`, "The loop"; skill `simkit:simulator`). What matters here:
the optional png is whichever panel is lit (466x678 pt closed, 951x669 open, 669x951 open rotated), plain `./dev screenshot` may
capture a dark panel once the Duo is open, so use the pose/fold/orient capture there, and every coordinate and accessibility ref is
stale after a pose change. Finish a run with `./dev pose closed-portrait` and `./dev release`, so the next agent starts from the
default pose.

What to check in each pose:

- **Closed portrait / landscape**: compact width. The Dynamic Island, status bar, toolbar and tab bar sit in a strip on the
  trailing edge; nothing may be clipped under it, and every toolbar item shows a symbol.
- **Open wide / open tall**: regular width. The sidebar is expanded in wide and collapsed behind its toggle in tall; content must not
  stretch edge to edge.
- **After a pose change mid-session**: the same screen keeps its state when compact becomes regular.

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

simkit's crash guard fails a `./dev` verb during which SpringBoard, PosterBoard, backboardd or one of the app's own processes crashed
(`own_processes` in `simkit.json`). If that happens: stop and report it; never `simctl shutdown all` (it kills other agents' simulators)
and never retry past it.

## Live Activity on the simulator (proven 2026-11-03, task 1.5)

1. `./dev run -- -startSampleWorkout` (DEBUG: seeds sample data, starts the first template, starts a 300 s rest).
2. Background the app: `./dev home` (the MCP's `b h` / `b p` hardware buttons do nothing on this simulator).
3. Pull down the Lock Screen view with the MCP: `DeviceInteractionStartSession` on the Duo, then
   `DeviceInteractionSynthesize` `t 150 2 f 150 450 0.4` (closed pose, 466x678 pt). The Live Activity banner is there;
   the first time, the system asks "Allow Live Activities from Workouts?" inside the banner: tap Allow.
4. Tap the banner's buttons by coordinates from the screenshot (`t <x> <y> w 3`), read the screenshot after each.
   Dismiss with `t 233 670 f 233 200 0.3`, then `DeviceInteractionEndSession` (key `interactionSessionKey`).
The Dynamic Island is not drawn in simulator screenshots of the closed Duo's strip; use the Lock Screen banner.

- **Text size**: the `-UIPreferredContentSizeCategoryName` launch argument does **not** apply through `./dev shot` (Phase 3 review, 2026-11-04). Set it on the session's simulator: `./dev ui-env content_size accessibility-extra-large`, shoot, then `./dev ui-env reset`. Same for `./dev ui-env appearance dark|light`.
