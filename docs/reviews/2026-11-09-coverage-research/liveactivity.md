# Live Activity coverage and a repeatable Island check

Read-only research. Nothing was run on a simulator; coverage was read from `.build/results/latest-test.xcresult` and `latest-ui-test.xcresult`.

## 1 Current state

- **How the views are unit-covered.** `WorkoutsTests/Snapshot/SnapshotLiveActivityTests.swift` renders the views as plain SwiftUI with `Snapshot.assert(..., engine: .hostedFitting)`. It never builds an `ActivityViewContext`. The `WorkoutsLiveActivity/` view files are compiled into the test bundle (`docs/handoff.md:13-24`). The Island is faked with a black rounded `Island` frame (lines ~75-90) and the expanded row is hand-assembled from `ExpandedControlsView` + `ExpandedTimerView`, mirroring `WorkoutLiveActivity.swift:25-29`.
- **Why `DynamicIslandViews.swift` is 59.6% (56/94).** The tests drop every case that draws a ring. App-hosted `ProgressView(timerInterval:)` renders an animated spinner, not the widget ring (comments at `SnapshotLiveActivityTests.swift` `limitedWidthWorking`/`minimalWorking`; `docs/handoff.md:21-23`).
  - **Not exercised:**
    - `ActivityRing` `restOver` branch (`DynamicIslandViews.swift:14-22`).
    - `ActivityRing` running-rest branch (`:23-31`).
    - `CompactLeadingContent` limited-with-ring-rest and ring-rest branches.
    - `CompactTrailingContent` resting and `restOver` branches.
  - **Rendered:** expanded (all four states), compact working/rest-over, limited working, minimal working.
  - **Not testable at all:** compact-with-timer, because the system draws the timer; that is why `ActivityTimers.swift` is 89%.
  - **Inference:** I did not get per-line `xccov` output to parse, so the line list above is inferred from the test file, not read from the report.
- **`WorkoutLiveActivity.swift` is 0/82.** `ActivityConfiguration` and `DynamicIsland` are only constructed by the WidgetKit host. They are not instantiable in a test: I found no documented unit or snapshot path (Apple Forums threads [715866](https://developer.apple.com/forums/thread/715866), [713212](https://developer.apple.com/forums/thread/713212)). The supported render path is `#Preview(as: .dynamicIsland(.expanded/.compact/.minimal)` or `.content`, which exists in `ActivityPreviews.swift:107-148`. The file itself says the narrow stack cannot be previewed because `isDynamicIslandLimitedInWidth` is get-only (`ActivityPreviews.swift:118-120`).
- **`-liveActivity` is used by no UI test.** `grep liveActivity WorkoutsUITests dev` finds nothing. The flag is read only at `Workouts/App/WorkoutsApp.swift:268-277`. `docs/reviews/2026-11-07-test-gaps.md:113` says a fixture "exists for the one test that needs it", but no such test exists. UI-test coverage of `LiveActivityController` is 11.7% and of `EngineActivityIntentHandler` 16.7% (latest-ui-test.xcresult).
- **Intent path is unit-covered.** `Shared/ActivityIntents.swift` is 100% in unit tests (`ActivityIntentTests`). `EngineActivityIntentHandler` (`skipRest`, `addRest(seconds:)`, `completeSet`, `flush`) and `LiveActivityController` (92%) are covered too. What is not covered is the render → tap → intent → re-render loop.
- **Crash note origin.** JC20 (`docs/judgment-calls.md:41-46`, commit a483d3a): after a reinstall, iOS relaunches the extension from the replaced bundle under containermanagerd `Dead/` while a test's activity is still up, and the extension crashes. `./dev` treats that exact path as install noise (warn only).

## 2 Options

### A. Snapshot the ring branches through a seam (unit; covers `DynamicIslandViews`)
- **Mechanism:** the ring cases fail only because the system ring is a `ProgressView(timerInterval:)`. Split `ActivityRing` the way `CompactLeadingContent` was split: a pure `ActivityRingContent(kind: .over / .running(range) / .idle)` plus a `#if DEBUG` seam that draws a static `Gauge`/`Circle().trim` stand-in under test. Alternatively, run the branches without a pixel assert.
- **Sketch:**
  ```swift
  // DynamicIslandViews.swift
  struct ActivityRing: View {
      var body: some View { ActivityRingContent(kind: .init(state, restOver), drawsSystemRing: true) }
  }
  // test: drawsSystemRing: false -> Circle().trim(from: 0, to: fraction) + glyph, deterministic
  @Test func minimalResting() { Snapshot.assert(Island(...){ MinimalView(...) }, named: "minimal-resting", ...) }
  ```
- **Proves:** the branch selection (restOver vs running vs idle, limited vs full), glyph/label/tint wiring, layout of the stacked Duo Island with a ring-sized element. **Cannot prove:** the system ring itself or the countdown drain.
- **Cost:** ~2 h. **Flakiness:** low (static drawing). Fits "change the design instead of hacking to match".
- **Moves:** `DynamicIslandViews` from 60% to roughly 90%+. Does nothing for `WorkoutLiveActivity.swift`.

### B. Cover `WorkoutLiveActivity.swift` by factoring the builder
- **Mechanism:** `ActivityConfiguration` cannot be run, so the 82 lines are mostly the builder closure. Move the closure bodies into testable functions (`WorkoutLiveActivity.lockScreen(context state:isStale:)`, `islandRegions(...)`) that take `(state, isStale)` and return views. Then the file is a thin shell. The remainder (`ActivityConfiguration(for:)`, `DynamicIsland {}` assembly) stays at 0% by design.
- **Proves:** the `isStale` → `restOver` derivation (`state.isRestOver(stale:)`) feeds the right views. **Cannot prove:** that the system accepts the configuration.
- **Cost:** ~1.5 h. **Flakiness:** none. Honest ceiling: ~40-50% of that file. Consider recording an exclusion rather than chasing 100%.
- **Sources:** no framework path exists; [Forum 715866](https://developer.apple.com/forums/thread/715866).

### C. XCUITest through SpringBoard (end-to-end tap of +30 s)
- **Mechanism:** launch `-uiTesting -liveActivity`, start a rest, `XCUIDevice.shared.press(.home)` or lock, then query `XCUIApplication(bundleIdentifier: "com.apple.springboard")` for the Lock Screen banner's `"Add 30 seconds of rest"` button (accessibility label set at `ActivityControls.swift:29`). Tap it, return to the app and compare `rest.ring`'s label.
- **Sketch:**
  ```swift
  let app = XCUIApplication.launchedInActiveWorkout(extra: ["-liveActivity"])
  addTeardownBlock { /* end activities: see D */ }
  let before = ringSeconds(app)
  XCUIDevice.shared.press(.home)
  let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
  let plus30 = sb.buttons["Add 30 seconds of rest"]
  XCTAssertTrue(plus30.waitForExistence(timeout: 15))   // lock-screen banner / notification centre
  plus30.tap(); app.activate()
  XCTAssertGreaterThan(ringSeconds(app), before + 20)
  ```
- **Proves:** extension loads, buttons render, intent runs in the app, engine mutates. This is the only path that covers `WorkoutLiveActivity.swift` and `EngineActivityIntentHandler` through the real system.
- **Cannot prove:** the Island (see below), or StandBy.
- **Evidence it is possible:** one project drives the Lock Screen Stop button this way ([vnhlvn/vetscribe PR #25](https://github.com/vnhlvn/vetscribe/pull/25)); SpringBoard is a public XCTest target ([callstack/agent-device #1296](https://github.com/callstack/agent-device/issues/1296)). A tutorial advises asserting app state first, not SpringBoard-private selectors ([qajobfit Appium LA guide](https://qajobfit.com/resources/appium-3-test-ios-live-activities)). No source confirms the Island (compact/expanded) is exposed in the accessibility tree, nor anything about the iPhone Duo or the closed-Duo strip. **Unverified on iOS 27 and on the Duo; needs a spike.**
- **Cost:** 4-8 h including a spike. **Flakiness:** high. The activity needs the extension to launch and may not appear on a pooled, parallel-sharded simulator; the banner position depends on the lock state. Keep it out of the sharded suite or tag it opt-in.

### D. Activity cleanup so C is safe
- **Mechanism:** teardown calls `Activity<WorkoutActivityAttributes>.activities.forEach { await $0.end(nil, dismissalPolicy: .immediate) }` through a `-liveActivityCleanup` launch path, or the app ends all activities at `-uiTesting -liveActivity` launch (the controller already enumerates `Activity.activities`, `LiveActivityController.swift:52-58`).
- **What it fixes:** the crash needs an activity alive across a reinstall. Ending in teardown (and at next launch) removes that precondition, but only if the process survives long enough; a test that crashes or is killed still leaves one. `./dev` should keep its "dead-bundle crash = install noise" tolerance. **Not verified**: this is reasoned from JC20, not reproduced.
- **Cost:** ~1.5 h with C.

### E. Reviewable PNGs without a device
- **Mechanism:** the `#Preview(as: .dynamicIsland(.expanded/.compact/.minimal))` and `.content` blocks already exist. Xcode MCP `RenderPreview` (CLAUDE.md "UI proof" rule) can render them without a simulator. A third-party README ([pi-xcode-mcp](https://cdn.jsdelivr.net/npm/pi-xcode-mcp@0.1.0/README.md)) says it returns a `previewSnapshotPath`. No source confirms that widget `as:` previews work through it. **Spike:** call `RenderPreview` once on `ActivityPreviews.swift` "Expanded".
- **Proves:** layout and colours per region and Dynamic Type. **Cannot prove:** the narrow Duo Island (read-only `isDynamicIslandLimitedInWidth`), StandBy night recolouring, hardware. Forum reports say previews render while on-device activity fails ([thread 822724](https://developer.apple.com/forums/thread/822724)).
- **Cost:** 1 h. **Flakiness:** none.
- For the narrow Duo, the existing snapshot `limited-working` plus A (ring cases) is the closest simulated check.

## 3 Recommendation

1. **A** (ring seam + 5 snapshots, ~2 h): the cheapest real move on `DynamicIslandViews`.
2. **E** spike (1 h): gives Eric reviewable PNGs of expanded/compact/minimal/Lock Screen per region. If `RenderPreview` refuses `as:` previews, document that and keep `./dev run` + the sim.
3. **B** (~1.5 h): factor the builder closures; accept the remaining `ActivityConfiguration` lines as uncoverable and say so in `docs/PLAN.md`.
4. **C + D** only after a 1-hour spike on whether SpringBoard exposes the Lock Screen banner on the iOS 27 Duo sim. Opt-in, run alone, never in the shard.
5. The two device checks (narrow Island on the closed Duo during a rest, buttons in StandBy night) stay with Eric. No simulator path found that exercises either.

## 4 Open questions for Eric

- Is a "repeatable Island check" a PNG he can review (E) or an automated pass/fail (C)? C is the only one that touches the real extension but is the flakiest.
- OK to add a DEBUG seam in `ActivityRing` (A), given the "change the design" rule? The alternative is leaving the ring branches uncovered.
- Accept `WorkoutLiveActivity.swift` below 100% (builder-only coverage), or add an explicit coverage exclusion?
- If C goes ahead, is it acceptable to run it with `-liveActivity` on a dedicated sim outside the sharded pool, given the Dead/ bundle crash?
- Can `docs/reviews/2026-11-07-test-gaps.md:113` be corrected? It claims a `-liveActivity` fixture test exists; none does.
