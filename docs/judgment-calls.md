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
18. **Settings** (5.7a): one combined footer under unit + formula (a Section has one footer); "Download all videos" now prefetches every library video for the
    current colour scheme over Wi-Fi (`BulkVideoDownload`, progress row; keeps going after the sheet closes); iCloud row reads "Not set up yet" (no entitlement, no CloudKit call).
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
    in-content name would duplicate it); video comes from CloudKit's public database (JC54; `CloudKitMediaSource`, off under `-uiTesting`; thumbnails cross-fade
    while it loads or when there is no record; Reduce Motion stops it); finish-summary PR rows now push the exercise's Records.
30. **Workout detail** (5.5): Save as Template is one sheet (name prefilled, folder list, "No Folder", or a new "Templates"
    folder when none exist) instead of the web's two steps; it copies completed sets only. Set labels number by position among
    completed sets. Shared `Color.superset(_:)` palette for SetTable and the detail.
31. **Exercise History/Charts** (4.3): metric chips (scrolling row) not a segmented picker (five labels don't fit closed); the
    spec's range control (1M/3M default/6M/1Y/All) added; no duration chart metric (none in the kit/spec lists); history in the
    session's own unit, charts in the display unit (per spec).
32. **Past-workout editor** (5.6): duration is a whole-minute Stepper (not an end time); edits go to a kit value draft and
    Save applies them (Cancel drops it); with no check column, Save marks sets with values completed and drops empty sets and
    emptied exercises; the back button is hidden in favour of Cancel/Save.
33. **Folders** (3.1): an "Unfiled" section exists (the model's folder is optional and Save as Template offers No Folder),
    though the web spec never orphans templates; deleting a folder offers move-to-Unfiled or delete-with-templates. Folder
    headers are a `Menu` with a primaryAction (tap = collapse, long press = Rename/Move/Delete) because `.contextMenu` on a
    Section header never opened on the Duo simulator. Regular width hides headers (sizeClass proxy for "sidebar visible").
34. **Custom exercises** (4.4): body part optional (spec says required; a name-only save must work); equipment as tick rows;
    no un-archive yet; saving from New Exercise doesn't open the new exercise.
35. **Import/Export** (5.7b): Export via `ShareLink` with a lazily written `workouts-export-YYYY-MM-DD.json`; Import applies on
    the main context (the models are MainActor-bound) with file read/decode off-main — a very large import can briefly block;
    a dedicated result alert (decode and version errors read plainly).
36. **Template cards** (3.2a): 160 pt minimum so the closed Duo shows two columns like Fitness; "Last performed" from the
    newest finished workout linked to the template, else same name; long exercise names truncate on narrow cards.
37. **Phase 5 review accepted** (docs/reviews/phase-5.md). Taste rows decided per the reviewer: duration gets a number field +
    stepper (reverses JC32), "workouts this week", `doc.on.doc` for Save as Template, plainer iCloud copy (reverses JC18's
    copy), `.headline` row titles everywhere, card heights equalised (reverses JC24). R5-06/R5-14 tokens deferred to a sweep.
38. **Natural-language search** (4.6): runs only when plain search finds nothing and the model is available; 400 ms debounce;
    a fresh prewarmed session per parse (no transcript leakage); body-part/category pills still apply on top of parsed
    results. Verified with the real model on the simulator ("rear delts with dumbbells" → shoulder dumbbell exercises).
39. **Template preview and dialogs** (3.3): preview has Close only (Edit comes with 3.4); "Workout in progress" and "Update
    Template?" are confirmationDialogs (popover form drops the cancel-role button; tapping outside = keep). Structure = exercise
    order, set count, kinds, superset grouping; values = weight/reps/duration/distance. DEBUG `-seedSampleData` for UI tests.
40. **Template editor** (3.4): edits go to a kit `TemplateDraft`; Save writes it in one go, Cancel drops it (same model as the
    past-workout editor, JC32), so the back button is hidden. Save stays enabled with no changes; the title menu has Rename
    only until 3.6 adds block actions. Edit lives in the template preview's toolbar (`pencil`).
41. **Sticky note** (4.5): edited in the exercise detail (and so in the logging/editor pane, which is now the embedded detail);
    shown read-only as a yellow band under the exercise name in every set table, so on the open Duo it appears twice (table
    and pane) — kept, each surface stands alone when the other is folded away. Notes trim and cap at 2000 characters; blank =
    removed. The 3.6 header menu will reuse `StickyNoteEditor`. A SetTable UI test now waits for the new row's id instead of
    a row count (the band shifts the lazy layout).
42. **Template block ops** (3.6 kit): Replace in the template editor takes the new exercise's unit/bar/rest defaults (the
    logging engine keeps the old block's), since a template has no performed sets tied to the old settings. Warm-ups ramp
    from the first working set's weight, as in logging. Removing a block renumbers supersets 1, 2, 3 (the engine only
    dissolves); rest changes one block only.
43. **Simulator pool** (dev): `./dev sims` cloned the Duo four times (pool of 5, Eric: "we have tons of ram"); each checkout sticks to one simulator (claim file, 24 h
    expiry), each simulator has its own lock (the original keeps the old path), the crash guard stays global. `./dev run`
    no longer opens Simulator.app (headless boot; three windows would pile up on your Mac); restore `open -a Simulator` in
    `cmd_run` if you want to watch. A cold boot waits 15 s before `shot` captures.
44. **Template card actions** (3.2b): context menu only (Edit, Duplicate, Move ▸ folders + No Folder, Delete); no swipes (a
    grid isn't a List) and no drag reorder yet. Delete copy from the spec ("Delete <name>?" … "Workouts you did from it stay
    in your history."); a moved card lands last in its folder; a copy of a copy is "X copy copy". New Template sits in the
    + menu and opens in the first folder (or unfiled).
45. **Real sidebar on the open Duo** (3.7): it never appeared before — `.defaultAdaptableTabBarPlacement` is iPadOS-only;
    iPhone needs `.defaultTabBarPlacement(.sidebar)` (found during 3.7, so the "open-wide sidebar" Phase 2 assumed was a
    strip until now). `.sidebarOnly` template tabs still leak into the 27.2 bar, so they're built only at regular width
    (closed = compact = no sidebar). Grid folder headers now always show (open-tall is regular with the sidebar collapsed).
46. **Phase 4 review accepted** (docs/reviews/phase-4.md). Taste rows: R4-14 yes (row subtitle one line below AX sizes);
    R4-20 no (list stays flat — search, pills and the natural-language fallback carry a 1,038-row list; no letter sections).
47. **Phase 4 fixes** (R4-*): custom exercise bar defaults by weight type (barbell → Olympic, else none) and follows a
    weight-type change until you pick one; the hero is capped at 35 % of the container height (measured with
    `containerRelativeFrame` + `onGeometryChange`, since that modifier only sets exact sizes); History/Records rows open
    the workout in History except inside the logging pane (it would switch tabs behind the cover); the sticky note has a
    `stickyNote` asset (#FFF1B0 / #4A370E). Unverified until a device: the `.warning` haptics on Archive/Delete/Remove fire
    as their sheet dismisses and may be cut off — move the trigger to the presenting view if you don't feel them.
48. **TestFlight signing** (dev testflight): the archive is built unsigned (`CODE_SIGNING_ALLOWED=NO`) and the export applies
    cloud-managed distribution signing, because automatic signing archives with a development profile and Apple won't make
    one for a team with no registered devices (you don't want to pair the Duo). Needs an **Admin** API key (App Manager
    can't use cloud-managed certificates). Caveat for later: entitlements (iCloud, Time Sensitive) must then come from the
    export's profile — re-check when 7.x adds them.
49. **Finish/Done fold into "More" on the closed Duo** (found by the FinishUITests fix): with the number pad up and a rest
    running, the trailing strip is too short, so the system overflows Finish and the keyboard accessory's Done into a More
    menu. Tests now dismiss via the accessory; the UX itself goes to the Phase 3 review (visibilityPriority / fewer items).
50. **Phase 3 review accepted** (docs/reviews/phase-3.md). Taste rows: R3-04 the reviewer's six superset hues; R3-09 rest
    lives only in "Update Rest Timer" (dropped from Preferences); R3-15 the block note becomes a multi-line sheet; R3-16 a
    card hides a lone superset bar whose partner is in "+ N more". R3-01 changes behaviour: rest "Off" is now really off
    (0) and a new "Default (1:30)" row follows Settings (nil).
51. **R3-02 partly fixed, rest accepted**: `visibilityPriority` keeps the keyboard's Next and Done in the accessory (the
    in-gym blocker). With the pad up and a rest running the closed strip only fits Minimise + More, so Finish still folds
    into More until the pad is dismissed — acceptable (you finish after typing). Moving Minimise into the title menu would
    free the slot; not done.
52. **Eric's call (2026-11-04): no app sidebar.** After trying build 202611041648 he found Exercises clunky (the app sidebar
    plus the Exercises split view's own list column = the list hidden behind a toggle). Decided: tabs stay in the trailing
    strip in every pose (`.defaultTabBarPlacement(.tabBar)` or no placement override), the 3.7 sidebar template sections go
    away (templates live on the Workout grid), and Exercises on regular width is a permanent two-pane list + detail. Settings
    moves from the sidebar bottom bar to the toolbar everywhere.
53. **Half-open bench mode (6.1)**: SwiftUI's `.split` style has no placement control (UIKit's `setViewProperties(forPlacement:)`
    has no SwiftUI twin), and the system stacks the primary on the upper half, so `ActiveWorkoutCover` uses
    `BenchArrangementStyle` (`ArrangementViewStyle`, documented). Outside bench mode it renders `ArrangementView(configuration)`
    with `.split.axes(...)` unchanged; with an active `.division` region wider than tall (read via `reservedRegions`) it lays the
    configuration's `secondary` (pane, `RestCountdownHeader` while a rest runs) above the division and `primary` (table) below.
    Both branches use the style's placeholders, so the content stays hosted by the `ArrangementView`. Draft/focus/scroll across
    a live fold into bench mode is unverified (the sim fold is not scriptable from XCUITest).
54. **Eric's call (2026-11-04): exercise videos in CloudKit's public database** (single-user app, so the licensing reason
    for keeping them off Apple no longer applies). Plan in docs/port/media.md; needs 7.1's container first. SwiftData stays
    local (`cloudKitDatabase: .none`) until 7.2 even once the iCloud entitlement exists.
55. **TestFlight signing, final** (supersedes JC48's unsigned archive): the archive is development-signed through the Xcode
    account on this Mac (your Apple ID + the registered Duo; you approved the keychain prompt once), which keeps the
    iCloud and Time Sensitive entitlements; the export/upload still uses the Admin API key and cloud-managed distribution
    signing. The API key alone is refused for development provisioning ("Authentication failed"). If a future run hangs at
    the archive, a keychain prompt is waiting on the server's screen.
56. **Video upload is a local command, not part of the build**: `./dev media-upload --env development|production` pushes the
    1,029 web-app videos (light + dark) into the public `ExerciseMedia` records through CloudKit Web Services with a
    server-to-server key (one key per environment: 1Password item "Apple Cloud Kit for Workouts Duo", sections
    `development` and `production`). Same trapped-temp-file handling as the ASC key; it skips records that already exist
    and stops at the first 401/403. Both environments were uploaded 2026-11-04 (Development 1,029, Production 1,029).
57. **Thumbnail cross-fade fades both frames** (Eric saw two poses overlapped): the bundled thumbnails are transparent PNGs,
    so the web's "end frame over an opaque start frame" left the start pose showing through. The start frame now fades out
    as the end frame fades in (opacities sum to 1), same timing as before.
58. **Book-pose fold rule for single-column screens (6.2)**: Apple ships no API that makes a ScrollView/List/Form avoid the
    division (SwiftUICore 27.2 has only `reservedRegions`, `ArrangementView`, `DeviceHinge`); sheets and split views move on
    their own. So: History's regular-width dashboard becomes two columns with the gutter on the division; Settings relies on
    the sheet's own fold handling (`presentationSizing`/`presentationPlacement` only if the real sheet still crosses);
    the pushed exercise detail gets an `ArrangementView` on regular width. Laptop pose (horizontal fold) is accepted for
    scrolling content (rows scroll through the fold); editors and the cover keep the table below it (bench style).
59. **One layout tree for the logging screen and both editors** (`BenchLayout`, replaces nesting the system `.split`):
    folding book → laptop rebuilt the set table (value kept, focus and scroll lost). The custom `Layout` reproduces the
    system split in every pose (measured pixel-identical) and adds bench mode; the editors now use it too, so the table is
    below the fold in laptop. While the keyboard is up in laptop the system removes the division from the area above the
    keyboard, so the screen splits side by side there and returns to bench when the keyboard goes; accepted as system
    behaviour rather than forcing bench under the keyboard. The rest header shows only in the logging screen.
60. **Small 6.2 fixes**: the exercise list column has a 320 pt minimum (no max, so the split still sizes to the fold);
    the exercise video uses an `AVPlayerViewController` wrapper with a clear backdrop and aspect-fill (all 2,058 videos are
    exactly 1920x1080, and `VideoPlayer`'s black backdrop showed as a 1 px line at fractional sizes); "Weight type" in the
    custom exercise form is a navigation-link picker at every size (a menu value is one line and truncated at AX sizes);
    the filter pills are one shared `FilterPillRow` that stacks at AX sizes; the gallery's exercise detail is pushed like the
    real app (a root detail with no bar items gets no strip, so the clock vanished there only).
61. **Template preview's info button uses an item destination** (Eric: did nothing on the open Duo): at regular width the
    preview is itself pushed by `navigationDestination(item:)`, and a value `NavigationLink` inside it never activates
    (hoisting the value destination to the stack root did not help either). The button now sets `@State` consumed by
    `.navigationDestination(item:)` in the preview, which works closed, open wide and open tall; `ExerciseAboutRoute` is gone.
    A UI test taps it (compact only; XCUITest cannot fold).
61b. **Past-workout editor at AX sizes**: Start and Duration stack label above control and drop their `.fixedSize()`, which
    had kept them wider than the screen so the whole editor was centred and clipped on both edges.
62. **6.3 contrast scope**: plain `.secondary` text on system backgrounds stays as Apple ships it (3.3–3.5:1 in light mode
    by WCAG, but it is the system semantic colour every Apple app uses; swapping 62 call sites for a custom grey would
    fight Increase Contrast and the HIG). Same for the system's `.borderedProminent` white-on-accent in dark mode. Fixed
    instead: every custom colour that fails (finish-summary stat tints, set-kind letters on the checked row, tags, filter
    chips, calendar day, below-goal bars, sticky-note button, the Previous value/placeholder in set cells).
63. **HealthKit, reversed (Eric, 2026-11-04)**: read-only enrichment from Apple Fitness (PLAN 7.1b), testing
    infrastructure first: research what the simulator supports, a kit `HealthSource` boundary with a fake, launch-arg
    fixtures for UI tests and the gallery, and a real-store integration check, before the reader and the UI. Lands before
    7.2 so the new optional `Workout` fields are in the first Production schema.
64. **Resume control icon is a stopwatch** (Eric, 2026-11-04, spotted the duplicate): the idle resume button reused the
    Exercises tab's `figure.strengthtraining.traditional`, so the closed Duo's strip showed the same figure twice. It is now
    `stopwatch` (a running workout clock); the draining rest ring is unchanged.
65. **`NSHealthUpdateUsageDescription` in every configuration** (2026-11-04): App Store export refuses a HealthKit
    entitlement without it even when the app only reads. Release says "Workouts Duo only reads from Health and never
    writes to it."; Release never requests share access, so the string is never shown there.
66. **When Fitness is read** (2026-11-04; opt-in per Eric): enrichment is a Settings toggle "Read Apple Fitness Workouts",
    off by default; Health access is asked only when it is turned on. Turning it off asks whether to keep or remove the
    Fitness data already added. While on, lookups run when the app becomes active and right after a finish, plus once more
    two minutes later (the Watch workout usually ends just after ours). Unmatched workouts are re-checked at most every 15
    minutes and given up after 7 days; an unavailable store stamps nothing, so a later pass still finds them. A denied read is invisible (HealthKit answers "no data"), so it stamps workouts unmatched; each opt-in therefore clears the stamp of unmatched workouts before the backfill (`HealthEnrichmentRun.resetUnmatched`), and matches are kept.
67. **Store a full Fitness snapshot, not only what is shown** (Eric, 2026-11-04: "get all the info we can"): the matched
    HealthKit id makes re-reading possible, but not if the workout leaves Health, and every new read type re-prompts. So
    all relevant read types are requested up front and each enriched workout keeps a versioned JSON snapshot of everything
    HealthKit returns (statistics, metadata, events, source/device, effort, zones, time zone, any route), beside typed fields for
    what the UI uses.
68. **Heart-rate zones are proven by the fixture only** (2026-11-04): on the iOS 27.2 simulator `HKWorkoutBuilder` never
    produces a zone group (not from added samples, a live-timed workout or a custom configuration), so the real-store
    integration test checks effort, weather, time zone and statistics but not zones. The zone mapping is covered by the
    `full` fixture; real zones are confirmed on Eric's device once enrichment is on.
69. **Plan renumbered (Eric, 2026-11-04)**: CloudKit on, Settings KVS and the final import moved from 7.2/7.3/7.4 to a new
    Phase 8 (8.1/8.2/8.3), the very last steps; the whole-app Fable review is 7.6, before them. Earlier entries that say
    "7.2" or "7.4" mean 8.1 and 8.3.
70. **Phase 6 review folded into 7.6** (2026-11-05): Eric asked for a whole-app Fable review before Phase 8, covering
    bugs, framework fit, Duo UX, iOS 27 guidelines and polish, which is a superset of the Phase 6 (Duo and accessibility)
    review. One Fable pass after 6.4 and 7.1b land, instead of two back to back; it also covers Phase 7's HealthKit work.
71. **6.4 closed with one known cost left** (2026-11-05): after the fixes, scrolling stays under 16.7 ms per commit and
    tab/detail opening dropped from ~1 s to ~0.28 s (the rest is SwiftUI list build). The exercise thumbnails' 30 fps
    cross-fade `TimelineView` still costs ~0.5 s of CPU over a long scroll; it is Eric's approved look, so it stays, and
    the 7.6 review weighs it (pausing off-screen rows would be the native fix).
72. **Design review "Exercises, open wide" closed, no change** (2026-11-05): verified on the simulator that in the book pose
    the system moves the split divider onto the fold (list fills the left panel, detail entirely right). Flat open has no
    division (duo-layout: "The division is active only when partially open"), so a detail crossing the middle there is
    fine. The laptop pose with a horizontal division could not be produced on the simulator; Eric checks it on the Duo.
73. **History has no title once scrolled on the closed display: accepted as system behaviour** (2026-11-05): the closed
    Duo's bar is the vertical trailing strip, which has no title slot in any title mode (`.inlineLarge` changes nothing
    there, and pushed details lose theirs the same way). On the open display `.inlineLarge` on Workout and History keeps
    the large title consistent across pose changes. The stacked exercise detail now sizes its top pane to its content
    (`splitArrangementFixedLayoutSize`), which also makes the tall hero image smaller (35 % of a shorter container).

74. **Resume control is a ring with `dumbbell.fill` in every state** (Eric chose option A over a ring with a dot, 2026-11-05): `RestArc` takes an optional centred glyph; idle is the bare accent track, resting drains the accent arc, an over rest turns ok-coloured with a `checkmark`. `stopwatch` now only means "start a rest" (the idle `RestRingItem` menu).

75. **Exercise info is a sheet, closed from the top** (2026-11-05): an informational, glanceable view over the current
    task is a sheet per the HIG; its system close button stays in the top bar (Eric asked for a bottom button, then agreed:
    every system sheet closes there, and a swipe down is the thumb gesture). The template preview presents the same sheet
    over itself rather than pushing, so the two entry points look identical. A segment tap does not grow it
    (removed in JC107, restored in JC109, removed again in JC117).
76. **Health data has no section of its own** (2026-11-05, Fable spec): values sit in the workout header as peers of
    Duration/Volume; the only branding is "Data from Apple Health" (HealthKit HIG naming). No Activity-ring visuals (Apple
    reserves them for Move/Exercise/Stand). Zones collapse to one line when the workout never left zone 1.
77. **Quality review fix batch, wave 1** (2026-11-05, after a test-coverage + Swift-practices review): one `ClockFormat`
    (`Duration.TimeFormatStyle`, en_US) replaces five clock formatters, so a 3600 s rest now reads `1:00:00` everywhere (the
    set table used to say `60:00`); one `CalendarFormatting` (`VerbatimFormatStyle`) replaces per-call `DateFormatter`s with
    byte-identical output. A store read that fails is never read as "nothing": `CustomExerciseForm.isReferenced` throws and
    the form fails safe to Archive; a JSON import whose health data cannot be stored aborts and rolls back (the file is the
    only copy); a stored health blob that no longer decodes still reads as "no data" but is logged (`KitLog`).
78. **Full-history reads run on `WorkoutStatsReader`** (2026-11-05): workout detail and last-performed dates no longer
    fetch every finished workout on the main actor. Every flush before a reader load goes through
    `ModelContext.saveIfChanged(reportingTo:)`, so a failed save is the alert, never silent; a detail that cannot be read
    shows "Could Not Load Workout" instead of a spinner.
79. **TestFlight uploads need a full UI run on the exact commit** (2026-11-05): `./dev ui-test` with no filter stamps HEAD
    when it passes on a clean tree; `./dev testflight --upload` refuses otherwise (`DEV_SKIP_UI_GATE=1` overrides with a
    warning). The commit gate stays `./dev check`, because a full UI run per commit is too slow. App coverage is now
    recorded (`./dev coverage`, `./dev kit-coverage`).
80. **Long Settings work runs to completion; notification calls leave the main thread** (2026-11-05): `SettingsFlow` owns
    import, Health opt-in and opt-out, and lets them finish when the sheet closes (each is a confirmed change to stored
    data that is only consistent once done); the post-import Fitness look-up is restartable, so it lives in the sheet's
    `.task(id:)` and is cancelled with it. `SystemNotificationCenter` sends its remove/add/category calls on one serial
    queue: they are synchronous XPC, and from `WorkoutsApp.init` a slow notification daemon got the app killed by the
    launch watchdog (0x8BADF00D) in UI tests under load, which could happen on a device too.
81. **Snapshot tests are home-grown, no package** (2026-11-05): `WorkoutsTests/Snapshot` renders with `ImageRenderer`, or
    hosts in a real window for views ImageRenderer cannot draw (TextField, List), and compares per pixel with 0.05%
    tolerance against PNGs in `WorkoutsTests/__Snapshots__`. `SNAPSHOT_RECORD=1 ./dev test SnapshotTests` re-records;
    a mismatch writes `.actual.png` beside the reference. Remote packages need Eric's say, and the need is small.
    Formatting goes through a pinned Toronto calendar so the references hold in any time zone.
82. **Accessibility audits gate every main screen, with narrow, commented filters** (2026-11-05):
    `AccessibilityAuditUITests` runs `performAccessibilityAudit` on nine screens at the default size and four at
    accessibility XL. Open for Eric (taste): `.secondary` text measures 4.2–4.5:1 on grouped backgrounds ("nearly
    passed") and the template preview's translucent sheet fails contrast. Both are filtered with a TODO rather than
    re-coloured. Single-line truncation by design is filtered at the default size. Empty states were not wrapped: each
    `ContentUnavailableView` is already the native component, and only "Workout Not Found" repeats (two sites).
83. **Default rest is 1:00** (Eric, 2026-11-05): `SettingsStore.defaultRestSecondsDefault` 90 → 60. A rest already chosen in
    Settings is stored and kept; only devices that never set it change. Engine rest tests pin their own 90 s default.
84. **Appearance is a Settings choice: System (default), Light, Dark** (Eric, 2026-11-05): a segmented picker in a new
    Display section; `.preferredColorScheme` once at the scene root, so sheets, the cover and the preview gallery follow.
    Not part of the JSON export (no other UI setting is). Found on the way: launch-argument overrides reach the defaults
    as text, and integer/boolean settings were read with `as?` only, so `-defaultRestSeconds 90` was silently ignored
    (the Settings UI test passed only because 90 was the old default). They now parse their text.
85. **Exercise video is a card the colour of the video's own background** (Eric, 2026-11-05): every source video has a
    flat background (light #FFFFFF, dark #282A2C), so the hero is a 20 pt continuous card filled with `VideoBackground`
    and the video fits instead of filling (Apple's iPhone Duo checklist: aspect-fill heroes crop on wide displays). The
    exercise info sheet opts out of the Duo's vertical bar (`toolbarVerticalBehavior(.disabled)`) so its content uses the
    full width, and drops its ✕: it is a read-only, resizable sheet with a grabber, dismissed by swiping (HIG Modality:
    "a button in the top toolbar or swipe down"). This replaces the close-button half of JC75. The medium detent keeps
    the full-size video; the rest of the content is one swipe or a segment tap away (true again since JC109, and kept by JC117 through the layout, not by growing the sheet; the segments
    sit right under the name at the medium detent).
86. **The simulator pool looks after itself, and the full UI suite runs sharded** (2026-11-05, two Fable reviews):
    `./dev` shuts down pool clones idle 30 min (never the original, never one running the app), erases a clone after two
    system-process crashes on it (PosterBoard crash-looped on clones with thousands of leftover poster records), and
    `./dev sims --prune` erases clones over 1,000 poster records. The full `./dev ui-test` builds once and runs suites
    enumerated from the test bundle on up to 3 free simulators (~14 min instead of ~40), one shard when the load average
    is above 4 × CPUs. A failed test is retried once; the retry must run exactly the failed tests and pass, is logged to
    `.build/ui-flaky.log`, shows in the totals and the ship stamp, and a test flaky two full runs in a row fails hard.
87. **While a set field is being edited, the closed Duo's strip shows only Minimise and Finish** (Eric, 2026-11-05):
    with the number pad up the trailing strip is about three items tall, and the six workout items overflowed into a
    ⋯ pill beside the keyboard bar (Finish itself got folded on Eric's device, where the Island also shows the Live
    Activity). The rest ring, Skip, +30 s and Add Exercise leave the strip while a set cell has focus (a preference from
    SetTable); the rest countdown, Skip and +30 are in the keyboard accessory meanwhile, and everything returns on Done.
88. **Live Activity like Apple Fitness** (Eric, 2026-11-05): the closed Duo's narrow Island stacks the ring over a ticking
    time (rest countdown while resting, else elapsed; Eric: "Do ticking then", since a "45min" label cannot self-update).
    The lock screen keeps one progress bar (sets); the second blue rest bar is gone.
89. **Expanded Island is one row** (Eric: "polluted compared to Apple's workout app", then "remove the grey text"):
    round buttons leading (Skip and +30 while resting, a blue Done otherwise), one large tinted time trailing. No app
    glyph, no exercise caption, no "n of m sets", no "Elapsed" label.
90. **The workout header minimises on scroll down and the system restores it on scroll up**: `.toolbarMinimizationBehavior(.onScrollDown)`
    and nothing else. A timed auto-return was rejected: it would have to flip the behaviour to `.never`, which the system
    applies in one frame (no public API animates it), and the HIG ties restoring hidden chrome to a user gesture.
91. **Turning off "Download all videos" asks Keep / Remove / Cancel**, like the Fitness toggle; with nothing cached it
    just turns off. Remove clears the whole video cache, including videos only watched.
92. **Pull to refresh on History forces a Fitness lookup** (Eric, 2026-11-05): the native `.refreshable`, attached only
    while Fitness reading is on (toggling it rebuilds the list once; `refreshable` cannot be switched off in place). It
    re-checks recent workouts past the 15-minute throttle and runs the backfill; it does not touch iCloud sync, which
    has no public trigger. Its UI test asserts the effect (calories appear), since XCUITest cannot see the spinner live.
93. **A superset is one band in the heart-rate chart**, named "Superset N" and tinted with that superset's colour;
    selection still names the exercise of the set. A band label is drawn only when the band spans ≥ 8% of the axis.
94. **Test-gap research adopted where simple** (Eric: "adopt where it makes sense, not if too complicated or hacky"):
    in-process tests for the Live Activity intents, a CloudKit model-rules check on the schema, a unit test of the
    Wi-Fi-only media configuration, in-flight refresh tests. Skipped as
    too fragile: driving the real Island / notification banners through SpringBoard, moving the hinge from the test runner.
95. **Health passes skip workouts before the earliest readable date without stamping them** (iOS 27 shares the past 30
    days by default): the later of `earliestPermittedSampleDate` and the workout type's `earliestAuthorizedSampleDate`.
    Widening access later lets the backfill find them.
96. **Bug review round 1** (Eric: Opus reviewers over the whole project until diminishing returns): six fresh read-only
    Opus reviewers, one per area, given only the code and "find real bugs". 27 confirmed across all six areas; each fix
    has a regression test. Decisions within the fixes:
    - Renaming a custom exercise renames its template rows and in-progress workout rows; finished history keeps the
      name at the time.
    - A bar change offers "Update Template?"; a unit switch with an equal load does not (existing rule kept).
    - An import with several unfinished workouts keeps the newest in progress and imports the others as finished at
      their last completed set.
    - Editing a past workout's time clears its Fitness match so the next pass re-matches it.
    - Pull to refresh on History clears unmatched stamps first: the explicit "check again" after a later Health grant.
    - A video fetch finishing after Remove is discarded; a cellular-allowed request never waits on a Wi-Fi-only one.
97. **Round 1, remaining fixes**:
    - Plan and Previous match sets by kind (n-th warm-up ↔ n-th warm-up, n-th working ↔ n-th working), so adding
      warm-ups no longer shifts the working values.
    - A reorder that separates a superset member takes the mover out of the group (engine, template editor,
      past-workout editor).
    - "+30 s" from the notification or the Island starts a 30 s rest when the rest is already over or was cleared
      on a cold launch.
    - Background actions (Island buttons, notification actions) flush the Live Activity and notification changes
      before returning.
    - The rest-expiry haptic and clearing live on the logging cover, not on the toolbar ring, so they work while a
      set is being typed.
    - Download all videos resumes on every activation while on and retries failed fetches.
    - An import that saved is never reported as failed.
98. **Bug review round 2** (cross-cutting angles: data integrity, concurrency, Duo navigation, numbers/dates, system
    integrations; five fresh Opus reviewers). 19 new confirmed, smaller than round 1's 27; the only data-loss one was
    a round-1 regression (editing any set of a past workout cleared its Fitness data because of fractional seconds),
    fixed here. Decisions:
    - PRs count rows of the same exercise in one workout as one session everywhere (History, detail, exercise
      history), matching the Finish screen.
    - Dates format in the Gregorian calendar with the device time zone regardless of the device calendar system.
    - Weight entry accepts plain decimals only, up to 10,000; a custom bar converts with the row's unit.
    - "Add Warm-up Sets" keeps checked warm-ups and replaces only unchecked ones.
    - Not fixed: a custom exercise's default bar weight follows the Settings unit (needs a model field; unlikely).
    - The exercise info sheet's vertical-bar opt-out is documented in duo-layout.md (Eric-approved, JC85).
99. **An unsaved past-workout edit survives a link from Exercises**, and History's own pop-to-root waits while the
    draft is dirty. Not covered: tapping the History tab again pops the editor through UIKit's native tab reselect,
    which app code cannot veto (same for the template editor on the Workout tab). Closing that gap means presenting
    both editors modally instead of pushed: a design call left for Eric. The rest ring's sheets now share one stable
    presenter and close with the rest, so none reopens by itself.
    Superseded: both editors are now full-screen covers with their own `NavigationStack` (Eric-approved, HIG Modality), so
    a tab reselect cannot pop them; the dirty-flag guards on `AppNavigation` and `HistoryRoute.editWorkout` are gone.
100. **Bug review round 3** (angles: regressions from rounds 1–2, a gym session walked step by step, hostile imports
    and text): 13 confirmed, two P1 (Update Values Only shifting warm-up weights into working sets; a replaced timed
    exercise keeping the Time column, a round-2 regression), the rest P2 or hostile-file only. Decisions:
    - Update Values Only pairs sets by kind and copies only checked sets; the template's structure never changes.
    - The Live Activity's current set is the first unchecked set after the most recently checked one (a skipped set
      no longer holds it back), wrapping to the first unchecked.
    - Previous pairs the n-th row of an exercise with the n-th row last time (falling back to the first).
    - Add Warm-up Sets ramps from the typed, planned or Previous weight.
    - Dropping a non-member inside a superset places it after the superset (the drag's source ids disambiguate).
    - Opening the workout from the Lock Screen closes tab sheets first; the resume ring hides only while the cover is
      actually on screen.
    - The importer renumbers extreme positions, drops impossible Fitness values, never re-parents an existing row, refuses
      custom ids that collide with the library, and reports a newer file version as such.
101. **Round 4 and the stop** (two fresh reviewers: round-3 regressions, and the screens around the workout read
    with fresh eyes). Confirmed: one regression (closing tab sheets when the workout link opens could discard a form
    being typed; it was added for a failure never reproduced, so it is removed and only the resume-ring safety net
    stays), a superset-drag edge case on already-split groups, and three small screen bugs (template editor's
    warm-up alert, History totals after a weight-type change, the picker's always-available New). Rounds found
    27 → 19 → 13 → 5, the last mostly minor and partly self-inflicted, so the review loop stops here (diminishing
    returns, per Eric's brief).
102. **The past-workout and template editors are full-screen covers** (Eric, 2026-11-06, after HIG Modality: a
    self-contained edit with Save/Cancel is modal): a tab re-tap can no longer pop an editor and drop its unsaved draft.
    Every other editing surface was already a sheet; pushed screens are read-only. The dirty-editor guards from JC99
    are removed; each editor cover hosts its own save-error alert.
103. **Two in-progress workouts after a sync** (C-11 c, ahead of 8.1): `resume()` keeps the newest start (ties by id, so
    every device agrees) and settles the older ones with the importer's demotion rule (finish at the last completed
    set, never before the start). One with no completed set is deleted rather than finished, since `finish()` refuses
    an empty workout. A remote-change merge never settles a workout running here; that waits for the next `resume()`.
104. **Old agent worktrees archived, not removed** (2026-11-07): the handoff said they were archived; none was, and all
    held uncommitted changes. Each diff is now `.build/worktree-archive/<name>.patch`; the worktrees stay until Eric
    says to remove them.
105. **`./dev shot` pins the status bar** (C.2): a settled capture must hash the same across runs, and the clock and
    indicators change, so `shot` applies `simctl status_bar override` (9:41, full battery, Wi-Fi) for the capture and
    clears it after. Documented simctl, not a display toggle. The warm-boot wait before settling dropped from 4 s to 1 s.
106. **A workout link waits for an open editor** (handoff item 3, 2026-11-07): a Live Activity / notification /
    `workouts://workout` request used to close an open past-workout or template editor silently, losing unsaved edits.
    Now `AppNavigation` defers the request while an editor cover is up and presents the workout cover once the editor
    closes (Save, Cancel, or Discard).
107. **Exercise info sheet no longer grows on a segment tap** (Eric, 2026-11-07; superseded by JC109): the tabs sit below the medium detent since
    the video grew to full width, so the user drags the sheet up to reach them anyway; the grow-on-tap (JC75) was dead
    behaviour and its `onExerciseSegmentChange` environment hook is gone. Detents stay medium and large.
108. **No workout-level note writer** (Eric, 2026-11-07, notes review): `Workout.note` keeps its field and History keeps
    showing notes that came in through the web import, but no screen writes one; Eric wants sticky notes, not that kind.
109. **Sticky note is the first block of About; the info sheet grows on a segment tap again** (Eric, 2026-11-07, supersedes
    JC107; Fable placement review `docs/reviews/2026-11-07-info-sheet-note-placement.md`): the sticky row sat between the
    name and the segmented control and pushed the tabs below the medium detent, which is why the grow-on-tap looked dead.
    Eric wants the tabs visible at the medium detent, right under the name, and a tap on another segment growing the sheet
    to large again (`onExerciseSegmentChange` is back). The sticky note (band + Edit, or "Add Sticky Note" when none)
    moves out of `ExerciseDetailView.summary` into `ExerciseAboutSection`'s `note` slot, after the retired notice and
    before the body-part line, in every host (info sheet, pushed detail, embedded pane). Accessibility ids are unchanged.

- **JC110 (2026-11-07, PLAN 7.8b): block menu groups by `Divider`, one `pin` glyph.** A `Section` inside the block
  `Menu` dropped its buttons' accessibility identifiers (labels only in the tree), so the groups (notes; sets/rest;
  exercise; remove) are split with `Divider`, which renders the same separators. `pin.badge.plus` is not an SF Symbol,
  so Add/Edit Sticky Note… both use `pin` and the title carries the difference. The detail's `StickyNoteView` stays
  uncapped (it is where the full text is read); the set-table band caps at 3 lines.

- **JC111 (2026-11-07, review r1 A11Y-5): note rows keep their visual height; no hit-area overhang.** The sticky band (~26 pt)
  and note line (~18 pt) under a block name are below 44 pt. A pad / contentShape / negative-pad overhang was proposed and
  rejected (hard-coded heights, overlaps the exercise-name button above). A true 44 pt row visibly loosens the block header;
  that is Eric's taste call, open in the review.
- **JC112 (2026-11-07, Eric, from screenshots): the exercise detail keeps no bar title (JC29 stands); the template preview shows the bar title only (in-content name removed); the sticky band and note line are 44 pt tall, which resolves JC111.**
- **JC113 (2026-11-07, Eric, from screenshots): durations stay "40min"; the template preview sheet stays Liquid Glass; values you can't tap (records, reps, chart headline, PR counts) use primary text, not the accent; info (i) buttons are secondary grey; exercise names stay one line cut off at accessibility sizes; Settings keeps segmented pickers at accessibility sizes; below-goal weeks keep their own `ChartBelowGoal` blue.**
- **JC114 (2026-11-08, orchestrator, Eric asleep): the set keyboard's +/− on an empty cell steps from the greyed placeholder (Previous or plan) rather than from 0, the same source that checking a set fills from. Review R3W-4.**
- **JC115 (2026-11-08, orchestrator, Eric asleep): folder headers put the chevron right after the title (no trailing spacer), so on the open Duo the header stays on one panel and its tap area no longer spans the hinge. Review R2-6.**
- **JC116 (2026-11-08, orchestrator, review r5 nit): the heart-rate chart's Avg, like its Max, describes the plotted line (time-weighted over the clipped series, lead-in dropped), while the detail header's "Avg HR"/"Max" stats keep the Fitness workout's own stored numbers. The header reports what Apple Fitness recorded; the chart captions what it draws, so the two may differ by a few bpm when the Watch workout started early.**
- **JC117 (2026-11-08, Eric): the exercise info sheet never grows on a segment tap, from any entry point. A sheet presented over the template preview sheet inside the tab shell ignores programmatic detent changes on iOS 27.2 (verified: the binding flips, the sheet stays at medium; deferring the change does not help), the active-workout path is a cover so it worked there, and Eric wants one behaviour everywhere rather than a hack. Supersedes the grow part of JC109; JC109's layout (segments right under the name at medium, sticky note leads About) stands.**
- **JC118 (2026-11-08, Eric): sticky notes are gone.** The per-exercise note that followed an exercise into every template and workout (PLAN 4.5, 7.8; JC108–JC112) is removed end to end: `StickyNoteView`, the set-table band and menu entry, the kit's `StickyNotes` API, the `stickyNotes` JSON field and the `StickyNote` entity (SchemaV2 with a lightweight V1 → V2 stage; the class stays in the kit only so V1 still describes old stores; an older JSON document's `stickyNotes` key is ignored on import). Block notes (Note… on a block, the template note, past-editor block notes) are the one note kind. JC108 stands: no workout-level note writer either.
- **JC119 (2026-11-08, orchestrator): stat tiles are one caption plus one value line, always.** A second line in one tile ("Total 300" under Active, "Max 161" under Avg HR, "Estimated" under Effort) made that tile taller than its row-mates and misaligned the grid, which Eric finds off-putting; each value is its own tile (Total: `flame`, Max HR: `arrow.up.heart.fill`) and an estimated effort says "Est. Effort" in the caption. The same rule drove the alignment sweep (every sibling in a row or grid shares its structure, insets and icon width). The set table's centred Previous column has ragged left edges by construction; it stays centred until Eric says otherwise.
- **JC120 (2026-11-08, Eric, from a Strong screenshot): holds are timed from the first set.** Plank showed lb + Reps because "timed" was inferred only from sets that already had a duration. A library exercise tagged `isometric` (44 of them: Plank and its variants, Side Plank, Dead Hang, L-Sit, Wall Sit, Hollow Body Hold, Handstand Hold…) is now `ExerciseInfo.isTimed`: a new template row is timed, the engine's `isTimed` consults an injected `timedByDefault` lookup (so it survives relaunch), and a timed row whose weight type is not a strength type (bodyweight, unweighted, band) has no weight column at all, like Strong; Weighted Plank and other weighted holds keep weight + Time. Custom exercises keep the set-based inference (no new form field; Eric's 2026-11-03 answer limits custom edits to rename/unit/bar/rest). Carries and walks (Farmer Walk) are not tagged isometric and stay reps until Eric says otherwise.
- **JC121 (2026-11-08, Eric, from a Strong recording): durations are `m:ss` everywhere and typed from the right.** The Time cell, its placeholder, the Previous column and set summaries print `0:45` / `1:30` (`h:mm:ss` past an hour) instead of plain seconds or "45 s"; typing fills like a microwave ("130" shows 1:30, "190" normalises to 2:30); the keyboard's −/+ steps 5 s. One duration format across the set table, history and the Live Activity rather than seconds in cells and "45 s" in text.
- **JC122 (2026-11-08, Eric: block drag is "EXTREMELY clunky"): the template editor's title menu gets Reorder Exercises…, a compact `List` of exercise names with always-on drag handles (edit mode forced active, superset badge per row), like Strong and Reminders.** Lifting a whole block with its set rows is what makes the drag awkward, so the list is the primary reorder; the block drag (`reorderable`) stays as it was. Both go through the same `source.reorder` path, so the split-superset rule is unchanged. The template editor, the active-workout cover and the past-workout editor all have the menu item.
- **JC123 (2026-11-08, Eric asked for Strong's block drag, where every block folds to its header on lift): rejected after measuring; the Reorder Exercises… sheet (JC122) stays the compact reorder.** The collapse itself is possible with documented API (`onDragSessionUpdated` on the `reorderContainer`, header-only blocks while the session is `initial`/`active`), and on video it folds and re-expands as Strong does. But the system keeps the lifted block's placeholder at its pre-lift height, so the compact list sits under a block-sized blank gap and a drop inside the compact headers resolves to the no-op "before the second block"; the drop target never follows the finger through the folded list (Xcode MCP multi-touch drags on the simulator, 2026-11-08). No public API resizes that placeholder, and faking it is a hack. XCUITest's `press(forDuration:thenDragTo:)` starts the reorder session in about 1 run in 12 even on an unchanged build, so block-drag flows are proven with the Move Up/Move Down accessibility actions or `mt` multi-touch via the MCP, never with a plain XCUITest drag.
- **JC124 (2026-11-08, Eric's recording: the exercise video "changes size" when the detail opens): the hero's 35 % cap is measured by the detail screen on its whole column and passed down as `exerciseHeroCapHeight`; the hero also takes that cap as its ideal height.** The old probe (`containerRelativeFrame` inside the hero) measured the stacked split's content-fitted top pane, which is sized from the hero, so the two shrank each other to a 77×43 pt still that snapped to a full card once the video loaded. With the cap as ideal height the fitted pane is cap-sized plus name and segments; the cap is `min(0.35 × column height, 16:9 of the column width)` so the card never leaves a gap. The stills were not the cause: measured against the videos' first frames, their framing matches within 2 %, so no thumbnail regeneration. `ExerciseHeroUITests` asserts a column-wide 16:9 hero in the Exercises split (passes in the closed and the open-tall pose).
- **JC125 (2026-11-08, Eric looked for the reorder sheet in an exercise's … menu and did not find it): Reorder Exercises… is also an entry of every block's … menu, in all three editors (cover, past-workout editor, template editor), opening the same `ReorderExercisesSheet` as the title menu.** It sits in its own group just above Remove Exercise, where Strong puts it, and is disabled with fewer than two exercises. `SetTableBlockActions.reorder` takes no block id (the sheet covers the whole list); `BlockActionState.actions(host:reorder:)` and `noteActions(reorder:)` pass the owner's closure through. One entry point was not enough: the title menu's chevron is easy to miss, and the block menu is where the exercise actions already live.
- **JC126 (2026-11-08, PLAN 8.1): CloudKit sync is on (`cloudKitEnabled = true`) with `aps-environment` and the `remote-notification` background mode added, and TestFlight uploads are held until the Production schema exists.** The mirror needs silent pushes to learn about another device's changes, which is Apple's documented setup for Core Data with CloudKit (Push Notifications capability plus Background Modes › Remote notifications); the iCloud entitlement alone only lets the app read and write. SwiftData creates the record types in the Development environment on the first run with an iCloud account, and only a developer can deploy them to Production, which is the environment TestFlight builds use, so a build uploaded before that deploy would log a schema error on every sync attempt and sync nothing; one upload right after the deploy costs nothing. The pool simulators have no iCloud account, so the two-simulator proof needs Eric at the server's screen; the steps are in `docs/cloudkit.md`. 8.2 (settings on iCloud KVS) stays unstarted: the Duo is the only device.
- **JC127 (2026-11-08, PLAN 8.1): the Development schema is created by a Debug launch flag, `-initializeCloudKitSchema`, which runs `NSPersistentCloudKitContainer.initializeCloudKitSchema` over the SwiftData model (`NSManagedObjectModel.makeManagedObjectModel(for: SchemaV2.models)`) against a throwaway store, not by seeding data and letting the mirror infer the types.** The mirror only creates a field once some uploaded record carries a value for it, so inferring from data leaves every always-nil optional (a health summary, a note) out of the schema and Production then rejects the first record that sets one. Apple's documented answer is `initializeCloudKitSchema`, which writes and deletes one fully populated record per entity; SwiftData has no public equivalent, so the flag does it with Core Data on the same model in the same process. Debug only, one helper beside the other `…IfRequested` launch flags. The two-simulator proof used `-seedSampleData` on one sim and a fresh second sim, both signed into a test iCloud account.
- **JC128 (2026-11-08, PLAN 8.1): the CloudKit schema's Production deploy stays a Console click; `./dev ck-schema` only reads (`export`, `diff`).** The Management API behind `cktool` answers "endpoint not applicable in the environment 'production'" to both `import-schema` and `validate-schema`, so a scripted promotion is impossible, not merely unbuilt. The command keeps the readable half: it resolves the management token through `op run` (the reference goes in the child's environment, the value never touches this shell), exports an environment's `.ckdb` and lists its record types, and `diff` names what Production still lacks, which is the check that gates the TestFlight upload after each model change.
- **JC129 (2026-11-09, Eric: "Sync doesn't seem to be working", reading the Settings row): the iCloud row shows a live status instead of the pre-Phase-8 "Not available yet" placeholder.** Phase 8 turned sync on but left the row as the 5.7a stub, so the shipped build told Eric sync did not exist. `CloudSyncMonitor` (app) reads `CKContainer.accountStatus` and the mirror's `NSPersistentCloudKitContainer.eventChangedNotification` (SwiftData still posts it) and feeds `CloudSyncStatus` (kit, pure, tested), which renders Synced <relative>, Waiting for first sync, Not signed in, Restricted, Unavailable, Error (footer carries the error text) or Off (in-memory stores: tests, previews, `-uiTesting`). No manual sync button and no per-record progress: the mirror has no public API for either, and the last finished import/export plus the account state is what Apple's own apps show.
