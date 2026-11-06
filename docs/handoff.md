# Handoff (2026-11-06)

State: `main` is at `a668089` (past-workout and template editors as full-screen covers), committed and pushed.
Everything below is optional follow-up; nothing on `main` is half-done. Read `CLAUDE.md` first, then
`docs/judgment-calls.md` JC94–102 for what the last session decided and why.

## 1. Log the last upload (2 min)

A full `./dev ui-test` + `./dev testflight --upload` was started for `a668089` as a plain background shell. Its
output went to `/private/tmp/claude-501/-Users-ericribeiro-Projects-workouts/4ef2d514-ca6b-4c6b-8880-a17b4ecf3054/tasks/b1mcccjiq.output`
(may be gone after a reboot).

- If it printed `testflight: uploaded build <N>`: append a row to `docs/testflight.md`
  (`| <N> | a668089 | Gated (...): past-workout and template editors open full screen |`), commit, push.
- If it failed or the file is gone: check `.build/ui-test.stamp` (`commit=` must be `a668089…`, `clean=1`). If it
  doesn't match, run `./dev ui-test` then `./dev testflight --upload` from the main checkout (never a worktree,
  never with uncommitted changes), and log the build. Never pass `DEV_SKIP_UI_GATE=1` without Eric's OK.

## 2. Live Activity snapshot tests (unfinished, tests only)

Uncommitted work in worktree `.claude/worktrees/agent-a453ac934c56baafa` (based on `39613f1`, old):
`WorkoutsTests/Snapshot/SnapshotLiveActivityTests.swift`, references under
`WorkoutsTests/__Snapshots__/SnapshotLiveActivityTests/`, a view split in `WorkoutsLiveActivity/DynamicIslandViews.swift`
(`CompactLeadingContent`/`CompactTrailingContent` taking `isLimited: Bool`, because `isDynamicIslandLimitedInWidth`
is get-only), the lock-screen `#Preview` moved to `ActivityPreviews.swift`, and a `project.xcproj` membership change
that compiles five `WorkoutsLiveActivity/` view files and the `Shared/` folder into `WorkoutsTests`.

Two open problems before it can merge:
1. Drop the five cases that draw a ring (compact-resting, minimal-resting, minimal-rest-over, limited-resting,
   limited-rest-over): app-hosted `ProgressView(timerInterval:)` renders an animated spinner, so they verify nothing
   and may flake.
2. Compiling `Shared/` into `WorkoutsTests` duplicates `SkipRestIntent`/`AddRestIntent`/`DoneSetIntent` and
   `ActivityIntentRouter` next to the `@testable import Workouts` copies. `WorkoutsTests/ActivityIntentTests.swift`
   must keep exercising the app's router. Least invasive clean fix: don't add `Shared/` to the test target; have the
   Live Activity views take their buttons/intents from outside, or include only what compiles without them.

Simplest path: take the patch (`git -C <worktree> add -A && git -C <worktree> diff --cached --binary HEAD`), apply it
to a fresh worktree off `main` with `git apply --3way`, fix the two problems, then `./dev test SnapshotTests`,
`./dev test ActivityIntentTests`, `./dev check`. Project-file changes only via `xcrun xcodeproj` +
`xcprojformatter` (skill `xcode-project`).

## 3. Known edge case (unverified)

If the workout cover is requested (Live Activity tap, rest-notification tap) while a past-workout or template editor
cover is up, the workout cover can't present over it. Unchecked: whether it presents once the editor closes. The
resume ring shows once the editor is gone (it follows `AppNavigation.isWorkoutCoverOnScreen`) and tapping it
re-requests. Worth one UI test in `OpenWorkoutURLUITests` (open editor → `XCUIDevice.shared.system.open(workouts://workout)`
→ Cancel the editor → expect the cover or the ring).

## 4. Still open from before

- Device tool `Tools/duo` Phase C (pose names, settle, four-pose set, app-truth hinge, keyframes, tree dump),
  then a Fable review of the phase (`docs/plan-device-tool.md`).
- Taste items for Eric, in `WorkoutsUITests/AccessibilityAuditUITests.swift` as `TODO(Eric, design)`: secondary text
  contrast just under WCAG AA; the template preview sheet's material background.
- A custom exercise's default bar weight follows the Settings unit (JC98: needs a model field; deliberately not done).

## 5. Housekeeping

- Many finished agent worktrees remain under `.claude/worktrees/`. Their diffs are archived in
  `.build/worktree-archive/*.patch`. All except `agent-a453ac934c56baafa` (item 2) are merged and can be removed
  (`git worktree remove --force <path>` per worktree, then `git worktree prune`).
- The bug-review loop is finished (rounds found 27 → 19 → 13 → 5; JC96–101). Don't restart it without Eric asking.
