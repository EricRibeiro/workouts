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
  accessibility-extra-large`, `xcrun simctl ui booted appearance dark`. Then `./dev screenshot` and look at the PNG.
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
Change poses with `./dev fold closed|half-open|open [png]` and `./dev orient portrait|landscape-left|… [png]`
(agent-device, pinned in `dev`; it sends the simulator's own HID hinge event and confirms the hinge angle). The optional
png captures whichever panel is lit: 466x678 pt closed (outer), 951x669 open, 669x951 open rotated. Plain
`./dev screenshot` may capture a dark panel once the Duo is open, so use the fold/orient capture there. Every
coordinate and accessibility ref is stale after a pose change. Finish a run with `./dev orient portrait` and
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
