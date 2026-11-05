# Final design review (Fable, 2026-11-05) — whole app, UX half of PLAN 7.6

Read-only. Method: `.claude/skills/design-review`; poses and captures per `verify-ui`. Evidence: 101 captures under
`/private/tmp/claude-501/-Users-ericribeiro-Projects-workouts/396cb7c1-8aec-4e77-a169-18e72f4177ca/scratchpad/review/`
(listed at the end), every gallery screen closed-portrait in light, dark and `accessibility-extra-large`, the real root on
`-sampleWorkouts 200 -healthFixture full` (templates, history, Fitness enrichment on), a logged set, the rest sheet, the
keyboard, finish and the update-template dialog driven through Xcode's device-interaction MCP (it connected this session),
then open wide, open tall, half-open (bench) and closed landscape via `./dev fold` / `./dev orient`, including a
closed → open → half-open → closed → open round trip with a cell focused and a value typed. Not covered: the Dynamic Island
(no Island simulator in the pool; PLAN §7 risk) and the Lock Screen Live Activity banner (proven in 1.5; unchanged since).

## Verdict

**Slop test: pass.** Every screen reads as a native iOS 27 app, not a ported site: system bars and strip placement
everywhere, large titles, `Menu`/`Picker` pills, `confirmationDialog` popovers anchored on their items, `contextMenu` on
cards, `Form` settings, `ContentUnavailableView` empties, one tint, cards by fill, SF Symbols only, no bottom chrome, no
hand-placed glass. The Duo poses feel intentional: the trailing strip stacks Close → ring → actions → Finish, closed
landscape moves the strip to the leading edge without any layout change, the open display gives History a two-column
dashboard with its gutter on the fold, Exercises a permanent two-pane split, and the logging screen a table + exercise
pane that follows the focused exercise; folding mid-set keeps the typed value, the focused cell and the keyboard in every
direction. What stops it being finished is one in-gym blind spot (no countdown anywhere while typing on the closed display),
one cross-screen data inconsistency (set numbering), and a handful of pose-specific layout gaps that need a check on the
real hinge.

Scores: **conformance 4 · hierarchy/layout 3 · colour/appearance 3 · type/content 3 · states/resilience 3.**

| Dimension | Score | Key finding |
|---|---|---|
| Platform conformance | 4 | System components throughout; the only non-system control is the set table, which is the product. |
| Hierarchy and layout | 3 | Open-tall exercise detail leaves a ~130 pt hole under the segments; bench pose keyboard sits over its accessory; AX workout-detail header drifts. |
| Colour and appearance | 3 | Semantic assets, dark designed; a checkable set row draws its check exactly like a row that cannot be checked. |
| Type and content | 3 | Set labels differ between Exercise History and everything else; a lowercase body part and "Workouts Duo" slip through. |
| States and resilience | 3 | Empty, search, disabled, dialog and error states exist and read well; the rest countdown disappears entirely while typing closed. |

## Findings

Severity first. Fix class in the Fix column: *token* / *one-off* / *conceptual* / *local*.

| P | Screen · file:line | What (evidence) | Rule | Fix | Taste? |
|---|---|---|---|---|---|
| P1 | Logging, closed, keyboard up · `Workouts/Features/Shared/SetTable/SetKeyboardToolbar.swift:27-54` | With the pad up and a rest running, the strip shrinks to Minimise · More (ring, Skip, +30, Finish inside More, accepted JC51) **and** the keyboard group folds its countdown, Skip and +30 into ⋯ (`.visibilityPriority(.low)` on the rest trio). The remaining time is visible nowhere on the closed display while the user types the next set (`active-keyboard-closed-light.png`, `active-keyboard-more-closed-light.png`, `active-refolded-closed.png`; the ⋯ menu holds only "Add 30 seconds" and "Skip"). | DECISIONS "Rest UI": the keyboard group *prepends the countdown*; "nothing below the ring may be needed mid-set". §5 the user in the gym. | *local*: give the countdown its own keyboard `ToolbarItemGroup` with `.visibilityPriority(.high)` (it is 36 pt of digits); leave Skip/+30 low and −/+ default so they fold first. Brief A below. | no |
| P1 | Exercise detail › History vs Workout detail / set table · `Packages/WorkoutsKit/Sources/WorkoutsKit/Library/ExerciseHistory.swift:106-116` vs `History/WorkoutDetail.swift:177` | The same session is numbered **W, W, 1, 2** in Exercise History ("markers do not consume numbers") and **W, W, 3, 4** in the workout detail and the live table (`exercisedetail-history-closed-light.png` vs `workoutdetail-closed-light.png`, `settable-closed-light.png`). | DECISIONS "Web rules kept verbatim" (set numbering), JC30 "number by position among completed sets". Two rules for one fact. | *local (kit)*: label by `index + 1` as `WorkoutDetail` does; update `ExerciseHistoryTests`. Brief B below. | no |
| P2 | Logging, half-open (laptop/bench) with keyboard · `Workouts/Features/ActiveWorkout/BenchArrangement.swift`, `SetKeyboardToolbar.swift` | In the half-open pose the system gives the pad the right half but its backdrop spans the full width from y 453, over the keyboard accessory (items at y 440–478: countdown, Skip, +30, −, +, Previous, Next, Done). The accessory renders faded under the glass and a tap on Done's hit point did not dismiss (`active-half-open-bench.png`; hierarchy `Final Design Review Duo4 Open-01_18_36_663`). JC59 accepted the side-by-side split under the keyboard, not an occluded accessory. | duo-layout "Keyboard accessory bars stay horizontal"; HIG keyboards: accessory views must stay reachable. | *verify on the Duo first* (simulator keyboard layouts in the bench pose are suspect). If real: while the division is active and the keyboard is up, mirror Next/Done/countdown into the strip `ToolbarItemGroup` (BenchLayout already knows the pose) and file Feedback for the keyboard. | no |
| P2 | Exercises, open wide · `Workouts/Features/Exercises/ExercisesView.swift` (split), `ExerciseDetailView.swift:25,112` | The split's divider sits at x≈300 while the fold is at x≈475: the detail column (300→880) straddles the fold and, inside the split, the detail deliberately does **not** use an `ArrangementView` (`inSplitColumn`). The empty-state placeholder is centred at x≈593 (`exercises-open-wide.png`). A selected exercise in the half-open book pose will put instructions through the hinge. | DECISIONS "Navigation": "the system keeps columns off the fold"; duo-layout "Keep each view entirely on one side of the division"; JC60 "no max so the split still sizes to the fold". | *conceptual (verify)*: `./dev run -- -selectTab exercises`, pick a row, `./dev fold half-open png`. If the divider does not move to the fold, the DECISIONS premise is wrong and the question goes to Eric (ideal column width from `onGeometryChange` vs. the detail becoming an `ArrangementView` inside the split). Not a polish row. | no |
| P2 | Exercise detail, open tall (pushed, regular) · `Workouts/Features/Exercises/ExerciseDetailView.swift:112-134` | Stacked split gives the hero + name + note + segments pane half the height; its content ends ~130 pt above "Chest / Instructions", a dead band in the middle of the screen (`exercisedetail-open-tall.png`). Wide is fine (`exercisedetail-open-wide.png`). | HIG layout (no unexplained empty regions); duo-layout "stacked when tall". | *local*: when the split axis is vertical, size the primary to its content (`fixedSize(horizontal: false, vertical: true)` on the pane, or move the segmented control into the secondary so the content follows it). | no |
| P2 | Set row check control · `Workouts/Features/Shared/SetTable/SetRow.swift:186-193` | A row whose two fields are filled (checkable) draws the same `.quaternary` box and `.secondary` glyph as a row with empty fields (cannot be checked by rule). After typing 70 × 8 nothing on the row says "you can check this now" (`active-keyboard-closed-light.png` row 1 vs rows 2–6; `active-checked-closed-light.png`). | HIG buttons/toggles: enabled and disabled states must differ; design-review §5 "every action gives feedback". | *local*: glyph `.primary` (or accent) when the row is checkable, keep `.secondary` when it is not; no shape change. | no |
| P2 | History, closed, scrolled · `Workouts/Features/History/HistoryView.swift:45` | Once the large title collapses, no "History" remains: the sticky month header is the first thing on screen and the strip has no title either (`history-list-closed-light.png`, `history-list-scrolled-closed-light.png`). The pushed detail does keep an inline "Pull" at the top, and Exercises keeps its search field there, so the outer display can show an inline bar. | design-review §3.2 "the large title collapses on scroll" (into an inline one), HIG navigation bars. | *verify*: compare with Fitness on the Duo; if the system drops inline titles above a `List` with sticky headers, accept; else `toolbarTitleDisplayMode(.inlineLarge)` on History (and Workout). | no |
| P3 | Workout tab, open tall · `Workouts/Features/Workout/WorkoutView.swift:70,191` | After rotating to tall the title shows inline ("Workout", centred) while History in the same pose shows a large title; the grid's `ScrollView` seems to keep an offset across the pose change (`workout-open-tall.png` vs `history-open-tall.png`). | Consistency between tabs. | *verify*: scroll to top after the pose change; if it persists, reset the offset on size-class change. | no |
| P3 | Template preview rows · `Workouts/Features/Workout/TemplatePreview.swift:133-134` | Subtitle shows the raw key ("chest", "shoulders") where every other row shows the display label ("Chest") (`templatepreview-closed-light.png` vs `exercises-closed-light.png`). | Type & content: copy is the web's. | *local*: map through `LibraryCatalog` labels like `ExerciseRow`. | no |
| P3 | Exercise picker rows · `Workouts/Features/Shared/ExercisePicker/ExercisePickerView.swift:204` | The "about this exercise" peek is `questionmark.circle` here and `info.circle` in the template preview (`:150`) (`exercisepicker-closed-light.png`). | PLAN §3 names `info.circle`; one glyph per meaning. | *local*: `info.circle`. | no |
| P3 | Settings copy · `Workouts/Features/Settings/SettingsView.swift:81,245` | "Workouts Duo stops reading…", "Workouts Duo never writes to Health." while the display name is "Workouts" (`project.xcproj:85`) and the system prompt says "Workouts" (`settings-fitness-on-closed-light.png`, `root-active-closed-light.png`). | One product name. | *local*: "Workouts" (or rename the app — Eric). | yes |
| P3 | Workout detail at AX sizes · `Workouts/Features/History/WorkoutDetailView.swift` (ExerciseBlockView header) | "Best Set" caption drifts to a mid-card x under the trophy instead of stacking under the name (`workoutdetail-closed-ax.png`). | Type: AX layouts stack via `ViewThatFits`. | *local*: `ViewThatFits` on the block header (name + trophy / best set). | no |
| P3 | Finish summary header · `Workouts/Features/ActiveWorkout/FinishSummaryView.swift:79-82` | Stars fall over "Workout complete / Your 615th workout" for ~3 s (rows are protected, the header is not) (`finishsummary-closed-light.png`, `-dark`, `-ax`). Reduce Motion draws the static scatter correctly (`StarCelebration.swift:25`). | Legibility of the one line the screen exists for. | *local*: keep the header above the star layer (zIndex) or fade stars under text. | yes |
| P3 | Template cards, closed · `Workouts/Features/Workout/TemplateCard.swift:104-107` | "Last performed · 5 / days ago" wraps mid-phrase on 160 pt cards (`root-workout-closed-light.png`). | Polish. | *local*: "5 days ago" with the clock glyph the preview uses, or a non-breaking separator. | yes |
| P3 | First run · `Workouts/App/Notifications/RestNotifier.swift:127-139` | The notifications permission alert appears when the first rest starts, i.e. over the table right after the first check (`root-active-closed-light.png`). In context per HIG, but with no pre-explanation of what the alert will do. | HIG "ask in context, explain why". | none required; optional one-line footer in the first rest sheet. | yes |
| P3 | Update Template dialog · `Workouts/Features/ActiveWorkout/TemplateUpdateDialog.swift` | "Update Template and Values" is red (destructive role) (`update-template-dialog-closed-light.png`). It overwrites structure, so defensible, but red reads as "delete". The dialog's timing (after the summary dismisses, on the Workout tab) is good. | HIG destructive role. | taste. | yes |

Not filed (settled or system): the strip order with Finish at the bottom (system places `.confirmationAction` there; JC49/51);
the notifications alert covering the table (system); the gallery's cards lacking "Last performed" (gallery data, not code:
`gallery-workout-recheck-closed-light.png`); the four 200 pt columns on the open display (the grid is correct, the folders
have two templates — see taste); the thin rest arc reading "full" for most of a rest (JC1); hero watermark (content, see
taste); `.secondary` text contrast (JC62).

## Fix briefs (P1)

**A. Countdown survives the keyboard on the closed display** — `Workouts/Features/Shared/SetTable/SetKeyboardToolbar.swift`.
Split the first `ToolbarItemGroup(placement: .keyboard)`: the `TimelineView` countdown becomes its own group with
`.visibilityPriority(.high)` (same as Next/Done); Skip and +30 stay in a `.low` group; −/+/Previous keep the default. Order
within the bar stays countdown → Skip → +30 → − → + → Previous → Next → Done. Prove: closed pose,
`./dev run -- -sampleWorkouts 200 -startSampleWorkout -openWorkoutCover`, tap a weight cell; `rest.keyboard.countdown` must
be in the accessory, not behind ⋯. Add `LoggingUITests/keyboardKeepsCountdownWhenCompact()` asserting
`app.staticTexts["rest.keyboard.countdown"].exists` with a rest running and the keyboard up; proving command
`./dev ui-test LoggingUITests/keyboardKeepsCountdownWhenCompact()`. Also re-check that the ⋯ menu now holds Skip and +30 only.

**B. One set-numbering rule** — `Packages/WorkoutsKit/Sources/WorkoutsKit/Library/ExerciseHistory.swift:106-116`. Drop the
`number` counter; label with `SetInputFormat.setLabel(number: index + 1, kind: set.kind)` exactly as
`WorkoutDetail.swift:177`, and update the doc comment on `ExerciseHistorySet.label` (line 8). Fix the kit test expectations
(`ExerciseHistoryTests`) so a W, W, N, N session labels N as 3, 4. Proving command: `./dev kit ExerciseHistoryTests`. Then
`./dev shot … -- -preview ExerciseDetail` and tap History to see W, W, 3, 4 (`exercisedetail-history-closed-light.png` is the
before picture).

## State inventory (what was seen; missing rows are the findings above)

- **Empty**: Exercises search → `ContentUnavailableView.search` with the filter pill still applied (`exercises-empty-search-closed-light.png`); Exercises split with no selection → "Select an Exercise"; cover without a workout → "No workout in progress" (`activeworkoutcover-closed-light.png`); set cells → Previous value as prompt in `.secondary`.
- **Loading**: thumbnails and the hero cross-fade in (`exercisedetail-closed-light.png`); nothing else spins. The Fitness backfill runs oldest-first without a spinner in History; rows gain "· 310 kcal" as they land (`history-list-kcal-closed-light.png`).
- **Error**: Finish-failed alert with Retry (code, JC3); import result alert (JC35). Not provoked.
- **Success**: finish → summary cover with stars + `.success` haptic; Done → Workout tab → "Update Template?" (`finish-summary-real-closed-light.png`, `update-template-dialog-closed-light.png`); checking a set → green `okRow`, rest restarts, ring label "Rest timer, 2:29" (`active-checked-closed-light.png`).
- **Disabled**: empty set cannot be checked (hierarchy: `Mark set done, Not done`); past editor Save greyed until dirty (`pasteditor-closed-light.png`, `PastWorkoutEditor.swift:104`); Finish with nothing checked → "18 sets are not checked and will not be saved" popover (`finish-dialog-closed-light.png`).
- **Overflow**: 200 workouts list scrolls at 60 fps with month headers; 1,038-row Exercises list; long names truncate on cards and wrap in the picker (`exercisepicker-closed-light.png`); AX sizes stack rows and cards (`*-closed-ax.png`).
- **First run**: notifications alert at the first rest (above); Health access is the fixture here (no prompt); "Allow Live Activities" not exercised.
- **Poses**: closed portrait and landscape (strip trailing / leading), open wide and tall, half-open; a workout survives relaunch and the cover is restored (`workout-closed-landscape.png` is in fact the restored cover).

## Taste calls for Eric (preference, not defects)

1. **Open-wide Workout grid**: four ~200 pt columns; with two templates per folder the right half is empty (`workout-open-wide.png`). Fitness uses mixed-width cards when open. Keep the even grid, or raise the minimum card width on regular width so two larger cards fill each half?
2. **Rest arc** in the strip is a hairline circle that looks complete at 4:17/5:00 and at 2:29/2:30 (`active-resting-closed-light.png`). Per JC1 by design; confirm it reads as draining on the real panel.
3. **Stars over the title** on the finish summary (P3 above): keep the celebration on top of everything, or protect the header?
4. **"Workouts Duo" vs "Workouts"**: which is the product name? Two Settings strings say Duo, the app and the system prompt say Workouts.
5. **Update Template and Values** in red: destructive styling for an overwrite, or plain?
6. **Media watermark**: the source thumbnails/videos tile "SMART WORKOUT GYM LOG TRACKER" behind every figure, visible in light and dark heroes (`exercisedetail-closed-light.png`, `-dark`). Content, not code; acceptable or worth re-exporting?
7. **Pre-permission line** for rest notifications in the first rest sheet, or leave the system alert alone?
8. **"Last performed" wrap** on closed cards: "5 days ago" with a clock, or the full phrase on two lines?

## Tooling notes for the orchestrator

- `iPhone Duo 5` was contended: another checkout's `./dev check` reinstalled the app and relaunched it under a test runner mid-review (01:04:28–39), so the review moved to `iPhone Duo 4` (claimed only by a Nov 4 17:26 worktree). `./dev sims` showed Duo 5 as unlocked when this review started; the claim column only reflects `.build/dev-sim-udid`, not `DEV_SIM_UDID` overrides.
- The first cold-boot `./dev shot … -- -preview Workout` launched the real root (tab bar, gear, persisted sample data), not the gallery; every warm shot honoured `-preview`. Worth a look in `cmd_shot`'s cold-boot path.
- Xcode's device-interaction MCP connected and drove the closed display well; in open poses its screenshot is the dark outer panel and the hierarchy omits the strip items, so open-pose proofs stayed with `./dev fold` / `./dev orient` captures.
- Both simulators were left closed, portrait, light, `medium`. No SpringBoard crash reports were produced.
- Seen in the log, for the code reviewer: on relaunch with a live workout the app logs `Live Activity request failed … WorkoutsTests.LiveActivityControllerTests … Refused error 1` — a test type name inside the app process's error.

## Screenshots relied on

All under `/private/tmp/claude-501/-Users-ericribeiro-Projects-workouts/396cb7c1-8aec-4e77-a169-18e72f4177ca/scratchpad/review/`:

- Gallery, closed portrait, light / dark / AX: `workout-`, `history-`, `exercises-`, `settings-`, `exercisedetail-`, `workoutdetail-`, `templatepreview-`, `templateeditor-`, `settable-`, `finishsummary-`, `fitnesscard-`, `calendar-`, `exercisepicker-`, `pasteditor-`, `customexerciseform-` × `closed-light.png` / `closed-dark.png` / `closed-ax.png` (where taken); `activeworkoutcover-closed-light.png`, `exercisepane-closed-light.png`, `gallery-workout-recheck-closed-light.png`.
- Real root, closed: `root-workout-closed-light.png`, `root-history-closed-light.png`, `root-exercises-closed-light.png`, `root-active-closed-light.png`, `root-workout-duo4.png`, `history-dashboard-kcal-closed-light.png`, `history-list-closed-light.png`, `history-list-kcal-closed-light.png`, `history-list-scrolled-closed-light.png`, `workoutdetail-real-closed-light.png`, `workoutdetail-bottom-closed-light.png`, `workoutdetail-fitness-closed-light.png`, `workoutdetail-fitness-section-closed-light.png`.
- Flows, closed: `active-resting-closed-light.png`, `rest-sheet-closed-light.png`, `active-keyboard-closed-light.png`, `active-keyboard-more-closed-light.png`, `active-blockmenu-closed-light.png`, `active-checked-closed-light.png`, `finish-dialog-closed-light.png`, `finish-summary-real-closed-light.png`, `update-template-dialog-closed-light.png`, `workout-addmenu-closed-light.png`, `card-contextmenu-closed-light.png`, `settings-bottom-closed-light.png`, `settings-fitness-on-closed-light.png`, `exercises-bodypart-menu-closed-light.png`, `exercises-empty-search-closed-light.png`, `exercises-scrolled-closed-light.png`, `exercises-list-scrolled-closed-light.png`, `exercisedetail-history-closed-light.png`, `exercisedetail-charts-closed-light.png`, `exercisedetail-records-closed-light.png`.
- Open and half-open: `workout-open.png`, `workout-open-wide.png`, `workout-open-tall.png`, `history-open-wide.png`, `history-open-tall.png`, `exercises-open-wide.png`, `exercises-open-tall.png`, `templatepreview-open-wide.png`, `exercisedetail-open-wide.png`, `exercisedetail-open-tall.png`, `settings-open-wide.png`, `finishsummary-open-wide.png`, `active-open-wide.png`, `active-open-tall.png`, `active-half-open-bench.png`, `active-half-open-bench-mcp.png` (dark outer panel; hierarchy only), `active-refolded-closed.png`, `active-reopened-wide.png`.
- Closed landscape: `active-closed-landscape.png`, `workout-closed-landscape.png` and `history-closed-landscape.png` (both the restored cover), `exercisedetail-closed-landscape.png`, `gallery-workout-closed-landscape.png`, `gallery-history-closed-landscape.png`, `gallery-exercises-closed-landscape.png`.
