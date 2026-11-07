# Review: device tool Phase C (C.1–C.6) and the B.4 full proof

Reviewer: Fable (read-only), 2026-11-07. Scope: `Tools/duo` (DuoKit, guest, `duo` main, tests), the `dev` paths
`pose`/`poses`/`shot`/`shot --burst`/`fold --keyframes`/`tree`/`ui-status`, `Workouts/Debug/HingeLogger.swift`,
`WorkoutsUITests/TreeDumpUITests.swift`, `.claude/skills/verify-ui/SKILL.md`. Commits a76e45a (C.1) … b8943dc (C.5).

Ran: `./dev duo-test` (153 tests, 39 suites, 1.2 s, pass); `./dev poses .build/screenshots/review-poses -- -preview Swatches`
(pass, four PNGs at the documented sizes, 16 min wall of which ~15 was waiting for another agent's lock on iPhone Duo 4);
`./dev duo hinge` afterwards → `angleDegrees: 0, pose: closed, litPanel: LCD`. The sim was left closed-portrait.

## Summary

Phase C is in good shape. The architecture holds: every command is stateless, every pose is proven by documented reads
before it succeeds, the 60 Hz schedule and the pose set are pure over injected clocks/runners and are tested as such,
and nothing in `Tools/duo` or `dev` touches `screenConfig`, display power or `shutdown all` (grep is empty). The
`sim_guarded` lock + crash guard wraps every simulator verb, `./dev duo` refuses an explicit `--udid`, and `poses`
restores closed-portrait in-process even after a failure.

The findings concentrate in the one place that is not behind the `ProcessRunning` seam: the two long-lived child
processes of `fold --keyframes` (`GuestHingeStream`, `SimctlRecorder`). They hard-code `/usr/bin/xcrun`, so none of
their ready/stop/exit paths has a test, and that is exactly where the bugs are (silent success after a dead recorder,
a 15 s wait for an error that is already known, an orphaned `recordVideo` when `duo` is killed). Nothing is P0.
B.4 passes.

## Findings

| # | Sev | Where | Issue | Suggested fix (one worker task each) |
|---|-----|-------|-------|--------------------------------------|
| 1 | P1 | `Tools/duo/Sources/DuoKit/Keyframes.swift:376-389` | `SimctlRecorder.stop` begins with `guard process.isRunning else { return }`: if `recordVideo` died between `start` and `stop` (refused display, crash, killed), `stop` returns success and `duo` prints `recorded <path>` for a missing or truncated movie. | When not running: read `terminationStatus`, check the file exists with size > 0, else throw `commandFailed` with the saved stderr. Test it (needs #5). |
| 2 | P2 | `Keyframes.swift:272-280` | Ready wait only signals on non-empty data. A guest that exits at once (IOKit symbols missing → exit 1, sim not booted, bad udid) delivers EOF: the handler is cleared without signalling, so `init` waits the full 15 s and throws `timed out … (ready)` with no stderr. The real reason is in the temp file that is then leaked (`errorURL` not removed on this path nor on the `finish` timeout path, line 303-306). | Signal on any readability event (including EOF) and also from `process.terminationHandler`; after the wait, if `!process.isRunning` throw `commandFailed(status, stderr)`. Remove `errorURL` in every exit path (a `deinit` or `defer`). |
| 3 | P2 | `Keyframes.swift:325-394`, `main.swift:137-168` | Child lifetime on a non-terminal kill. Ctrl-C in a terminal is fine (the children share the process group; SIGINT finalises the movie, the guest exits on stdin EOF). But a SIGTERM/SIGKILL aimed at `duo` alone (harness timeout, `kill <pid>`) orphans `simctl io recordVideo`, which keeps recording to the file until the simulator shuts down; the hinge is also left mid-motion. | In `Keyframes.run`, install SIGTERM/SIGINT handlers (`DispatchSource.makeSignalSource`) that SIGINT the recorder pid, close the stream's stdin and re-raise; document in usage that an interrupted keyframe run needs `./dev pose closed-portrait`. SIGKILL cannot be handled; accept and note it. |
| 4 | P2 | `Tools/duo/Sources/DuoKit/Orient.swift:163-173`; the C.3 flake (`open-tall … lit panel LCD-1 rot90` after 24 polls) | The rotate HID event is dispatched exactly once, then polled for 12 s. `Fold.verify` returns the instant the inner panel is lit, so `pose open-*` can send the rotate while the panel switch is still finishing, and a dropped event can never be recovered. The failure text does include `device …`, so the next occurrence will say whether `devicectl` followed and only the panel lagged. | Bounded re-dispatch: after N (8) unmatched polls, send the rotate once more and keep polling; one retry only, noted in the summary (`orient: re-sent`). Script it in `OrientRunTests` (observe matches only after the second `rotate` call). Do not add a fixed sleep between fold and orient. |
| 5 | P2 | `Keyframes.swift:265, 352` (+ `Keyframes.run` 200-241) | Test gap behind #1-#3: `GuestHingeStream` and `SimctlRecorder` hard-code `/usr/bin/xcrun`, so `KeyframeArgumentTests` can only check argument arrays; `Keyframes.run` (display resolution for `--record`, `stream.finish` on a failed play) is untested. | Inject the executable + arguments (default xcrun) like `ProcessRunning` does, then test with `/bin/sh -c` stand-ins: ready line vs immediate exit, `stop` after the child has died, `finish` after a non-zero exit. |
| 6 | P2 | `dev:1293` (`cmd_tree`) | `rm -rf "$RESULTS/latest-ui-test.xcresult"` destroys the merged bundle of the last full `./dev ui-test` (what `./dev coverage ui-test` reads), and after `tree` that name holds the one-test TreeDump bundle. | Call `run_tests tree WorkoutsUITests 'TreeDumpUITests/testDump()'` directly (the name is the bundle: `latest-tree.xcresult`; `test_summary`/progress only special-case `ui-test`) instead of going through `cmd_ui_test`; drop the `rm`. |
| 7 | P2 | `.claude/skills/verify-ui/SKILL.md:74-88`; `AGENTS.md:120` | The skill, which agents follow, still says "Change poses with `./dev fold` … `./dev orient`" and "Finish a run with `./dev orient portrait` and `./dev fold closed`"; it never mentions `./dev pose`, `./dev poses`, `duo hinge --app` / `-logHinge`, `settle`, or `fold --keyframes`. AGENTS.md's safety sentence says "Change Duo poses only with `./dev fold` / `./dev orient`" (should list `pose`/`poses`). | Docs task: rewrite §4's pose paragraph around `pose`/`poses` (fold/orient as the low-level verbs), add one line each for `hinge --app`, `settle` and `--keyframes`, and "finish with `./dev pose closed-portrait`". |
| 8 | P3 | `Tools/duo/Sources/duo/main.swift:198-212`, `NamedPose.swift:70-78` | `pose <name> --settle` or `--timeout` without `--png` is accepted and silently ignored (settling only applies to the capture). | `usageError("--settle needs --png")` like `--display` without `--record` already does. |
| 9 | P3 | `Tools/duo/Sources/DuoKit/Devicectl.swift:47-61` | Narrow race: the `terminate` work item can fire between `waitUntilExit()` returning and `terminate.cancel()`, marking a finished call as timed out (and `Process.terminate()` on an exited task may raise). Also stdout is read to EOF before the wait, so a grandchild that inherits the pipe would outlive the timeout; theoretical for the `hinge` guest, which exits by itself. | Guard the item with `process.isRunning`, or drive expiry from `terminationHandler`; read stdout on a background thread so the wait, not the pipe, is what the timeout bounds. |
| 10 | P3 | `Keyframes.swift:261` | `signal(SIGPIPE, SIG_IGN)` is a process-global side effect inside a type's `init`. | Move to the top of `main.swift`. |
| 11 | P3 | `Keyframes.swift:357-369` | Recorder readiness is "Recording started" grepped from simctl's stderr: undocumented text; an Xcode wording change turns every `--record` into a 15 s timeout. Bounded and the error carries stderr, so acceptable; noted. | Also accept the output file appearing/growing as the ready signal. |
| 12 | P3 | `dev:1027`, `dev:1019` | `die "poses: the set failed (closed-portrait was restored)"` is printed even when `duo` just reported `restoring closed-portrait also failed`; and `sim_require_booted` after `cmd_run` is redundant. | Message: "see duo's lines above; run `./dev pose closed-portrait` if it says the restore failed"; drop the redundant check. |
| 13 | P3 | `Tools/duo/Sources/DuoKit/AppHinge.swift:37-41, 56-58`; `main.swift:22-26` | `--last 5m` can return a stale line from a previous run (app relaunched without `-logHinge`), and the known closing-fold angle (81) is the angle at the moment status flipped, which the usage text does not say. | Print the compact-style timestamp with the status, and say in usage "angle = at the status change; rely on status". |
| 14 | P3 | `Workouts/Debug/HingeLogger.swift:15, 34` | `installed: Set<ObjectIdentifier>` can be fooled by identifier reuse after a window deallocates (a new window at the same address never gets the interaction). Debug-only. | `NSHashTable<UIWindow>.weakObjects()` or check `window.interactions` for an existing `UIHingeInteraction`. |
| 15 | P3 | `main.swift:141-144` | `--record=` (empty value) passes the check (`rest.contains("--record")` only sees the bare form) and reaches `createDirectory("")`. | Validate `record?.isEmpty == false`. |
| 16 | P3 | `Tools/duo/Guest/DuoGuest.swift:45` | Stale comment ("the part of the contract that is real in A.4"). `GuestBuilder.binaryURL()` appears unused outside tests. | Delete the comment; drop `binaryURL()` if nothing calls it. |

Known items, assessed: the orient flake is #4 (a real one-shot design gap, not noise); the mid-animation hinge angle is
#13 (documentation, status is the truth); "one movie is one panel" is correctly documented in usage, AGENTS.md and the
plan, fine as is; `./dev tree` deleting `latest-ui-test.xcresult` is #6.

## B.4 verdict: pass

Looked at the four settled PNGs from `./dev poses .build/screenshots/review-poses -- -preview Swatches`:

- `closed-portrait.png` 1398x2034 px (466x678 pt, LCD): two swatch columns, the system's vertical status strip (9:41,
  battery/Wi-Fi) on the trailing edge, nothing clipped.
- `closed-landscape.png` 2034x1398 px (678x466 pt, LCD): three columns, safe-area gutter on the leading side.
- `open-wide.png` 2853x2007 px (951x669 pt, LCD-1): five columns, status strip trailing, all 15 swatches visible.
- `open-tall.png` 2007x2853 px (669x951 pt, LCD-1): four columns, status bar across the top.

Every frame is a steady state (no half-drawn tiles or panel-switch black), the status bar is pinned to 9:41 in all four,
and the final `duo hinge` read was closed/LCD. `./dev check` and the full `./dev ui-test` were not re-run here (the
orchestrator's gate; `duo-test` passed).

## Fine as is

- `Keyframes.play`: absolute deadlines from the frame index, lateness measured against them, recorder stopped on the
  error path too; the fake-clock tests (`KeyframePlaybackTests`) exercise the real loop including the hiccup case.
- `PoseSet.run` and `PoseSetTests`: the stateful `FakeDuo` drives the real fold/orient/verify code, and the three
  scenarios (clean, mid-set failure, failed restore) check call order, files and messages.
- `Settle` / `Screenshot.captureSettled`: the final file is the settled capture by construction; timeout semantics are
  tested with a fake clock.
- `Burst`: bounded in-flight captures, first failure surfaced, pure layout arithmetic tested; `cmd_shot_burst` waits
  the background launch before reporting.
- `SystemProcessRunner`: stderr to a file (no pipe deadlock), SIGTERM then SIGKILL, tests with a TERM-ignoring child.
- `DirectoryLock` and `GuestBuilder`: atomic mkdir with dead-owner reclaim, partial-then-rename binary, stale builds pruned.
- Error messages name the observed state and the way out (`fold … not reached: hinge X deg after N reads (…), lit panel Y`,
  `no hinge line from the app … launch it with ./dev run -- -logHinge`, `--keyframes: atMs must be strictly ascending …`).
- `TreeDumpUITests` skips itself unless `TREE_PREVIEW` is set, so the full suite only gains one skipped test;
  `cmd_tree` reads the kept attachment rather than the quiet log.
- `cmd_ui_status`: reads the progress file and pid, falls back to the stamp; no simulator touched.
- Safety: no display toggling anywhere; every simulator verb is under `sim_guarded`; `--udid` always comes from `dev`'s
  resolved pool simulator; `poses` restores closed-portrait in-process.
