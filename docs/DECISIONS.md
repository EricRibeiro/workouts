# Workouts: settled decisions

These are the technical and product decisions for the native app, settled 2026-11-03, and they are not to be re-litigated. The earlier product decisions live in `AGENTS.md` → Product decisions; the roadmap is `docs/PLAN.md`. New decisions are appended here with an absolute date.

Eric deferred the technical choices to Claude. These close every item in `docs/port/OPEN-QUESTIONS.md`.

## Recorded from the final review (2026-11-03; `plan-review-2026-11-03-final.md`; not to be re-litigated)

- **Library is a bundled catalog, not synced rows** (finding 2): no seeding, `ExerciseOverride`, `LibraryMeta` or
  `libraryVersion`; only custom exercises are `@Model` rows.
- **The JSON codec comes first** (finding 3): `WorkoutsJSON` (1.7) is the sample data, the import of Eric's 615 workouts now, and
  the backup (Export…); with CloudKit off the phone's store is the only copy.
- **A proof never depends on a tool's mood** (finding 5): the Xcode MCP is optional; the proof of record is the `-preview` gallery
  (`./dev run -- -preview <Name>` + `./dev screenshot`) and XCUITests (`./dev ui-test`).
- **History is a `NavigationStack` in both widths** (finding 7); only Exercises keeps `NavigationSplitView`.
- Rest controls: **Skip + +30 s** everywhere (Island, notification, keyboard group, and the one place per context in "Visual language"); **−10 s / +10 s** only
  inside the running rest sheet. No Repeat workout (Save as Template is the reuse path). Weeks start Monday.

## Data and sync

- SwiftData + CloudKit private database, container `iCloud.com.ericribeiro.Workouts`, **on** since 8.1 (2026-11-08) behind one
  flag (`WorkoutsApp.cloudKitEnabled` → `ModelConfiguration(cloudKitDatabase: .automatic)`); in-memory stores (tests, previews,
  `-uiTesting`) always resolve to `.none` (`CloudKitChoice`). Sync needs `aps-environment` and the `remote-notification`
  background mode; the Production schema is deployed by hand from Development (`docs/cloudkit.md`). The schema is CloudKit-safe
  from day one.
- Two in-progress workouts across devices: the newest-started one is shown, an older one untouched for 6 h is settled (finished at
  its last completed set, or deleted when empty), a recently updated one is left running on its device (`InProgressResolution`).
- Settings live outside SwiftData, in `SettingsStore` (WorkoutsKit, Foundation-only, `@Observable`, injected in the environment so
  unit and formula changes recompute derived numbers; `@AppStorage` alone would not) with a protocol and one key list:
  **`UserDefaults`** now, `NSUbiquitousKeyValueStore` only if a second device appears (8.2). Keys: `defaultUnit`,
  `defaultRestSeconds` (90), `weeklyGoal` (3), `e1rmFormula` (epley), `restPresets`, `keepScreenOn` (true), `downloadAllVideos`
  (false, Wi-Fi only). No appearance key: the app is dark-only.
- Library: 1,038 exercises bundled as `library.json` + thumbnails (`scripts/build-library`), decoded once into a read-only
  `LibraryCatalog` (`retired` is a flag in the file; display labels ride in it). Custom exercises are `@Model Exercise` rows
  carrying their own unit/bar/rest defaults; `TemplateExercise`/`WorkoutExercise` hold `exerciseID: UUID` (and an `exerciseName`
  snapshot), resolved by `ExerciseStore.exercise(id:)` = catalog ∪ custom. RESTRICT applies to custom
  exercises only: deletable when no history references them, otherwise "Archive" (= retire). New rows for a library exercise start
  from Settings (unit, rest) and its weight type (bar). Media: `docs/port/media.md`.
- Migration and backup: one `WorkoutsJSON` document (folders, templates, custom exercises, workouts; exercise ids
  via `LibraryID`) with an idempotent `Importer` (1.7); `scripts/export-web` (Postgres → JSON) runs on this Mac; Settings has
  **Import** and **Export…** (5.7); Eric's export is gitignored in `docs/port/fixtures/`.
- Schema changes: `OnDiskStoreMigrationTests` (kit) opens a committed on-disk V1 store (`Tests/WorkoutsKitTests/Fixtures/store-v1/`)
  with `WorkoutsMigrationPlan` and checks counts and field values. Any model change must keep it green. A change SwiftData cannot
  infer (rename, type change, new required attribute without a default, a new enum case in a stored attribute) needs a new
  `VersionedSchema` plus a migration stage; never regenerate the fixture to silence the test (P-03, 2026-11-07).
- Errors: a failed `ModelContext.save()` is an alert with the message; the draft is never discarded.

## Navigation and layout

- **No app sidebar** (JC52, Eric 2026-11-04). A plain `TabView` (no `.sidebarAdaptable`, no `defaultTabBarPlacement`): the tabs
  stay in the system tab bar, which is the trailing strip on the Duo in every pose. Three top-level `Tab`s in Eric's order,
  **History · Workout · Exercises**; **Workout is the default selection**. Templates live on the Workout tab's card grid only
  (the 3.7 sidebar `TabSection`s, their `.sidebarOnly` tabs and the sidebar resume card were removed). Never assume where the
  bar lands.
- **Settings**: the gear `toolbar` button on every tab (Workout, History, Exercises), in every pose, opening a `Form` sheet (judgment-calls.md: Settings moved from the sidebar bottom bar to the toolbar everywhere).
- **Toolbar items** carry a symbol and a title; the ellipsis belongs to the system's `ToolbarOverflowMenu`, so no `⋯` menus.
  Workout: Settings (`gearshape`), Add (`plus`, a `Menu`: **Empty Workout** / New Template / New Folder); other screens' items
  are in their specs. Row and card actions are `contextMenu` + `swipeActions` only, except the template card's play button ("Visual language");
  only content blocks inside the set table may keep `ellipsis.circle`. Task screens set `toolbarVerticalCompressionBehavior(.prefersToolbarItems)` and order items
  Close → prominent → state (ring) → actions, since the bottom overflows first: nothing below the ring may be needed mid-set.
- Exercises uses `NavigationSplitView(columnVisibility: .all)` with `.balanced` and no column-width modifiers: on regular width the
  list is a **permanent** pane beside the detail (never behind a toggle; JC52); the system keeps columns off the fold (compact
  -> push); the empty detail is a `ContentUnavailableView` ("Select an Exercise"). History and Workout are single columns in both
  widths. The Workout tab is a **card grid** (collapsible folders) with an even column count from the grid's own width via
  `onGeometryChange`, `max(2, 2 * floor(width / (2 * minCard)))`, so no card straddles the fold; with `.includeInactive`
  reserved regions the hinge gap widens. Card tap: compact -> medium-detent preview sheet (a Maps/Flighty-style panel, fine at
  phone size); regular -> push the preview (zoom transition). The grid's folder headers always show. The folder collapse flag
  is per-device `@AppStorage`.
- **Sheet placement**: on regular width every sheet names `presentationPlacement`: picker, settings, calendar, custom timer,
  finish summary → `.center`; rest ring → `.trailing` (it belongs to the strip's ring item).
- **Active workout**: one presentation in both widths, a `fullScreenCover` on the root `TabView`, not tied to any tab. Layout
  follows `horizontalSizeClass`: compact → the set table; regular → an `ArrangementView` (iOS 27.1, in SwiftUICore: `import
  SwiftUI` suffices), set table primary, exercise pane (video, instructions, Previous, records) secondary, following
  the focused exercise: side by side when wide, stacked when tall, split across the fold when partially open
  (`docs/port/duo-layout.md`). Folding only changes the size class, so draft, focus and scroll are untouched. Minimise is the
  cover's Close-slot item (`Button("Minimise", systemImage: "chevron.down")`) with Finish (`flag.checkered`, prominent) next: no grab
  handle, drag or tab-tap (a cover has no interactive dismissal, no tab bar). It dismisses the cover; the resume control (and Live
  Activity) restore it; a running workout survives any tab change.
- Minimised workout lives in the system bars, never in a bottom pill (Eric, 2026-11-03: no native app on the Duo has a bottom bar;
  Flighty's trailing strip is the model). One `ToolbarItem` carries it in every width: a ring (custom `ProgressViewStyle`,
  `Circle().trim` fed by `TimelineView`; `ProgressView(timerInterval:)` `.circular` is a spinner on iOS) with
  `Text(timerInterval:)` inside (elapsed time when no rest runs), placed by the system. **Measured 2026-11-03 (27.2):** the
  system stacks only symbol/`Image` `Label` items in the trailing strip (a custom-view item stays in the top bar; no public API
  moves it). So the running ring item is a `Label` whose icon is a thin draining arc drawn with `Image(size:renderer:)` (Eric:
  like Claude's context indicator), no digits; the countdown is in its accessibility label ("Rest timer, 4:57"), the rest
  sheet, the keyboard group and the Live Activity. The strip renders it as a template (foreground colour, no tinted track). It is the resume control (tap restores) and the logging screen's own timer item; no
  `.glassEffect()`. Toolbar items do not inherit on push, so a shared `ViewModifier` applies it on every screen's root. Additive: while a rest runs, the Skip / +30 s group sits beside it ("Visual language"); nothing else (no sidebar card, JC52). No `.tabViewBottomAccessory`.
  History and Exercises lists set `tabBarMinimizeBehavior(.onScrollDown)`.
- `AppNavigation` (@Observable, WorkoutsKit) with typed routes, so Live Activity buttons and notification actions can open the
  logging screen or a template. App Intents exist only behind those buttons (no Shortcuts or Spotlight).

## Active workout behaviour

- Start from a template (the card's play button, or Start Workout in its preview) or **Empty Workout** (Workout tab → Add; name "Workout"); exactly one in progress. Finish summary is a
  centred sheet with a **PR count** (native improvement; `prsInSession` exists): Done is its Close-slot item, nothing
  bottom-anchored (`active-workout.md` §3).
- Web rules kept verbatim (`docs/port/screens/active-workout.md`): check → rest starts (superset too, on every check), presets
  0:30/1:00/2:00/3:00 + up to 6 customs (1–3600 s, no repeats), empty sets cannot be checked, Finish dialogs, Discard
  confirmation, Previous autofill, warm-up ramp, supersets numbering. No RPE UI (field kept in the model). Previous autofill
  across units: the previous entry in kg and the row in lb (or the reverse) converts and rounds to 0.5. Duplicate gives "<name>
  copy". The editor draft does not survive relaunch; a running workout does.
- Rest end: local `.timeSensitive` notification, body "Rest over · Set 3 · 27.5 lb × 8" (next set included), actions **Skip** and
  **+30 s**; in foreground `willPresent` returns `[]` and the app plays haptic + flash. Dynamic Island only while closed (the
  inner camera is under the display): open and backgrounded, the Lock Screen presentation and the notification are the only
  signals.
- Timer correctness: render with `Text(timerInterval:)` from `restEndsAt`, never a counter; rest state persists on the in-progress
  `Workout` (`restEndsAt`, `restSeconds`, `restSetID`).
- Rest UI: the controls live in the bars. The ring `ToolbarItem` is idle: a stopwatch `Menu`: 0:30 / 1:00 / 2:00 / 3:00, a
  divider, saved customs (newest first), "Custom…" opening a small sheet with two `Picker` wheels (min / sec; SwiftUI has no
  countdown `DatePicker`) and a Start toolbar item; running: the countdown, opening the expanded sheet (Clock's ring, remaining
  over total) whose −10 s / +10 s / Skip are a horizontal `ToolbarItemGroup` placed by the system. Skip and +30 s sit in one place per context
  ("Visual language": the inline row for a set's rest, a `ToolbarItemGroup` of `forward.end` and `goforward.30` for a rest started
  by hand and beside the minimised ring); the keyboard `ToolbarItemGroup` prepends the countdown, Skip and +30 s. No `safeAreaBar`, no bottom
  glass.
- Keyboard: system `.decimalPad` with a keyboard `ToolbarItemGroup` (−step, +step, Previous, Done) and a Next that advances weight
  → reps → next row; steps from the web. It covers half the closed screen, so Next is the mitigation; custom keypad only if this
  proves worse. Checking a set dismisses the keyboard (Eric, 2026-11-07). The exercise pane follows the **focused exercise**: the last focused cell's or tapped header's exercise, else the
  first with an unchecked set.
- **SetTable** (`Workouts/Features/Shared/SetTable`, 2.2–2.3): one component, three modes (template / active / past).
  `isIdleTimerDisabled` while logging when `keepScreenOn`.
  - Timed rows: a library exercise tagged `isometric` is timed from its first set (`ExerciseInfo.isTimed`; the engine's
    `timedByDefault` lookup; `TemplateDraft.add`); a timed row of a non-strength weight type has no weight column (JC120).
  - Note row: the block note line is at least 44 pt tall, text vertically centred, button or not (Eric, 2026-11-07; JC112). Block notes
    are the only note kind; sticky notes were removed (JC118).

## Native layer

- **Live Activity** (`WorkoutsLiveActivity` extension; `NSSupportsLiveActivities`). `swift test` builds the kit for macOS, where
  `ActivityAttributes` and `LiveActivityIntent` are unavailable, so state stays in the kit and conformances in the app.
  `WorkoutActivityState` (kit, Codable,
  Sendable): exercise name, set index/count, next-set text, `startedAt`, `restEndsAt?`. Lock screen + expanded Island: exercise,
  "Set 3 of 4", rest countdown `Text(timerInterval:)` or elapsed time when no rest runs; buttons `Button(intent:)` **Skip** /
  **+30 s** / **Done set**, `LiveActivityIntent`s that run in the app process. Compact: exercise glyph + countdown; minimal:
  `ProgressView(timerInterval:)` ring (drawn by the system). `staleDate = restEndsAt`, `relevanceScore` 1 while resting. Request
  on start, update on every check/skip/adjust, `end(dismissalPolicy: .immediate)` on Finish/Discard. Suspended (no push server) it
  cannot flip to "rest over": 0:00 is the only in-Island signal, the notification the alarm. `WorkoutActivityAttributes:
  ActivityAttributes` wraps the state and lives in `Shared/`, a synced folder in both the app and the extension target.
- **Haptics** via `.sensoryFeedback`: check `.impact(weight: .light)`, rest end `.success`, PR `.levelChange`, destructive
  confirm `.warning`, minimise/restore `.selection`.
- **Liquid Glass**: system bars and controls; no hand-placed `.glassEffect()` (nothing floats over content);
  `.navigationTransition(.zoom(sourceID:in:))` + `.matchedTransitionSource(id:in:)` on card/row → preview/detail. Eric's palette
  is semantic asset-catalog colours, one dark value each ("Visual language"); everything else is system material.
- **Accessibility**: every interactive element labelled (agents and XCUITests navigate by the tree); Dynamic Type everywhere; at
  AX sizes each set row becomes a two-line stack via `ViewThatFits`.
- **Natural-language search is in-app only** (Eric, 2026-11-03; PLAN 4.6). The on-device Foundation Models model
  (`SystemLanguageModel.default`, `@Generable` → kit `ExerciseQuery`) turns a sentence typed into the Exercises/picker search field
  into body-part/category/equipment/word filters, and only when plain all-words search finds nothing. Additive by design: model
  unavailable (ineligible device, Apple Intelligence off, model not ready) or any error means the field is the plain search, silently.
  **No Siri route**: Siri AI reaches an app through App Intents entities indexed with `IndexedEntity`/Spotlight under an assistant
  schema, there is no fitness/exercise schema (WWDC26 lists messages, mail, photos), its third-party availability is still unclear,
  and App Intents here stay behind the Live Activity buttons. Revisit only if Apple ships a fitness schema.

- **Duo poses are set by `Tools/duo` (private HID hinge event, verified by documented reads)** (Eric, 2026-11-05; formerly a
  pinned third-party wrapper; `docs/plan-device-tool.md`). The simulator has no documented API to fold or rotate the Duo
  (`devicectl device orientation set` is acknowledged and ignored), so `Tools/duo` (SwiftPM, no dependencies, Swift) sends the vendor
  HID event Xcode's Device Hub sends, from a small helper compiled for the simulator and run with `simctl spawn`. The private pieces
  are only that event and CoreMotion's `CMAngleManager` hinge read; every pose is then proved with documented reads
  (`devicectl` orientation and display table, the lit panel) so an Xcode change fails loudly as "pose not reached" instead of
  producing a wrong screenshot. Stateless, so `./dev`'s per-simulator lock is the only serialisation. The tool and the
  Fold.m-derived parts carry the upstream MIT notice (`THIRD-PARTY-NOTICES.md`). `./dev check` runs its tests.

## Duo rules (distilled in `docs/port/duo-layout.md`, also `AGENTS.md`): size classes and the system's bars, never breakpoints or fixed widths.

- Size classes only (never `UIScreen.main`, idiom, orientation or hardcoded sizes); width changes mid-session and the app keeps
  selection, scroll and the active workout. Asymmetric safe areas are normal (`.safeAreaInset`, no magic numbers). All four
  orientations; hinge APIs drive the half-open **bench mode** (6.1); poses and scenarios are verified per 6.2 (`verify-ui`).
- **Web keeps that are fine** (not re-litigated): tab set and order; set-table columns, Previous autofill, Add Set row; cards by
  fill; large titles; `ContentUnavailableView` empty details; segmented About / History / Charts / Records; chip row; calendar
  sheet; `confirmationDialog` copy; `fullScreenCover` logging with the ring item as resume control.

## Design review (2026-11-03)

- **No design plugin; one repo-local skill.** Eric asked whether [impeccable](https://github.com/pbakaus/impeccable)
  (Apache 2.0) and [Design with Intent](https://designwithintent.ai) (CC0) should steer the UI. Neither is installed. Impeccable's
  detector, hooks, `live`/`generate` and `craft-floor` read and judge web markup (JSX/HTML/CSS; its hook never fires on `.swift`),
  it runs a downloaded binary at setup, and its bans (cards, progress rings, hero metrics, system display faces) contradict the
  Fitness-style cards, the ring item and SF that DECISIONS settles; its `PRODUCT.md`/`DESIGN.md` would duplicate `AGENTS.md`
  and this file. Intent is a UX-process system (research, IA, service blueprints, HEART, dark-pattern catalog) for teams and
  products with users to persuade; this is a private single-user app whose copy and flows are decided. What transfers (the iOS
  slop test, a scored native audit, the cognitive-load rule, polish triage, the state inventory) is distilled into
  `.claude/skills/design-review`, ~8 KB per worker instead of 45 KB+ references. **HIG and this file remain the authority**;
  a review never re-litigates a settled heading and never proposes custom chrome.
- **A review is a phase gate, read-only** (PLAN 2.11, 3.8, 4.7, 5.8): findings P0–P3 with the fix classified (token / shared
  component / conceptual / local), P0–P2 become worker tasks, taste rows become one batched question to Eric. Accessibility
  audits stay with Apple's `accessibility-*` skills (6.3); poses stay with `verify-ui` (6.2).

## Visual language: lime, dark-only (2026-11-10)

- **Dark-only** (Eric, 2026-11-10). `INFOPLIST_KEY_UIUserInterfaceStyle = Dark` on the app target; there is no Appearance
  setting, no `preferredColorScheme` and no light variant of a colour, snapshot or UI test (variants: `large-dark`,
  `ax3-dark`). The system still draws its own surfaces: the Lock Screen Live Activity follows the phone's appearance, so the
  extension keeps adaptive colours (`ActivityStyle`) and never reads the app's single-valued colour sets.
  `./dev ui-env appearance` changes the simulator, not the app.
- **Colour roles.** One accent, lime `#C4F861` (`AccentColor`, `.tint`, `Color.ok`), on black and system fills.
  - *Lime fill, black content* (`Color.onAccent`): the actions that start or end a session and the completion mark (the
    card's play disc, Start Workout, Finish, New Template, the summary's check). Nothing else is a lime fill.
  - *Lime text or stroke*: the one value that matters on a surface (a History row's volume, the dashboard's "1 / 3", chart
    bars at the goal), the next set's ring, the rest row's bar and controls, a done set's check.
  - *Dark olive* `#1B2A0A` (`Color.okRow`): the row behind a done set. A week under the goal is the accent at 0.35 alpha
    (`Color.chartBelowGoal`).
  - *Gold* (`Color.record`): personal records only, always with `trophy.fill`. Set-kind and superset colours are unchanged
    and stay distinct from lime.
  - Everything else is `.primary` / `.secondary` on `.fill.*` styles; card titles are plain `.headline`, untinted, no glyph.
  - Metrics are set Fitness-style by `MetricText` (kit `MetricPieces`): rounded medium digits, the unit in small caps glued
    to the number, in the value's colour. The Finish summary's stats are white metrics, and its PR count is gold when the
    workout set a record.
- **Set-row states** (active workout; `SetRow`, `SetProgress.nextIndex` over the rows that show a check):
  - *Done*: olive row, values as plain text (no field fill), a quiet lime disc (`ok` at 0.18) with a lime check.
  - *Next* (the block's first unchecked set): a raised row (`.fill.secondary` at 0.5), brighter fields (`.fill.tertiary`),
    an empty 3 pt lime ring. It is the strongest mark in the column.
  - *Pending*: no row fill, `.fill.quaternary` fields, an empty 2 pt `.secondary` ring.
  - An unchecked set never shows a check glyph. A refused check gets the red border, the announcement and a short shake,
    which Reduce Motion drops. The Previous cell omits the unit (`60 × 8`; the column header and the accessibility label
    carry it). The block header is the name (one line, two at accessibility sizes), its chevron and a `.secondary`
    `ellipsis.circle`: no thumbnail, no progress line. Add Set is a full-width quiet row.
- **Rest controls sit in one place per context** (Eric, 2026-11-10):
  - *A set's rest* (started by a check): an inline row directly under that set (`RestTimerRow`: `timer`, the countdown, a
    draining bar that accessibility sizes drop, **+30**, **Skip**; `rest.row.*`). It leaves at `endsAt`, without waiting for
    the engine's grace. The logging toolbar shows the ring alone.
  - *A rest started by hand* (the ring's menu; no `setID`): the logging toolbar's **Skip** / **+30 s** group
    (`RestToolbarGroup`, `rest.toolbar.*`).
  - *Minimised*: the same group beside the resume ring on every tab root while a rest runs, its grace included
    (`resume.rest.*`), so a rest is skipped or extended without reopening the cover.
  - The ring's expanded sheet, the keyboard group, the notification actions and the Live Activity buttons apply to every rest.
- **One-tap start** (Eric, 2026-11-10). Each template card carries a lime play disc (36 pt scaled, 44 pt target, trailing on
  the name's first line; under the name at accessibility sizes) that starts the workout through the same `StartWorkoutFlow`
  as the preview's Start Workout, so a running workout raises "Workout in progress" first. It is a sibling overlay of the
  card button (a button cannot nest in a button), labelled "Start <name>" (`template.<uuid>.start`), disabled for a template
  with no exercises. The card's footer is the recency alone ("Yesterday", `.footnote`, `.primary`; none for a template never
  performed, "No exercises" in `.secondary` for an empty one); the exercise count is in its VoiceOver label. The play disc is
  the only visible action on a card; the others stay in the `contextMenu`. Tapping the card still
  opens the preview. A mis-tap costs a Discard, never data.
- **History dashboard order and the hero** (Eric, 2026-11-10). The page opens with the This Week hero, then the weekly chart,
  then Recent PRs and Last Workout; at regular width the left column is hero then chart, the right Recent PRs then Last
  Workout. The hero is the done count as the big lime figure beside "of 3 workouts", one equal-width capsule per goal
  workout under it (lime done, `.fill.tertiary` the rest, decorative), then Volume and Time as white `MetricText` over a
  "avg" line, the mean of the four weeks before this one (shown only with history; the two metrics stack at accessibility
  sizes). The Fitness lines stay below. The accessibility sentence appends the four-week averages.
- **Finish** is `flag.checkered` (prominent, lime): the checkmark belongs to sets.

## Pushed-screen chrome (2026-11-07)

- **Chrome sits on the outermost view and never waits for data** (Eric / Fable test-gap review,
  `docs/reviews/2026-11-07-test-gaps.md` section 3 item 7): on a pushed screen, `navigationTitle`, `toolbar` and
  `searchable` are attached to the outermost view and take values available synchronously (the `@Query` row, the pushed id),
  never inside a loaded-state branch. A button that needs the loaded value is disabled until it arrives; it is not
  omitted. Loading is a named state that is rendered (a placeholder body under the final chrome), not a blank frame, so
  the title and bars do not pop in after the push. Reference: `WorkoutDetailView` (fix `f1be1bd`, "History detail: title
  and toolbar from the first frame of the push"). Proven by the first-frame UI checks and loading-frame snapshots (PLAN 7b.4, 7b.5).
