# Judgment calls (unsupervised runs)

Decisions the orchestrator made without asking, for Eric to review. Newest last. Each: what, why, how to revert.

## 2026-11-03 (overnight run)

1. **Rest ring in the strip is a drawn arc, no digits** (2.5 follow-up, Eric's "progress line" idea). The system only stacks
   symbol/`Image` labels in the trailing strip; the arc is `Image(size:renderer:)`. Countdown digits live in the rest sheet,
   keyboard group, Live Activity and the button's accessibility label. Revert: `RestRingItem.runningButton` back to the
   TimelineView ring (it then sits in the top bar). DECISIONS "Minimised workout" records it.
2. **Finish dialogs keep the system popover behaviour** (2.8): attached to Finish, iOS shows them as a popover without the
   cancel-role buttons (Keep Going / Cancel / Keep Logging); tapping outside dismisses. Native, so kept.
3. **"Finish failed" alert offers Retry** besides Dismiss (spec §4 asks for a way to retry).
4. **Finish summary PR value is pink, not Fitness yellow** (2.9): yellow text failed contrast on the light background; trophy
   icons stay yellow. Stat tints are system colours (orange, blue, green, cyan, pink).
5. **Exercise list best set = best set of the most recent session**, written "100 kg × 5" (4.1a), per the spec rather than an
   all-time heaviest set.
6. **History duration reads "1h 0min"** for an exact hour; spec only showed "1h 12min", "45min", "<1min" (5.1).
7. **Search scopes appear when search opens** (`activation: .onSearchPresentation`), since with the default the All · PRs
   control only appeared after typing (5.1).
8. **Tab bar minimises on scroll everywhere except the Workout tab** (`tabBarMinimizeBehavior` is a TabView modifier) (5.1).
9. **Design tools**: neither impeccable nor Design with Intent is installed; their native-transferable parts became the
   `design-review` skill and review gates 2.11 / 3.8 / 4.7 / 5.8 (DECISIONS "Design review").
10. **Placeholder Previous digits are content**: the 2.11 review will darken them to secondary text (≥ 4.5:1) rather than keep
    Apple's faint placeholder (Eric deferred).
11. **Design-review taste rows are decided by the orchestrator and logged here**, not batched as questions (Eric deferred).
12. **Empty set fields report "Empty" to accessibility** instead of the placeholder (the Previous value), so VoiceOver and UI
    tests can tell a filled field from an empty one (2.4).
13. **Picker Superset** adds the picks then groups them with the new `makeSuperset` (3.5 kit rules: members gathered at the
    first member's position, groups < 2 dissolve, renumbered 1, 2, 3).
14. **Warm-up ramp with no bar** has no empty-bar step; a custom bar without a weight counts as no bar (3.5).
15. **"Discard workout?" anchors on the Finish item** (2.8): the confirmation lives with the Finish dialogs, so on regular width
    its popover points at Finish rather than the title menu. Rename errors get their own small alert.
16. **Weekly chart** (5.2): device time zone (not the web's server TZ), labels unpadded `11/2`, hidden under search and the PRs
    scope, card on `secondarySystemBackground` (the grouped colour was white on white). Goal stays in Settings only.
17. **UI tests clear the app's UserDefaults at launch** (`-uiTesting`), so settings tapped in one test never leak into another.
18. **Settings** (5.7a): one combined footer under unit + formula (a Section has one footer); "Download all videos" only persists
    until MediaStore gets a bulk-download hook; iCloud row reads "Not set up yet" (no entitlement, no CloudKit call).
19. **Resume control** (2.7): strip item = the rest arc while resting, else `figure.strengthtraining.traditional`; time in the
    accessibility label. It is appended after each screen's own items (Add, Settings, ring), so it is last in the strip;
    filed for the Phase 2 review (may need `visibilityPriority` so it never overflows). Relaunch restores the cover from a
    per-device `@AppStorage` flag (ignored under `-uiTesting`).
20. **Live Activity crash on reinstall** (dev): `WorkoutsLiveActivity` crashed twice in ExtensionFoundation from a bundle under
    containermanagerd `Dead/` — iOS relaunching the extension from the build a reinstall just replaced, while a test's
    activity was still up. UI tests now skip Live Activities unless `-liveActivity`, and `./dev` warns (not fails) on that
    exact path. Any other extension crash still stops work.
21. **4.1b landed inside a483d3a** with its UI tests unverified (a `git apply --3way` had staged it); fixed forward rather than
    rewriting pushed history. Filters use body parts in use (Other only if used); New Exercise opens a stub until 4.4.
22. **Regular-width logging** (2.10): one `ArrangementView` in both widths (compact = `.split` with no axes, so folding never
    swaps view branches); the pane follows the last focused/tapped block, else the first with an unchecked set, else the
    first block. Open-tall (portrait open) is unverified: `./dev orient` hung there. Draft/focus/scroll across a live fold
    is unverified (XCUITest cannot fold) — for the Phase 2 review.
23. **Mistake, fixed forward**: b20b73e (2.10) was committed with `LoggingUITests` red — my filter showed only the `check: ok`
    line. `check` does not run UI tests. From here on every feature commit is preceded by a full `./dev ui-test` read in full.
    A worker is fixing the red suites (ExerciseList from 4.1b, Logging) on main.
24. **Dashboard cards** (5.3): even column count from the grid's own width (1 closed, 2 open; adaptive gave 3 and the middle
    card straddled the fold); chevron only on Last Workout (the only card that opens something); Recent PRs = one row per
    exercise session with its first record (e1RM first); card heights not equalised (LazyVGrid can't).
25. **Phase 2 review accepted in full** (docs/reviews/phase-2.md). R-13 taste: ring keeps last place in the strip, in its own
    glass group via `ToolbarSpacer(.fixed)`. R-11 (Time Sensitive entitlement) goes to the TestFlight checklist; R-15/R-19 later.
26. **Save-failure rollback scope** (R-05): structural mutations (finish, discard, start, add/remove/replace/reorder, superset,
    warm-ups) roll the context back on a failed save; single-value edits (check, values, kind, rename, rest) keep the typed
    value in memory, since they delete nothing. After a successful finish save the engine always lets go of the workout.
27. **Set row colours** (R-02/R-09): checked-row tint is a new `okRow` asset (lighter than okFill so the solid okFill check
    still stands out), check glyph a dark `onOkFill` asset (white on okFill is ~2:1). Placeholder prompt is `Color.secondary`.
    A rest that already ended before the ring appeared (relaunch) does not buzz (R-01).
28. **Calendar** (5.4): a day with several workouts lists them under the grid (tap one); unmarked days are plain text (no dead
    buttons); Done sits in the confirmation slot like Settings; the push waits for the sheet to dismiss.
29. **Exercise detail** (4.2): segments About and Records only until 4.3 adds History/Charts; empty navigation title (the large
    in-content name would duplicate it); video stays off until `WorkoutsMediaBaseURL` is set in Info.plist (thumbnails cross-fade
    meanwhile; Reduce Motion stops it); finish-summary PR rows now push the exercise's Records.
30. **Workout detail** (5.5): Save as Template is one sheet (name prefilled, folder list, "No Folder", or a new "Templates"
    folder when none exist) instead of the web's two steps; it copies completed sets only. Set labels number by position among
    completed sets. Shared `Color.superset(_:)` palette for SetTable and the detail.
31. **Exercise History/Charts** (4.3): metric chips (scrolling row) not a segmented picker (five labels don't fit closed); the
    spec's range control (1M/3M default/6M/1Y/All) added; no duration chart metric (none in the kit/spec lists); history in the
    session's own unit, charts in the display unit (per spec).
32. **Past-workout editor** (5.6): duration is a whole-minute Stepper (not an end time); edits go to a kit value draft and
    Save applies them (Cancel drops it); with no check column, Save marks sets with values completed and drops empty sets and
    emptied exercises; the back button is hidden in favour of Cancel/Save.
