# Duo open poses: automated proof options

## 1 Current state

- **Placement decisions are already pure and unit-tested.** `FoldPlacement.placement(size:divisions:axes:)` and `frames(for:in:headerHeight:)` live in the kit (`Packages/WorkoutsKit/Sources/WorkoutsKit/Layout/FoldPlacement.swift:50,78`), with 24 tests covering wide/tall/square, book, laptop/bench, keyboard-up and clamping (`FoldPlacementTests.swift:17-239`). The 0% file is only the glue around it.
- **BenchArrangement responds to real geometry, not only to the environment.** `BenchArrangementBody` reads `GeometryReader` `proxy.size` and `proxy.reservedRegions(kind: .division)` (`BenchArrangement.swift:41-58`). The size class is read one level up: `ActiveWorkoutCover` passes `axes: []` unless `horizontalSizeClass == .regular` (`ActiveWorkoutCover.swift:240,257-261`). Two consequences:
  - Injecting `.regular` at 951x669 with no division gives `.sideBySide`; at 669x951 it gives `.stacked`. That is exactly open-wide and open-tall.
  - Bench (half-open laptop) needs a real active division. A snapshot cannot fake one.
- **Wide snapshots today use `ImageRenderer`.** `SnapshotDashboardCardsTests.swift:77-88` (width 800) and `SnapshotHeartRateChartTests.swift:37-44` (width 700) inject `.environment(\.horizontalSizeClass, .regular)` on the default `.image` engine. The dashboard comment says outright that "a hosted window cannot be wider than the scene". `Snapshot.host` (`SnapshotTesting.swift:332-358`) builds a `UIWindow(windowScene:)` from the closed sim's scene and only overrides the colour scheme and content size. On a closed sim, the hosted engines (which the cover needs: List, TextField) cannot reach 951 pt.
- **Hinge control is host-only.** `duo-guest` is spawned into the sim via `simctl spawn` and drives a vendor-HID/CoreMotion private path (`Tools/duo/Guest/DuoGuest.swift:1-25`). `pose` = fold + orient, verified by hinge reads and the lit panel (`NamedPose.swift`; open-wide = open+portrait, open-tall = open+**landscape-left**). The app-side hinge read is a `log show` of `-logHinge` lines (`Tools/duo/Sources/DuoKit/AppHinge.swift`).
- **Tests never pose the sim.** `run_tests` → `sim_reset_ui` resets only content size and appearance (`dev:233-238,240-277`). Closed-portrait is a convention (`./dev pose closed-portrait` after every pose). There are no `.xctestplan` files. Env reaches the runner only through `TEST_RUNNER_*` (`dev:297,304,1414`).
- **Seams that already exist:**
  - Test → app: Darwin `notify` with `notify_register_dispatch` in the app (`Workouts/Debug/RestExpirySeam.swift:11-32`).
  - App → test: a zero-size AX probe (`debug.restState`, `:39-69`).
  - Host ↔ test through the xcresult: `TreeDumpUITests` reads `TREE_PREVIEW`, skips itself otherwise, and leaves an attachment that `dev tree` exports (`TreeDumpUITests.swift:12-30`, `dev:1407-1430`).
- **XCUITest:** `XCUIDevice.shared.orientation` (documented) can rotate the device, which moves between open-wide and open-tall. I found no XCUIDevice API for hinge or fold, and no simctl hinge verb; the web search turned up only Android Espresso fold actions. There is no Apple CLI for rendering previews; only third-party test-target libraries.

## 2 Options

### A. ImageRenderer placement snapshot of the arrangement itself (static, no sim pose)
**Mechanism.** Host `ArrangementView` with coloured, labelled placeholders under `BenchArrangementStyle` at 951x669 and 669x951 on the `.image` engine, as the wide dashboard does.
```swift
@Test(arguments: [CGSize(width: 951, height: 669), CGSize(width: 669, height: 951)])
func openPlacement(size: CGSize) {
    Snapshot.assert(
        ArrangementView { Color.blue.overlay(Text("primary")) }
            secondary: { Color.orange.overlay(Text("secondary")) }
            .arrangementViewStyle(BenchArrangementStyle(axes: [.horizontal, .vertical]))
            .frame(height: size.height),
        named: size.width > size.height ? "open-wide" : "open-tall",
        variant: .default, width: size.width)
}
```
- **Proves:** the glue applies `FoldPlacement` (equal halves side by side and stacked). It covers `BenchArrangementBody`/`BenchLayout`. With axes `[]` it also proves single.
- **Cannot prove:** the real table and pane, bench mode (no division), or the fold transition. Whether `ArrangementView` renders under ImageRenderer is unverified.
- **Cost:** 1 h. **Flakiness:** very low.

### B. Pose-aware snapshot and UI runs (`DEV_POSE`)
**Mechanism.** `dev` poses the sim after `sim_reset_ui`, under the same lock, and always restores it. The tests learn the pose from `TEST_RUNNER_DUO_POSE` and skip without it, following the `TreeDumpUITests` pattern.
```bash
# in run_tests, after sim_reset_ui "$SIM_UDID"
if [[ -n "${DEV_POSE:-}" ]]; then
  duo_bin; "$DUO_BIN" pose "$DEV_POSE" --udid "$SIM_UDID" || die "pose $DEV_POSE failed"
  export TEST_RUNNER_DUO_POSE="$DEV_POSE"
  trap '"$DUO_BIN" pose closed-portrait --udid "$SIM_UDID" >/dev/null 2>&1 || true; sim_release' EXIT
fi
```
```swift
// OpenPoseUITests
try XCTSkipIf(env["DUO_POSE"] != "open-wide", "run with DEV_POSE=open-wide ./dev ui-test OpenPoseUITests")
let app = XCUIApplication.launchedForTesting(["-preview", "ActiveWorkoutCover"])
XCTAssertEqual(app.windows.firstMatch.frame.size, CGSize(width: 951, height: 669))
let pane = app.descendants(matching: .any)["cover.exercisePane"]
XCTAssertTrue(pane.waitForExistence(timeout: 10))
XCTAssertGreaterThan(pane.frame.minX, 951 / 2 - 1)   // secondary on the right half
```
- **Proves:** the real app in a real open pose, with real size class and focus following the pane. Coverage lands in `latest-ui-test`. The same env lets a `DEV_POSE=open-wide ./dev test SnapshotBenchTests` hosted snapshot of the full cover work (the scene is 951 wide). Mid-test `XCUIDevice.shared.orientation = .landscapeLeft` gives open-wide → open-tall, a **real placement change (sideBySide → stacked)**. That tests the identity claim (focused cell, typed draft and scroll survive) with a documented API only.
- **Cannot prove:** a hinge fold (open↔closed changes the size class and the scene).
- **Cost:** 3-4 h. Add one `-only-testing` exclusion so the sharded full run leaves the suites skipped.
- **Flakiness:** low to medium. The pose is verified before launch, and rotation settles are the main risk.

### C. Mid-test fold handshake (host folds while the test waits)
**Mechanism.** The test logs a request; a host watcher started by `dev` folds; the test waits on observable geometry, so no reply channel is needed.
- Test: `os_log` "fold-request open" under subsystem `com.ericribeiro.Workouts.uitest`.
- Host watcher (a background job inside the lock): `simctl spawn $udid log stream --predicate 'subsystem == "…uitest"'`, then `duo pose <p>` on each request. This reuses the `AppHinge` log-read pattern.
- Test: `wait(for: window.frame.width == 951)`, then checks focus, `value` and the row frame.

```swift
os_log("fold-request %{public}s", log: uitestLog, "open-wide")
XCTAssertTrue(app.windows.firstMatch.wait(for: \.frame.width, toEqual: 951, timeout: 20))
XCTAssertTrue(cell.hasKeyboardFocus); XCTAssertEqual(cell.value as? String, "102.5")
```
Half-open (`duo fold half-open`) would also prove bench mode and `bench.rest`. A Darwin channel through `simctl spawn notifyutil -w/-p` is an alternative, but I could not confirm that `notifyutil` exists in the sim runtime.
- **Proves:** the actual product claim: a fold, closed → open → half-open, keeps the table's focus and scroll.
- **Cost:** 6-10 h (watcher lifecycle, timeouts, always restoring closed-portrait).
- **Flakiness:** medium to high. The hinge HID path is private, and SpringBoard crash guards are involved. It must run single-sim and outside the shards.

### D. Previews CLI
Apple ships none; `RenderPreview` exists only through the Xcode MCP. Third-party tools (SnapshotPreviews, SnapView) amount to option A/B with another dependency, and the project bans remote packages without asking. Not worth it.

## 3 Recommendation
1. **A now (1 h).** Cheapest, deterministic, and it takes `BenchArrangement` off 0% inside `./dev check`.
2. **B next (3-4 h).** `DEV_POSE` plus an `OpenPoseUITests` suite proves the real open-wide and open-tall layouts. The rotation test proves the fold-stable identity claim with documented APIs only, which fits "change the design instead of hacking" better than C. Optionally add a posed hosted snapshot of the full cover.
3. **C only if the fold itself must be gated.** Keep it opt-in (like `HealthKitIntegrationUITests`) and run it before TestFlight, not on every check. Otherwise keep `./dev poses` as reviewer evidence for open↔closed and half-open.

## 4 Open questions for Eric
- Does a rotation-in-open test (B) count as enough proof of "focus and scroll survive a pose change", or must the hinge fold itself be automated (C)?
- Should posed suites join the `testflight --upload` gate, or stay opt-in?
- Is it acceptable for `run_tests` to pose the sim (it already holds the lock), or should posing stay limited to `pose`/`poses`?
- Spike needed: does `ArrangementView` render under `ImageRenderer`? If not, A collapses into B's posed hosted snapshot.

Sources: [Microsoft Surface Duo foldable UI test kit](https://devblogs.microsoft.com/surface-duo/foldable-ui-test-kit/), [Espresso device actions (Android fold)](https://developer.android.com/reference/kotlin/androidx/test/espresso/device/action/package-summary), [simctl spawn usage](https://gist.github.com/ahcode0919/fba90a8c4d6c5026573a8ecf77f09aca), [Swift Forums: snapshot previews from CLI](https://forums.swift.org/t/snapshot-swiftui-previews-from-cli-without-changing-source-code/80580), [SnapshotPreviews](https://emergetools.com/blog/posts/unit-test-xcode-previews), [SnapView](https://github.com/Abdo-codes/SnapView).
