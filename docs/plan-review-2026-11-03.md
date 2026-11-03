# Review of `docs/PLAN.md` — 2026-11-03

Lens: is this the right plan for a Duo-first, iOS 27 native port of the web tracker? Facts were checked
against the installed iOS 27.2 SDK swiftinterfaces (Xcode 27.2) and Apple's `swiftui-whats-new-27`,
`swiftui-specialist` and `app-resizability` skills; the Xcode MCP server did not connect, so
`DocumentationSearch` was not available. "Verified" below means a declaration and its `@available` were
read in the SDK; "judgment" means design opinion.

**API audit (all verified in the SDK).** `.tabViewStyle(.sidebarAdaptable)`, `TabSection`,
`TabPlacement.sidebarOnly/.pinned`, `defaultAdaptableTabBarPlacement(.sidebar)`, `tabViewSidebarBottomBar`
— iOS 18. `.tabViewBottomAccessory`, `tabViewBottomAccessoryPlacement` (`.inline`/`.expanded`),
`tabBarMinimizeBehavior`, `.glassEffect(_:in:)`, `GlassEffectContainer`, `safeAreaBar(edge:)`,
`.buttonStyle(.glass)` — iOS 26. `.navigationTransition(_:)` + `.zoom(sourceID:in:)` — iOS 18 (needs
`matchedTransitionSource`; the plan's bare `.navigationTransition(.zoom)` does not compile).
`Text(timerInterval:pauseTime:countsDown:showsHours:)` and `ProgressView(timerInterval:)` — iOS 16.
`Button(intent:)` — iOS 17 (`_AppIntents_SwiftUI`); `LiveActivityIntent` exists. `.sensoryFeedback` with
`.impact(weight:)`, `.success`, `.levelChange`, `.selection`, `.warning` — iOS 17. `NSUbiquitousKeyValueStore`
present. `ModelConfiguration(cloudKitDatabase: .none)` present. `.reorderable()`/`reorderContainer(for:)`
and `swipeActionsContainer()` — iOS 27. **Hinge APIs exist**: UIKit `UIHinge`/`UIHingeInteraction` and
SwiftUI `DeviceHinge`, `DeviceHingeContext`, `View.onHingeChange(isEnabled:_:)` — iOS 27.1, below our
27.2 target. `UNNotificationInterruptionLevel.timeSensitive` exists and `UNAuthorizationOptionTimeSensitive`
is deprecated "Use time-sensitive entitlement". Nothing the plan names is deprecated.

## Findings, ranked by impact

### 1. The active workout must not change host when the phone folds (high; judgment, API-backed)

Plan (§2 Navigation): "Active workout: a full-screen cover on compact. On regular width it takes the
detail column of the Workout tab". Three problems: (a) a fold mid-set moves the view between a
`fullScreenCover` and a column — a different view identity, so focus, scroll and the keyboard are lost at
the worst moment, and task 3.4 "fold mid-workout keeps state" becomes a fight against the framework;
(b) a running workout must survive any tab change (the web minimises on tab tap), but a detail column
belongs to one tab; (c) with Templates as `TabSection` items, selecting one in the sidebar replaces the
Workout tab's content entirely (see 2), so "the Workout tab's detail column" is not a stable place.
Replace with:

> **Active workout**: one presentation in both widths — a `fullScreenCover` on the root `TabView`, not
> tied to any tab, as the web's full-screen layer. Inside it the layout follows `horizontalSizeClass`:
> compact → the set table; regular → `HStack` set table | exercise pane (video, instructions, Previous,
> records, sticky note), the pane following the focused exercise. Folding only changes the size class
> inside the cover, so the draft, focus and scroll are untouched. Minimise dismisses the cover; the
> bottom accessory (and Live Activity) restore it.

### 2. The sidebar design is under-specified and will not behave as written (high; verified)

Plan: "Compact → bottom tab bar; regular (open Duo) → sidebar. The sidebar carries a Templates
`TabSection`: one item per folder, templates as children". Facts: on regular width `.sidebarAdaptable`
defaults to the iPad-style tab bar with a sidebar toggle, not a sidebar — `defaultAdaptableTabBarPlacement(.sidebar)`
sets the default; `Tab`s inside a `TabSection` need `.tabPlacement(.sidebarOnly)` or they appear in the
compact tab bar; a selected template `Tab` *is* the content, so its view must be the preview; and
`TabSection` has one level (folder header → template tabs), not folder tabs with children. Also,
AGENTS.md warns bars may be placed vertically on the inner display, and at 867 pt a sidebar + list +
detail is three columns, so inner `NavigationSplitView`s need widths. Replace with:

> `TabView` with `.tabViewStyle(.sidebarAdaptable)` and `.defaultAdaptableTabBarPlacement(.sidebar)`.
> Three top-level `Tab`s (Workout, History, Exercises). One `TabSection` per **folder**, header = folder
> name, children = that folder's templates as `Tab`s with `.tabPlacement(.sidebarOnly)` (never in the
> compact bar), each rendering the template preview with Start / Edit; `.sectionActions` carries "New
> Template". Settings sits in `tabViewSidebarBottomBar`. Where the system places the bar (sidebar, top
> bar, or a vertical bar on the inner display) is not assumed; both open poses are screenshots in 0.5.
> Exercises and History use `NavigationSplitView` with `navigationSplitViewColumnWidth(min:ideal:max:)`
> on the list so the detail keeps ≥ 420 pt beside an open sidebar; the Workout tab is a single column
> (grid) in both widths since the sidebar already lists templates.

### 3. Live Activity, notification and extension plumbing (high; verified + judgment)

Plan (§4): intents reach the engine "via an app-group-shared store (the extension gets a read-only
snapshot in `UserDefaults(suiteName:)` and sends intents to the app)". A `LiveActivityIntent`'s
`perform()` runs **in the app process**, so the intent calls `ActiveWorkoutEngine` directly; the
extension renders `ContentState` and reads nothing. Drop the snapshot store; the App Group is unneeded
until something else wants it. Two gaps: the activity cannot change state at rest end while the app is
suspended (no push server), so `Text(timerInterval:)` reaching 0:00 is the only in-Island signal and the
local notification is the alarm; and nothing says the notification is suppressed when the app is
foreground (then it duplicates the haptic + flash). Replace §2 "Native layer" Live Activity bullet with:

> **Live Activity** (`WorkoutsLiveActivity` extension; `NSSupportsLiveActivities` in Info.plist).
> `ContentState`: exercise name, set index/count, next-set text, `startedAt`, `restEndsAt?`. Lock screen
> + expanded Island: exercise, "Set 3 of 4", rest countdown `Text(timerInterval:)` or elapsed
> `Text(timerInterval: startedAt...distantFuture, countsDown: false)` when no rest runs; buttons
> `Button(intent:)` **Skip** / **+30 s** / **Done set** as `LiveActivityIntent`s that call the engine
> in-process. Compact: leading exercise glyph, trailing countdown text; minimal `ProgressView(timerInterval:)`
> ring. `staleDate = restEndsAt`, `relevanceScore` 1 while resting. Request on workout start, update on
> every check/skip/adjust, `end(dismissalPolicy: .immediate)` on Finish/Discard. The activity cannot
> flip to "rest over" while suspended; the notification is the alarm. Rest end in foreground: the
> `UNUserNotificationCenterDelegate` returns `[]` from `willPresent` and the app plays haptic + flash.
> Entitlements (§4): add `com.apple.developer.usernotifications.time-sensitive` for
> `.timeSensitive`; remove App Groups until a consumer exists.

### 4. Rest timer: persistence and the pill's placement (medium-high; verified + judgment)

Plan: "store `restEndsAt: Date`" in the engine, but `data-model.md` gives `Workout` no rest fields, so a
relaunch (task 3.1 "resume") cannot restore a running rest; and the "floating bottom-centre glass pill"
sits exactly where the decimal keyboard and its accessory are during logging. Replace with:

> Rest state is persisted on the in-progress `Workout` as optional `restEndsAt`, `restSeconds`,
> `restSetID` (CloudKit-safe, cleared on end), so relaunch resumes it. In the logging screen the
> running rest is a `safeAreaBar(edge: .bottom)` (system glass, stacks correctly with the keyboard and
> scroll-edge effects) showing the countdown, −10 s / +10 s / Skip as `.buttonStyle(.glass)`; the
> header keeps the web's timer button (idle: stopwatch; running: countdown) as a `ToolbarItem`. No
> hand-placed `.glassEffect()` unless something floats over content.

### 5. The shared set table is the product and has no task (medium-high; verified + judgment)

The template editor, logging screen and past-workout editor are "one shared component" (port spec), the
rows need swipe-to-delete and drag reorder outside a `List`, and the plan's "rows may wrap" at AX sizes
is not a layout. Add to Phase 2, before 2.3:

> **2.0 SetTable component** (`Workouts/Features/Shared/SetTable`): modes template / active / past.
> `LazyVStack` of rows inside `swipeActionsContainer()` (iOS 27) for trailing Delete; exercise blocks
> reorder with `.reorderable()` + `reorderContainer(for:)`; `@FocusState` per cell, `.decimalPad`,
> keyboard `ToolbarItemGroup(placement: .keyboard)` with −step / +step / Previous / Done, and a Next
> that advances weight → reps → next row (the native keyboard covers half the closed screen, so
> re-tapping cells is the cost the web keypad avoided). At `dynamicTypeSize.isAccessibilitySize` each
> row becomes a two-line stack (set+previous / weight+reps+check) via `ViewThatFits`. Haptics fire on
> engine counters (`checkCount`, `restEndCount`) as `.sensoryFeedback` triggers. Proof: previews at
> `.large` and `.accessibility3`, both widths.

### 6. Two contradictions with AGENTS.md (medium; verified in the two files)

AGENTS.md: tabs "(History, Workout, Exercises); Settings is a gear toolbar button on **History**".
PLAN.md: "Workout, History, Exercises (Workout first and default)" and the gear "on the **Workout** tab".
Eric's recorded answers are in AGENTS.md and the plan says never to re-ask. Replace PLAN §2 with:

> Tabs in the web's order **History, Workout, Exercises**; Workout is the default selection. Settings
> is a gear `ToolbarItem` on History (as answered) and `tabViewSidebarBottomBar` on regular width.

### 7. Hinge handling is a real, verified capability — use it (medium; APIs verified, value judgment)

Plan §7: "the hinge-aware layout APIs named in third-party posts are unverified". They are in the SDK
(above). The half-open pose is the one place a foldable beats a phone for logging: prop the Duo on the
bench, media on the upper half, table on the lower. Replace the risk bullet and add a task:

> §7: Hinge APIs are `View.onHingeChange` / `DeviceHinge.Status` (iOS 27.1, SwiftUI) and
> `UIHingeInteraction` (UIKit); the simulator's fold is not scriptable, so hinge work is verified by
> screenshot through Device Hub. **6.4 Half-open pose**: when `status == .partiallyOpen` and the width is
> regular, the logging screen stacks exercise media (top) over the set table (bottom) with the split on
> the hinge line (`safeAreaInsets` + `GeometryReader`); any other status restores the side-by-side
> layout. Proof: open-tall screenshots at fully open and partially open.

### 8. Phase order back-loads the risk Eric cares about (medium; judgment)

The engine, the extension target and notifications land in Phases 3–4 after two UI phases. The extension
target is a project-file change (new target, signing-free on the simulator) and the Live Activity is the
feature that justifies the port. Reorder: `0.5 shell → 3.1 engine → 4.2 extension + attributes (stub
UI) → 4.1 notifications → 3.2/3.3 logging → 2.x templates → 1.x exercises → 5.x history`. Then split the
oversized tasks: **0.5** → shell/tabs, `AppNavigation` + tests, Design colours; **1.2** → detail shell +
About/Records, History/Charts; **2.3** → editor shell + menus, supersets + warm-up ramp (kit) + colours;
**3.2** → table wiring, rest bar + minimise; **5.1** → list + paging, weekly chart, calendar. Each
currently names 4–8 features for "one Sonnet worker".

### 9. Settings on `NSUbiquitousKeyValueStore` before the entitlement exists (low-medium; judgment)

KVS needs the iCloud key-value entitlement (Phase 7.1). Until then the plan's "`UserDefaults` fallback for
previews/tests" must be the **runtime** path too, behind the same flag as CloudKit, or settings silently
fail to persist. Replace 0.4: "`SettingsStore` with a `UserDefaults` backend now and the KVS backend
selected by the same `cloudKit` flag as the container; both share one key list and one test."

### 10. Bottom accessory needs both placements and a minimising bar (low; verified)

`tabViewBottomAccessoryPlacement` reports `.inline` (collapsed into the tab bar on scroll) or
`.expanded`. Add to §2: "The accessory reads `tabViewBottomAccessoryPlacement`: `.expanded` shows name ·
elapsed · rest countdown · Skip; `.inline` shows only the countdown (or elapsed). History and Exercises
lists set `tabBarMinimizeBehavior(.onScrollDown)`." (Apple's skill names `toolbarMinimizeBehavior` for
iOS 27; it is not in the 27.2 interface, so do not plan on it.)

### 11. Small corrections (low; verified)

- `.navigationTransition(.zoom)` → `.navigationTransition(.zoom(sourceID:in:))` with
  `.matchedTransitionSource(id:in:)` on the card/row; works for the preview sheet too.
- Workout-tab template grid on regular: with Templates in the sidebar (2), the 3-column grid is the
  Workout tab's whole content; the "detail shows the preview" sentence in §3 goes.
- Multi-window and hardware-keyboard shortcuts: deliberately out — one scene, no keyboard on a Duo.
  Say so in §1 so nobody adds `UIApplicationSupportsMultipleScenes`.
- Drag and drop between folders (template → folder) is cheap once 2.0's `reorderContainer` exists;
  mention it in 2.1 as optional.

## Keep as is

- SwiftData + CloudKit rules (optional relationships, defaults, no `.unique`, `.none` until 7.1).
- Three tabs, no Settings tab; Settings as a `Form` sheet.
- Push for details on compact; template preview as a medium-detent sheet with Start pinned.
- Card grid on compact (2 columns) and 3 on regular; collapsible folders.
- `Text(timerInterval:)` from `restEndsAt`, never a tick counter; `isIdleTimerDisabled` gate.
- Notification copy with the next set, Skip / +30 s actions, `.timeSensitive`.
- System decimal pad + keyboard accessory first, custom keypad only if measured worse.
- Haptics map via `.sensoryFeedback`; superset rest on every check; PR count in the summary.
- Semantic colours in the asset catalog, system material everywhere else.
- Bundled library + thumbnails, streamed videos (`media.md`); no widgets/Shortcuts/HealthKit/Watch.
- `WorkoutsKit` owning models, engine, seeding and media, tested with an in-memory container.
- Phase 7 gated on the Developer Program; four-pose verification and accessibility audits in Phase 6.
