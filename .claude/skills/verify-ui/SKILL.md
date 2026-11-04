---
name: verify-ui
description: Prove a SwiftUI change visually — render a #Preview, or run the app on the iPhone Duo simulator, screenshot it, and drive it through the accessibility tree. Use after any view change, before handing back.
---

# Verifying UI changes

Pick the cheapest proof that answers the question. Each step below is more expensive than the one
before it.

## 0. The proof of record needs no MCP

Xcode's MCP (steps 1 and 3 below) is optional and has failed to connect in every session so far; a proof must not depend on
it. The fallback is the proof of record:

- **Screens**: `./dev run -- -preview <Name>` launches the `#if DEBUG` `PreviewGallery` root, which hosts the same views as the
  `#Preview`s on the sample container (PLAN task 0.10). Dynamic Type and dark: `xcrun simctl ui booted content_size
  accessibility-extra-large`, `xcrun simctl ui booted appearance dark`. Prefer `./dev shot <png> -- -preview <Name>`: run,
  settle and screenshot under one simulator lock, so a parallel worker cannot install its build in between. Then Read the PNG.
- **Flows**: an XCUITest in `WorkoutsUITests`, run with `./dev ui-test Suite/test()`. It navigates by accessibility
  identifier, so unlabeled controls fail it just as they stall agents.
- Register every new screen in the gallery in the same change.

## 1. Preview (no app launch, ~10–60s)

Every view file should carry a `#Preview`. Render it through Xcode's MCP:

1. `XcodeOpenWorkspace` with `/Users/ericribeiro/Projects/workouts/Workouts.xcodeproj` → note the
   `workspaceIdentifier` (it changes per Xcode launch; don't hardcode it).
2. `RenderPreview` with `sourceFilePath: "Workouts/<File>.swift"` and that identifier. Add
   `previewDefinitionIndexInFile` for a second `#Preview` in the same file.
3. Look at the returned PNG yourself. A successful render does not reveal clipped or truncated
   text; check it.

Previews are the right tool for layout, colours, Dynamic Type (`previewVariantOverrides`), and
dark mode. They are the wrong tool for navigation flows and state.

## 2. Simulator run + screenshot (~15s warm)

```
./dev run            # boots iPhone Duo, builds, installs, launches
./dev screenshot     # .build/screenshots/<timestamp>.png — open it with Read
./dev shot <png> [-- args]   # run + 4 s settle (DEV_SETTLE) + screenshot in one lock hold: the parallel-safe proof
```
Dark mode / text size: `xcrun simctl ui booted appearance dark`,
`xcrun simctl ui booted content_size accessibility-extra-large`.
Logs: `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.ericribeiro.Workouts"'`.

## 3. Drive the UI (flows, taps, typing)

Use Apple's device-interaction tools (skill `device-interaction` has the command syntax):
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
a cold boot settles 15 s before `shot` captures. `./dev sims` lists the pool.

Change poses with `./dev fold closed|half-open|open [png]` and `./dev orient portrait|landscape-left|… [png]`
(agent-device, pinned in `dev`; it sends the simulator's own HID hinge event and confirms the hinge angle). The optional
png captures whichever panel is lit: 466x678 pt closed (outer), 951x669 open, 669x951 open rotated. Plain
`./dev screenshot` may capture a dark panel once the Duo is open, so use the fold/orient capture there. Every
coordinate and accessibility ref is stale after a pose change. After `fold open`, `./dev orient portrait` gives the wide layout (951x669, sidebar expanded)
and `./dev orient landscape-left` the tall one (669x951, sidebar collapsed behind its toggle); the names are the reverse of the
PNG shape. Finish a run with `./dev orient portrait` and
`./dev fold closed` so the next agent starts from the default pose. Device Hub
(`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`) remains the manual fallback.

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
they run. If that happens: stop, `xcrun simctl shutdown all`, and report it. Never retry past it.

## Live Activity on the simulator (proven 2026-11-03, task 1.5)

1. `./dev run -- -startSampleWorkout` (DEBUG: seeds sample data, starts the first template, starts a 300 s rest).
2. Background the app: `./dev home` (the MCP's `b h` / `b p` hardware buttons do nothing on this simulator). Never run
   agent-device `open` by hand without a matching `close`: a leaked session holds the Duo and every later `./dev fold`
   fails with DEVICE_IN_USE.
3. Pull down the Lock Screen view with the MCP: `DeviceInteractionStartSession` on the Duo, then
   `DeviceInteractionSynthesize` `t 150 2 f 150 450 0.4` (closed pose, 466x678 pt). The Live Activity banner is there;
   the first time, the system asks "Allow Live Activities from Workouts?" inside the banner: tap Allow.
4. Tap the banner's buttons by coordinates from the screenshot (`t <x> <y> w 3`), read the screenshot after each.
   Dismiss with `t 233 670 f 233 200 0.3`, then `DeviceInteractionEndSession` (key `interactionSessionKey`) and
   `npx --yes agent-device@0.21.36 close --udid <udid>`.
The Dynamic Island is not drawn in simulator screenshots of the closed Duo's strip; use the Lock Screen banner.

- **Text size**: the `-UIPreferredContentSizeCategoryName` launch argument does **not** apply through `./dev shot` (Phase 3 review, 2026-11-04). Your checkout has its own pool simulator, so set it there: `xcrun simctl ui <udid> content_size accessibility-extra-large` (udid = the THIS-CHECKOUT row of `./dev sims`), shoot, then `xcrun simctl ui <udid> content_size medium`. Same for `appearance dark|light`.
