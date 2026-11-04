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
- Rest controls: toolbar group = **Skip + +30 s** everywhere (Island, notification, strip, keyboard group); **−10 s / +10 s** only
  inside the running rest sheet. No Repeat workout (Save as Template is the reuse path). Weeks start Monday.

## Data and sync

- SwiftData + CloudKit private database, container `iCloud.com.ericribeiro.Workouts`. Until the Developer Program is approved
  CloudKit runs **off** behind one flag (`ModelConfiguration(cloudKitDatabase: .none)`); the schema is CloudKit-safe from day one.
- Settings live outside SwiftData, in `SettingsStore` (WorkoutsKit, Foundation-only, `@Observable`, injected in the environment so
  unit and formula changes recompute derived numbers; `@AppStorage` alone would not) with a protocol and one key list:
  **`UserDefaults`** now, `NSUbiquitousKeyValueStore` only if a second device appears (7.3). Keys: `defaultUnit`,
  `defaultRestSeconds` (90), `weeklyGoal` (3), `e1rmFormula` (epley), `restPresets`, `keepScreenOn` (true), `downloadAllVideos`
  (false, Wi-Fi only). Appearance follows the system.
- Library: 1,038 exercises bundled as `library.json` + thumbnails (`scripts/build-library`), decoded once into a read-only
  `LibraryCatalog` (`retired` is a flag in the file; display labels ride in it). Custom exercises are `@Model Exercise` rows
  carrying their own unit/bar/rest defaults; `TemplateExercise`/`WorkoutExercise`/`StickyNote` hold `exerciseID: UUID` (the first
  two also an `exerciseName` snapshot), resolved by `ExerciseStore.exercise(id:)` = catalog ∪ custom. RESTRICT applies to custom
  exercises only: deletable when no history references them, otherwise "Archive" (= retire). New rows for a library exercise start
  from Settings (unit, rest) and its weight type (bar). Media: `docs/port/media.md`.
- Migration and backup: one `WorkoutsJSON` document (folders, templates, custom exercises, sticky notes, workouts; exercise ids
  via `LibraryID`) with an idempotent `Importer` (1.7); `scripts/export-web` (Postgres → JSON) runs on this Mac; Settings has
  **Import** and **Export…** (5.7); Eric's export is gitignored in `docs/port/fixtures/`.
- Errors: a failed `ModelContext.save()` is an alert with the message; the draft is never discarded.

## Navigation and layout

- `TabView` with `.tabViewStyle(.sidebarAdaptable)` and `.defaultAdaptableTabBarPlacement(.sidebar)`. Three top-level `Tab`s in
  Eric's order, **History · Workout · Exercises**; **Workout is the default selection**. One `TabSection` per **folder** (header =
  folder name), its templates as `Tab`s with `.tabPlacement(.sidebarOnly)` (never in the compact bar) rendering the template
  preview with Start / Edit; `.sectionActions` carries "New Template". Don't assume where the bar lands.
- **Settings**: a gear `toolbar` button on the Workout tab and `tabViewSidebarBottomBar` on regular width, opening a `Form` sheet.
- **Toolbar items** carry a symbol and a title; the ellipsis belongs to the system's `ToolbarOverflowMenu`, so no `⋯` menus.
  Workout: Settings (`gearshape`), Add (`plus`, a `Menu`: **Empty Workout** / New Template / New Folder); other screens' items
  are in their specs. Row and card actions are `contextMenu` + `swipeActions` only; only content blocks inside the set table
  may keep `ellipsis.circle`. Task screens set `toolbarVerticalCompressionBehavior(.prefersToolbarItems)` and order items
  Close → prominent → state (ring) → actions, since the bottom overflows first: nothing below the ring may be needed mid-set.
- Exercises uses `NavigationSplitView` with no column-width modifiers: the system sizes columns and keeps them off the fold
  (compact → push); the empty detail is a `ContentUnavailableView` (Mail's model). History and Workout are single columns in both
  widths (the sidebar lists templates). The Workout tab is a **card grid** (collapsible folders) with an even column count from
  the grid's own width via `onGeometryChange`, `max(2, 2 * floor(width / (2 * minCard)))`: sidebar open gets 2, full width 4, so
  no card straddles the fold; with `.includeInactive` reserved regions the hinge gap widens. Card tap: compact → medium-detent
  preview sheet (a Maps/Flighty-style panel, fine at phone size); regular → push the preview (zoom transition) so the sidebar
  stays. Beside a visible sidebar the grid drops its folder headers. The folder collapse flag is per-device `@AppStorage` and
  drives only the compact header; the sidebar's `TabSection` expansion is the system's and independent (27.2 `TabSection` has no
  `isExpanded` binding).
- **Sheet placement**: on regular width every sheet names `presentationPlacement`: picker, settings, calendar, custom timer,
  finish summary → `.center`; rest ring → `.trailing` (it belongs to the strip's ring item).
- **Active workout**: one presentation in both widths, a `fullScreenCover` on the root `TabView`, not tied to any tab. Layout
  follows `horizontalSizeClass`: compact → the set table; regular → an `ArrangementView` (iOS 27.1, in SwiftUICore: `import
  SwiftUI` suffices), set table primary, exercise pane (video, instructions, Previous, records, sticky note) secondary, following
  the focused exercise: side by side when wide, stacked when tall, split across the fold when partially open
  (`docs/port/duo-layout.md`). Folding only changes the size class, so draft, focus and scroll are untouched. Minimise is the
  cover's Close-slot item (`Button("Minimise", systemImage: "chevron.down")`) with Finish (`checkmark`, prominent) next: no grab
  handle, drag or tab-tap (a cover has no interactive dismissal, no tab bar). It dismisses the cover; the resume control (and Live
  Activity) restore it; a running workout survives any tab change.
- Minimised workout lives in the system bars, never in a bottom pill (Eric, 2026-11-03: no native app on the Duo has a bottom bar;
  Flighty's trailing strip is the model). One `ToolbarItem` carries it in every width: a ring (custom `ProgressViewStyle`,
  `Circle().trim` fed by `TimelineView`; `ProgressView(timerInterval:)` `.circular` is a spinner on iOS) with
  `Text(timerInterval:)` inside (elapsed time when no rest runs), placed by the system in the trailing strip when closed or
  open-wide and in the top bar when open-tall. It is the resume control (tap restores) and the logging screen's own timer item; no
  `.glassEffect()`. Toolbar items do not inherit on push, so a shared `ViewModifier` applies it on every screen's root. Additive:
  a `tabViewSidebarBottomBar` card (name · elapsed · countdown · Skip) while the sidebar is visible. No `.tabViewBottomAccessory`.
  History and Exercises lists set `tabBarMinimizeBehavior(.onScrollDown)`.
- `AppNavigation` (@Observable, WorkoutsKit) with typed routes, so Live Activity buttons and notification actions can open the
  logging screen or a template. App Intents exist only behind those buttons (no Shortcuts or Spotlight).

## Active workout behaviour

- Start from a template or **Empty Workout** (Workout tab → Add; name "Workout"); exactly one in progress. Finish summary is a
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
  over total) whose −10 s / +10 s / Skip are a horizontal `ToolbarItemGroup` placed by the system. While a rest runs the logging
  toolbar gains a `ToolbarItemGroup` of **Skip** (`forward.end`) and **+30 s** (`goforward.30`) below the ring, stacked like
  Flighty's map tool group; the keyboard `ToolbarItemGroup` prepends the countdown, Skip and +30 s. No `safeAreaBar`, no bottom
  glass.
- Keyboard: system `.decimalPad` with a keyboard `ToolbarItemGroup` (−step, +step, Previous, Done) and a Next that advances weight
  → reps → next row; steps from the web. It covers half the closed screen, so Next is the mitigation; custom keypad only if this
  proves worse. The exercise pane follows the **focused exercise**: the last focused cell's or tapped header's exercise, else the
  first with an unchecked set.
- **SetTable** (`Workouts/Features/Shared/SetTable`, 2.2–2.3): one component, three modes (template / active / past).
  `isIdleTimerDisabled` while logging when `keepScreenOn`.

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
  becomes semantic asset-catalog colours (accent, ok, danger, warm-up, set-kind), light/dark; everything else is system material.
- **Accessibility**: every interactive element labelled (agents and XCUITests navigate by the tree); Dynamic Type everywhere; at
  AX sizes each set row becomes a two-line stack via `ViewThatFits`.
- **Natural-language search is in-app only** (Eric, 2026-11-03; PLAN 4.6). The on-device Foundation Models model
  (`SystemLanguageModel.default`, `@Generable` → kit `ExerciseQuery`) turns a sentence typed into the Exercises/picker search field
  into body-part/category/equipment/word filters, and only when plain all-words search finds nothing. Additive by design: model
  unavailable (ineligible device, Apple Intelligence off, model not ready) or any error means the field is the plain search, silently.
  **No Siri route**: Siri AI reaches an app through App Intents entities indexed with `IndexedEntity`/Spotlight under an assistant
  schema, there is no fitness/exercise schema (WWDC26 lists messages, mail, photos), its third-party availability is still unclear,
  and App Intents here stay behind the Live Activity buttons. Revisit only if Apple ships a fitness schema.

## Duo rules (distilled in `docs/port/duo-layout.md`, also `AGENTS.md`): size classes and the system's bars, never breakpoints or fixed widths.

- Size classes only (never `UIScreen.main`, idiom, orientation or hardcoded sizes); width changes mid-session and the app keeps
  selection, scroll and the active workout. Asymmetric safe areas are normal (`.safeAreaInset`, no magic numbers). All four
  orientations; hinge APIs drive the half-open **bench mode** (6.1); poses and scenarios are verified per 6.2 (`verify-ui`).
- **Web keeps that are fine** (not re-litigated): tab set and order; set-table columns, Previous autofill, Add Set row; cards by
  fill; large titles; `ContentUnavailableView` empty details; segmented About / History / Charts / Records; chip row; calendar
  sheet; `confirmationDialog` copy; `fullScreenCover` logging with the ring item as resume control.
