# Active workout

Sources: web `PLAN.md:149-171`, `app/docs/ui.md` "The active workout" + "side column/bottom bar",
`app/docs/schema.md` "Workouts", `POLISH.md` items 3-5 and 11. The exercise blocks and set table are
the **template editor's** component in a `workout` mode (see `screens/workout.md`); this file covers only what differs.

## 1. Purpose

Log a session in progress: start it from a template or empty, tick sets off with weight and reps, get a rest
countdown after each tick, leave the screen without losing anything, then Finish into a saved workout. Only
**finished** workouts are persisted as history (`schema.md` "Workouts"); the in-progress one is a separate, local,
single-instance draft. At most one workout runs at a time.

## 2. Data shown

- **Header** (native: the strip, no grab handle): **Minimise** (`chevron.down`, Close slot), **Finish** (`checkmark`,
  prominent), the ring timer item, **+ Add Exercise** (`plus`). Title `navigationTitle(name)` with
  `navigationSubtitle("Nov 3 · 0:00")` (start date + live elapsed, `formatElapsed`: `m:ss`, `h:mm:ss` past an hour)
  and `toolbarTitleMenu` carrying Rename and Discard Workout.
- **Per exercise** (editor blocks): each exercise is a `Section`: header = name (primary text, tappable to the
  detail), caption "Rest 2:00", trailing `ellipsis.circle` `Menu` (Add Note, Sticky Note, Add Warm-up Sets, Update Rest
  Timers, Replace Exercise, Create/Edit Superset, Preferences, Remove Exercise; a content-level menu, so it may keep
  `ellipsis.circle`); no permanent grip (reorder with `.reorderable()`) and no chart button (name -> detail -> Charts);
  then the set table, **+ Add Set** (native: a plain trailing
  `Label("Add Set", systemImage: "plus")` row).
- **Set row**: Set # / kind (`W` warm-up, `D` drop, `F` failure; normal shows the number), **Previous**, weight
  (`lbs`/`kg` by exercise unit), Reps (or duration for time exercises; columns vary by `weight_type`), check button.
- **Previous** = the same set index from the exercise's most recent *finished* workout that has at least one completed set,
  in that entry's unit (`schema.md` "Previous"). Fetched at start and when exercises are added; stored with the draft.
- **Plan** = the template's weights/reps, shown as input placeholders; an empty set takes them when checked.
- **Rest state**: `{startedAt, durationMs, rowId?, setId?}` (`rest.ts:5-12`); display is `formatClock` (whole seconds
  rounded **up**, `m:ss`) so 0:00 coincides with the end.
- **Finished summary** (a centred `.sheet`, see §3 Finish): `checkmark.circle.fill` in ok-green, title "Workout
  complete", subtitle "Your 615th workout" (ordinal from the local count, omitted if absent), then a
  `Grid`/`LabeledContent` list in Fitness's coloured-value style: Duration, Volume, Sets, Exercises, **PRs** (count +
  trophy rows). **Volume** = weight x reps over checked,
  non-warm-up sets, kg x 2.2046226218 -> lb, for the total only (`ui.md` "Volume"; `schema.md`).
- Exercise rest length: the exercise's own, else Settings `defaultRestSeconds` (read at start, **90 s** if unset); 0 = Off.

## 3. Interactions

- **Start from template** (template preview "Start Workout") -> new ids for all exercises/sets, sets empty and
  unchecked, template weights/reps kept as plans, original template kept as `base` for the update question.
  **Start empty** -> native: Workout tab → Add → **Empty Workout** (name "Workout", no exercises; add them with "+ Add Exercise").
- **Start while one runs** -> sheet "Workout in progress": "You are in the middle of “<name>”. Resume it, or discard it
  and start the new one." Actions **Resume Workout** (recommended), **Discard and Start New** (destructive).
- **+ Add Exercise** -> exercise picker, multi-select; Previous is fetched for the new ones.
  **Replace Exercise** (exercise ⋯) -> single-select picker, keeps the sets. **Remove Exercise** -> removes it (a rest started by hand
  is left running; one tied to its sets is not, `ui.md`).
- **Edit weight / reps** -> numeric keypad on touch devices; digits, `.` (weight only, once), backspace, `-step`,
  `+step`, **Previous** (copies that set's values into the focused row), **Done** (only closes the keypad; never
  checks). Steps: weight 2.5 lb / 1.25 kg (doubled for barbell), reps and time 1. Weight max 2 decimals, never < 0.
  Focus selects cell text; first key replaces it. No Next key, no check key.
- **Tap Previous cell** -> copies that set into the row. **Tap Set #** -> pick kind (W, D, F, normal).
- **+ Add Set** -> copies previous set's values, unchecked. **Swipe left / long-press** on a set -> delete.
- **RPE**: the web UI has **no RPE entry** (only the stored field `rpe`, kept by the past-workout editor,
  `history/draft.ts:50,93`); `POLISH.md:451` lists it as an unbuilt idea. See Open questions.
- **Check a set** (44 px button) -> `filled()` first fills empty weight/reps/time from Previous, else from the plan;
  row turns green (tinted edge to edge, fields read as plain text, still editable); button pops (scale 1->1.18
  over 360 ms) and the tick draws; **rest starts** (exercise rest, else default; replaces any running rest);
  haptic switch on the check. **Uncheck** -> row reverts and cancels the rest *that set* started.
- **Check a set with nothing to record** (no weight/reps/time even after `filled()`, e.g. a fresh + Add Set) ->
  refused: check greys, row shakes (400 ms, `cell-shake`) with a red ring; nothing is checked (`workout/model.ts` `canCheck`, `ui.md`).
- **Rest timer button** (native: the ring toolbar item; idle = stopwatch glyph; running = countdown ring). Idle it is
  a `Menu` (a toolbar item that offers a short list is a menu, not a sheet): **0:30, 1:00, 2:00, 3:00**, a divider,
  saved customs (newest first), then **Custom...** opening a small sheet with two `Picker` wheels (min / sec; SwiftUI has no
  countdown `DatePicker`) and a **Start** toolbar item, which also saves it. Customs: setting `restPresets`, newest first,
  max **6**, no repeats, never a default one, 1 s to 3600 s (`rest.ts`). A preset/custom starts a rest belonging to no
  set. The web's printed-inside-a-ring preset layout and bottom "Create Custom Timer" bar are not carried over.
- **Running rest sheet** (tapping the ring): the expanded ring (Clock's: arc shrinking from 12 o'clock, time left over
  total), trailing placement on regular width. **-10s**, **+10s**, **Skip** are a horizontal `ToolbarItemGroup` placed
  by the system (vertical in the strip when closed), not a button row in content; ±10 s exist only here. While a rest runs the
  logging toolbar also gains **Skip** (`forward.end`) and **+30 s** (`goforward.30`) items below the ring: the one pair used
  everywhere else (strip, keyboard group, Live Activity, notification). `-10s` clamps at 0 (ends it). `+10s` on an already-over rest restarts from now with just +10 s. Skip ends the rest and closes the sheet.
- **Rest ends** (zero) -> pill flashes green `0:00`, phone vibrates (not on iOS Safari) and beeps once per end time,
  skipped if it ended > **8 s** before the page looked (`STALE_MS`); ~**3 s** later (`FLASH_MS`) the rest is
  forgotten and the idle button returns. Backgrounded: nothing fires in a frozen PWA (`POLISH.md:142`); on return the
  remaining time is recomputed from the clock, and a long-over rest is silently dropped.
- **Minimise**: tap the Close-slot item (`Button("Minimise", systemImage: "chevron.down")`, top of the strip, Finish
  next). No grab handle, drag, 1/3-height threshold, velocity rule or tab-tap: a `fullScreenCover` has no interactive
  dismissal and no tab bar. **Tap the ring item** (or the sidebar card) -> reopen.
- **Other tabs while running** -> the logging screen is a full-screen layer above all tabs, not routed; minimised,
  every tab works normally and the ring toolbar item stays visible (`DECISIONS.md` "Minimised workout").
- **Ring item content**: a custom `ProgressViewStyle` ring (`Circle().trim` fed by `TimelineView`) with `Text(timerInterval:)` inside; elapsed time when no
  rest runs. The sidebar card (name · elapsed · countdown · Skip) is additive while the sidebar is visible.
- **Screen stays on** while the logging screen is open if Settings "Keep screen on during a workout" (default on).
- **Finish** (tap green Finish):
  - nothing checked -> sheet "Nothing logged yet" / "Check off at least one set to save this workout, or discard it." with **Discard Workout** (destructive) and **Keep Going**.
  - unchecked sets with values -> action sheet "Finish Workout?": **Complete Unfinished Sets** (recommended; checks them, `doneAt = now`, no rest started), **Discard Unfinished Sets** (destructive), **Cancel**.
  - unchecked sets without values only -> "N sets are not checked and will not be saved" with **Finish Workout** / **Keep Logging**.
  - Unchecked sets not completed are not saved; an exercise with no checked set is dropped. `finishedAt` is clamped to >= `startedAt`.
  - Saved as one document, then the summary appears as a `.sheet` (`presentationPlacement(.center)` on the inner
    display): **Done** is the Close-slot toolbar item, nothing bottom-anchored. Content per §2; `sensoryFeedback(.levelChange)`
    on a PR; tapping a PR row opens that exercise's Records.
  - From a template, if exercises/sets differ -> "Update Template?" sheet: **Update Values Only**, **Update Template and Values** (destructive), **Keep Original Template**; or just **Update Template** / **Keep Original Template** when only values differ. The workout is saved either way. Skipped if the template was deleted meanwhile.
- **Discard Workout** (`toolbarTitleMenu`) -> confirm "Discard workout?" / "This workout and everything logged in it will be deleted. It cannot be undone." with **Discard Workout** (destructive) and **Keep Going**.

## 4. States

- **Empty / nothing running**: no ring item, no timer. Idle rest button is a plain stopwatch.
- **Relaunch with a workout in progress**: the whole draft (sets, start time, rest, Previous, default rest, whether the
  screen was open) is written on every change; reload, app switch, eviction or fold/rotate loses nothing and it reopens on
  the logging screen if it was open, else the ring item. Unreadable storage means a clean start. A rest still running keeps
  counting from its timestamps; one that expired while away shows over/gone per the 8 s and 3 s rules.
- **Finish in flight**: draft, check, use-Previous and Complete-Unfinished actions are ignored (rest actions still work).
- **Finish failed**: workout stays active; message "Could not save the workout: <why>. It is still here and nothing is lost." with
  **Retry** / Dismiss. Web-specific 20 s request timeout. Never discard on error.
- **First run / no Previous**: Previous cells empty; Previous key disabled; checking needs typed values or a plan.
- **Stale Finish**: if a late save lands after "Discard and Start New", the old summary shows but the new workout is untouched.

## 5. Native mapping

- **State**: an `@Observable` active-workout model, one instance, persisted as a SwiftData draft written on each change
  (CloudKit-friendly: optional relationships, defaults). Finish converts the checked sets into `Workout` rows in one save;
  no network, so no Retry/in-flight lock/20 s timeout. Snapshot `exercise_name` into each workout exercise (`schema.md`).
- **Rest timer correctness**: store `endsAt` (a `Date`) and the total duration, never a tick counter; derive remaining
  time with `TimelineView`/`Text(timerInterval:)` so it is right after lock, background or relaunch.
- **Live Activity + Dynamic Island** (ActivityKit) replace the dock's rest display and the web "no alarm on a locked
  phone" gap (`POLISH.md:23`): shows exercise, current set, and the countdown via a timer-interval text so it runs with
  the app suspended; end the activity on Finish/Discard. Skip / +30 s as `Button(intent:)` App Intents. The Island
  exists only on the closed display; open, the Lock Screen presentation and the notification are the signals.
- **Rest end**: schedule a local `UNNotificationRequest` at `endsAt` ("Rest over"; cancel on Skip, uncheck, adjust, Finish).
  Foreground end: `sensoryFeedback` + flash instead of vibrate/beep; no AudioContext priming needed.
- **Haptics**: `sensoryFeedback` on check, rest end, Finish, and minimise/restore.
- **Minimised workout**: no dock and no bottom inset. See `DECISIONS.md` "Minimised workout": the ring toolbar item on
  every screen (trailing strip closed/open-wide, top bar open-tall) plus an additive `tabViewSidebarBottomBar` card
  while the sidebar is visible; tap reopens the full-screen cover. Do not read device idiom; use the size class.
- **Logging screen**: `fullScreenCover` with the set table; Minimise and Finish are toolbar items (no drag-down, no
  `interactiveDismissDisabled` gesture). Rest controls are toolbar items (ring, then Skip / +30 s; the keyboard
  `ToolbarItemGroup` prepends the countdown, Skip and +30 s), never a `safeAreaBar`. Idle ring = `Menu`; running ring = the
  expanded sheet (trailing placement), Close in the strip.
- **Regular width (open Duo)**: `ArrangementView(primary: SetTable, secondary: exercise pane)` per `DECISIONS.md` / task
  2.10; the pane has no Close of its own (the web's X was the pane's, `duo-open-wide-active-workout-exercise-pane.png`).
- **Keypad**: a custom numeric keypad was a web workaround for the iOS keyboard; native uses `.keyboardType(.decimalPad)`
  with a toolbar of -step, +step, Previous, Done and a Next (weight → reps → next row), keeping the same steps.
- **Keep screen on**: `isIdleTimerDisabled` while the logging screen is open and the setting is on.

## 6. Dropped or changed on purpose

- Web Push, service worker, Screen Wake Lock re-acquire on `visibilitychange`, WebAudio priming, `navigator.vibrate`
  fallbacks: replaced by local notifications, Live Activity, `sensoryFeedback`.
- localStorage draft, idempotent client-UUID `PUT`, Retry/Dismiss finish error, 20 s timeout, stale-Finish guard, send-lock:
  not needed local-first (`AGENTS.md` product decisions).
- Server-computed ordinal and PR counts: derive locally from SwiftData.
- Custom in-app keypad, its blur-close timing and click-through concerns.
- Rest 3-second "forget after flash" is a web display detail; native may keep it for the in-app ring item.

## 7. Open questions (all closed 2026-11-03; answers in `DECISIONS.md`)

- ~~Start empty: where does it live and what is it called?~~ Workout tab → Add → Empty Workout, named "Workout".
- ~~PR count in the summary?~~ Shown (native improvement; computed by `prsInSession`, `data-model.md` §3).
- ~~RPE?~~ No UI; the `rpe` field stays in the model.
- ~~Time/distance weight types?~~ Timed sets in, distance out (`screens/workout.md` §6).
- ~~Open-Duo layout: set table + exercise detail or table + History? Does Rest Timer stay a sheet?~~ `ArrangementView`,
  exercise pane; the idle ring is a `Menu`, the running ring an expanded sheet.
- ~~Superset rest?~~ Web behaviour: a rest starts on every check.
- ~~Notification copy?~~ Includes the next set ("Rest over · Set 3 · 27.5 lb × 8").
