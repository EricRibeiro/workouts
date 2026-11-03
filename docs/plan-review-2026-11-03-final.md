Applied on 2026-11-03; kept for the rationale.

# Plan review: the whole, before building (2026-11-03, final round)

Scope: `AGENTS.md`, `docs/PLAN.md`, `docs/port/*`, the three applied reviews, `Packages/WorkoutsKit`, `dev`, `.claude/`.
No lens; read as the senior engineer and designer who signs off before a team starts. API claims were checked in the
installed 27.2 SDK swiftinterfaces (the Xcode MCP did not connect, third session in a row — see finding 5). "Verified"
= read in the SDK, a file, or reproduced on this machine; "judgment" = design opinion. Ranked by consequence.

## 1. `WorkoutsKit` cannot hold ActivityKit types and still pass `./dev kit` (high; verified)

**Where**: PLAN §2 Native layer ("`WorkoutActivityAttributes` lives in `WorkoutsKit`"), §4 tree (`Activity/` in the kit),
tasks 1.3, 1.5 ("Skip / +30 s / Done set `LiveActivityIntent`s in WorkoutsKit. Proof: `./dev kit Activity`").
**What**: `swift test` builds the package for macOS. In the macOS 27.2 SDK `ActivityAttributes` and `LiveActivityIntent`
are both `@available(macOS, unavailable)` (only the macabi interface exists). The first file that conforms to either
breaks the kit's macOS build, so every task after 1.3 loses the seconds-fast loop that `AGENTS.md` builds the workflow on.
**Fix**: keep the *state* in the kit and the *conformances* in the app. Replace the 1.3/1.5 text with:
> **1.3** `WorkoutActivityState` (Codable, Sendable, nonisolated) in `WorkoutsKit/Activity` with
> `ActiveWorkoutEngine.activityState` mapping; the `WorkoutActivityAttributes: ActivityAttributes` wrapper and the
> `WorkoutsLiveActivity` target in the app. Proof: `./dev kit Activity` (mapping) + `./dev build`.
> **1.5** Intents as `nonisolated struct`s in `Workouts/App/Intents/` (AppIntents' `perform()` is nonisolated; under
> `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` the type must opt out, then `await MainActor.run` into the engine, which
> first resumes the persisted workout). Proof: `./dev test Activity` + a Lock Screen tap on the sim.
Also add to AGENTS "Put logic in WorkoutsKit": *anything that imports ActivityKit, UIKit, WidgetKit or AppIntents'
Live Activity types stays in the app target; the kit must compile for macOS.*

## 2. The library lives in the synced store, and that is where the schema fights CloudKit (high; judgment, hazards verified)

**Where**: PLAN §2 Data ("seeded on first launch and upserted when `libraryVersion` is newer"), tasks 0.2/0.3,
`data-model.md` §4 ("de-dupe by id on seed, since two devices seeding before a sync can both insert").
**What**: 1,038 `Exercise` rows with dictionaries and five string arrays each are inserted on first launch (seconds on the
main actor unless 0.3 grows a `ModelActor` and a launch state), then sync to CloudKit as ~1k records plus 1k on every
`libraryVersion` bump, and the spec's own note admits the duplicate problem CloudKit cannot solve (no uniqueness).
Three model types (`Exercise` library rows, `ExerciseOverride`, `LibraryMeta`) and the seeder/retire/upsert logic exist
only to make read-only content look like user data. For one person this is the largest avoidable risk in Phase 0.
**Fix** (replace the Data bullet; 0.2 stays, 0.3 shrinks):
> Library content is a bundled, read-only `LibraryCatalog` (decoded once from `library.json`, in memory; `retired` is a
> flag in the file). Only **custom** exercises are `@Model Exercise` rows, carrying their own unit/bar/rest defaults.
> `TemplateExercise`/`WorkoutExercise`/`StickyNote` hold `exerciseID: UUID` (plus the `exerciseName` snapshot), resolved
> through `ExerciseStore.exercise(id:)` = catalog ∪ custom. No seeding, no `libraryVersion`, no `ExerciseOverride`, no
> `LibraryMeta` (labels ride in `library.json`). RESTRICT applies to custom exercises only (archive when referenced).
> **0.3 ExerciseStore** (kit): catalog decode, custom merge, name sort, search normalisation. Proof: `./dev kit Library`.
If Eric prefers to keep the seeded design, the minimum is a `ModelActor` seeder, a launch "Preparing library" state,
and a dedupe pass keyed by id after every CloudKit import — three tasks the plan does not have.

## 3. The JSON codec is the sample data, the backup and day-one usability; it is scheduled last (high; judgment)

**Where**: task 7.4 (needs the Developer Program), 5.1 "preview with 50 seeded workouts", 6.4 "600-workout chart",
Settings (5.7) "Import placeholder". No export anywhere; no sample-data task anywhere.
**What**: until 7.4 lands the native app has none of Eric's 615 workouts, so Previous is empty, PRs are zero and "Last
performed" is blank: strictly worse than the PWA for every day before TestFlight. Meanwhile every preview and perf task
needs realistic data and nothing produces it. And with CloudKit off, the phone's SwiftData store is the only copy.
**Fix**: add to Phase 1 and trim 7.4:
> **1.7 WorkoutsJSON codec + importer** (kit): one `Codable` document (folders, templates, custom exercises, sticky
> notes, workouts), `Importer.apply(to: ModelContext)` idempotent by id, exercise ids via `LibraryID`; a
> `scripts/export-web` Postgres → JSON script run on this Mac now. Proof: `./dev kit Import` (round-trip + idempotence);
> Eric's real export (gitignored, `docs/port/fixtures/`) imports.
> **0.9 Sample data + preview container**: `ModelContainer.preview` seeded by `SampleData` (3 templates, 50 workouts
> with PRs) and a `#if DEBUG` "Load sample data" row in Settings; every `#Preview` uses it. Proof: `./dev kit Sample`.
> **5.7** adds **Export…** (share sheet, same codec) beside Import. **7.4** keeps only the TestFlight-time run.

## 4. Phase 2 cannot be executed in the written order (high; verified by reading the tasks)

- **No entry point starts a workout.** PLAN §2 says "Start from a template or **Empty Workout** (name 'Workout')";
  `workout.md` §1 and §6 say "There is **no** Quick Start and no empty workout… gone by decision"; `active-workout.md`
  §7 still asks where Start-empty lives; the toolbar table (§2) gives the Workout tab only Settings and Add (New
  Template / New Folder). Task 2.2's proof is "start empty workout, log a set". Fix: PLAN §2 toolbar table → "Add
  (`plus`, a `Menu`: **Empty Workout** / New Template / New Folder)"; `workout.md` §1/§6: "Empty Workout exists natively
  (PLAN §2); the web's lack of it is not carried over"; close the §7 question.
- **An empty workout has no sets to log** until the exercise picker (3.1) exists. Fix: move 3.1 before 2.2 (it is a
  Shared component, not a Workout-tab feature), or make 2.2's proof "start the sample template" via 0.9.
- **2.8's exercise pane is 4.2 + 4.5 built twice** (video, instructions, Previous, records, sticky note). Fix: 4.2 builds
  `ExerciseDetailView` with an `embedded` mode; 2.8 moves after 4.5 (or ships with a `ContentUnavailableView` pane and
  is re-proved after 4.5). Say which; today a worker on 2.8 invents the pane.
- **2.7** "a PR row → that exercise's Records" needs 4.2; **5.6** needs 2.8; **3.4** needs 2.1 + 3.1. Add a one-line
  "Needs:" to those tasks so the orchestrator never dispatches them early.
- **2.5** "resume sheet on launch" is new and unspecified; `active-workout.md` §4 says relaunch reopens the cover if it
  was open, else only the ring. Fix: drop "resume sheet", keep "cover restored if it was open".

## 5. Every UI proof routes through a tool that has not connected yet (high; verified this session)

**Where**: AGENTS "Xcode's MCP tools are available"; `verify-ui` steps 1 and 3; "Proof: preview"/"flow" on ~20 tasks.
**What**: `plugin:xcode-integration:xcode` failed to connect in this session and both earlier reviews. If that holds for
workers, `RenderPreview` and `DeviceInteraction*` are unavailable and the only remaining proof is `./dev run` +
`./dev screenshot` with no way to tap. `WorkoutsUITests` exists and nothing in the plan uses it.
**Fix**: (a) `verify-ui` gets a fallback section: `./dev run -- -preview <Name>` launches a `#if DEBUG` `PreviewGallery`
root that hosts the same views as the `#Preview`s (Dynamic Type and dark via `simctl ui`), then `./dev screenshot`;
flows are XCUITests in `WorkoutsUITests` (`./dev ui-test Suite/test()`), which also forces the accessibility
identifiers AGENTS already demands. (b) `dev run` must accept launch arguments (today it ignores extra args). (c) AGENTS:
"MCP when it connects; the fallback is the proof of record" — a proof must not depend on a tool's mood.

## 6. The data spec still describes the web; task 0.1 points a worker at it (medium-high; verified)

**Where**: `data-model.md` §1 `Workout.source` (AGENTS: dropped), `ExerciseOverride.name` + `barUnit` (library rename
is gone: library rows are read-only), §5 eight "open questions" all answered elsewhere; PLAN §4 "ten `@Model` types"
(§1 lists eleven); `history.md`/`exercises.md`/`workout.md`/`active-workout.md` §7 carry 20+ questions closed in PLAN §2
without the `~~strike~~` the few closed ones got.
**Fix**: add a "Native deltas" block at the top of `data-model.md` (the field list 0.1 implements): drop `source`,
drop override `name`/`barUnit` (and, with finding 2, the whole `ExerciseOverride`/`LibraryMeta`), add
`Workout.restEndsAt/restSeconds/restSetID`, `muscles` as `[String: Int]`, the final model count. Strike every answered
§7 question with its pointer (empty workout, PR count, RPE off, timed sets in (distance out), superset rest on every
check, next-set copy, Duplicate name = "<name> copy", editor draft does not survive relaunch, sticky note editable in
the detail, archive/delete rule, sorts final, alternatives hidden, credit + 70 kept).

## 7. History on the open display: dashboard or split, not both (medium; judgment + `ref-fitness-open-wide-dark.png`)

**Where**: PLAN §2 "Exercises and History use `NavigationSplitView`"; §3/5.1 "Fitness-style dashboard… regular width
shows [the detail] as the split's detail column".
**What**: on open-wide that is the tab sidebar + a list column holding a hero chart, three cards and month rows + a
detail column: three columns, the dashboard squeezed into the narrowest. Fitness's Summary is full width with no
detail pane (photo); its disclosures push. **Fix**: "History is a `NavigationStack` in both widths (the dashboard is
full width beside the tab sidebar); rows push the detail with the zoom transition. Only Exercises keeps
`NavigationSplitView`." Update §2, 5.1, `history.md` §5.

## 8. Decisions stated twice, differently (medium; verified in the files)

- **Rest adjust pair**: §2 "Skip and +30 s (the one pair on every surface)" vs the expanded sheet's "−10 s / +10 s /
  Skip" and 1.2 "±10 s, +30 s". Decide: sheet = −10 / +30 / Skip (one engine op `adjust(by:)`), or keep ±10 in the
  sheet and say the pair rule applies to *remote* surfaces only.
- **Repeat workout**: task 5.5 lists a Repeat toolbar item; §2's toolbar table and `history.md` §3 ("the web has none",
  open question) do not. Either add Repeat to §2 (engine: `start(from: Workout)`) or delete it from 5.5.
- **TabSection expansion** (§2, 3.2): "one persisted collapse flag drives both the compact header and the `TabSection`
  expansion" — `TabSection` has no `isExpanded` binding in 27.2 (only `TableSection`'s inits take one). Rewrite: the
  header flag is per-device `@AppStorage`; sidebar section expansion is the system's and independent.
- **Week start**: AGENTS/PLAN "Monday in the device time zone" vs `history.md` §5 "consider the locale's first weekday".
  Keep Monday; delete the aside.
- **Settings tests**: 0.4 puts `SettingsStore` in `Workouts/App` with `./dev test`; it is Foundation-only (both
  backends) and belongs in the kit under `./dev kit Settings`. Same for the `AppNavigation` route model (0.6).

## 9. Engine rules a worker would have to invent (medium; judgment, kit-testable)

Add to 1.1/1.2/5.2 text: **Previous autofill across units** (the previous entry is in kg, the row in lb: convert and
round to 0.5, or refuse to fill; today unstated). **Focused exercise** for the pane (2.8): the exercise of the last
focused cell or tapped header, else the first with an unchecked set. **Weekly buckets** as a kit function
(`weeklyCounts(workouts:calendar:weeks:)`, ISO weeks, injected `Calendar`/`TimeZone`) with tests on a DST boundary
(America/Toronto, 2026-11-01) — 5.2 currently proves a chart by preview only. **Unit/formula switch**: `SettingsStore` is
`@Observable` in the environment so derived numbers recompute; `@AppStorage` alone will not refresh kit-computed values.
**Save errors**: one policy line — "`ModelContext.save()` failures surface as an alert with the message; the draft is
never discarded" (the specs dropped the web's retry UI without replacing it).

## 10. Task sizing (medium; judgment)

2.1 (five features: swipe, reorder, focus/keyboard group, AX layout, haptics), 3.2 (collapse, columns, cards, zoom,
two menus, delete-folder dialogs, drag) and 3.4 (shell, kind cycling, unit/bar/rest, notes, title menu, guard) each
name 5–8 features for one worker. Split: 2.1a set row + keyboard group (preview), 2.1b table/sections/reorder/swipe/
modes; 3.2a folders + dialogs, 3.2b grid + cards + transitions; 3.4a editor shell + save/guard, 3.4b block menu actions.

## 11. API notes for the tasks that use them (low; verified unless marked)

- `ArrangementView`, `arrangementViewStyle`, `reservedRegions`, `onHingeChange`, `ConcentricRectangle` are in
  **SwiftUICore** 27.1 (`import SwiftUI` suffices); `presentationPlacement` 27.0 with `.automatic/.leading/.center/
  .trailing` (the plan says "centred": use `.center`). Inside a `fullScreenCover` + `NavigationStack` is undocumented
  but not excluded; make 0.5 put an empty `ArrangementView` in the cover and screenshot it (cheap spike for 2.8).
- `DatePicker` has no count-down style in SwiftUI (2.3 "Custom…"): two `Picker` wheels (min / sec) or a
  `UIViewRepresentable` of `UIDatePicker` `.countDownTimer`.
- `ProgressView(timerInterval:)` with `.circular` is an indeterminate spinner on iOS (judgment from experience; the
  Live Activity minimal ring is drawn by the system). The in-app ring item needs a custom `ProgressViewStyle`
  (`Circle().trim`) fed by `TimelineView` or `ProgressView` value.
- `xcrun xcodeproj` can `target add --product-type app-extension`, `add-dependency` and `phase add-copy`, but
  `GENERATE_INFOPLIST_FILE` is not defaulted for extensions; 1.3 needs an Info.plist with `NSExtensionPointIdentifier
  = com.apple.widgetkit-extension`, the copy phase to PlugIns, and `pkg link` of the kit. Write the recipe into
  `.claude/skills/xcode-project` as part of 1.3; it is the first non-trivial project change.
- `tabBarMinimizeBehavior`, `tabViewSidebarBottomBar`, `toolbarVerticalCompressionBehavior`, `navigationSubtitle` (iOS),
  `visibilityPriority`, `sectionActions`, `swipeActionsContainer`, `reorderable`, `backgroundExtensionEffect`,
  `searchScopes`, `ToolbarOverflowMenu`: all present. Nothing else named in the plan is missing.

## 12. Workflow and settings (low; verified)

- `.claude/settings.json` allowlists `Bash(xcodebuild:*)` while AGENTS says "Always go through `./dev`" because raw
  xcodebuild floods context. Remove it (keep `xcrun:*` for `simctl`/`xcodeproj`); the hook already formats.
- Localization stance is unstated beyond "use the String Catalog": say "English only; `Text("…")` literals, no catalog
  maintenance, no `String(localized:)` in the kit" or every string becomes a catalog chore for one user.
- App icon is a placeholder and a taste item: add "0.10 App icon (ask Eric)". `media.md`: "Download all videos" (1 GB)
  is Wi-Fi-only. Phase 7 KVS backend (7.3) buys nothing for one phone; mark "only if a second device appears".

## Ready to build?

**Yes, after a half-day of document edits**: findings 1, 4 and 6 are prerequisites (a worker on 0.1, 1.3 or 2.2 today
builds the wrong thing or breaks the loop); 2, 3, 5 and 7 are decisions for the orchestrator to record in §2 before the
tasks they touch. The design itself is coherent and better than the PWA for the one thing that matters daily: rest
alarms that fire on a locked phone, with a sidebar and a fold-safe table on the Duo. The remaining risk is tooling, not
product. **Start with 0.1** against the reconciled field list from finding 6 (and finding 2 if accepted), because every
later task inserts into that schema and `SchemaV1` freezes at 7.2.
