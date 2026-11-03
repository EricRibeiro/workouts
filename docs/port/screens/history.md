# History tab (and Settings)

## 1. Purpose

The log of finished workouts. Top to bottom: a "Workouts per week" chart with a goal line, then
cards grouped by month, newest first. A Calendar sheet jumps to any day. A card opens a workout
detail, which can be edited after the fact. Settings is not a tab (section 8).

## 2. Data shown

- **Card** (`WorkoutCard`): `name`; date `Sunday, Nov 1` (year added only when not the current year);
  duration `1h 12min` / `45min` / `<1min`; volume `15,421 lb` (rounded to whole units, display
  unit); PR count `N PR` / `N PRs`; and an `Exercise | Best Set` table of rows `N × Name`
  (`N` = completed sets of that exercise, warm-ups included) with a best-set text per row:
  `25 lb × 8`, `10 reps`, `45 s`. Superset rows get a colour bar. An exercise with no completed
  set is left off the card. The card's `set count` is also returned (`setCount`: completed sets,
  warm-ups included) but ui.md lists no set-count stat on the card (see Open questions).
- **Grouping**: month headings `November 2026`, in the device time zone, title case, newest first.
- **Volume** (`records.md` "Volume"): sum of weight x reps over counted sets (completed, non-warm-up),
  in the display unit, rounded to 0.5. Bodyweight and assisted volume is 0; timed sets add nothing.
- **PR count** = number of records the workout newly set, summed over its exercises
  (`PRsInSession`), compared only with sessions strictly **before** that workout, so a card's count
  never depends on which page it was loaded in and editing an old workout never compares with the
  future. Equal is not a PR. Kinds: `e1rm`, `heaviest`, `volume`, `repsAtWeight`, `duration`.
  Reps PRs use dominance, and the weight that set the heaviest PR is skipped for the reps PR
  (`100 lb x 10` then `105 lb x 1` is one PR, `records.md` 88-97). First session of a barbell
  exercise with one working weight sets three (e1RM, heaviest, volume).
- **Display unit**: volume and best sets follow the unit setting; stored weights never change.
- **Detail**: `Sunday, Nov 1 · 10:05 AM`; duration, volume, PRs; the workout note; per exercise a
  name (with a trophy when it set records), its note, its **completed** sets only, labelled `1, 2...`
  with `W` (warm-up), `D` (drop), `F` (failure) in place of a number; then one line per PR:
  `Est. 1RM: N lb`, `Heaviest: N lb` (assisted: `Least assistance`), `Set volume: N lb`,
  `Reps: 8 at 100 lb`, `Duration: 1:30`. Short durations print `45 s`, longer ones `m:ss`.
- **Weekly chart**: 8 ISO weeks (Mon-Sun), oldest left, current week last, zero-filled; count above
  each non-empty bar; x label `10/26` (the Monday); bar solid when count >= goal; dashed goal line;
  y axis whole workouts from 0 with one step of headroom over the goal or the busiest week. Weeks and
  days are cut in the **server's** time zone (`TZ`), not the device's.
- **Calendar**: month grid, Monday first (`M T W T F S S`), days with workouts marked.

## 3. Interactions

- Open History -> first **20** cards load; scrolling within 400 px of the end loads the next 20
  (cursor = previous card's start time, `limit` 1-100). Refresh keeps as many cards as were loaded.
- Tap a card -> workout detail (right pane when expanded, sheet when compact). Tapping another
  card while one is open swaps it; Close goes back to the list.
- Card **⋯** (aria `<name> options`) -> menu: **Edit**, **Save as Template**, **Delete**.
  The detail's bar has Close, Edit and ⋯ (**Save as Template**, **Delete**). Native: no ⋯ (see §5).
- **Edit** -> past-workout editor (full-screen layer): the template editor's blocks and menus, the
  active workout's check column (un-check a set to stop counting it), plus a start time
  (`datetime-local`) and duration in minutes under the name. A set that gets a value, or is added
  with **+ Add Set**, is checked at once; unchecked empty sets and exercises left with no set are
  dropped on save. Unsaved-changes guard on close. Save = the same idempotent upsert of the whole
  workout (all ids kept). Nothing derived is stored, so PR counts, volume and best sets of this and
  **every later** workout follow (moving a workout in time moves who holds records).
- **Save as Template** -> pick a folder (sheet `Save Template to Folder`; with no folder it offers to
  make one called `Templates`) -> sheet `Save as Template`, confirm `Save Template` -> toast.
  Copies exercises, sets with kinds/weights/reps, supersets, notes under new ids.
- **Delete** -> confirm sheet `Delete workout?`, message `"<name>" and every set in it will be
  deleted. This cannot be undone.`, button `Delete Workout` (destructive). No undo. Deleting from
  the detail closes it. Exercises and sets go with it; repeating the delete is harmless.
- **Calendar** button (title row, glass icon) -> full sheet `Calendar`: `Previous month` /
  `Next month` arrows; tap a marked day -> lists that day's workouts (name + time); tap one -> sheet
  closes and the detail opens. Hint text below the grid.
- **Target button** (chart header, shows the goal, aria `Weekly goal: N. Change it.`) -> sheet
  `Weekly goal` with a stepper 1-14 and Save; error `Could not save the goal.` Moving the goal moves
  the line. Native: dropped; the goal lives in Settings only.
- **Repeat as a new workout**: the web has none and native does not add one. The only reuse path is Save as Template, then start
  that template from the Workout tab. **Strong import**: no UI, it is a server CLI (`import-strong
  <csv>`, PLAN.md 56, 292-321); nothing in History or Settings exposes it.
- Failed actions show a dismissable banner: `Could not open the workout.`, `Could not read the
  workout.`, `Could not save the template.`, `Could not delete the workout.`

## 4. States

- **Loading**: skeleton for the list; detail shows `Loading...`; paging shows `Loading...` under the list.
- **Empty**: `No workouts yet. Finish one from the Workout tab and it shows up here.` (chart still shows).
- **Error**: `Could not load the history.` + `Try again`; a failed page shows the message + `Try again`.
  Detail: `Could not load the workout.` or `That workout does not exist.` (404).
- **No selection** (expanded, no detail): pane text `Select a workout`. Native: none; History is a `NavigationStack` in both widths, so there is no empty detail.
- Calendar: `Could not load the calendar.`; empty month `No workouts this month.`; otherwise `Tap a
  marked day to see its workouts.` Chart with no workouts: bars absent, goal line still drawn.
- A workout in progress: sources specify no History behaviour.

## 5. Native mapping

- Root: `TabView` tab "History", a Fitness-style dashboard (`PLAN.md` §3): large title; hero card = the weekly goal
  chart (full width); then even-column cards from the grid's own width (`onGeometryChange`, same rule as the template
  grid): This Week (count vs goal), Recent PRs (trophy list), Last Workout (name · duration · volume, `chevron.right`
  to its detail); then the month list. Which cards is taste: ask Eric. A `NavigationStack` in **both** widths: the dashboard
  is full width beside the tab sidebar (a list | detail split would squeeze it into the narrowest of three columns, and
  `ref-fitness-open-wide-dark.png` has no detail pane either). Rows push the detail with the zoom transition; folding must
  keep the path and the list's scroll, so drive both from state, not from layout.
- List: `List` with a `Section` per month (header = month title), **workout rows** (name, date, duration · volume ·
  PRs, trophy; the per-row `Exercise | Best Set` table moves into the detail), `.contextMenu` /
  trailing `swipeActions` carrying Edit / Save as Template / Delete; no ⋯ `Menu` (the ellipsis is the system's
  overflow). Toolbar: Calendar (`calendar`). Workout detail toolbar: Edit (`pencil`), Save as Template
  (`doc.on.doc`), Delete (`trash`, destructive), each with symbol and title. SwiftData `@Query` sorted by start descending replaces cursor paging; use lazy rows, no
  manual sentinel. `.confirmationDialog` for Delete. `.searchable` over workout name and exercise names with
  `searchScopes` (All · PRs), as every Flighty list has.
- Weekly chart: Swift Charts `BarMark` per ISO week + `RuleMark` goal line (dashed), bar style by
  `count >= goal`; the chart header is plain (no goal button, the goal is a Settings `Stepper`). Compute weeks and days in the device
  calendar (no server); the web's "server time zone" quirk goes away. The counts are a kit function,
  `weeklyCounts(workouts:calendar:weeks:)` (ISO weeks, Monday, injected `Calendar`/`TimeZone`, DST-tested).
- Calendar: a sheet with a month grid (`Grid`, Monday first, always), day tap -> workouts of the day -> push detail.
- Edit past workout: reuse the shared exercise editor in a past mode, pushed from the workout detail (not a cover
  or sheet); on regular width its body is the logging screen's `ArrangementView(primary: SetTable, secondary:
  exercise pane)` so the table never straddles the fold.
- Save as Template: sheet with folder picker. Toast -> `sensoryFeedback(.success)` and the sheet dismissing; no banner.
- Units, volume, best sets and PR counts are derived on read in WorkoutsKit, not stored.
- Settings: not a tab and not in the split; `PLAN.md` §2 (gear toolbar item on the Workout tab, plus
  `tabViewSidebarBottomBar` on regular width, presenting a `Form` sheet).
- iCloud/CloudKit: no status exists in the web app. Natural place is a footer row in the Settings
  `Form` (sync status / last synced, account unavailable warning); History only needs the empty state.

## 6. Dropped or changed on purpose

- Server `GET /api/workouts` paging and `/api/stats/*`: replaced by local queries.
- Server-time-zone weeks/days: native uses the device calendar.
- `refreshHistory()` re-read machinery: SwiftData/`@Query` updates views.
- Web-only chrome (glass pills, `section-h` CSS, safe-area/haptic "Device check"): system styling.
- Card PR count and every aggregate stay computed, never stored.

## 7. Open questions (all closed 2026-11-03; answers in `PLAN.md` §2)

- ~~Is there a "duplicate as template" distinct from Save as Template?~~ No: Edit, Save as Template, Delete only.
- ~~Add "Repeat workout"?~~ No; Save as Template then Start is the reuse path.
- ~~Show the card set count?~~ No (duration, volume, PRs only).
- ~~Where should the weekly goal live on iPhone?~~ Settings only (2026-11-03); the chart header is plain.
- ~~Keep Settings a fourth tab?~~ No: `PLAN.md` §2 (gear item + `tabViewSidebarBottomBar`).
- ~~Later charts (weekly volume, sets per muscle group, PR feed)?~~ Out of scope; the dashboard cards (This Week, Recent
  PRs, Last Workout) replace them.

## 8. Settings

Not a fourth tab (the web had one): per `PLAN.md` §2 it is a gear toolbar button on the Workout tab and a
`tabViewSidebarBottomBar` on regular width, presenting a `Form` sheet (`gearshape`). Inset grouped list;
every change is shown at once and saved behind; a refused save restores the old value with a message;
a saved unit or formula change refreshes History numbers. Native: `Form` with `Section`s; footers as
`Section` footers; `Picker(.segmented)`, `Stepper`, `Menu` / `Picker(.menu)`, `Toggle`.

| Setting (exact label) | Options | Default | Takes effect |
|---|---|---|---|
| `Appearance` | `System` / `Light` / `Dark` | System | Dropped natively: the app follows the system |
| `Weight unit` | `lb` / `kg` (`defaultUnit`) | `lb` | Weights/volume in History, charts, records; "Logged weights stay as entered." |
| `Default rest timer` | menu of `0, 30, 45, 60, 90, 120, 150, 180, 240, 300` seconds, shown `1:30`; the current value is ticked and added if off-list; no Custom item (`defaultRestSeconds`, 0-3600) | 90 s | Exercises with no timer of their own |
| `Weekly goal` | stepper 1-14 (`weeklyGoal`) | 3 | Dashed line on "Workouts per week" |
| `Estimated 1RM formula` | `Epley` / `Brzycki` (`e1rmFormula`) | `epley` | Charts and records ("Brzycki reads higher at low reps.") |
| `Keep screen on during a workout` | toggle (`keepScreenOn`) | on | Holds the screen awake while the workout screen is open (native: idle timer disabled). |
| `Device check` | link to a web diagnostics page | n/a | PWA only; drop |

Native additions: `Download all videos` (`downloadAllVideos`, Wi-Fi only), iCloud status, Import / Export… (the JSON codec), a `#if DEBUG`
Load sample data row. Settings live in `SettingsStore`, not rows.

`restPresets` (up to 6 distinct custom rest durations, 1-3600 s, newest first, the four built-ins never
stored) is a settings key used by the Rest Timer sheet, not shown on this tab. Strong import: PLAN.md 189
lists it under Settings but `SettingsPage.tsx` has no such row. Note IOS.md:116 mentions a "Custom..." item
in the rest menu that `SettingsPage.tsx` does not have (ui.md 240 says there is none).
