# Workouts: the native plan

The document Eric and the orchestrating agent (Opus) work from. Written 2026-11-03 by Fable after the scaffold, the port
spec and the `WorkoutsKit` math landed. It is a living file: tick tasks, record decisions in section 2, never
re-litigate what is settled here or in `AGENTS.md`.

Orchestrator: read `AGENTS.md` first (toolchain, loop, rules), then section 6 to find the next unticked task. Each task
is sized for one Sonnet worker and names its proving command. Fable/Opus plans and reviews; Sonnet implements. Reviewed
2026-11-03; accepted findings are applied here, rationale in `docs/plan-review-2026-11-03.md`, `-duo.md` and `-bias.md`.

## 1. Goal

A private, single-user, native SwiftUI iPhone app that keeps the web app's curated workout-tracking experience (feature
complete, Eric-designed, "awesome") and adds what a PWA cannot do on the **iPhone Duo**: a real sidebar on the inner
display, split layouts, Live Activity + Dynamic Island for the rest timer, notifications, haptics. Parity is the floor.
Not goals: App Store release, other users, iPad/Mac, widgets, Shortcuts, Control Center, HealthKit/Apple Fitness (Eric
starts his Fitness workouts in Apple's app himself), Apple Watch, the web app, multi-window and keyboard shortcuts (one
scene; no `UIApplicationSupportsMultipleScenes`).

## 2. Decisions (settled; see `AGENTS.md` → Product decisions for the ones made earlier)

Eric deferred the technical choices to Claude. These close every item in `docs/port/OPEN-QUESTIONS.md`.

**Data and sync**
- SwiftData + CloudKit private database, container `iCloud.com.ericribeiro.Workouts`. Until the Developer Program is
  approved CloudKit runs **off** behind one flag (`ModelConfiguration(cloudKitDatabase: .none)`); the schema is
  CloudKit-safe from day one.
- Settings live outside SwiftData, in a `SettingsStore` with two backends sharing one key list and one test:
  **`UserDefaults` until the iCloud key-value entitlement exists (phase 7)**, then `NSUbiquitousKeyValueStore` (syncs,
  cannot produce duplicate rows), selected by the container's `cloudKit` flag in task 7.3. Keys: `defaultUnit`,
  `defaultRestSeconds` (90), `weeklyGoal` (3), `e1rmFormula` (epley), `restPresets`, `keepScreenOn` (true),
  `downloadAllVideos` (false). Appearance follows the system.
- Library: 1,038 exercises bundled as `library.json` + thumbnails (`scripts/build-library`), seeded on first launch and
  upserted when `libraryVersion` is newer; never touches custom exercises, overrides or sticky notes; retires what left.
  Media: `docs/port/media.md`.
- One-time web Postgres migration: an **Import** action in Settings reads a JSON export through SwiftData, so it syncs;
  exercise ids match via UUIDv5(source, sourceId) (task 7.4).
- Custom exercise: deletable when no history references it, otherwise "Archive" (= retire).

**Navigation and layout**
- `TabView` with `.tabViewStyle(.sidebarAdaptable)` and `.defaultAdaptableTabBarPlacement(.sidebar)`. Three top-level
  `Tab`s in Eric's order, **History · Workout · Exercises**; **Workout is the default selection**. One `TabSection` per
  **folder** (header = folder name), its templates as `Tab`s with `.tabPlacement(.sidebarOnly)` (never in the compact
  bar) rendering the template preview with Start / Edit; `.sectionActions` carries "New Template". Don't assume where
  the bar lands.
- **Settings** is a gear `toolbar` button on the Workout tab, and `tabViewSidebarBottomBar` on regular width, presenting
  a `Form` sheet. No fourth tab.
- **Toolbar items** carry a symbol and a title; the ellipsis belongs to the system's `ToolbarOverflowMenu`, so no `⋯`
  menus. Workout: Settings (`gearshape`), Add (`plus`, a `Menu`: New Template / New Folder). Exercises: New Exercise
  (`plus`), Show Retired (`eye`, toggle). History: Calendar (`calendar`). Exercise detail: Edit (`pencil`, custom only).
  Workout detail: Edit (`pencil`), Save as Template (`doc.on.doc`), Delete (`trash`, destructive). Row and card actions
  are `contextMenu` + `swipeActions` only, folder actions a `contextMenu` on the header; only content blocks inside the
  set table may keep `ellipsis.circle`. Task screens set `toolbarVerticalCompressionBehavior(.prefersToolbarItems)` and
  order items Close → prominent → state (ring) → actions, since the bottom overflows first: nothing below the ring may
  be something Eric needs mid-set.
- Exercises and History use `NavigationSplitView` with no column-width modifiers: the system sizes columns and keeps
  them off the fold (compact → push); the empty detail is a `ContentUnavailableView` (Mail's model). The Workout tab is
  a single column in both widths (the sidebar lists templates): a **card grid** (collapsible folders) with an even
  column count from the grid's own width via `onGeometryChange`, `max(2, 2 * floor(width / (2 * minCard)))`: sidebar
  open gets 2, full width 4, so no card straddles the fold; with `.includeInactive` reserved regions the hinge gap
  widens. Card tap: compact → medium-detent preview sheet (a Maps/Flighty-style panel, fine at phone size); regular →
  push the preview (zoom transition) so the sidebar stays. Beside a visible sidebar the grid drops its folder headers;
  one persisted collapse flag per folder drives both the compact header and the `TabSection` expansion, not a second
  flag.
- **Sheet placement**: on regular width every sheet names `presentationPlacement`: picker, settings, calendar, custom
  timer, finish summary → centred (horizontal bars); rest ring → trailing (vertical bars, it belongs to the strip's ring
  item). The template preview is pushed on regular, a sheet only on compact.
- **Active workout**: one presentation in both widths, a `fullScreenCover` on the root `TabView`, not tied to any tab.
  Layout follows `horizontalSizeClass`: compact → the set table; regular → an `ArrangementView` (iOS 27.1), set table
  primary, exercise pane (video, instructions, Previous, records, sticky note) secondary, following the focused
  exercise: side by side when wide, stacked when tall, split across the fold when partially open
  (`docs/port/duo-layout.md`). Folding only changes the size class, so draft, focus and scroll are untouched. Minimise
  is the cover's Close-slot item (`Button("Minimise", systemImage: "chevron.down")`) with Finish (`checkmark`,
  prominent) next: no grab handle, drag or tab-tap (a cover has no interactive dismissal, no tab bar). It dismisses the
  cover; the resume control (and Live Activity) restore it; a running workout survives any tab change.
- Minimised workout lives in the system bars, never in a bottom pill (Eric, 2026-11-03: no native app on the Duo has a
  bottom bar; Flighty's trailing strip is the model). One `ToolbarItem` carries it in every width: a
  `ProgressView(timerInterval:)` ring with `Text(timerInterval:)` inside (caption size; elapsed time when no rest runs),
  placed by the system in the trailing strip when closed or open-wide and in the top bar when open-tall. It is the
  closed display's resume control (tap restores), also on the open display's strip, and the logging screen's own timer
  item; no `.glassEffect()` (toolbar items are already glass). Toolbar items do not inherit on push, so a shared
  `ViewModifier` applies it on every screen's root. Additive: a `tabViewSidebarBottomBar` card (name · elapsed · rest
  countdown · Skip) while the sidebar is visible. No `.tabViewBottomAccessory`. History and Exercises lists set
  `tabBarMinimizeBehavior(.onScrollDown)` (not Apple's `toolbarMinimizeBehavior`: absent from 27.2).
- `AppNavigation` (@Observable) with typed routes, so Live Activity buttons and notification actions can open the
  logging screen or a template. App Intents exist only behind those buttons (no Shortcuts or Spotlight).

**Active workout behaviour**
- Start from a template or **Empty Workout** (name "Workout"); exactly one in progress. Finish summary is a centred
  sheet with a **PR count** (native improvement; `prsInSession` exists): Done is its Close-slot item, nothing
  bottom-anchored (`active-workout.md` §3).
- Web rules kept verbatim (`docs/port/screens/active-workout.md`): check → rest starts (superset too), presets
  0:30/1:00/2:00/3:00 + up to 6 customs (1–3600 s, no repeats), ±10 s adjust, empty sets cannot be checked, Finish
  dialogs, Discard confirmation, Previous autofill, warm-up ramp, supersets numbering. No RPE UI (field kept in the
  model).
- Rest end: local `.timeSensitive` notification, body "Rest over · Set 3 · 27.5 lb × 8" (next set included), actions
  **Skip** and **+30 s** (the one pair on every surface); in foreground `willPresent` returns `[]` and the app plays
  haptic + flash. Dynamic Island only while closed (the inner camera is under the display): open and backgrounded, the
  Lock Screen presentation and the notification are the only signals.
- Timer correctness: render with `Text(timerInterval:)` from `restEndsAt`, never a counter; rest state persists on the
  in-progress `Workout` (`restEndsAt`, `restSeconds`, `restSetID`).
- Rest UI: the controls live in the bars. The ring `ToolbarItem` is idle: a stopwatch `Menu` (a toolbar item that offers
  a short list is a menu, not a sheet): 0:30 / 1:00 / 2:00 / 3:00, a divider, saved customs (newest first), "Custom…"
  opening a small sheet with a countdown wheel (`DatePicker` `.countDownTimer`) and a Start toolbar item; running: the
  countdown, opening the expanded sheet (Clock's ring, remaining over total) whose −10 s / +10 s / Skip are a horizontal
  `ToolbarItemGroup` placed by the system (vertical in the strip when closed), not a content button row. While a rest
  runs the logging toolbar gains a `ToolbarItemGroup` of **Skip** (`forward.end`) and **+30 s** (`goforward.30`) below
  the ring, stacked like Flighty's map tool group; while the keyboard is up, its horizontal `ToolbarItemGroup` prepends
  the countdown and Skip. No `safeAreaBar`, no bottom glass.
- Keyboard: system `.decimalPad` with a keyboard `ToolbarItemGroup` (−step, +step, Previous, Done) and a Next that
  advances weight → reps → next row; steps from the web. It covers half the closed screen, so Next is the mitigation;
  custom keypad only if this proves worse.
- **SetTable** (`Workouts/Features/Shared/SetTable`, task 2.1) is one shared component in three modes (template / active
  / past). `isIdleTimerDisabled` while logging when `keepScreenOn`.

**Native layer**
- **Live Activity** (`WorkoutsLiveActivity` extension; `NSSupportsLiveActivities` in Info.plist). `ContentState`:
  exercise name, set index/count, next-set text, `startedAt`, `restEndsAt?`. Lock screen + expanded Island: exercise,
  "Set 3 of 4", rest countdown `Text(timerInterval:)` or elapsed `Text(timerInterval: startedAt...distantFuture,
  countsDown: false)` when no rest runs; buttons `Button(intent:)` **Skip** / **+30 s** / **Done set** as
  `LiveActivityIntent`s that call the engine in-process. Compact: exercise glyph + countdown; minimal:
  `ProgressView(timerInterval:)` ring. `staleDate = restEndsAt`, `relevanceScore` 1 while resting. Request on start,
  update on every check/skip/adjust, `end(dismissalPolicy: .immediate)` on Finish/Discard. Suspended (no push server) it
  cannot flip to "rest over": 0:00 is the only in-Island signal, the notification the alarm. `WorkoutActivityAttributes`
  lives in `WorkoutsKit`.
- **Haptics** via `.sensoryFeedback`: set checked `.impact(weight: .light)`, rest end `.success`, PR at finish
  `.levelChange`, destructive confirm `.warning`, minimise/restore `.selection`.
- **Liquid Glass**: system bars and controls; no hand-placed `.glassEffect()` unless something floats over content
  (nothing does today); `.navigationTransition(.zoom(sourceID:in:))` with `.matchedTransitionSource(id:in:)` on the card
  or row, card → preview sheet and row → detail. Eric's palette becomes semantic asset-catalog colours (accent, ok,
  danger, warm-up, set-kind) with light/dark variants; everything else is system material.
- **Accessibility**: every interactive element labelled (agents navigate by the tree too); Dynamic Type everywhere; at
  AX sizes each set row becomes a two-line stack via `ViewThatFits`.

**Duo rules (distilled in `docs/port/duo-layout.md`, also `AGENTS.md`): size classes and the system's bars, never
breakpoints or fixed widths.**
- Size classes only; never `UIScreen.main`, idiom, orientation, or hardcoded sizes. Width can change mid-session
  (fold/unfold) and the app must keep selection, scroll and the active workout.
- Asymmetric safe areas are normal (`.safeAreaInset`/`.safeAreaPadding`, no magic numbers): on Eric's closed Duo the
  status area is a trailing vertical strip (`docs/port/screenshots/duo-closed-*`).
- All four orientations supported. Hinge APIs drive the half-open **bench mode** (6.1). Verify on the `iPhone Duo`
  simulator per the pose and scenario list in 6.2 (`.claude/skills/verify-ui`).
- **Web keeps that are fine** (not re-litigated): tab set and order; set-table columns, Previous autofill, Add Set row;
  cards by fill, no rim or glass; large titles; `ContentUnavailableView` empty details; segmented About / History /
  Charts / Records; body-part and category chip row; calendar sheet; `confirmationDialog` copy; semantic colours
  following the system; `fullScreenCover` logging with the ring item as resume control.

## 3. Experience, screen by screen (what "awesome" means here)

- **Workout tab**: large title, folder sections with the card grid; cards in Fitness's shape: title row with
  `chevron.right`, headline = exercise count ("7 exercises"), caption = first exercises, footnote "Last performed · 5
  days ago". Tap → the preview (sheet on compact, push on regular, §2): Close (`xmark`), Edit (`pencil`) in the strip;
  the title, "Last performed", a `.borderedProminent` **Start Workout** (`play.fill`) capsule directly under it
  (Flighty's `+ Add Friend`), then rows with an `info.circle` peek; nothing is bottom-anchored. On the open Duo the grid
  is the tab's whole content and the sidebar lists the templates (a selected one shows its preview). The editor is
  pushed in both widths; on regular its body is the logging screen's `ArrangementView(primary: SetTable, secondary:
  exercise pane)` (2.8), so the table never straddles the fold, no width cap.
- **Logging screen**: the set table (set · previous · weight · reps · ✓) with the native keyboard accessory; each
  exercise is a `Section` (header = name as primary text, tappable to the detail; caption "Rest 2:00"; trailing
  `ellipsis.circle` `Menu`; no permanent grip, reorder with `.reorderable()`, no chart button); checked rows tint; rest
  controls are toolbar items (§2). Minimise (`chevron.down`) is the Close-slot item, Finish (`checkmark`) the prominent
  one: no handle, no drag. `navigationTitle(name)` + `navigationSubtitle("Nov 3 · 0:33")` with `toolbarTitleMenu`
  (Rename, Discard Workout); **+ Add Exercise** is a toolbar item (`plus`) and the last row of the table, **Add Set** a
  plain trailing `Label` row. Open Duo: the right pane follows the focused exercise; half-open (on the bench): media on
  the upper half, set table on the lower. Rest: toolbar items in app, Dynamic Island when away and closed, Lock Screen +
  notification otherwise; Skip/+30 s via the same intents. Finish opens the centred summary sheet (§2): "Workout
  complete", "Your 615th workout", then a Fitness-style list (Duration, Volume, Sets, Exercises, PRs).
- **History tab**: a Fitness-style dashboard: large title; hero card = the weekly goal chart (Swift Charts, full width,
  plain header: the goal lives in Settings only); then even-column cards from the grid's own width (the template grid's
  `onGeometryChange` rule): This Week (count vs goal), Recent PRs (trophy list), Last Workout (name · duration · volume,
  chevron to its detail); then month `Section`s of workout rows (name, date, duration · volume · PRs, trophy). Rows push
  the detail (zoom transition; the split's detail column on regular) holding PR lines, trophies and the per-exercise
  Exercise | Best Set table. `.searchable` over workout and exercise names with `searchScopes` (All · PRs). Edit past
  workout (pushed from the detail); calendar sheet; saving a template gives `sensoryFeedback(.success)` and the sheet
  dismissing, no banner. Which cards: ask Eric.
- **Exercises tab**: `.searchable` only, body part and category as two `Menu` pills at the top of the list (or
  `searchScopes` if ≤ 4 values), no sort control while Name A-Z is the only sort, **no A-Z rail** (no SwiftUI section
  index; the trailing edge is the system's); rows with thumbnail + latest best set and tags; detail with segmented About
  / History / Charts / Records, video loop at the top (`.backgroundExtensionEffect()`), sticky note editable here too.
- **Settings sheet**: unit, default rest, weekly goal, e1RM formula, keep screen on, download all videos, iCloud status,
  Import (migration), About (SmartWorkout credit).

## 4. Architecture

```
Workouts.xcodeproj
├─ Workouts/                 app target (SwiftUI shell + features)
│  ├─ App/                   WorkoutsApp, AppNavigation, ModelContainer setup, Settings store
│  ├─ Design/                Colours (asset catalog), typography helpers, ring toolbar item, haptics map
│  ├─ Features/{Shared,Workout,ActiveWorkout,History,Exercises,Settings}/   views + view models (@Observable)
│  └─ Resources/Library/     library.json + thumbs/ (generated, committed; ~25 MB)
├─ WorkoutsLiveActivity/     widget extension holding only the Live Activity
├─ Packages/WorkoutsKit/     platform-free: Model (SwiftData @Model types), Math (done),
│                            Library (seed/upsert), Media (MediaStore), Session (ActiveWorkoutEngine,
│                            RestTimer), Activity (WorkoutActivityAttributes, Live Activity intents)
└─ scripts/build-library     Swift script: snapshot → library.json + thumbs (run on this Mac)
```

- **SwiftData models** (`docs/port/data-model.md`, CloudKit-safe, ten `@Model` types): relationships optional with
  explicit `deleteRule` (RESTRICT becomes an app check), every property defaulted, enums as raw strings, `Double`
  weights, no `.unique`. `Workout.finishedAt == nil` marks the one in-progress workout; every query excludes it
  (`#Predicate`). Positions are Ints.
- **ActiveWorkoutEngine** (WorkoutsKit, `@Observable`, `@MainActor`): owns the in-progress `Workout`:
  check/uncheck/add/replace/remove/reorder, Previous lookup, warm-up ramp, rest timer state, finish/discard, and
  `checkCount` / `restEndCount` counters that views turn into `.sensoryFeedback` triggers. The Live Activity only
  renders the `ContentState` it pushes; `LiveActivityIntent.perform()` runs in the app process, so intents (types in
  `WorkoutsKit`) call the engine through a launch-registered dependency (no shared store, no App Group).
- **Entitlements** (once a team exists, via `xcrun xcodeproj`): iCloud (CloudKit and key-value), Push,
  remote-notification, time-sensitive notifications. **No App Groups**; the extension needs only
  `NSSupportsLiveActivities`.
- **Testing**: `./dev kit` for all WorkoutsKit logic (SwiftData in memory works on macOS), `./dev test` for the few
  app-level tests, UI proof by `RenderPreview` and device-interaction tools.

## 5. Agentic workflow for this project

- **One worker, one task, one proving command.** Tasks below are already that size; if a worker reports more than one
  feature, split next time. **Order of proof**: `./dev kit <filter>` → `./dev build` → `RenderPreview` → `./dev test` →
  device-interaction on the Duo for flows → the four poses before a screen is called done.
- **Skills to add as patterns appear** (procedural; rules stay in `AGENTS.md`): `new-screen`, `swiftdata-model`,
  `live-activity`, `testflight-release`; use Apple's SwiftUI, resizability and accessibility skills by name.
- **Ask Eric only for taste** (colours, copy, native deviations); technical questions are Claude's, recorded in section
  2. **Status**: tick the task, add one outcome line, dates absolute.

## 6. Phases and tasks

Workers do not commit; the orchestrator runs `./dev check` and commits per task. Phases follow risk: shell → engine →
Live Activity → notifications → logging, then templates, exercises, history.

### Phase 0 — Foundations

- [ ] **0.1 SwiftData schema** in `WorkoutsKit/Model/`: all `@Model` types from `docs/port/data-model.md`, `SchemaV1` +
  `VersionedSchema`, `ModelContainer.workouts(inMemory:cloudKit:)`, optional
  `Workout.restEndsAt`/`restSeconds`/`restSetID`. Proof: `./dev kit Schema` (inserts, cascade-delete, nullify, builds
  with `cloudKitDatabase: .none`).
- [ ] **0.2 Library builder script** `scripts/build-library` (Swift): reads
  `~/Server/docker-volumes/workouts/snapshot/{manifest.json,exercises/*.json}`, emits
  `Workouts/Resources/Library/library.json` and `thumbs/<id>-start.png`/`-end.png`; ids = UUIDv5(namespace,
  "source:sourceId"), namespace pinned in `WorkoutsKit/Library/LibraryID.swift` with one test value. Proof: the script
  runs (≈ 25 MB), `./dev build` sees the folder.
- [ ] **0.3 Library seeding** `WorkoutsKit/Library/LibrarySeeder`: upsert by id, retire missing, never touch
  custom/override/notes, idempotent. Proof: `./dev kit Library`.
- [ ] **0.4 Settings store** `Workouts/App/SettingsStore`: `UserDefaults` backend behind a protocol, section 2 defaults,
  one key list; KVS in 7.3. Proof: `./dev test Settings`.
- [ ] **0.5 Shell and tabs**: `TabView(.sidebarAdaptable)` + `.defaultAdaptableTabBarPlacement(.sidebar)`, empty History
  · Workout · Exercises skeletons (Workout selected), Settings gear + `tabViewSidebarBottomBar` + empty Form sheet,
  empty root `fullScreenCover`. Proof: `./dev run` screenshots closed and both open poses (record where the bar lands).
- [ ] **0.6 AppNavigation**: selected tab, typed routes, cover and minimise state. Proof: `./dev test Navigation`.
- [ ] **0.7 Design colours**: asset-catalog semantic colours, light/dark. Proof: `RenderPreview` swatches, both modes.
- [ ] **0.8 MediaStore** per `docs/port/media.md`, fake `URLProtocol`. Proof: `./dev kit Media`.

### Phase 1 — Engine and native layer

- [ ] **1.1 ActiveWorkoutEngine core** (WorkoutsKit/Session): start from template/empty, resume, check/uncheck (empty
  sets refused), Previous autofill, add/replace/remove/reorder, finish (dialog data, PR count), discard. Proof: `./dev
  kit Engine` (~20 tests incl. relaunch).
- [ ] **1.2 Rest timer in the engine**: `RestTimer` over the persisted rest fields, presets, ±10 s, +30 s, skip,
  superset rest on every check, counters, relaunch restore. Proof: `./dev kit Rest`.
- [ ] **1.3 Live Activity extension + attributes**: `WorkoutsLiveActivity` target (`xcode-project` skill),
  `NSSupportsLiveActivities`, `WorkoutActivityAttributes`, stub view. Proof: `./dev build`.
- [ ] **1.4 Live Activity views**: lock screen and Island presentations per section 2 (no Island on the inner display).
  Proof: `RenderPreview` of each (`#Preview(as:using:)`).
- [ ] **1.5 Live Activity lifecycle + intents**: request/update/end from the engine; Skip / +30 s / Done set
  `LiveActivityIntent`s in WorkoutsKit. Proof: `./dev kit Activity` (state mapping, intents).
- [ ] **1.6 Notifications**: permission on first workout, `.timeSensitive` rest-end request with next-set copy, Skip/+30
  s actions, `willPresent` returns `[]`. Proof: simulator flow (shown backgrounded, absent in the foreground).

### Phase 2 — Active workout

- [ ] **2.1 SetTable component** (`Workouts/Features/Shared/SetTable`): modes template/active/past; `LazyVStack` in
  `swipeActionsContainer()` for Delete; blocks reorder via `.reorderable()` + `reorderContainer(for:)`; per-cell
  `@FocusState`, `.decimalPad`, keyboard group (−step, +step, Previous, Done, Next); `ViewThatFits` two-line rows at AX
  sizes; **Add Set** a plain trailing `Label` row; exercise `Section` headers per section 3; `.sensoryFeedback` on
  engine counters. Proof: previews at `.large` and `.accessibility3`, both widths.
- [ ] **2.2 Logging screen (compact)**: cover with the SetTable on the engine, toolbar and title per section 3,
  `isIdleTimerDisabled` gate. Proof: flow (start empty workout, log a set).
- [ ] **2.3 Rest ring item** per section 2: idle `Menu` + "Custom…" wheel sheet, running expanded sheet (trailing
  placement) with the −10 s / +10 s / Skip group. Proof: flow (pick 1:00, adjust, Skip; create a custom).
- [ ] **2.4 Rest toolbar group and minimise**: Skip / +30 s group while a rest runs, countdown + Skip in the keyboard
  group, Minimise in the Close slot. Proof: flow (check a set → ring counts down, Skip ends it, Minimise returns).
- [ ] **2.5 Resume control and resume on launch**: the ring `ToolbarItem` (elapsed when no rest runs) from a shared
  `ViewModifier` on every screen's root; additive `tabViewSidebarBottomBar` card while the sidebar is visible; tap
  restores the cover; resume sheet on launch. Proof: flow on both widths, the ring visible from History and Exercises.
- [ ] **2.6 Finish and Discard**: finish dialogs, Discard confirmation, `.warning` haptic. Proof: flow.
- [ ] **2.7 Finish summary sheet** per `active-workout.md` §3: centred, Done in the Close slot, coloured-value list
  incl. PRs (a PR row → that exercise's Records), `.levelChange` on a PR. Proof: preview at `.large` and
  `.accessibility3` + flow.
- [ ] **2.8 Regular-width logging**: `ArrangementView(primary: SetTable, secondary: exercise pane)` following the focus,
  `.split`; the pane never straddles a `.division` region. Proof: open-tall/open-wide screenshots; fold mid-workout
  keeps draft, focus, scroll.

### Phase 3 — Workout tab (templates)

- [ ] **3.1 Exercise picker** (single/multi, `.searchable`, body-part and category `Menu` pills, "?" peek), a reusable
  sheet for Add / Replace (inline create: 4.4); Add (N) (`plus`) and Superset (`rectangle.stack`) are toolbar items,
  Cancel in the Close slot. Proof: preview + flow.
- [ ] **3.2 Folders + template grid**: per-device `@AppStorage` collapse (shared with the sidebar sections, headers
  dropped beside a visible sidebar), width-derived even columns, Fitness-shaped cards (section 3),
  `matchedTransitionSource`, tap = sheet on compact / push on regular, `contextMenu`s on cards (Edit, Duplicate, Move,
  Delete) and folder headers (rename, reorder, delete with move-or-delete), no ⋯; optional drag via `reorderContainer`.
  Proof: preview + flow.
- [ ] **3.3 Template preview** (medium-detent sheet on compact, zoom push on regular) laid out per section 3. Proof:
  preview + flow on both widths.
- [ ] **3.4 Template editor shell**: pushed in both widths, `ArrangementView` on regular as in 2.8, no width cap;
  SetTable template mode, blocks, kind cycling, unit/bar/rest per row, notes, name via `toolbarTitleMenu`, exercise
  `Section` headers as in 2.1 (trailing `ellipsis.circle` menu), unsaved-changes guard. Proof: flow.
- [ ] **3.5 Supersets and warm-up ramp**: `WorkoutsKit/Session` helpers (ramp, renumbering) and superset colours. Proof:
  `./dev kit Template` + preview.
- [ ] **3.6 Sidebar Templates sections**: `TabSection` per folder, `.sidebarOnly` template tabs rendering the preview,
  `.sectionActions` "New Template". Proof: open-Duo screenshot; compact bar unchanged.

### Phase 4 — Exercises tab

- [ ] **4.1 Exercise list**: `@Query` by displayed name, `.searchable` only (no inline field, sort control or A-Z rail),
  body-part and category `Menu` pills, thumbnail rows with best set and tags, New Exercise + Show Retired toolbar items,
  `tabBarMinimizeBehavior(.onScrollDown)`. Proof: seeded preview.
- [ ] **4.2 Exercise detail shell**: About and Records segments, `MediaStore` video header with
  `.backgroundExtensionEffect()`, `records(...)`, Edit (custom only), zoom from the row. Proof: preview per segment.
- [ ] **4.3 Exercise detail History and Charts**: History segment, Swift Charts from `chartSeries`. Proof: preview per
  segment.
- [ ] **4.4 Custom exercise form** (create/edit/archive/delete-if-unused) + picker inline create. Proof: flow (create →
  in list → archive).
- [ ] **4.5 Sticky note** editor in the detail, shared with the logging pane. Proof: preview + flow.

### Phase 5 — History

- [ ] **5.1 History list**: split view (§2), month `Section`s of workout rows (section 3), paging, zoom push to the
  detail, `.searchable` + `searchScopes` (All · PRs), `contextMenu` + `swipeActions`,
  `tabBarMinimizeBehavior(.onScrollDown)`. Proof: preview with 50 seeded workouts.
- [ ] **5.2 Weekly goal chart** as the hero card (Swift Charts, goal line, Monday weeks; plain header). Proof: preview.
- [ ] **5.3 Dashboard cards**: This Week, Recent PRs, Last Workout, even columns from the grid's width, Fitness's card
  shape. Proof: preview, both widths.
- [ ] **5.4 Calendar sheet** from the Calendar toolbar item: month grid, workout days marked, tap opens the workout.
  Proof: preview.
- [ ] **5.5 Workout detail**: PR lines, trophies, the per-exercise Exercise | Best Set table, toolbar items Edit, Save
  as Template (success = `sensoryFeedback(.success)` + dismiss, no banner), Repeat, Delete. Proof: preview + flow.
- [ ] **5.6 Past-workout editor** (SetTable past mode, start time, duration), pushed from the detail, `ArrangementView`
  on regular as in 3.4. Proof: flow; later workouts' PR counts update.
- [ ] **5.7 Settings sheet** complete (iCloud status, Download all videos, Import placeholder). Proof: preview.

### Phase 6 — Duo and accessibility pass

- [ ] **6.1 Half-open bench mode**: partially open on a bench, the arrangement view puts the SetTable on the lower half
  and the exercise pane + rest countdown on the upper (glanceable on top, controls below); use `reservedRegions(kind:
  .division)` only if the system split is wrong (`onHingeChange` is for effects, not layout). Proof: Device Hub
  screenshots at two angles.
- [ ] **6.2 Pose and scenario pass** of every screen with `verify-ui`: closed portrait and landscape (title collapse, ~2
  rows above the keyboard, strip), open tall and wide, book and laptop half-open (`ArrangementView` and the split
  divider vs the fold; `List`/`Form` rows across a vertical fold; the laptop pose's lower half is also where the
  keyboard lands), Split View with another app (safe areas flip sides; PiP), fold mid-flow with a sheet, menu or dialog
  up (ring, picker selection, preview, calendar, custom timer, finish and confirmation dialogs) and with focus in a
  cell, keyboard in each pose, AX Dynamic Type in the set table, strip and pane (VoiceOver order across the strip and
  the fold). Proof: pass/fail table, every screen × pose/scenario, no breaks.
- [ ] **6.3 Accessibility audits**: VoiceOver, Dynamic Type, contrast skills. Proof: audits report clean.
- [ ] **6.4 Performance**: full-library scrolling, 600-workout chart. Proof: `xctrace` run shows no hitches.

### Phase 7 — Sync, migration, distribution (needs the Developer Program)

- [ ] **7.1 Team + entitlements**: `DEVELOPMENT_TEAM`, iCloud (container + key-value), push, time-sensitive; no App
  Group. Proof: `./dev build` signs with the team.
- [ ] **7.2 CloudKit on**: flip the flag, promote the schema to production. Proof: two simulators sync.
- [ ] **7.3 Settings on iCloud KVS**: `NSUbiquitousKeyValueStore` backend behind the `cloudKit` flag. Proof: `./dev test
  Settings` runs both backends.
- [ ] **7.4 Migration**: web Postgres → import JSON script, in-app Import. Proof: sample export imports.
- [ ] **7.5 TestFlight**: archive, export, upload. Proof: `./dev testflight`; the build installs on the Duo.

## 7. Risks and unknowns

- **Hinge APIs are real**: SwiftUI `View.onHingeChange(isEnabled:_:)` with `DeviceHingeContext` / `DeviceHinge.Status`
  (iOS 27.1) and UIKit `UIHinge` / `UIHingeInteraction`, below our 27.2 target. The simulator's fold is not scriptable
  (`verify-ui`), so 6.1 is verified by Device Hub screenshot.
- **Sidebar placement**: `.sidebarAdaptable` defaults to the iPad-style tab bar on regular width without
  `defaultAdaptableTabBarPlacement(.sidebar)`, and template `Tab`s without `.tabPlacement(.sidebarOnly)` leak into the
  compact bar (screenshots in 0.5, 3.6).
- **Live Activity cannot update itself while the app is suspended** (no push server): the countdown hitting 0:00 and the
  time-sensitive notification are the "rest over" signals. Its intents run in the app process, so the engine must resume
  the persisted workout first.
- **SwiftData + CloudKit**: no unique constraints, optional relationships, additive-only migrations once CloudKit is on;
  keep `SchemaV1` frozen after 7.2. **Island screenshots** need an Island sim (`iPhone 18 Pro`; the Duo's inner display
  has none); **TestFlight** needs the paid program (simulator-only until then).
