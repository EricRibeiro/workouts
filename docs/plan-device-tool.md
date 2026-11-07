# Plan: our own Duo device tool (replacing `agent-device`)

Status: Phase A implemented in `Tools/duo` (2026-11-05) and wired into `./dev` (Phase B, B.4 is the orchestrator's commit). Original proposal: read-only investigation of `agent-device@0.21.36` (Callstack, MIT) plus what Xcode 27.2 /
iOS 27.2 offer natively. Nothing in the repo changed besides this file. Source read from `npm pack` into the session
scratchpad (`agent-device-src/package/…` paths below refer to that extraction; the same files are on GitHub at
<https://github.com/callstack/agent-device>, e.g. `apple/fold-helper/Fold.m`).

**Phase A findings (2026-11-05, `iPhone Duo 3`, iOS 27.2) that correct the sections below:**

- **`devicectl device orientation set` does not rotate the Duo (A.3).** It exits 0 and echoes the requested `deviceOrientation` in its
  own JSON, but `orientation get` stays `portrait`, `LCD` stays `rot0` and screenshots stay 1398x2034. Rotation therefore goes through the
  vendor HID `orientation-picker-control` event (A.7), verified by the documented `orientation get` plus the lit panel's `currentOrientation`.
- **Rotation table** (`currentOrientation` of the lit panel; `nativeOrientation` is `rot0` for both): cover `LCD` portrait `rot0`,
  landscape-left `rot270`, landscape-right `rot90`; inner `LCD-1` portrait `rot90`, landscape-left `rot0`, landscape-right `rot180`. The
  dark inner panel idles at `rot90`. `devicectl orientation get` normally follows within ~1 s, but once trailed the panel by a step for
  4-5 s, so the verifier polls up to 12 s.
- **Oriented sizes.** `nativeSize` ignores `currentOrientation`: a quarter-turned panel captures with width and height swapped (open inner
  portrait = 2853x2007 px = 951x669 pt; cover landscape = 2034x1398 px = 678x466 pt). `duo screenshot` prints the oriented size; `duo panels`
  prints the native one.
- **The panel switch lags the hinge.** After a fold both panels read dark for several seconds (a closed fold takes ~6 s end to end), so
  the panel check waits up to 20 s instead of failing on "no lit panel".
- **Half-open settles at ~123 deg, not 130.** The commanded 130 deg preset ends at 123.3 deg and holds, so a named half-open is
  verified by category plus two agreeing reads, not by the commanded angle.
- Guest `panels` was dropped: the host's documented `devicectl` table is enough. `THIRD-PARTY-NOTICES.md` lives at the repo root.

## 1. Findings: how `agent-device` does the four things `./dev` uses

`./dev fold|orient|home` (dev lines 450–476) call `npx --yes agent-device@0.21.36 open <bundle> → fold|orientation|screenshot → close`.
Of the package's 771 files, our commands touch one 267-line Objective-C file and ~4 host modules. Everything else (daemon,
cloud providers, Android, web, XCTest runner, AX snapshot bridge) is unused by us.

### 1.1 Host vs guest

| Step | Where | What it runs | Source |
|---|---|---|---|
| `open <bundle> --udid U` | host | starts/attaches a local daemon, claims a **session lease** on the UDID, then `xcrun simctl launch [--terminate-running-process] U <bundle>` | `dist/src/app-launch.js` (`B()` builds the argv), `dist/src/session-open.js` |
| `open com.apple.springboard` | host | same path: `simctl launch U com.apple.springboard` foregrounds SpringBoard (= Home) | `dist/src/app-launch.js`, help text in `dist/src/cli-help.js` |
| `fold <pose>` | host → guest | builds the guest helper once, then `xcrun simctl spawn U <helper> set <pose>`; verifies with repeated `… hinge <windowMs>` reads; reports the lit panel | `dist/src/fold-helper.js`, `dist/src/app-backend.js` (`v()`, `S()`), `apple/fold-helper/Fold.m` |
| `orientation <o>` | host → guest | foldable: `simctl spawn U <helper> rotate <o>` (private HID), then verifies with **documented** `xcrun devicectl device orientation get --device U`. Non-foldable: the XCTest runner sets `XCUIDevice.shared.orientation`. `portrait-upside-down` is refused on a foldable ("device-state control has no upside-down value") | `dist/src/interactor.js` (`rr()`, `er()`, `kr()`), `Fold.m` `runRotate` |
| `screenshot <png>` | host | `xcrun devicectl device info displays --device U --json-output -` → picks the single panel whose `backlightState` is lit → `xcrun simctl io U screenshot --display=<name> <png>` (retries up to 5×). Falls back to the XCTest runner only when simctl fails | `dist/src/display-inventory.js` (`u()`, `D()`, `P()`), `dist/src/interactor.js` (`xn()`) |
| `close` | host | releases the lease; without it the next `open` on that UDID fails with `DEVICE_IN_USE` ("The leased app is in use by another session. Retry once the other session ends.") | `dist/src/session-runtime.js`, `dist/src/sdk-contracts.js` |

**How the helper gets into the simulator.** No XCTest runner, no injected dylib. `fold-helper.js` compiles `Fold.m` on first use with
`xcrun --sdk iphonesimulator clang -mios-simulator-version-min=15.0 -fobjc-arc -framework Foundation -framework IOKit Fold.m -o fold-helper`,
caches the binary under `~/.agent-device/fold-helper/` keyed by source hash + toolchain, and runs it with the **documented**
`xcrun simctl spawn <udid> <absolute host path> <args>` (`simctl help spawn`: an absolute path is taken from the host's root). The
process runs inside the simulator runtime as a plain command-line tool, so it can talk to the guest's HID event system and
CoreMotion. The XCTest runner under `dist/apple/runner/AgentDeviceRunner` (built with `xcodebuild` on `prepare ios-runner`) and the
idb-derived accessibility bridge under `apple/snapshot-bridge` (see `LICENSE.idb`) exist for `snapshot`/`press`/`fill`; our four
commands never load them.

### 1.2 The private mechanism (`Fold.m`)

- **Dispatch (`set`, `rotate`)** — `Fold.m` lines 10–30: creates an `IOHIDEventSystemClient` (`IOHIDEventSystemClientCreate`), serialises
  a dictionary with `IOCFSerialize`, wraps it in a **vendor-defined HID event** (`IOHIDEventCreateVendorDefinedEvent`, usage page
  `0xff61`, usage `0x5b`) and dispatches it (`IOHIDEventSystemClientDispatchEvent`). The payload is
  `{provider: "com.apple.Virtualization.VirtualMachines", source: "hinge-slider-control", type: "range", value: <angle 0–180>}` for the
  hinge and `{source: "orientation-picker-control", type: "enum", value: "portrait"|"landscape-left"|"landscape-right"}` for rotation.
  Presets: closed = 0°, half-open = 130°, open = 180° (`readFrames`, line 44). Keyframe sequences (2–64 frames, ≤ 60 s) are interpolated
  at 60 Hz with `mach_wait_until` (`runFrames`).
- **Where those strings come from.** They are Xcode's own Device Hub protocol: `strings` on
  `/Applications/Xcode.app/Contents/SharedFrameworks/DeviceKit.framework/Versions/A/PlugIns/CoreDevicePopDeviceKitExtension.devicekitplugin/Contents/MacOS/CoreDevicePopDeviceKitExtension`
  contains `hinge-slider-control`, `orientation-picker-control`, `com.apple.Virtualization.VirtualMachines`, `HIDEventSender`,
  `HingeController`, and the log line "No hinge reading agreed with the commanded %s and the fold never came to rest…". Inside the iOS
  27.2 runtime the only consumer of `hinge-slider-control` is **`/usr/libexec/locationd`** (the daemon that hosts CoreMotion's
  simulated sensors). So the helper sends exactly what Device Hub's slider sends, and the guest treats it as a hinge sensor reading.
- **Why it does not crash SpringBoard.** The event goes through the sensor path: locationd → CoreMotion hinge angle → UIKit/SpringBoard
  run the designed posture transition (which itself switches which panel is lit). `simctl io … screenConfig power off` instead pulls a
  framebuffer out from under SpringBoard, a state the OS never expects on hardware. Verified in this repo on 2026-11-03: zero
  SpringBoard crashes across folds (`dev` line 451).
- **Readback (`hinge`)** — `Fold.m` lines 150–195: `dlopen`s CoreMotion, instantiates the **private** `CMAngleManager`
  (`isAvailable`, `startAngleUpdatesToQueue:handler:`, sample `angleDegrees`/`isAngleValid`), takes the first sample (3 s timeout),
  optionally sleeps `windowMs`, and prints `{"angleDegrees":…, "angleValid":…}`. `CMAngleManager` is not in the public CoreMotion
  headers of the 27.2 SDK (checked). The host (`app-backend.js` `S()`) reads up to 8 times with a 1 s window until the angle's pose
  category matches; half-open additionally needs two consecutive reads within 0.5°; otherwise it fails with
  `fold-pose-unverified` / `fold-pose-unsettled` and the observed angle. Expect 2–4 s per fold (`cli-help.js` "foldable" topic).
- **Panels (`panels`)** — `Fold.m` lines 205–262: private `CADisplay`/`BLSBacklight` reads, used **only** when the simulator lives in a
  scoped device set, where `devicectl` cannot see it. In the default set (ours) the host uses documented `devicectl device info displays`.

### 1.3 Sessions and the UDID lock

`agent-device` keeps a background daemon; `open` claims a lease on the UDID for a named session and every later command needs it;
`close` releases. A leaked `open` (crashed worker, Ctrl-C) therefore blocks every later `./dev fold` with `DEVICE_IN_USE`, which is why
`verify-ui` warns about it. Our tool needs none of this: `./dev`'s per-simulator mkdir lock (`sim_lock`, dev line 382) already
serialises commands, and each tool invocation is stateless.

### 1.4 Version-fragility points (what an Xcode / runtime update can break)

1. The vendor HID protocol: usage page/usage (`0xff61`/`0x5b`), the dictionary keys and the control names. Owned by Xcode's DeviceKit
   extension and the runtime's locationd; both move together with Xcode, so a new Xcode can rename them silently.
2. `CMAngleManager` selectors (private CoreMotion).
3. `IOHIDEvent*`/`IOCFSerialize` symbols exported by the simulator SDK's `IOKit.framework` (private but long-stable; `Fold.m` links
   `-framework IOKit`).
4. `devicectl device info displays` JSON (`jsonVersion: 5`, fields `backlightState`, `active`, `name`, `nativeSize`, `pointScale`,
   `currentOrientation: rot0|rot90|…`) and the panel names `LCD` (outer) / `LCD-1` (inner) accepted by `simctl io … --display=`.
5. The guest must be rebuilt per toolchain: `agent-device` keys its cache on source hash + toolchain; we do the same.

Mitigation: every private call is behind one guest executable with a JSON contract, and every pose is **verified by a documented read**
(`devicectl` displays/orientation), so a protocol change surfaces as "pose not reached" rather than silent wrong screenshots.

## 2. What Apple offers natively (Xcode 27.2 / iOS 27.2 simulator) — documented vs private

Checked on this machine (`xcrun simctl help`, `xcrun devicectl … --help`, SDK headers, Xcode's exported `device-interaction` skill at
`~/Library/Developer/Xcode/CodingAssistant/ExportedPlugins/27B52/claude/skills/device-interaction/SKILL.md`).

| Job | Documented API | Private / undocumented | Plan |
|---|---|---|---|
| Fold the hinge | **none**: no `simctl` subcommand mentions hinge/fold/posture; `devicectl device simulate` has only `biometrics`, `location`, `statusBar`; `XCUIDevice` (XCUIAutomation headers) has no posture API; Xcode MCP `DeviceInteractionSynthesize` has `orientation …` and `b h/p/u/d` but no fold; Device Hub is GUI-only | vendor HID `hinge-slider-control` (what Device Hub sends) | private, isolated in the guest helper |
| Read hinge angle | **none host-side**. App-side: `UIHinge.status` / `UIHingeInteraction` (UIKit, iOS 27.1+, public header `UIHinge.h`) | `CMAngleManager` (CoreMotion) | private for the angle; documented lit-panel read distinguishes closed vs not; app-side `UIHinge` as a "should" cross-check (§4 C.6) |
| Which panel is lit (+ sizes, orientation) | `xcrun devicectl device info displays --device U --json-output -` works on the simulator (verified on `iPhone Duo 4`: outer `LCD` 1398×2034 @3x, inner `LCD-1` 2007×2853 @3x, `backlightState`, `active`, `currentOrientation`); `--stream` subscribes to changes | `CADisplay`/`BLSBacklight` (only needed for scoped device sets) | documented |
| Screenshot of one panel | `xcrun simctl io U screenshot --display=<name|id|uuid> <png>` (`simctl io help`); or `xcrun devicectl device capture screenshot --display-unique-id` | — | documented (`simctl`, already in `dev`) |
| Rotate | `xcrun devicectl device orientation set --device U portrait|landscapeLeft|landscapeRight|portraitUpsideDown|faceUp|faceDown` ("for devices that support it"; `get` works on the Duo; `set` is acknowledged but does **not** rotate it, see the Phase A findings); `XCUIDevice.shared.orientation` in a UI test; Xcode MCP `orientation landscapeLeft` | vendor HID `orientation-picker-control` (what agent-device uses on foldables) | HID (A.3 showed `set` is a no-op on the Duo), verified by documented `get` + displays |
| Home / background the app | `xcrun simctl launch U com.apple.springboard` (what agent-device's `open com.apple.springboard` reduces to); `XCUIDevice.shared.press(.home)` in a UI test | — | documented |
| Run code inside the simulator | `xcrun simctl spawn U /abs/path args` | — | documented |
| Accessibility tree | `XCUIApplication().debugDescription` / element queries in `WorkoutsUITests`; Xcode MCP `DeviceInteractionSynthesize` returns a hierarchy with `hitPoint`s | idb-style AX bridge (`apple/snapshot-bridge`, private `XCTAccessibilityFramework`) | documented only (later) |

Bottom line: **only two things need private API — sending the hinge angle and reading it back.** Everything else moves to documented
`simctl`/`devicectl` calls, and both private pieces are verified by documented reads.

## 3. Recommended architecture

**Language and placement.** A small SwiftPM package at `Tools/duo/` (Swift 6, macOS host, no remote dependencies; argv parsed by hand,
the surface is tiny):

```
Tools/duo/
  Package.swift              products: executable `duo`, library `DuoKit`, test target `DuoKitTests`
  Sources/DuoKit/            Simctl.swift, Devicectl.swift (JSON decoding of `info displays` / `orientation get`),
                             Panels.swift (lit-panel choice), PoseVerifier.swift (the 8-read state machine),
                             GuestBuilder.swift (compile + cache), Commands/*.swift
  Sources/duo/main.swift     subcommand dispatch, exit codes, one-line JSON or text output
  Guest/DuoGuest.swift       the in-simulator helper (single file; compiled on demand, never checked in as a binary)
  Tests/DuoKitTests/         fixtures: a captured `devicectl` JSON for the Duo, verifier timelines, argv parsing
  THIRD-PARTY-NOTICES.md     MIT notice for the Fold.m-derived parts (§5)
```

**The in-simulator piece** is `Guest/DuoGuest.swift`, a command-line tool with the same four verbs as `Fold.m` (`set`, `rotate`, `hinge`,
`panels`), compiled on first use by the host with
`xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios27.2-simulator -framework IOKit Guest/DuoGuest.swift -o .build/duo/guest/<key>/duo-guest`
(`<key>` = SHA-256 of the source + `xcodebuild -version` + `xcrun --sdk iphonesimulator --show-sdk-version`), and run with
`xcrun simctl spawn <udid> <abs path> <verb> …`. The four IOKit entry points are declared with `@_silgen_name`; `CMAngleManager` is
reached through `NSClassFromString` + `perform(_:with:with:)` with a `@convention(block)` handler. If that dynamic Objective-C dance
turns out brittle in Swift, the escape hatch is a ~120-line `Guest/DuoGuest.m` compiled with `clang` exactly as agent-device does
(judgment call, log it in `docs/judgment-calls.md`).

**Host contract.** Stateless; one process per command; exit 0 only when the requested state was verified by a documented read; failures
print the observed state (`hinge 93.4° after 8 reads`, `lit panel LCD, expected LCD-1`). Every command takes `--udid`; `./dev` supplies it.

**Fit with `./dev` and the pool.** `dev` builds the tool lazily (`swift build -c release --package-path Tools/duo --scratch-path
.build/duo/spm`, cached; ~seconds warm) into `DUO=.build/duo/spm/release/duo` and calls it inside `sim_guarded`, so the existing
per-simulator lock, crash guard (`sim_crashes`) and `sim_require_booted` wrap it unchanged. No sessions, no daemon, nothing to leak:
the "`DEVICE_IN_USE` after a leaked `open`" failure class disappears, and `./dev home` no longer needs an `open … close` pair.

## 4. Command surface

Must = needed to replace `agent-device` today; should = clear agent value next; later = nice to have.

| Command | Priority | Behaviour |
|---|---|---|
| `duo fold closed\|half-open\|open [--png P]` | must | guest `set`; verify by hinge reads (closed 0°, open 180°, half-open = category plus two agreeing reads; it settles near 123°) **and** by `devicectl` displays (closed ⇒ `LCD` lit, otherwise `LCD-1`); optional lit-panel PNG |
| `duo orient portrait\|landscape-left\|landscape-right [--png P]` | must | guest `rotate` (vendor HID, no upside-down), verified with `orientation get` + the lit panel's `currentOrientation` (rotation table above), polled up to 12 s |
| `duo home` | must | `simctl launch U com.apple.springboard`; verify a screenshot was possible (no lease) |
| `duo screenshot P [--display outer\|inner\|lit]` | must | lit panel by default (`devicectl` displays → `simctl io --display=`), explicit panel on request; prints the PNG size in px and pt |
| `duo hinge` | must | JSON `{angleDegrees, angleValid, pose, litPanel}` |
| `duo panels` | must | the decoded display table (name, lit, px, pt, orientation); the cheap "which panel am I on" question agents ask before trusting coordinates |
| `duo pose closed-portrait\|closed-landscape\|open-wide\|open-tall` | should | fold + orient + settle in one verified step; the names match `verify-ui` §4 and PLAN Phase 6 (open-wide = fold open + `orient portrait` 951×669; open-tall = `orient landscape-left` 669×951) |
| `duo settle [--timeout 10]` / `screenshot --settle` | should | wait until two consecutive lit-panel captures are byte-identical (hash), so proofs are deterministic instead of `DEV_SETTLE` sleeps |
| `duo poses <dir>` | should | the four-pose proof set in one lock hold, restoring closed-portrait at the end (the Duo pass's proof of record) |
| `duo hinge --app` | should | app-truth cross-check: the app, under `-logHinge` (DEBUG), logs `UIHinge.status` from a `UIHingeInteraction`; the tool reads it via `simctl spawn U log show --last 5s --predicate 'subsystem == "com.ericribeiro.Workouts"'` |
| `duo fold --keyframes '[{atMs,angle}…]'` | later | timed hinge motion (port of `runFrames`) for testing live fold animations (ArrangementView cover) |
| `duo tree` | later | accessibility-tree dump through a documented path: a `WorkoutsUITests` harness test that prints `XCUIApplication().debugDescription` (or the Xcode MCP hierarchy when it connects); no idb-style bridge |
| `duo record <mov>` | later | `simctl io … recordVideo --display=<lit>` around a pose sequence |

## 5. License obligations

`agent-device` is MIT (`package/LICENSE`, "Copyright (c) 2026 Callstack"). Porting `Fold.m` (even translated to Swift) is a derivative
of a "substantial portion"; the licence requires keeping the copyright and permission notice. Do it in
`Tools/duo/THIRD-PARTY-NOTICES.md` (full MIT text, the project URL, which files derive from `apple/fold-helper/Fold.m` and the version
0.21.36) and a one-line header in `Guest/DuoGuest.swift`. Nothing from `apple/snapshot-bridge` (which also carries `LICENSE.idb`,
Meta's idb) is ported. No notice is needed for the protocol facts themselves (HID constants, control names) but keep it anyway; it is
honest and costs nothing. agent-device stays untouched upstream; we do not fork or redistribute it.

## 6. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Xcode update renames the HID control or `CMAngleManager` | medium (per major Xcode) | pose verification via documented reads turns it into a clear failure; cache key rebuilds the guest per toolchain; `./dev` prints "fold unverified: see docs/plan-device-tool.md §1.4" |
| `devicectl device orientation set` does nothing on the Duo | medium | spike A.3 decides; HID `orientation-picker-control` is the known-working fallback (no upside-down) |
| Swift guest cannot express the private calls cleanly | low | Objective-C single-file escape hatch (same compile path as agent-device) |
| A guest build on a cold machine takes >10 s and races parallel workers | low | build under `.build/duo/` guarded by a mkdir lock, like `sim_lock` |
| HID dispatch during a running UI test or Live Activity perturbs the app | low | unchanged from today; `./dev` already serialises per simulator |
| Half-open never settles (the hinge keeps drifting) | low (agent-device reports it) | same 8×1 s policy and `fold-pose-unsettled` failure; half-open is not in our pose set, so no proof depends on it |
| SpringBoard crash from a bad event | very low (none seen since 2026-11-03) | `sim_guarded` crash guard stays around every call; the tool never touches `screenConfig`, display power or device defaults |

## 7. Tasks (PLAN §6 style; one worker, one proving command each; workers do not commit)

A `Needs:` reference names a task here. Proof commands assume `U=$(cat .build/dev-sim-udid)` after `./dev run` on this checkout.

### Phase A — the tool, documented pieces first

- [x] **A.1 Package skeleton + display table**: `Tools/duo/Package.swift` (tools 6.0, macOS 15, executable `duo`, library `DuoKit`,
  tests), `DuoKit/Devicectl.swift` decoding `devicectl device info displays --json-output -` (`result.displays[]`: `name`, `displayId`,
  `uniqueId`, `active`, `backlightState`, `nativeSize`, `pointScale`, `currentOrientation`, `primary`, `type.integrated`),
  `Panels.swift` choosing the lit panel (`backlightState ∈ {activeOn, inactiveOn, activeDimmed}` ⇒ lit; exactly one lit ⇒ that one; else
  error naming the count), `duo panels --udid U`. Fixture: the Duo's JSON captured once into `Tests/DuoKitTests/Fixtures/`. Add
  `.build/` of the package to nothing (the repo `.gitignore` already ignores `.build/` everywhere). Proof: `swift test --package-path
  Tools/duo` (fixture: `LCD` lit, 466×678 pt; `LCD-1` dark) and `swift run --package-path Tools/duo duo panels --udid $U`.
  **Outcome:** done. `swift test` green; `duo panels` prints `LCD lit 1398x2034 px 466x678 pt rot0` and `LCD-1 dark 2007x2853 px 669x951 pt rot90`; fixture `displays-closed.json`.
- [x] **A.2 Screenshot of the lit panel**: `Commands/Screenshot.swift`: `--display lit|outer|inner` (default lit) → `xcrun simctl io U
  screenshot --display=<name> P`; prints `P 1398x2034 px (466x678 pt, LCD)`. Needs: A.1. Proof: `swift run --package-path Tools/duo duo
  screenshot /tmp/duo-closed.png --udid $U` then `sips -g pixelWidth -g pixelHeight /tmp/duo-closed.png` = 1398×2034 on a closed Duo.
  **Outcome:** done. `duo screenshot` of the closed Duo = 1398x2034; the printed size is the oriented one (see findings).
- [x] **A.3 Orientation spike (documented path)**: `Commands/Orient.swift` using `xcrun devicectl device orientation set --device U
  <landscapeLeft|…>` and verifying with `orientation get` (`deviceOrientation`) plus displays `currentOrientation` (`rot0/rot90/rot270/rot180`)
  within 5 s. Record the outcome at the top of this file. Needs: A.1. Proof: `swift run … duo orient landscape-left --udid $U --png
  /tmp/duo-ll.png` → PNG 2034×1398 and `duo orient portrait` restores 1398×2034. If the Duo does not rotate, the task ends with that
  finding and A.7 becomes a must.
  **Outcome:** done as a finding: `orientation set` does not rotate the Duo, so A.7 was required (see findings).
- [x] **A.4 Guest helper build + cache**: `Guest/DuoGuest.swift` with the verbs `set <closed|half-open|open|angle>`, `rotate <o>`, `hinge
  [windowMs]` (JSON on stdout, usage on exit 2); `DuoKit/GuestBuilder.swift` compiles it with `xcrun -sdk iphonesimulator swiftc
  -target arm64-apple-ios27.2-simulator -O -framework IOKit` into `.build/duo/guest/<sha256(source)+xcodebuild -version+sdk version>/duo-guest`
  under a mkdir lock; `duo guest-build` prints the path. Add `THIRD-PARTY-NOTICES.md` (§5). Proof: `swift run … duo guest-build` and
  `file` on the printed path says `Mach-O 64-bit executable arm64`; `swift test --package-path Tools/duo` covers the cache key.
  **Outcome:** done. Guest compiles (`-target arm64-apple-ios<sdk>-simulator`, deployment target follows the SDK version) and runs under `simctl spawn`; cache key and mkdir lock unit-tested. The guest `panels` verb was dropped.
- [x] **A.5 Hinge readback**: guest `hinge` = `CMAngleManager` first sample + optional window (port of `Fold.m` `readHinge`, exit 3 when the
  class is missing, 4 on no sample in 3 s); host `duo hinge --udid U` = `simctl spawn U <guest> hinge <ms>` → `{angleDegrees, angleValid,
  pose, litPanel}` (pose: 0 ⇒ closed, 180 ⇒ open, else half-open). Needs: A.1, A.4. Proof: `swift run … duo hinge --udid $U` prints
  `angleDegrees: 0, pose: closed, litPanel: LCD` on a closed Duo.
  **Outcome:** done. `duo hinge` on a closed Duo = `angleDegrees: 0, angleValid: true, pose: closed, litPanel: LCD`; `CMAngleManager` is available in 27.2.
- [x] **A.6 Fold**: guest `set` sends the vendor HID event (`IOHIDEventCreateVendorDefinedEvent` page `0xff61` usage `0x5b`, payload
  `{provider: com.apple.Virtualization.VirtualMachines, source: hinge-slider-control, type: range, value: angle}`); host `duo fold <pose>
  [--png P]` = dispatch, then `PoseVerifier`: up to 8 hinge reads (window 0 then 1000 ms) until the pose category matches (half-open: two
  consecutive reads within 0.5°), then the documented panel check (`closed` ⇒ `LCD` lit, else `LCD-1`), then the optional PNG. Failure
  prints the observed angle and lit panel. `PoseVerifier` is pure and unit-tested with scripted read sequences. Needs: A.2, A.5. Proof:
  `swift run … duo fold open --udid $U --png /tmp/duo-open.png && swift run … duo fold closed --udid $U --png /tmp/duo-closed.png` →
  open PNG 2007×2853 (or 2853×2007), closed PNG 1398×2034, and `command ls -t ~/Library/Logs/DiagnosticReports | head -3` shows no new
  `SpringBoard-*.ips`.
  **Outcome:** done. open 2853x2007 px (lit `LCD-1`), closed 1398x2034, half-open settles at ~123 deg; no SpringBoard/backboardd reports across all folds. The panel check waits up to 20 s.
- [x] **A.7 Orientation HID fallback** (required: A.3 failed): guest `rotate` = `orientation-picker-control` enum event (no upside-down);
  host `orient` falls through to it and still verifies with `devicectl orientation get`. Needs: A.3, A.4. Proof: as A.3.
  **Outcome:** done (now the primary path, not a fallback): `duo orient` verified by `orientation get` + the lit panel; landscape-left cover 2034x1398, open portrait 2853x2007, open landscape-left 2007x2853; restores 1398x2034.
- [x] **A.8 Home**: `duo home --udid U` = `xcrun simctl launch U com.apple.springboard`, then confirms a lit-panel screenshot succeeds.
  Needs: A.2. Proof: `./dev run -- -startSampleWorkout`, `swift run … duo home --udid $U`, `duo screenshot /tmp/duo-home.png`; Read the PNG:
  Home screen, Workouts in the background.
  **Outcome:** done. `duo home` launches SpringBoard, confirms with a lit-panel capture (temporary file when `--png` is omitted); the PNG showed the Home screen with Workouts installed.

### Phase B — cutover (orchestrator reviews; one commit)

- [x] **B.1 Wire `./dev`**: `duo_bin()` builds `Tools/duo` into `.build/duo/spm` on demand (`swift build -c release …`, lock-guarded,
  skipped when up to date); `cmd_fold`, `cmd_orient`, `cmd_home` call `"$DUO" … --udid "$SIM_UDID" [--png]` inside `sim_guarded`;
  `agent_device_do`, `AGENT_DEVICE` and the `open`/`close` pairs are deleted; help text (dev lines 708–712) and the comment at line 450
  rewritten; `sim_require_booted` kept. Add `./dev duo <args>` as a pass-through for the new verbs (`panels`, `hinge`, `screenshot
  --display`). Needs: A.6, A.8 (A.7 if needed). Proof: `./dev fold open .build/screenshots/open.png && ./dev orient landscape-left
  .build/screenshots/tall.png && ./dev orient portrait && ./dev fold closed .build/screenshots/closed.png` → sizes 951×669 / 669×951 /
  466×678 pt as `verify-ui` documents, no crash report.
  **Outcome:** done. `duo_bin()` builds release into `.build/duo/spm` only when a file under `Tools/duo` is newer than the binary (no extra lock; SwiftPM's scratch lock suffices; `dev: building Tools/duo…` on stderr before a rebuild). `fold`/`orient`/`home` call the tool inside `sim_guarded`; `./dev duo <verb>` injects `--udid` and rejects an explicit one (use `DEV_SIM_UDID`). Measured in review: `fold open` 2.1 s, `fold closed` 5.3 s. Sizes 951x669 / 669x951 / 466x678 pt, no crash reports.
- [x] **B.2 Docs and skill**: `.claude/skills/verify-ui/SKILL.md` §4 and "Live Activity" steps 2 and 5 (drop the leaked-session warning
  and the `npx … close` line; `./dev home` is enough), `AGENTS.md` loop table (`fold`/`orient` lines), `docs/PLAN.md` 0.5b note and
  Phase 6 wording, `docs/DECISIONS.md` "Native layer" gets one heading "Duo poses are set by Tools/duo (private HID hinge event, verified
  by documented reads)". Needs: B.1. Proof: `grep -rn "agent-device\|npx" dev AGENTS.md .claude docs --exclude=plan-device-tool.md` is
  empty except history notes that say "formerly".
  **Outcome:** done. verify-ui §4 and the Live Activity steps, AGENTS.md rows, PLAN 0.5b and Phase 6/risk wording and the DECISIONS "Native layer" entry updated; the grep is empty.
- [x] **B.3 Gate**: `./dev check` runs `swift test --package-path Tools/duo` after `kit` (sub-second); `./dev lint` covers `Tools/duo`
  (`LINT_PATHS`). Needs: B.1. Proof: `./dev check`.
  **Outcome:** done. `./dev check` runs `duo-test` after kit (`duo: Test run with 93 tests …`); `LINT_PATHS` includes `Tools/duo`; `./dev duo-test` added.
- [ ] **B.4 Full proof before the commit** (orchestrator's commit, not a worker task): `./dev check`, `./dev ui-test`, and the four-pose screenshot set from B.1 read
  by a reviewer. Then commit and `./dev testflight --upload` is **not** needed (tooling only; no app change) — note that in
  `docs/testflight.md` only if the commit also touches the app.

**Rollback.** One `git revert` of the B.1–B.3 commit restores the pinned `npx --yes agent-device@0.21.36` path (its helper cache in
`~/.agent-device/` is untouched by this plan, so the first fold after a revert needs no rebuild). Nothing in the simulator pool changes
shape, so no simulator needs recreating.

### Phase C — evolutions for agents

- [x] **C.1 Pose names**: `duo pose closed-portrait|closed-landscape|open-wide|open-tall` = fold + orient + verify in one call; `./dev pose
  <name> [png]`. Needs: B.1. Proof: `./dev pose open-tall .build/screenshots/tall.png` → 669×951 pt, then `./dev pose closed-portrait`.
- [x] **C.2 Settle**: `duo settle --timeout 10` hashes two consecutive lit-panel captures 300 ms apart until equal; `screenshot --settle`
  and `pose … --png` use it; `./dev shot` replaces its fixed `DEV_SETTLE` sleep with it (keep the cold-boot 15 s). Needs: C.1. Proof:
  `./dev shot .build/screenshots/settled.png -- -preview Swatches` twice → identical SHA-256.
- [x] **C.3 Four-pose set**: `duo poses <dir>` writes `closed-portrait.png … open-tall.png` and restores closed-portrait; `./dev poses
  <dir> [-- args]` runs it under one lock after `run`. Needs: C.2. Proof: `./dev poses .build/screenshots/poses -- -preview Swatches` →
  four PNGs with the documented sizes, final `duo hinge` = closed.
- [ ] **C.4 App-truth hinge**: DEBUG launch argument `-logHinge` installs a `UIHingeInteraction` on the root window (app target; the
  kit cannot import UIKit) that logs `UIHinge.status` changes under `subsystem com.ericribeiro.Workouts, category hinge`; `duo hinge
  --app` reads the last line through `simctl spawn U log show`. Needs: B.1. Proof: `./dev run -- -logHinge`, `./dev fold open`, `./dev
  duo hinge --app` prints `fullyOpen`; then `./dev fold closed`.
- [ ] **C.5 Keyframes** (later): `duo fold --keyframes '[{"atMs":0,"angle":0},{"atMs":3000,"angle":180}]'` porting `runFrames` (60 Hz,
  absolute deadlines) with `--record <mov>` via `simctl io … recordVideo`. Proof: a 3 s movie whose first and last frames are the two
  panels.
- [ ] **C.6 Tree dump** (later): `WorkoutsUITests/TreeDumpUITests` prints `XCUIApplication().debugDescription` for `-preview <Name>`;
  `./dev tree <Name>` runs it and prints the text; no private AX bridge. Proof: `./dev tree Swatches` lists the swatch labels.

## 8. Decisions (Eric, 2026-11-05)

1. **Guest language: Swift**, with the Objective-C single-file escape hatch only if a private API is awkward from Swift.
2. **No `swift-argument-parser`**: argv is parsed by hand; `Tools/duo` has no dependencies.
3. **Half-open stays** a supported pose.
4. **Clean cut**: no agent-device fallback; rollback is a revert.
5. **`./dev check` runs the tool's tests.**
6. **A Fable review after each phase** (A, B, C) before the next starts.
