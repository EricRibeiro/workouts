# XCUITest flakes: findings and fix list

## 1 Current state

**Evidence limit.** Only the latest run (12f5649) still has bundles: `.build/results/ui-test-shards/{shard-1,shard-3,retry-1,retry-3}.xcresult`. `.build/logs/` holds no shard logs. The ExerciseList (11-06) and FirstFrame (11-08) failure messages are gone, so those two are diagnosed from code and git history only.

| Test | Failure (xcresult) | Likely race | Side |
|---|---|---|---|
| `AccessibilityAuditUITests/testActiveWorkoutLogging` (shard 1, 11 s) | "Hit area is too small" at `AccessibilityAuditUITests.swift:55`, with an element screenshot. Passed on retry in 12 s. | Audit runs straight after `screen.activeWorkout` appears (`launchedInActiveWorkout`, `XCUIApplication+Launch.swift:75`). The cover is still presenting, and a 300 s rest ring is live in the toolbar. The `-902` retry in `audit()` (`:55-70`) covers only "invalid target app". | Probably test-side (unsettled UI). It could be a real undersized control in one transient state, so it needs the element's identity (see Fix 1). |
| `RestRingUITests/testRestEndsWhileSetFieldHasFocus` (shard 3) | `expectation(for: label BEGINSWITH 'Rest timer, ')` timed out at 5 s (`startRest`, `RestRingUITests.swift:122`). **The test took 256 s**; the retry took 21 s. | Environmental stall. Earlier steps passed, and the same shard's next-slowest test took 73 s. Shard 3 ran 24m12s against 19m49s and 19m41s for the others. A 5 s budget after a tap is too tight when the runner or sim stalls. | Test-side budget. Hypothesis, unverified: the always-on `TimelineView(.periodic 0.25)` in `RestStateProbe` (`RestExpirySeam.swift`) keeps the app from going idle while a rest runs. It only appears in `-uiTesting`, so it is no product risk. |
| `ExerciseListUITests/testBestSetFollowsUnitChange` | Message lost. | Long chain: Settings, swipe-until-hittable loops (`:131,144`), tab switches, then a 10 s predicate (`:161`). Each query waits for idle and snapshots the tree. The Settings alert OK and the unit-segment tap are un-anchored UI steps. | Test-side. |
| `FirstFrameUITests/testTemplatePreviewChromeBeforeLastPerformed` | Message lost. `FirstFrameUITests.swift:75-78` documents an earlier flake of this test: the 10 s `-slowLoads` hold starts at the push, while queries on a busy shard took > 3 s. | The "not there yet" assertion races the load hold. Slack is now 10 s, but `card.tap()` and `waitForExistence(template.preview)` (5 s) both burn it before the `.exists` check at `:89`. | Test-side. Absence is the only claim, and it is inherently timing-bound. |

**Sleeps**

- `CoverTimerUITests.swift:17`: `Thread.sleep(2.5)` waits for the nav subtitle (`Nov 8 · 0:52`) to tick. The tick period is minute-ish or per-second, so 2.5 s is a gamble.
- `SetTableKeyboardRevealUITests.swift:38,106,115`: `sleep(1)` waits for keyboard avoidance and the reveal scroll to settle. Line 111 deliberately does not wait. The assertions are on frames read after the sleep.
- `LoggingBlockMenuUITests.swift:124`: `RunLoop.run(1)` negative settle. It needs a sleep, since "did not move" cannot be awaited.
- `PerfDriverUITests.swift`: 13 sleeps (`:31-142`), but it skips itself without `PERF_DRIVER` (`:20`), so it is in the run only as 3 skips. Leave it.
- `XCUIElement+Waiting.swift` already has `waitUntilGone`, `assertStaysAbsent` and `waitUntil(_:)`. A `XCUIApplication+Waiting.swift` does not exist. `Support/` has the other helpers.
- The Darwin seam exists: `expireRestNow()` (`XCUIApplication+Launch.swift:43`) and the `debug.restState` probe (`none`, `running`, `over`).

**Retry policy** (`dev:496-497`, `ui_shard_retry` at `~dev:410`)

- A shard with failures reruns exactly those tests once, alone, on the same sim. A full pass records `flaky=<ids>` in the stamp and appends to `ui-flaky.log`.
- "Flaky twice in a row" compares only the same test id against the previous stamp's `flaky=` line. Four different tests flaking in four runs never trips it. Any run that is not a full pass leaves the stamp untouched, and a filtered run does not write it.
- The `ui-flaky.log` line records only time, commit and id: no failure message, no duration, no shard, no load. That is why two of the four causes are lost.
- The retry runs in a quiet, single-test setting, which hides load-dependent app and test bugs. For `RestRing` it hid a 256 s stall, and for the audit the transient-state finding.

## 2 Options

**A. Make each test wait on a state, not a clock** (mechanism: `expectation(for:)`, `waitForExistence`, `waitUntil`, the probe)
- Sketch for `CoverTimer`: `let before = subtitle.label; let ticked = NSPredicate(format: "label != %@", before); expectation(for: ticked, evaluatedWith: subtitle); waitForExpectations(timeout: 15)`.
- Sketch for the keyboard tests: wait on geometry. `waitUntil { after.maxY <= next.frame.minY && next.frame == lastPillFrame }`. Two frames 0.25 s apart that are equal mean settled.
- Proves: the same assertions, without a dead 1 s. Cannot prove: "stays put" claims (`LoggingBlockMenu:124` keeps a sleep).
- Cost 2-3 h. Flake risk: low, and it lowers the existing risk.
- Sources: [Apple, XCTWaiter](https://developer.apple.com/documentation/xctest/xctwaiter), [Apple, waitForExistence](https://developer.apple.com/documentation/xctest/xcuielement/waitforexistence(timeout:)).

**B. Wider budgets and settle anchors for the four tests**
- `startRest`: raise 5 s to 15 s and assert via a `waitUntil` that records the elapsed time.
- Audit test: before `audit()`, wait for `app.buttons["rest.ring"]` label `BEGINSWITH 'Rest timer, '` and the first `setrow.*.weight`, then `_ = app.wait(for: .runningForeground, timeout: 10)`.
- Wrap `audit()` to include `issue.element?.debugDescription` and `compactDescription` in the failure text, so the next hit area flake names the element.
- Reorder FirstFrame: do `.exists` first, then the other asserts. Take the app's own timestamp or `-slowLoads` from the first frame (`debug.*` value) instead of wall-clock. Raise the hold to 20 s.
- Cost 2 h. Risk: low. It cannot tell a slow machine from a real app stall.

**C. Replace dev's retry with `xcodebuild -retry-tests-on-failure -test-iterations 2`** (or `-test-repetition-mode retry-on-failure`)
- On `test-without-building -xctestrun`, the result bundle keeps every attempt per test (`testRuns[]` in `xcresulttool get test-results test-details`). The shard's own retry then disappears, along with the extra relaunch cost.
- Proves: the same as dev's retry, plus per-attempt messages kept in one bundle. Cannot prove: anything about masking. Apple and third parties both say it is a diagnosis aid, not a fix ([WWDC21 10296](https://developer.apple.com/videos/play/wwdc2021/10296/), [Tuist flaky tests](https://docs.tuist.dev/en/guides/features/test-insights/flaky-tests)).
- Not a better fit here: dev's retry already adds the "same test flaky twice in a row fails" rule, which the flags do not provide. Keep dev's retry and copy the first attempt's failure message into `ui-flaky.log`.
- I did not verify the flags in Xcode 27.2. Cost 1 h to try on one shard.

**D. Flake trend gate** (mechanism: shell over `ui-flaky.log`)
- Extend each log line: `<utc> <commit> <id> <shard> <secs> <first failure message, one line>`. The message comes from `xcresulttool get test-results summary` `testFailures[].failureText`, already read in `ui_shard_retry`.
- Gate in `cmd_ui_test` after a full pass: `awk -v n=3 -v m=8` counting distinct runs per test over the last 8 stamps. Fail if any test has >= 2 flakes in the last 8 full runs, or if the same suite flaked >= 3 times (the suite-level signal catches the 4-different-tests pattern).
- Add `./dev ui-flaky` for a weekly summary table: test, count, last commit.
- Cost 2 h. Risk: none to tests. The gate's threshold needs a run history of about 10 entries before it means anything. Today there are 4.

**E. Run-until-failure repro for each** (`-run-tests-until-failure -test-iterations 20`, one sim, no shards)
- Proves whether a flake is load-dependent (passes alone) or intrinsic. The brief forbids sim runs for me, so this is for Eric. Cost 30 min each, mostly waiting.

## 3 Recommendation

1. **Fix 1: audit test.** B on the audit test first, because a real tap target bug would hide here. View the "Element Screenshot" attachment in `shard-1.xcresult` now (Xcode, open the failed run). If the element is the rest ring or a keyboard accessory, it is an app issue and not test-side. Then add the settle anchor and the element description.
2. **Fix 2: RestRing.** B: widen the `startRest` wait to 15 s. Also record why a 256 s stall happened (check the Mac for sleep or thermal throttling at 2026-11-09 04:5x).
3. **Fix 3 and 4: ExerciseList and FirstFrame.** B plus the richer log in D, so the next occurrence leaves a message. Do not redesign them first.
4. **Sleeps: A**, for `CoverTimer` (predicate) and the three `SetTableKeyboardReveal` ones (frame equality). Leave `LoggingBlockMenu:124` and `PerfDriver`.
5. **D.** The suite-level trigger matters most, since the current rule cannot see this pattern.
6. **Skip C**; revisit only if shard time dominates.

## 4 Open questions for Eric

- Do you accept a gate that fails a run on a flake that passed on retry (D)? It blocks TestFlight uploads more often, so it needs a threshold you pick (my default: 2 in the last 8 full runs).
- Was something else heavy running on the Mac at 04:5x on 11-09? A 256 s test points to the machine, not the app.
- OK to add a failure-message column to `.build/ui-flaky.log` (it is untracked)?
- May I treat `RestStateProbe`'s 0.25 s `TimelineView` as a suspect for slowing quiescence, and test replacing it with a one-shot timer in `-uiTesting`?
