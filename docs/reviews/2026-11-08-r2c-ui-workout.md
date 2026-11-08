# UI review round 2c, part A: workout and logging screens (2026-11-08) — PARTIAL

Read-only, method `.claude/skills/design-review`, closed portrait. Evidence: the existing captures in `.build/review-ui-r2b/`
(no new screenshots, no simulator). Authority: HIG, `docs/DECISIONS.md`, JC109–JC112 (settled, not re-filed). Round 2's
findings (`docs/reviews/2026-11-08-r2-ui.md`) are not repeated; its P2s are fixed and the captures confirm the unchecked
check now reads `.secondary` on grey.

## Evidence status (read first)

**Viewed (light, dark, axxl):** `ActiveWorkoutCover-*`, `Cover-root-*`, `SetTable-*`, `FinishSummary-*`, `TemplateEditor-*`.
**Not reached (tool budget):** `TemplatePreview-*`, `Loading-TemplatePreview-light`, `Root-*`, `Workout-*`, `Empty-workout-*`,
`ExercisePicker-*`, `ExercisePickerMulti-*`. A part-A follow-up should read those and score States.

**Gap in the evidence:** no capture shows a *checked* set, so the checked-row green was judged from the asset catalog only
(contrast below), not from pixels. Add a gallery state with one checked row per block to the next shot batch.

## Slop test

**Pass** for the screens viewed: system bars in the trailing strip with symbol-only items, Minimise / Finish as the Close and
prominent slots, Finish summary as a grouped `List` with `LabeledContent` rows, no hand-placed glass, no bottom chrome.

## Findings

| P | Screen · file:line | What (evidence: png) | Rule | Fix (one worker task) | Taste? |
|---|---|---|---|---|---|
| P2 | Template editor (any set table without Previous) at accessibility sizes · `Workouts/Features/Shared/SetTable/SetRow.swift:87-99` | `twoLine` always puts the kind label on its own first line. With no Previous column (template mode) that line holds only "W" / "3", so every set costs an extra ~60 pt row of empty space and the label floats far from its cells. (`.build/review-ui-r2b/TemplateEditor-axxl.png`; compare the default-size `.build/review-ui-r2b/TemplateEditor-light.png`) | design-review §3.2 (tight groups), §3.4 (reflow, not padding, at AX) | *local defect*: in `twoLine`, when `!model.showsPrevious`, render one `HStack` of `kindButton` + `fields` + check (the first line exists only to carry Previous). Proof: `./dev test SnapshotTests` (add an AX3 template-mode row to the SetRow snapshot if none exists) | no |
| P2 | Set table at accessibility sizes, every mode · `Workouts/Features/Shared/SetTable/SetTable.swift:104` with `SetRow.swift:87-99` | The column header (Set · Previous · kg · Reps) is dropped at AX sizes, and the stacked cells carry no label, so a row is two bare numbers ("35", "8"). The unit is per row (kg or lb), and on a row with no Previous (template editor, a new exercise) nothing on screen says which unit or which cell is reps. (`.build/review-ui-r2b/TemplateEditor-axxl.png`, `.build/review-ui-r2b/ActiveWorkoutCover-axxl.png`) | design-review §5 (nothing to remember; ten-second read), HIG Dynamic Type (content keeps its meaning when it reflows) | *local defect*: at accessibility sizes give each stacked cell a caption: the unit (`row.unit.rawValue`) and "Reps"/"Time", e.g. a `.caption` `Text` above each cell in `twoLine`, hidden from VoiceOver (the cells already have labels and hints). Proof: `./dev test SnapshotTests` | no |
| P3 | Finish summary · `Workouts/Features/ActiveWorkout/FinishSummaryView.swift:148` | The PR trophy is `.yellow` on a white row in light (about 1.5:1); the glyph is the only thing that marks the row as a record before reading it. Fine in dark. (`.build/review-ui-r2b/FinishSummary-light.png` vs `.build/review-ui-r2b/FinishSummary-dark.png`) | design-review §3.3 (meaning by semantic colour, both appearances) | *missing token*: use an asset colour with a darker light variant (e.g. reuse `Warmup`'s light `#8A5C00`-range gold via a new `Record` colour set) for the trophy. Proof: `./dev test SnapshotTests` | maybe (the gold) |

No P0 or P1.

### Checked without a finding

- **Dark set table:** cells on `.quaternary` read as dark grey tiles, placeholders at `primary.opacity(0.7)` stay legible,
  warm-up "W" `#FFD60A` on black 14.9:1. (`SetTable-dark.png`, `ActiveWorkoutCover-dark.png`)
- **Sticky band in dark:** `#4A370E` with white footnote text, 11.4:1; it separates from black by fill (1.8:1, no rim), as
  cards should. 44 pt minimum height holds (JC112). (`ActiveWorkoutCover-dark.png`, `TemplateEditor-dark.png`)
- **Checked-set green (from the asset catalog):** `OnOkFill` on `OkFill` 7.7:1 dark / 7.0:1 light; white on `OkRow` dark
  `#173D24` 12.1:1; `OkFill` stands out of `OkRow` at 6.0:1 in dark (1.8:1 in light, where the glyph carries it).
- **Finish summary stat colours in dark:** all ≥ 4.6:1 on the `#1C1C1E` row (PRs 4.8, Volume 4.7); in light they are
  large bold text only, as round 2b noted. At axxl the `LabeledContent` rows stack label over value cleanly.
- **Rest running (`Cover-root-*`):** the strip grows Skip / +30 under the ring as decided; nothing clips in dark or axxl.

## Scores

| Dimension | Score | Key finding |
|---|---|---|
| Colour and appearance | 4 (screens viewed; checked row from source only) | Dark is designed, every measured pair passes; only the light-mode trophy is weak (P3) |
| States and resilience | not scored | Empty-workout, Loading-TemplatePreview, picker captures not reached this pass |

Slop verdict: **pass**.

## Taste calls for Eric (from images)

1. **Exercise name in the active workout at large text sizes: cut at two lines, or wrap in full?** In the logging screen the
   name stops at two lines with an ellipsis ("Barbell / Bench Pr…") because the chevron and the ⋯ button keep their own
   column; the same name wraps in full where there is no chevron. Compare `.build/review-ui-r2b/ActiveWorkoutCover-axxl.png`
   with `.build/review-ui-r2b/SetTable-axxl.png`. If "wrap in full": `Workouts/Features/Shared/ExerciseNameStyle.swift:14`
   drops the AX line limit for the active mode (or `SetTable.swift:146-158` puts the chevron inline with the text) — one
   worker task.

## Remaining for the follow-up pass

View `TemplatePreview-{light,dark,axxl}`, `Loading-TemplatePreview-light`, `Root-*`, `Workout-*`, `Empty-workout-*`,
`ExercisePicker-*`, `ExercisePickerMulti-*`; score States; capture a checked set in light and dark.
