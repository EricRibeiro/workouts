# Workouts: the native plan

The document Eric and the orchestrating agent (Opus) work from; a living file: tick tasks, record decisions in section 2,
never re-litigate what is settled here or in `AGENTS.md`. Written 2026-11-03 by Fable after the scaffold, the port spec and the
`WorkoutsKit` math landed; reviewed the same day (rationale in `docs/plan-review-2026-11-03.md`, `-duo.md`, `-bias.md`,
`-final.md`).

Orchestrator: read `AGENTS.md` first (toolchain, loop, rules), then section 6 to find the next unticked task. Each task is sized
for one Sonnet worker, names what it **Needs** (never dispatch it before those are ticked) and its proving command.

## 1. Goal

A private, single-user, native SwiftUI iPhone app that keeps the web app's curated workout-tracking experience (feature
complete, Eric-designed, "awesome") and adds what a PWA cannot do on the **iPhone Duo**: a real sidebar on the inner
display, split layouts, Live Activity + Dynamic Island for the rest timer, notifications, haptics. Parity is the floor.
Not goals: App Store release, other users, iPad/Mac, widgets, Shortcuts, Control Center, HealthKit/Apple Fitness (Eric
starts his Fitness workouts in Apple's app himself), Apple Watch, the web app, multi-window and keyboard shortcuts (one
scene; no `UIApplicationSupportsMultipleScenes`), localisation (English only: `Text("…")` literals, no catalog upkeep,
no `String(localized:)` in the kit).

## 2. Decisions (settled; see `AGENTS.md` → Product decisions for the ones made earlier)

Eric deferred the technical choices to Claude. These close every item in `docs/port/OPEN-QUESTIONS.md`.

**Recorded from the final review (2026-11-03; `plan-review-2026-11-03-final.md`; not to be re-litigated)**
- **Library is a bundled catalog, not synced rows** (finding 2): no seeding, `ExerciseOverride`, `LibraryMeta` or
  `libraryVersion`; only custom exercises are `@Model` rows.
- **The JSON codec comes first** (finding 3): `WorkoutsJSON` (1.7) is the sample data, the import of Eric's 615 workouts now, and
  the backup (Export…); with CloudKit off the phone's store is the only copy.
- **A proof never depends on a tool's mood** (finding 5): the Xcode MCP is optional; the proof of record is the `-preview` gallery
  (`./dev run -- -preview <Name>` + `./dev screenshot`) and XCUITests (`./dev ui-test`).
- **History is a `NavigationStack` in both widths** (finding 7); only Exercises keeps `NavigationSplitView`.
- Rest controls: toolbar group = **Skip + +30 s** everywhere (Island, notification, strip, keyboard group); **−10 s / +10 s** only
  inside the running rest sheet. No Repeat workout (Save as Template is the reuse path). Weeks start Monday.

**Data and sync**
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

**Navigation and layout**
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

**Active workout behaviour**
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

**Native layer**
- **Live Activity** (`WorkoutsLiveActivity` extension; `NSSupportsLiveActivities`). `swift test` builds the kit for macOS, where
  `ActivityAttributes` and `LiveActivityIntent` are unavailable, so state stays in the kit and conformances in the app.
  `WorkoutActivityState` (kit, Codable,
  Sendable): exercise name, set index/count, next-set text, `startedAt`, `restEndsAt?`. Lock screen + expanded Island: exercise,
  "Set 3 of 4", rest countdown `Text(timerInterval:)` or elapsed time when no rest runs; buttons `Button(intent:)` **Skip** /
  **+30 s** / **Done set**, `LiveActivityIntent`s that run in the app process. Compact: exercise glyph + countdown; minimal:
  `ProgressView(timerInterval:)` ring (drawn by the system). `staleDate = restEndsAt`, `relevanceScore` 1 while resting. Request
  on start, update on every check/skip/adjust, `end(dismissalPolicy: .immediate)` on Finish/Discard. Suspended (no push server) it
  cannot flip to "rest over": 0:00 is the only in-Island signal, the notification the alarm. `WorkoutActivityAttributes:
  ActivityAttributes` wraps the state and lives in the app (also a member of the extension target).
- **Haptics** via `.sensoryFeedback`: check `.impact(weight: .light)`, rest end `.success`, PR `.levelChange`, destructive
  confirm `.warning`, minimise/restore `.selection`.
- **Liquid Glass**: system bars and controls; no hand-placed `.glassEffect()` (nothing floats over content);
  `.navigationTransition(.zoom(sourceID:in:))` + `.matchedTransitionSource(id:in:)` on card/row → preview/detail. Eric's palette
  becomes semantic asset-catalog colours (accent, ok, danger, warm-up, set-kind), light/dark; everything else is system material.
- **Accessibility**: every interactive element labelled (agents and XCUITests navigate by the tree); Dynamic Type everywhere; at
  AX sizes each set row becomes a two-line stack via `ViewThatFits`.

**Duo rules (distilled in `docs/port/duo-layout.md`, also `AGENTS.md`): size classes and the system's bars, never
breakpoints or fixed widths.**
- Size classes only (never `UIScreen.main`, idiom, orientation or hardcoded sizes); width changes mid-session and the app keeps
  selection, scroll and the active workout. Asymmetric safe areas are normal (`.safeAreaInset`, no magic numbers). All four
  orientations; hinge APIs drive the half-open **bench mode** (6.1); poses and scenarios are verified per 6.2 (`verify-ui`).
- **Web keeps that are fine** (not re-litigated): tab set and order; set-table columns, Previous autofill, Add Set row; cards by
  fill; large titles; `ContentUnavailableView` empty details; segmented About / History / Charts / Records; chip row; calendar
  sheet; `confirmationDialog` copy; `fullScreenCover` logging with the ring item as resume control.

## 3. Experience, screen by screen (what "awesome" means here)

- **Workout tab**: large title; Add menu (Empty Workout / New Template / New Folder); folder sections with the card grid; cards in
  Fitness's shape: title row with `chevron.right`, headline = exercise count ("7 exercises"), caption = first exercises, footnote
  "Last performed · 5 days ago". Tap → the preview (§2): Close (`xmark`), Edit (`pencil`) in the strip; the title, "Last
  performed", a `.borderedProminent` **Start Workout** (`play.fill`) capsule directly under it (Flighty's `+ Add Friend`), then
  rows with an `info.circle` peek; nothing is bottom-anchored. The editor is pushed in both widths; on regular its body is the
  logging screen's `ArrangementView` (2.10), so the table never straddles the fold.
- **History tab**: a Fitness-style dashboard in a `NavigationStack`: large title; hero card = the weekly goal chart (full width,
  plain header: the goal lives in Settings only); then even-column cards from the grid's own width: This Week (count vs goal),
  Recent PRs (trophy list), Last Workout (name · duration · volume); then month `Section`s of workout rows (name, date, duration ·
  volume · PRs, trophy). Rows push the detail (zoom transition, both widths) holding PR lines, trophies and the per-exercise
  Exercise | Best Set table. `.searchable` over workout and exercise names with `searchScopes` (All · PRs). Saving a template
  gives `sensoryFeedback(.success)` and the sheet dismissing, no banner. Which cards: ask Eric.
- **Exercises tab**: `.searchable` only, body part and category as two `Menu` pills, no sort control, **no A-Z rail**; rows with
  thumbnail + latest best set and tags; detail with segmented About / History / Charts / Records, video loop at the top
  (`.backgroundExtensionEffect()`), sticky note editable here too.
- **Settings sheet**: `docs/port/screens/history.md` §8, plus Import / Export…, `#if DEBUG` Load sample data, iCloud status.

## 4. Architecture

```
Workouts.xcodeproj
├─ Workouts/                 app target (SwiftUI shell + features)
│  ├─ App/                   WorkoutsApp, ModelContainer setup, Intents/ (LiveActivityIntents), Activity/ (attributes)
│  ├─ Design/                Colours (asset catalog), typography helpers, ring toolbar item, haptics map
│  ├─ Features/{Shared,Workout,ActiveWorkout,History,Exercises,Settings}/   views + view models (@Observable)
│  ├─ Debug/                 PreviewGallery (#if DEBUG, launch argument -preview <Name>)
│  └─ Resources/Library/     library.json + thumbs/ (generated, committed; ~25 MB)
├─ WorkoutsLiveActivity/     widget extension holding only the Live Activity views
├─ Packages/WorkoutsKit/     platform-free, must compile for macOS: Model (@Model types), Math (done), Library
│                            (LibraryCatalog, ExerciseStore, LibraryID), Settings, Navigation, Media, Session
│                            (ActiveWorkoutEngine, RestTimer), Activity (WorkoutActivityState), WorkoutsJSON, Sample
└─ scripts/                  build-library (snapshot → library.json + thumbs), export-web (Postgres → JSON); run on this Mac
```

- **SwiftData models** (`docs/port/data-model.md`, CloudKit-safe, nine `@Model` types): relationships optional with explicit
  `deleteRule` (RESTRICT on custom exercises becomes an app check), every property defaulted, enums as raw strings, `Double`
  weights, no `.unique`. `Workout.finishedAt == nil` marks the one in-progress workout; every query excludes it (`#Predicate`).
  Positions are Ints.
- **ActiveWorkoutEngine** (WorkoutsKit, `@Observable`, `@MainActor`): owns the in-progress `Workout`:
  check/uncheck/add/replace/remove/reorder, Previous lookup, warm-up ramp, rest timer state (one `adjust(by:)` op),
  finish/discard, and `checkCount` / `restEndCount` counters that views turn into `.sensoryFeedback` triggers. The Live Activity
  only renders the `WorkoutActivityState` it pushes. `LiveActivityIntent.perform()` runs in the app process and is nonisolated:
  the intents (`nonisolated struct`s in `Workouts/App/Intents/`, members of both targets) `await MainActor.run` into the engine
  through a launch-registered dependency, and the engine first resumes the persisted workout (no shared store, no App Group).
- **Testing**: `./dev kit` for all WorkoutsKit logic (SwiftData in memory works on macOS; anything importing ActivityKit, UIKit,
  WidgetKit or the Live Activity AppIntents types stays in the app), `./dev test` for the few app-level tests, `./dev ui-test` for
  flows, the `-preview` gallery for screens.

## 5. Agentic workflow for this project

- **One worker, one task, one proving command**; a worker reporting two features means split next time. **Order of proof**: `./dev
  kit <filter>` → `./dev build` → preview (`./dev run -- -preview <Name>` + `./dev screenshot`; MCP `RenderPreview` is a bonus) →
  `./dev test` → flow (an XCUITest, `./dev ui-test Suite/test()`) → the four poses before a screen is done. "Proof: preview" and
  "flow" below mean exactly this; every UI task registers its views in the gallery (0.10).
- **Skills to add as patterns appear**: `new-screen`, `swiftdata-model`, `live-activity`, `testflight-release`. **Ask Eric only
  for taste** (colours, copy, native deviations). **Status**: tick the task, add one outcome line, dates absolute.

## 6. Phases and tasks

Workers do not commit; the orchestrator runs `./dev check` and commits per task. Phases follow risk: shell → engine →
Live Activity → notifications → logging, then templates, exercises, history.

### Phase 0 — Foundations

- [ ] **0.1 SwiftData schema** in `WorkoutsKit/Model/`: the nine `@Model` types from `docs/port/data-model.md` (read "Native
  deltas" first), `SchemaV1` + `VersionedSchema`, `ModelContainer.workouts(inMemory:cloudKit:)`, optional
  `Workout.restEndsAt`/`restSeconds`/`restSetID`. Proof: `./dev kit Schema` (inserts, cascade-delete, nullify, builds with
  `cloudKitDatabase: .none`).
- [ ] **0.2 Library builder script** `scripts/build-library` (Swift): reads
  `~/Server/docker-volumes/workouts/snapshot/{manifest.json,exercises/*.json}`, emits `Workouts/Resources/Library/library.json`
  (exercises, `retired`, alternatives as ids, labels) and `thumbs/<id>-start.png`/`-end.png`; ids = UUIDv5(namespace,
  "source:sourceId"), namespace pinned in `WorkoutsKit/Library/LibraryID.swift` with one test value. Proof: the script runs (≈ 25
  MB), `./dev build` sees the folder, `./dev kit Library`.
- [ ] **0.3 ExerciseStore** (kit): `LibraryCatalog` decode, custom merge (`exercise(id:)` = catalog ∪ custom), name sort,
  all-words accent-insensitive search over name and aliases, archive rule. Needs: 0.1, 0.2. Proof: `./dev kit Library`.
- [ ] **0.4 Settings store** `WorkoutsKit/Settings/SettingsStore`: `@Observable`, `UserDefaults` backend behind a protocol,
  section 2 defaults, one key list. Proof: `./dev kit Settings`.
- [ ] **0.5 Shell and tabs**: `TabView(.sidebarAdaptable)` + `.defaultAdaptableTabBarPlacement(.sidebar)`, empty History · Workout
  · Exercises skeletons (Workout selected), Settings gear + `tabViewSidebarBottomBar` + empty Form sheet, empty root
  `fullScreenCover` holding an empty `ArrangementView` (spike for 2.10). Proof: `./dev run` screenshots closed and both open poses
  (record where the bar lands and how the cover's arrangement behaves).
- [ ] **0.6 AppNavigation** (kit): selected tab, typed routes, cover and minimise state. Proof: `./dev kit Navigation`.
- [ ] **0.7 Design colours**: asset-catalog semantic colours, light/dark. Proof: `./dev build` + a swatch `#Preview` (shown in the
  gallery once 0.10 lands).
- [ ] **0.8 MediaStore** per `docs/port/media.md`, fake `URLProtocol`. Proof: `./dev kit Media`.
- [ ] **0.9 Sample data + preview container** (kit `Sample/`): `ModelContainer.preview` seeded by `SampleData` (takes a
  `LibraryCatalog`; 3 templates, 50 workouts with PRs) and a `#if DEBUG` "Load sample data" row in the Settings sheet; every
  `#Preview` and gallery entry uses it. Needs: 0.1, 0.3, 0.5. Proof: `./dev kit Sample`.
- [ ] **0.10 Preview gallery + UI-test harness**: `#if DEBUG` `PreviewGallery` root chosen by launch argument `-preview <Name>`
  (named view factories on `ModelContainer.preview`; register 0.5–0.9's views), one smoke XCUITest. `./dev run -- -preview <Name>`
  already passes arguments through. Needs: 0.9. Proof: `./dev run -- -preview Swatches` + `./dev screenshot`; `./dev ui-test
  Smoke`.
- [ ] **0.11 App icon** (placeholder; ask Eric, taste). Proof: `./dev build`; Eric approves the icon.

### Phase 1 — Engine and native layer

- [ ] **1.1 ActiveWorkoutEngine core** (WorkoutsKit/Session): start from template/Empty Workout, resume, check/uncheck (empty sets
  refused), Previous autofill (cross-unit: convert, round to 0.5), add/replace/remove/reorder, finish (dialog data, PR count),
  discard. Needs: 0.1, 0.3. Proof: `./dev kit Engine` (~20 tests incl. relaunch).
- [ ] **1.2 Rest timer in the engine**: `RestTimer` over the persisted rest fields, presets, one `adjust(by:)` op (−10 s, +10 s,
  +30 s), skip, superset rest on every check, counters, relaunch restore. Needs: 1.1. Proof: `./dev kit Rest`.
- [ ] **1.3 Live Activity state + extension**: `WorkoutActivityState` in `WorkoutsKit/Activity` with the
  `ActiveWorkoutEngine.activityState` mapping; the `WorkoutActivityAttributes: ActivityAttributes` wrapper (also in the extension
  target) and the `WorkoutsLiveActivity` target in the app (`xcode-project` skill; the first non-trivial project change: extension
  Info.plist with `NSExtensionPointIdentifier = com.apple.widgetkit-extension` (`GENERATE_INFOPLIST_FILE` is not defaulted), copy
  phase to PlugIns, `pkg link` of the kit; write the recipe into the skill), `NSSupportsLiveActivities`, stub view. Needs: 1.1.
  Proof: `./dev kit Activity` (mapping) + `./dev build`.
- [ ] **1.4 Live Activity views**: lock screen and Island presentations per section 2 (no Island on the inner display). Needs:
  1.3. Proof: `#Preview(as:using:)` renders (MCP) or, without it, Lock Screen/Island simulator screenshots.
- [ ] **1.5 Live Activity lifecycle + intents**: request/update/end from the engine; Skip / +30 s / Done set as `nonisolated
  struct` intents in `Workouts/App/Intents/` (`perform()` is nonisolated; under `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` the type
  opts out, then `await MainActor.run` into the engine, which first resumes the persisted workout). Needs: 1.2, 1.3. Proof: `./dev
  test Activity` + a Lock Screen tap on the sim.
- [ ] **1.6 Notifications**: permission on first workout, `.timeSensitive` rest-end request with next-set copy, Skip/+30 s
  actions, `willPresent` returns `[]`. Needs: 1.2. Proof: simulator flow (shown backgrounded, absent in the foreground).
- [ ] **1.7 WorkoutsJSON codec + importer + export script** (kit `WorkoutsJSON/`): one `Codable` document (folders, templates,
  custom exercises, sticky notes, workouts), `Importer.apply(to: ModelContext)` idempotent by id, exercise ids via `LibraryID`;
  `scripts/export-web` (Postgres → JSON, run on this Mac); add `docs/port/fixtures/` to `.gitignore`. Needs: 0.1, 0.2. Proof:
  `./dev kit Import` (round-trip + idempotence); Eric's real export imports.

### Phase 2 — Active workout (with its shared components)

- [ ] **2.1 Exercise picker** (moved from Phase 3: Empty Workout cannot log without it): single/multi,
  `.searchable`, body-part and category `Menu` pills, "?" peek, a reusable sheet for Add / Replace (inline create is wired by
  4.4); Add (N) (`plus`) and Superset (`rectangle.stack`) are toolbar items, Cancel in the Close slot. Needs: 0.3, 0.9, 0.10.
  Proof: preview + flow.
- [ ] **2.2 Set row + keyboard group**: one row (set · previous · weight · reps · ✓), kind cycling normal → W → D → F, Previous
  tap copies, per-cell `@FocusState`, `.decimalPad`, keyboard group (−step, +step, Previous, Done, Next), `ViewThatFits` two-line
  row at AX sizes, `.sensoryFeedback` on engine counters. Needs: 0.7, 0.10. Proof: previews at `.large` and `.accessibility3`,
  both widths.
- [ ] **2.3 SetTable** (`Workouts/Features/Shared/SetTable`): modes template/active/past; exercise `Section` headers per section
  3; `LazyVStack` in `swipeActionsContainer()` for set Delete; block reorder via `.reorderable()` + `reorderContainer(for:)`;
  **Add Set** a plain trailing `Label` row. Needs: 2.2. Proof: previews at `.large` and `.accessibility3`, both widths.
- [ ] **2.4 Logging screen (compact) + Empty Workout**: cover with the SetTable on the engine, toolbar and title per section 3,
  `isIdleTimerDisabled` gate; the Workout tab's Add menu gets **Empty Workout** (New Template / New Folder join in 3.1). Needs:
  1.1, 2.1, 2.3, 0.9. Proof: flow (load sample data → Add → Empty Workout → add an exercise via the picker → log a set; Previous
  fills).
- [ ] **2.5 Rest ring item** per section 2: idle `Menu` + "Custom…" two-wheel sheet, running expanded sheet (trailing placement)
  with the −10 s / +10 s / Skip group, custom `ProgressViewStyle` ring. Needs: 1.2, 2.4. Proof: flow (pick 1:00, adjust, Skip;
  create a custom).
- [ ] **2.6 Rest toolbar group and minimise**: Skip / +30 s group while a rest runs, countdown + Skip + +30 s in the keyboard
  group, Minimise in the Close slot. Needs: 2.5. Proof: flow (check a set → ring counts down, Skip ends it, Minimise returns).
- [ ] **2.7 Resume control**: the ring `ToolbarItem` (elapsed when no rest runs) from a shared `ViewModifier` on every screen's
  root; additive `tabViewSidebarBottomBar` card while the sidebar is visible; tap restores the cover; relaunch restores the cover
  if it was open (else only the ring). Needs: 2.6. Proof: flow on both widths, the ring visible from History and Exercises.
- [ ] **2.8 Finish and Discard**: finish dialogs, Discard confirmation, `.warning` haptic. Needs: 2.4. Proof: flow.
- [ ] **2.9 Finish summary sheet** per `active-workout.md` §3: centred, Done in the Close slot, coloured-value list incl. PRs
  (rows inert until 4.2 links them to Records), `.levelChange` on a PR. Needs: 2.8. Proof: preview at `.large` and
  `.accessibility3` + flow.
- [ ] **2.10 Regular-width logging**: `ArrangementView(primary: SetTable, secondary: ExercisePane)` following the focused exercise
  (section 2), `.split`; the pane never straddles a `.division` region. `ExercisePane` ships as a `ContentUnavailableView`
  placeholder; 4.5 swaps in the real pane and re-proves. Needs: 2.4, 0.5. Proof: open-tall / open-wide screenshots; fold
  mid-workout keeps draft, focus, scroll.

### Phase 3 — Workout tab (templates)

- [ ] **3.1 Folders**: per-device `@AppStorage` collapse flag per folder (header only; headers dropped beside a visible sidebar),
  `contextMenu` on headers (rename, reorder, delete with move-or-delete dialogs), New Folder in the Add menu. Needs: 2.4. Proof:
  preview + flow.
- [ ] **3.2 Template grid + cards**: width-derived even columns, Fitness-shaped cards (section 3), `matchedTransitionSource`, tap
  = sheet on compact / push on regular, `contextMenu`s and swipes on cards (Edit, Duplicate "<name> copy", Move, Delete), no ⋯;
  optional drag via `reorderContainer`; New Template in the Add menu. Needs: 3.1. Proof: preview + flow.
- [ ] **3.3 Template preview** (medium-detent sheet on compact, zoom push on regular) laid out per section 3, Start Workout from
  the engine. Needs: 3.2, 1.1. Proof: preview + flow on both widths.
- [ ] **3.4 Template editor shell**: pushed in both widths, `ArrangementView` on regular as in 2.10 (placeholder pane until 4.5),
  no width cap; SetTable template mode, name via `toolbarTitleMenu`, Save and unsaved-changes guard (dirty = differs from what
  opened). Needs: 2.1, 2.3, 2.10, 3.3. Proof: flow.
- [ ] **3.5 Supersets and warm-up ramp**: `WorkoutsKit/Session` helpers (ramp, renumbering) and superset colours. Needs: 0.1.
  Proof: `./dev kit Template` + preview.
- [ ] **3.6 Editor block actions**: exercise-header `ellipsis.circle` menu (note, Add Warm-up Sets, Update Rest Timers, Replace
  via the picker, Create/Edit Superset, Preferences unit/bar/rest per row, Remove); the Sticky Note entry arrives with 4.5. Needs:
  3.4, 3.5. Proof: flow.
- [ ] **3.7 Sidebar Templates sections**: `TabSection` per folder, `.sidebarOnly` template tabs rendering the preview,
  `.sectionActions` "New Template". Needs: 3.3. Proof: open-Duo screenshot; compact bar unchanged.

### Phase 4 — Exercises tab

- [ ] **4.1 Exercise list**: `NavigationSplitView`, rows from `ExerciseStore` by displayed name, `.searchable` only (no inline
  field, sort control or A-Z rail), body-part and category `Menu` pills, thumbnail rows with best set and tags, New Exercise +
  Show Retired toolbar items, `tabBarMinimizeBehavior(.onScrollDown)`. Needs: 0.3, 0.9, 0.10. Proof: sample-data preview.
- [ ] **4.2 Exercise detail shell**: `ExerciseDetailView` with an `embedded` mode (for the logging pane), About and Records
  segments, `MediaStore` video header with `.backgroundExtensionEffect()`, `records(...)`, Edit (custom only), zoom from the row;
  also links 2.9's PR rows to Records. Needs: 4.1, 0.8, 2.9. Proof: preview per segment.
- [ ] **4.3 Exercise detail History and Charts**: History segment, Swift Charts from `chartSeries`. Needs: 4.2. Proof: preview per
  segment.
- [ ] **4.4 Custom exercise form** (create/edit/archive/delete-if-unused) + picker inline create. Needs: 4.1, 2.1. Proof: flow
  (create → in list → archive).
- [ ] **4.5 Sticky note** editor in the detail, shared with the logging pane; swaps `ExerciseDetailView(embedded)` into
  `ExercisePane` (2.10, 3.4), adds 3.6's Sticky Note entry and re-proves the 2.10 fold flow. Needs: 4.2, 2.10, 3.6. Proof: preview
  + flow.

### Phase 5 — History

- [ ] **5.1 History list**: `NavigationStack` in both widths (section 2), month `Section`s of workout rows (section 3), lazy rows,
  zoom push to the detail, `.searchable` + `searchScopes` (All · PRs), `contextMenu` + `swipeActions`,
  `tabBarMinimizeBehavior(.onScrollDown)`. Needs: 0.9. Proof: preview with the 50 sample workouts.
- [ ] **5.2 Weekly goal chart** as the hero card (Swift Charts, goal line; plain header) over a kit function
  `weeklyCounts(workouts:calendar:weeks:)` (ISO weeks, Monday, injected `Calendar`/`TimeZone`). Needs: 5.1. Proof: `./dev kit
  Weekly` (incl. a DST boundary, America/Toronto, 2026-11-01) + preview.
- [ ] **5.3 Dashboard cards**: This Week, Recent PRs, Last Workout, even columns from the grid's width, Fitness's card shape.
  Needs: 5.2. Proof: preview, both widths.
- [ ] **5.4 Calendar sheet** from the Calendar toolbar item: month grid (Monday first), workout days marked, tap opens the
  workout. Needs: 5.1. Proof: preview.
- [ ] **5.5 Workout detail**: PR lines, trophies, the per-exercise Exercise | Best Set table, toolbar items Edit, Save as Template
  (success = `sensoryFeedback(.success)` + dismiss, no banner), Delete. Needs: 5.1. Proof: preview + flow.
- [ ] **5.6 Past-workout editor** (SetTable past mode, start time, duration), pushed from the detail, `ArrangementView` on regular
  as in 3.4. Needs: 5.5, 3.4. Proof: flow; later workouts' PR counts update.
- [ ] **5.7 Settings sheet** complete (iCloud status, Download all videos (Wi-Fi only), Import and **Export…** via the share
  sheet, same codec as 1.7). Needs: 1.7, 0.8. Proof: preview; `./dev ui-test` import → export round trip.

### Phase 6 — Duo and accessibility pass

- [ ] **6.1 Half-open bench mode**: the arrangement view puts the SetTable on the lower half and the exercise pane + rest
  countdown on the upper; `reservedRegions(kind: .division)` only if the system split is wrong (`onHingeChange` is for effects).
  Needs: 4.5. Proof: Device Hub screenshots at two angles.
- [ ] **6.2 Pose and scenario pass** of every screen with `verify-ui`: closed portrait and landscape (title collapse, ~2 rows
  above the keyboard, strip), open tall and wide, book and laptop half-open (arrangement and split divider vs the fold; the laptop
  pose's lower half is where the keyboard lands), Split View (safe areas flip sides; PiP), fold mid-flow with a sheet, menu,
  dialog or cell focus up, keyboard in each pose, AX Dynamic Type and VoiceOver order across the strip and the fold. Proof:
  pass/fail table, every screen × pose/scenario, no breaks.
- [ ] **6.3 Accessibility audits**: VoiceOver, Dynamic Type, contrast skills. Proof: audits report clean.
- [ ] **6.4 Performance**: full-library scrolling, 600-workout chart (sample data scaled up). Proof: `xctrace`, no hitches.

### Phase 7 — Sync, distribution (needs the Developer Program)

- [ ] **7.1 Team + entitlements**: `DEVELOPMENT_TEAM`, iCloud (container + key-value), push, time-sensitive; no App Group. Proof:
  `./dev build` signs with the team.
- [ ] **7.2 CloudKit on**: flip the flag, promote the schema to production. Needs: 7.1. Proof: two simulators sync.
- [ ] **7.3 Settings on iCloud KVS** (only if a second device appears): `NSUbiquitousKeyValueStore` backend behind the
  `cloudKit` flag. Needs: 7.1. Proof: `./dev kit Settings` runs both backends.
- [ ] **7.4 TestFlight-time migration run**: re-run `scripts/export-web`, Import the delta. Needs: 7.2. Proof: the device's
  workout count matches the export.
- [ ] **7.5 TestFlight**: archive, export, upload. Needs: 7.1. Proof: `./dev testflight`; the build installs on the Duo.

## 7. Risks and unknowns

- **Hinge APIs are real**: SwiftUI `onHingeChange(isEnabled:_:)` (iOS 27.1) and UIKit `UIHinge`. The simulator's fold is not
  scriptable (`verify-ui`), so 6.1 is verified by Device Hub screenshot. `ArrangementView` inside a `fullScreenCover` +
  `NavigationStack` is undocumented: 0.5 spikes it before 2.10 relies on it.
- **Sidebar placement**: without `defaultAdaptableTabBarPlacement(.sidebar)` the bar is iPad-style on regular width, and template
  `Tab`s without `.tabPlacement(.sidebarOnly)` leak into the compact bar (screenshots in 0.5, 3.7).
- **Live Activity cannot update itself while the app is suspended** (no push server): 0:00 and the time-sensitive notification
  are the "rest over" signals.
- **SwiftData + CloudKit**: no unique constraints, optional relationships, additive-only migrations once CloudKit is on; keep
  `SchemaV1` frozen after 7.2. **Island screenshots** need an Island sim (`iPhone 18 Pro`; the Duo's inner display has none);
  **TestFlight** needs the paid program (simulator-only until then).
