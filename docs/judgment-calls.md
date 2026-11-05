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
