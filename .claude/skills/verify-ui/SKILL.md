---
name: verify-ui
description: Prove a SwiftUI change visually — render a #Preview, or run the app on the iPhone Duo simulator, screenshot it, and drive it through the accessibility tree. Use after any view change, before handing back.
---

# Verifying UI changes

Pick the cheapest proof that answers the question. Each step below is more expensive than the one
before it.

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
Orientation changes go through `DeviceInteractionSynthesize`. Switching folded/unfolded from the
CLI is **not verified** on this machine; use the Simulator's Device Hub window for that and
screenshot with `./dev screenshot`. If you find a scriptable way, record it here.
