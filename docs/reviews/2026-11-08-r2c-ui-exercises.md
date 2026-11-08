# UI review round 2c, part B: Exercise screens (2026-11-08)

Read-only, method `.claude/skills/design-review`. Evidence: the existing captures in `.build/review-ui-r2b/` (closed portrait, light /
dark / accessibility-extra-large); no new screenshots, no simulator. Authority: HIG, `docs/DECISIONS.md`, JC109–JC112 (settled, not
re-filed). Round 2 / 2b findings (`docs/reviews/2026-11-08-r2-ui.md`) are not repeated. The custom-exercise form's axxl "Text clipped"
audit failure is being fixed by another worker and is not filed here.

Screens: ExerciseDetail (About, History, Charts, Records), its loading frame, ExerciseInfoSheet, Exercises list, the empty capture,
CustomExerciseForm (new and edit).

## Slop test

**Pass.** System bars in the trailing strip with symbol-only items, segmented `Picker`s, `searchable`, filter `Menu` pills, a system
`Form` sheet with Close / prominent checkmark, a medium-detent info sheet with the name and segments above the fold (R2-1 holds in light,
dark and axxl: `ExerciseInfoSheet-*.png`). Dark mode is designed, not inverted: the hero gets its own dark plate, cards separate by fill,
the sticky band has a dark variant.

## Findings

| P | Screen · file:line | What (evidence: png) | Rule | Fix (one worker task) | Taste? |
|---|---|---|---|---|---|
| P2 | Exercise detail, Charts · `Workouts/Features/Exercises/ExerciseChartsView.swift:77` | The metric chip row is a horizontal `ScrollView` inside the content's horizontal padding, so it is cut with a hard vertical edge at the card margin: "Total re" at default size, "Max weig" at axxl, where only 1.5 of 4+ chips show and nothing says the row scrolls. It reads as a layout bug, not as a scroller. (`.build/review-ui-r2b/ExerciseDetail-Charts-light.png`, `-dark.png`, `-axxl.png`) | design-review §3.2 (nothing clipped by a container edge); HIG Scroll views (content that scrolls should run to the edge) | *local defect*: let the scroller run to the screen edge and inset its content instead: drop the outer horizontal padding on `chips`, add `.contentMargins(.horizontal, Metrics.<content inset>, for: .scrollContent)` and `.scrollClipDisabled()` so the next chip visibly peeks past the margin. Proof: `./dev test SnapshotTests` (add or extend the Charts snapshot at default and accessibility-3) | no |
| P2 | Exercise detail, loading frame · `Workouts/Features/Exercises/ExerciseDetailView.swift:109-116` | `Loading-ExerciseDetail-{light,dark}.png` are pixel-identical in layout to the loaded About segment: About renders from the store synchronously, so the capture never shows the async `detail` state. The History, Charts and Records segments are the ones that wait on `loadExerciseDetail`, and their loading frame has no evidence (no capture, and no axxl loading capture at all). The States inventory cannot be closed for this screen. | design-review §4 (Loading is a named state that must be rendered and evidenced); DECISIONS → Pushed-screen chrome | *evidence/test*: add a gallery entry or launch arg that opens the detail on the History segment under `-slowLoads` (e.g. `-preview ExerciseDetail-History -slowLoads 30000`), capture it light/dark, and add a loading-frame snapshot for one async segment beside the existing WorkoutDetail one. Proof: `./dev test SnapshotTests` | no |
| P3 | Exercise detail, Charts · `Workouts/Features/Exercises/ExerciseChartsView.swift:161-169` | The highlighted (latest) point's 110-size symbol and its dashed `RuleMark` sit on top of the trailing y-axis labels: the large dot overlaps the leading edge of "240" and the rule runs through the label column. (`.build/review-ui-r2b/ExerciseDetail-Charts-light.png`) | §3.2 legibility; Swift Charts plot-area insets | *local defect*: give the plot a trailing inset (`.chartPlotStyle { $0.padding(.trailing, …) }` or `.chartXScale(range: .plotDimension(padding: …))`) so the last point and its rule end before the axis labels. Proof: `./dev test SnapshotTests` | no |
| P3 | Exercise detail, Charts · `Workouts/Features/Exercises/ExerciseChartsView.swift:166-168` | The selection rule is `.secondary.opacity(0.6)`, meaning by raw opacity (design-review §3.3). Legible in both appearances, but it is the one hand-tuned alpha on the screen. | §3.3 | *local defect*: use `.tertiary` (hierarchical style) instead of `secondary.opacity(0.6)`. Proof: `./dev test SnapshotTests` | no |

No P0 or P1. Contrast measured by eye against the system palette: sticky band text and the `Edit Sticky Note` link pass in dark (white
and system blue on the dark amber fill, `ExerciseDetail-dark.png`); warm-up `W` (amber) and failure `F` (red) set-kind letters read in
both appearances (`ExerciseDetail-History-{light,dark}.png`); selected metric chip in dark (blue on navy tint) is the system bordered
style and readable.

## Taste calls for Eric (from images)

1. **Accent blue on non-interactive values.** Record values (`ExerciseRecordsView.swift:125`), the Reps column (`:189`), the chart
   headline value (`ExerciseChartsView.swift:134`) and the "3 PRs" trophy label (`ExerciseHistoryView.swift:88`) all use `.tint`, the
   same blue as `Edit Sticky Note` and the segmented/chip selection, so a fluent user may expect them to be tappable. Health and
   Fitness colour their values too, so this is a style choice: keep the tint as the "your numbers" colour, or move values to `.primary`
   and keep the trophy in a dedicated PR colour. Compare `.build/review-ui-r2b/ExerciseDetail-Records-light.png` with
   `.build/review-ui-r2b/ExerciseDetail-Records-dark.png`.
2. **Hero size at accessibility sizes in the pushed detail.** At axxl the info sheet shrinks its hero (R2-1), but the pushed detail
   keeps the full-height hero and wraps the name to two lines, so the first screen at axxl is image + name + segments with the
   segment content starting near the bottom. Cap it like the sheet, or keep the full illustration? Compare
   `.build/review-ui-r2b/ExerciseDetail-light.png` with `.build/review-ui-r2b/ExerciseDetail-axxl.png` (and `ExerciseInfoSheet-axxl.png`).

## Observations, not filed

- `Empty-exercises-{light,dark}.png` does not show an empty state: the seeded library fills the list. The empty states in source are
  `ContentUnavailableView.search(text:)` (`ExercisesView.swift:103`) and the split-view placeholder (`:141`), both system views; a
  no-hit search capture (`-preview Exercises` with a query) would evidence them. This capture comes from the real root and shows the
  Settings gear in the Exercises tab's strip group (the gallery `Exercises-*.png` has only + and archive); DECISIONS → Navigation
  places Settings on the Workout tab. Worth a one-line check of whether a later JC moved it to every tab root.
- Segmented controls do not grow at axxl (system cap); the chips and content do. System behaviour, not a finding.
- CustomExerciseForm(Edit) at axxl reflows Body part / Weight type onto two lines with the value under the label; nothing else
  clipped in the visible part beyond what the other worker is fixing.
- The Records "Heaviest weight 198.5 lb" is the 90 kg set converted for display; PR lines stay in the display unit per r2b, so not
  re-filed.

## Scores (Exercise screens)

| Dimension | Score | Key finding |
|---|---|---|
| Colour and appearance | 3 | Dark designed and legible throughout (hero plate, sticky band, set-kind letters, chart); only a raw-opacity rule mark, plus the accent-on-values taste call |
| States and resilience | 2 | Loading frame for the async segments (History/Charts/Records) has no evidence; the empty-search state was not captured |

Slop verdict: **pass**.
