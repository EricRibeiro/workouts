# Review round 2c, part C: History and Settings (2026-11-08), PARTIAL

Read-only UI review following `.claude/skills/design-review`. Evidence: `.build/review-ui-r2b/` (git-ignored). No new
captures were taken and no simulator was used. Authority: HIG, then `docs/DECISIONS.md`, then `docs/judgment-calls.md`. JC109–JC112
are settled and are not re-filed. Findings already in `docs/reviews/2026-11-08-r2-ui.md` are not repeated. That includes its
P2s, now fixed: set units in the detail (`f2580b7`), card spacing and the duration field.

**Capture timing.** The `WorkoutDetail-*` PNGs (21:42–21:47) predate `f2580b7` (21:56). They still show converted per-set lines
("154.5 lb × 8"). That P2 is fixed in source and is not re-filed.

**Scope actually reviewed.** History (light, dark, axxl), Empty-history (light, dark), Loading-History-light, WorkoutDetail
(light, dark, axxl), Loading-WorkoutDetail (light, dark) and PastEditor (light, dark, axxl).
**Not reviewed** (the pass stopped at its tool budget): `Calendar-{light,dark,axxl}.png`, `Settings-{light,dark,axxl}.png` and
the Settings source (`Workouts/Features/Settings/`). Round 2b viewed `Calendar-light.png` and found nothing. A follow-up pass
should cover Calendar dark/axxl and all of Settings.

## Slop test

**Pass.** The screens use system bars with symbol-only items in the strip, a native `ContentUnavailableView` for empty history,
`searchable` with scopes, a pushed detail whose title and toolbar are final in the loading frame, and a cover editor with
Close and a prominent Save. No glass is placed by hand.

## Findings

| P | Screen · file:line | What (evidence: png) | Rule | Fix (one worker task) | Taste? |
|---|---|---|---|---|---|
| P2 | History dashboard, weekly chart · `Workouts/Features/History/WeeklyGoalChart.swift:74` | "Met goal" and "below goal" bars differ only by `Color.accentColor.opacity(0.75)`. In dark, 0.75 × `#0A84FF` over the `#1C1C1E` card comes to about `#0E6AC7`. Against the full accent that is roughly **1.5:1** between the two states, so the shades barely separate. In light the below-goal bars read as a washed-out accent rather than a designed state. Value labels and the goal line carry the same information, so nothing is lost; the only problem is the colour. (`.build/review-ui-r2b/History-dark.png` vs `.build/review-ui-r2b/History-light.png`) | design-review §3.3 (meaning by semantic asset colours only, never raw opacity; dark designed, not inverted) | *missing token*: add one asset colour for the below-goal bar (for example `ChartBelowGoal`, with light and dark values chosen for ≥ 3:1 against the card fill and visibly distinct from `AccentColor`), expose it in `Workouts/Design/Colors.swift`, and use it at line 74. Proof: `./dev test SnapshotTests`, then `./dev shot` of `-preview History` in dark. | Possibly (the exact hue) |
| P2 | History dashboard, loading frame · `Workouts/Features/History/HistoryView.swift:34-35,102-116` (cards: `DashboardCards.swift:118-125,174-177`) | The chart reads `finished` from `@Query` synchronously, but `entries` and `recentPRs` start empty until `refreshSummary()` returns. In the first frame the dashboard therefore contradicts itself: the chart shows 2 workouts for the week of 11/2, while This Week says **"0 / 3"** and Recent PRs says **"No records yet"**. No month sections are shown yet. The frame presents an empty result as fact; it does not render the loading state. (`.build/review-ui-r2b/Loading-History-light.png` vs `.build/review-ui-r2b/History-light.png`) | design-review §4 (Loading is a named state that is rendered); DECISIONS → Pushed-screen chrome (the same principle: never show a state the data does not support) | *local defect*: add `@State private var hasLoadedSummary = false`, set it in `refreshSummary()` after the first summary arrives, and until then render the `DashboardSection` (and `DashboardColumns`) with `.redacted(reason: .placeholder)` and without the "No records yet" line. Proof: `./dev test SnapshotTests` (add or extend a loading-frame snapshot), plus `./dev shot` of `-preview History -slowLoads 30000`. | no |
| P3 | History chart at axxl · `Workouts/Features/History/WeeklyGoalChart.swift:95-99` | At accessibility sizes, greedy collision resolution keeps every other label, but "10/12" and "10/26" still almost touch (about 7 pt apart) and "9/14" runs past the card's leading inset. (`.build/review-ui-r2b/History-axxl.png`) | design-review §3.4 (real copy fits at accessibility sizes) | *local defect*: at `typeSize.isAccessibilitySize`, pass explicit `AxisMarks(values:)` with every second week, or every third when the count exceeds 6, and anchor the first label `.leading`. Proof: `./dev test SnapshotTests`. | no |

No P0 or P1. Seen in passing, and not filed:

- The Finish summary's Fitness stat colours (`StatDuration`, `StatSets`, `StatPRs`, light 3.65–4.02:1) are used only in
  `FinishSummaryView.swift:126-132`, at `.title2.bold()`. That is large text, so they pass AA there. Their dark values
  (`#FF9F0A`, `#30D158`, `#FF375F`) measure ≥ 4.8:1 on `#1C1C1E`. History and Settings do not use them. Keep them off body
  text.
- In the detail, the records lines ("Est. 1RM: 450 lb", `.secondary` on the card fill) and the "Best Set" caption are the
  `.secondary`-on-grouped contrast question JC82 left open for Eric. Not re-filed.
- The warm-up "W" and failure "F" set-kind colours adapt properly in dark: brown to yellow, red to salmon
  (`WorkoutDetail-dark.png`, `PastEditor-dark.png`).
- The detail's loading frame already has its final chrome: title "Pull", Edit, Duplicate and Delete in the strip, and the
  delayed spinner (`Loading-WorkoutDetail-{light,dark}.png`, `WorkoutDetailView.swift:68-93`). This matches DECISIONS →
  Pushed-screen chrome.
- The gallery's History preview has no Settings gear because `AppNavigation` is absent there (`SettingsControl.swift:19`).
  This is a preview artefact; the real root shows the gear (`Empty-history-light.png`).

## Scores

| Dimension | Score | Key finding |
|---|---|---|
| Colour and appearance | 3 | Below-goal bars use raw accent opacity, about 1.5:1 apart in dark. Otherwise dark is designed: set-kind colours, cards separated by fill, one tint |
| States and resilience | 3 | Empty (native `ContentUnavailableView`), no-search-hit, "No PRs Yet" and the detail loader are all right. The History loading frame shows "0 / 3" and "No records yet" as fact |

Other dimensions are not rescored here (see r2). Slop verdict: **pass**.

## Taste calls for Eric (PNG pairs)

1. **Duration copy "40min" vs "40 min".** The same workout reads "40min" in the detail header and "1h 16min" on the History
   This Week card (web copy). One tap away, the past editor shows "40 min" as a field plus a unit label, which is the system's
   spacing. Pair: `.build/review-ui-r2b/WorkoutDetail-light.png` (header "40min") vs `.build/review-ui-r2b/PastEditor-light.png`
   ("40 min"). Also `.build/review-ui-r2b/History-light.png` ("1h 16min · 36,887 lb"). Option: keep the web copy, or switch
   to `Duration.formatted(.units(width: .abbreviated))` ("40 min", "1 hr, 16 min").
2. **Template preview sheet: glass vs opaque (JC82).** This is outside History and Settings, so it was not re-viewed here. It
   is still open from r2. Pair: `.build/review-ui-r2b/TemplatePreview-light.png` vs
   `.build/review-ui-r2b/TemplatePreview-dark.png`. Option: keep the system glass sheet, or set an opaque
   `presentationBackground`.
3. **Below-goal bar hue** (it goes with the P2 above). Pair: `.build/review-ui-r2b/History-light.png` vs
   `.build/review-ui-r2b/History-dark.png`. The options are a neutral fill (Fitness-style grey bars, with accent only for
   weeks that met the goal) or a distinct lighter accent token.

## Remaining for a follow-up pass

- View `Calendar-dark.png` and `Calendar-axxl.png`, and `Settings-{light,dark,axxl}.png`.
- Read `Workouts/Features/Settings/SettingsView.swift` (385 lines) and `CalendarSheet.swift` for anything those PNGs flag.
- `PastEditor-axxl.png` shows a large empty gap between the block name and its first set, with the column headers apparently
  dropped, and the block's `ellipsis.circle` sits inset from the set cells' trailing edge. The source (`Features/Shared/SetTable`)
  was not read, so this is not filed. Confirm it against `SetTable.swift` before filing it as a P3.
