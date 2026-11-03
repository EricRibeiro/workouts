Applied to PLAN.md and the screen specs on 2026-11-03; kept for the rationale.

# Plan review: PWA bias on the iPhone Duo (2026-11-03, round 2)

Eric's brief: "look for biases towards the PWA design in the plan instead of fully focusing on Apple guidelines and
the examples I shared for total duo support." Scope: `docs/PLAN.md` §2–3 and phases 2–5, `docs/port/screens/*.md`,
judged against `docs/port/duo-layout.md` and the photos (`ref-*.png` = Claude, Flighty, Fitness; `duo-*.png` = the
PWA). Round 1 (`plan-review-2026-11-03-duo.md`) is taken as applied. Test applied to every design statement: does it
exist because the PWA did it, or because Apple or a reference app does it? Pure product behaviour (data shown, rules,
dialog copy) is exempt. Confidence: **A** = Apple rule in `duo-layout.md`, **P** = observed in a photo, **J** = judgment.

What the photos add this round: **Fitness open-wide has no sidebar** — the vertical tab capsule stays in the strip and
the content is a full-width grid of mixed-width, plain-fill cards (`ref-fitness-open-wide-dark.png`). **Flighty
open-wide** keeps its tab bar *horizontal inside the leading panel* with search beside it; only map tools sit in the
strip. **Claude's sidebar** is fixed sections, then a "Recents" list, with the avatar and a compose button at its foot.
**No reference app shows a list | detail split with a "Select a …" placeholder**: that shape appears only in the PWA
(`duo-open-wide-workout.png`, `duo-open-wide-history-detail.png`). The findings below are ranked by how much they
still make the app read as a web port.

## Findings

### 1. The open-display screens are the PWA's two panes with the chrome moved (high; P + A)
**Plan says**: `workout.md` §5 "regular width (open Duo) `NavigationSplitView` with the folder/template list and the
template preview in the detail column ('Select a template' placeholder), mirroring web's expanded list + preview panes
(`ui.md:150`)"; `history.md` §5 "Expanded (open Duo): `NavigationSplitView` list | detail, placeholder `Select a
workout`"; `exercises.md` §5 the same with "Select an exercise"; PLAN §2 "Exercises and History use
`NavigationSplitView` with `navigationSplitViewColumnWidth(min:ideal:max:)` so the detail keeps 420 pt beside an open
sidebar". **PWA origin**: the web's `>= 600 px` expanded layout (`layout-and-style.md` §1: list pane 42 %, clamp
240–360 px, detail beside it, `.barcol` on the right) — every `duo-open-wide-*.png`. **Idiom**: `duo-layout.md`
"Split views expand on the inner display… `NavigationSplitView` adjusts column widths and margins to the fold on its
own", "design by size class, never by numbers", "fixed widths are forbidden"; Mail's model is *one more level of
hierarchy*, not a 50/50 table. 420 pt is a number that exists only because the web had `clamp(…)`. The `workout.md`
text also contradicts PLAN §2 (Workout is single-column; the sidebar lists templates) — a worker reading the spec
builds the web. **Replace**: in PLAN §2 drop the width clause: "Exercises and History use `NavigationSplitView` with
no column-width modifiers; the system sizes columns and keeps them off the fold. Compact → push." In `workout.md` §5
replace the first sentence with "Regular width: the Workout tab is one column (PLAN §2); templates are sidebar tabs
(3.6). No split view, no placeholder." In `history.md`/`exercises.md` §5 keep `NavigationSplitView` but delete the
width talk; the empty detail is `ContentUnavailableView` (Mail's "No Message Selected" — a native keep, see below).

### 2. History is the web's list; Fitness's dashboard never appears (high; P + J)
**Plan says**: PLAN §3 "History tab: weekly goal chart → month sections → cards with best sets and PR count… Open
Duo: list | detail"; task 5.1 "cards, month sections, paging, best sets"; `history.md` §2 the `WorkoutCard` with its
`Exercise | Best Set` table. `history.md` §5 "Search is not in the web; add `.searchable` only if Eric asks."
**PWA origin**: `HistoryPage.tsx` verbatim (`duo-open-wide-history-detail.png`: chart card, month heading, card with a
two-column table, 50/50 detail). "Not in the web" is the only reason search is missing. **Idiom**: `duo-layout.md`
names Fitness as the "direct model for… the History dashboard cards", yet no task builds one. Fitness
(`ref-fitness-*.png`): large title, a full-width hero card, then even-column cards each with a title row, a
`chevron.right` disclosure, one headline value and a caption; open-wide the same cards reflow to mixed widths across
the whole display, no detail pane. Flighty puts `.searchable` on every list (strip foot, `ref-flighty-closed-list.png`).
**Replace** PLAN §3 History with: "History is a Fitness-style dashboard: large title; hero card = the weekly goal chart
(Swift Charts, full width); then even-column cards from the grid's own width (the same `onGeometryChange` rule as the
template grid): This Week (count vs goal), Recent PRs (trophy list), Last Workout (name · duration · volume, chevron
to the detail); then month `Section`s of workout rows (name, date, duration · volume · PRs, trophy) — the per-row
Exercise | Best Set table moves into the detail. Rows push the detail (zoom transition); regular width shows it as the
split's detail column. `.searchable` over workout name and exercise names with `searchScopes` (All · PRs)." Task 5.1
→ "History dashboard + list"; 5.2 stays the hero card. Confidence on *which* cards is J (taste — ask Eric); on the
shape, P.

### 3. The finish summary is the web's modal with a bottom Done pill (high; A + P)
**Plan says**: task 2.5 "summary with PR count"; `active-workout.md` §2 "green check, 'Congratulations!', 'That's your
615th workout!', then duration, volume, sets, exercises", §3 "Summary appears, **Done** dismisses it". **PWA origin**:
`duo-open-wide-finish-summary.png` — centred modal, four 2×2 stat cards, "Saved to your history.", a full-width blue
Done pinned at the foot. **Idiom**: `duo-layout.md` "No bottom surfaces"; sheets get vertical bars with Close at the
top; Fitness shows a finished session as a stat list with coloured values and a toolbar Done. **Replace** `active-
workout.md` §3 "Finish" with: "Summary is a `.sheet` (`presentationPlacement` centred on the inner display): Done is
the Close-slot toolbar item, nothing bottom-anchored. Content: `checkmark.circle.fill` in ok-green, title
'Workout complete', subtitle 'Your 615th workout', then a `Grid`/`LabeledContent` list — Duration, Volume, Sets,
Exercises, **PRs** (count + trophy rows) — in Fitness's coloured-value style; `sensoryFeedback(.levelChange)` on a PR.
Tap a PR row → that exercise's Records." Task 2.5 text → "summary sheet per `active-workout.md` §3".

### 4. The rest sheet is the web's ring-with-presets (medium-high; J + P)
**Plan says**: PLAN §2 "The ring `ToolbarItem` (idle: stopwatch; running: countdown) opens the ring sheet, where −10 s
/ +10 s / Skip sit under the ring"; `active-workout.md` §3 "Idle sheet: presets 0:30, 1:00, 2:00, 3:00 plus saved
custom ones, and Create Custom Timer (minutes + seconds, then Start Timer)". **PWA origin**:
`duo-open-wide-rest-presets.png` (four presets printed inside a decorative ring, a grey "Create Custom Timer" bar at
the foot) and `duo-closed-rest-timer.png` (−10s / +10s / Skip as a bottom button row). Round 1 kept the sheet; the
*idle* half is pure web. **Idiom**: a toolbar item that offers a short list opens a `Menu`, not a sheet (Flighty's ⋯,
Claude's ⋯); Apple's Clock starts a timer from a wheel picker and shows recents as capsules. **Replace** PLAN §2 "Rest
UI" sentence 2 with: "Idle: the ring item is a `Menu` — 0:30 / 1:00 / 2:00 / 3:00, a divider, saved customs (newest
first, max 6), 'Custom…' opening a small sheet with a countdown wheel (`DatePicker` `.countDownTimer` style) and a
Start toolbar item. Running: tapping the ring opens the expanded sheet (Clock's ring, remaining over total); −10 s /
+10 s / Skip are a horizontal `ToolbarItemGroup` placed by the system (vertical in the strip when closed), not a
button row in content." Keep the business rules (max 6, 1–3600 s, no repeats). `active-workout.md` §3 follows.

### 5. The Workout tab on the open display duplicates the sidebar and keeps the web's sheet (medium; A + J)
**Plan says**: PLAN §3 "On the open Duo the grid is the tab's whole content and the sidebar lists the templates (a
selected one shows its preview)… Tap → preview sheet (medium detent)"; §2 "The template preview stays a
medium-detent sheet"; §3 "cards show the exercise summary and 'last performed' exactly as the web". **PWA origin**:
`duo-open-wide-workout.png` (grid left, preview right) — the sidebar template tabs were bolted on beside it, so a
template now exists twice on the inner display, and tapping a card there raises the web's sheet in a regular-width
window. **Idiom**: `duo-layout.md` "show one more level of hierarchy than on the outer display" — on regular width a
card should *select* (push with the zoom transition), not sheet; Claude's content area shows the selected Recents
item, never a second list of them. Fitness's cards carry a title row + `chevron.right`, a headline, a caption — not
"exactly as the web" (name, three clamped lines, clock glyph). **Replace** PLAN §2 sentence with: "Card tap: compact
→ the medium-detent preview sheet (a Maps/Flighty bottom panel, fine on a phone-sized display); regular → push the
preview (zoom transition) so the sidebar stays. On regular width the sidebar is the folder/template hierarchy and the
Workout tab's grid is its home screen — keep the grid, but with the sidebar visible the folder headers are redundant
and collapse state is the sidebar section's (`TabSection` expansion), not a second per-device flag." §3: "cards:
title row with `chevron.right`, headline = exercise count ('7 exercises'), caption = first exercises, footnote 'Last
performed · 5 days ago'; content is the web's, the shape is Fitness's." Tasks 3.2/3.3: "sheet on compact, push on
regular".

### 6. Sheets never pick a placement; the Island only exists closed (medium; A)
**Plan says**: nothing — PLAN §2/§3 and the specs present preview, rest, picker, settings, calendar, sticky note and
summary as `.sheet` with no `presentationPlacement`; §3 "Rest: toolbar items in app, Dynamic Island when away".
**PWA origin**: the web's "compact: rise from the bottom; expanded: float in the middle" rule (`layout-and-style.md`
§1), which it inherited by not deciding. **Idiom**: `duo-layout.md` "Sheets on the inner display: horizontal bars for
centered/leading placement, vertical for trailing; choose with `presentationPlacement(_:)`", "sheets… move off the
fold automatically"; "The outer camera… expands into the Dynamic Island… The inner camera is under the display" —
there is no Island on the open phone. **Replace**: add to PLAN §2 "Navigation and layout": "Every sheet names its
placement on regular width: preview, picker, settings, calendar, custom-timer, summary → centred (horizontal bars);
rest ring → trailing (vertical bars, it belongs to the strip's ring item); half-open the system moves it off the
fold." And in "Rest end": "Dynamic Island only while closed; open and backgrounded the Lock Screen presentation and
the notification are the only signals — name this in 1.4's previews (inner display has no Island)."

### 7. The exercise block header is the web's (low; J)
**Plan says**: `active-workout.md` §2 "name (tap opens detail), chart button, ⋯ menu"; `workout.md` §5 "Exercise
reorder: drag handle / `.onMove`". **PWA origin**: `duo-closed-active-workout-set-done.png` — a `⠿` grip, the name in
link blue, a ⋯ at the right. **Idiom**: Reminders/Notes section headers are plain text; reorder handles appear in edit
mode or via `reorderContainer`, never as a permanent column; `ellipsis.circle` in content is allowed (round 1).
**Replace** `workout.md` §5: "Each exercise is a `Section`: header = name (primary text, tappable), caption 'Rest
2:00', trailing `ellipsis.circle` `Menu`; no permanent grip — reorder with `.reorderable()`; the 'chart button' is
gone (round 1 kept name → detail → Charts)." Drop "drag handle".

### 8. Stale spec sentences that still describe the web (low, but workers read them)
- `active-workout.md` §5 "Open Duo: … Native: a `NavigationSplitView`/two-column layout … (`POLISH.md:438` suggests
  History as the default pane)" → "Regular width: `ArrangementView(primary: SetTable, secondary: exercise pane)` per
  PLAN §2/2.6; the pane has no Close of its own (the web's X was the pane's, `duo-open-wide-active-workout-exercise-
  pane.png`)". Also §7 "Open-Duo layout… Does Rest Timer stay a sheet?" → closed by PLAN §2 (A).
- `history.md` §5 "Duo: card list in the left pane, detail right; `Settings` can sit in the sidebar of the split
  view" and §8 "Fourth tab" → point at PLAN §2 (Settings = gear item + `tabViewSidebarBottomBar`) (A).
- `layout-and-style.md` §4 mapping rows "four `Tab`s", "`.tabViewBottomAccessory`… `.safeAreaInset(edge: .bottom)`",
  "Two-pane tabs… Workout" are superseded — mark the table "historical; PLAN §2 wins" (A).

## Web keeps that are fine (with the reason)
- **Tab set and order, Workout default** (PLAN §2): product structure, settled in `AGENTS.md`; Claude's sidebar
  likewise leads with fixed sections. Only the *phrase* "in the web's order" is inheritance — say "Eric's order".
- **Set table columns Set · Previous · weight · reps · ✓, Previous autofill, Add Set as a trailing `Label` row**:
  data and business rules; the native parts (keyboard `ToolbarItemGroup`, `ViewThatFits` at AX sizes) are Apple's.
- **Cards by fill, no rim, no glass** (`layout-and-style.md` §4): Fitness's cards are plain dark fills (P). Keep.
- **Large titles with full-height content**: Claude, Flighty, Fitness (P).
- **`ContentUnavailableView` as an empty detail** on Exercises/History: Mail's model (A/J) — only the web's *sizes*
  around it were wrong (finding 1).
- **Segmented About / History / Charts / Records**, **chip row for body part / category** (Flighty's chip row, P),
  **calendar sheet**, **`confirmationDialog` copy**, **semantic colours following the system**: round 1 reasoning holds.
- **`fullScreenCover` for logging** and **the ring toolbar item as resume control**: decided with Eric; Fitness+ shape.

## Coverage checklist: Duo poses and scenarios the plan still does not name
- **Closed landscape (compact × compact)** for the logging screen: large title collapses, the keyboard leaves ~2 rows;
  where the strip goes in landscape; AX sizes there. Named only as a screenshot pose.
- **Open tall with the keyboard**: horizontal bars; the stacked `ArrangementView` — does the keyboard hide the pane?
- **Laptop pose with the keyboard**: 6.1 puts the table on the lower half, which is also where the keyboard lands.
- **Book pose for Exercises / History**: the split's column divider vs the fold; a full-width `List`/`Form` (sidebar
  hidden, Settings sheet, exercise About text) whose rows cross a vertical fold.
- **Fold mid-flow with a sheet, menu or dialog up**: rest ring, picker (selection kept?), preview, calendar, custom
  timer, finish dialogs, confirmation dialogs — `presentationPlacement` and state for each.
- **Fold mid-flow with focus in a cell**: `@FocusState` and the keyboard across a size-class change.
- **Split View with another app** (50/50, safe areas flip sides) and **PiP** (the exercise video?) — `duo-layout.md`
  says nothing may break; no task checks it.
- **Live Activity when open**: no Island; Lock Screen only. Opening the phone while a rest runs in the background.
- **Dynamic Type AX in the strip** (icon-only items, the ring's caption numerals) and in the `ArrangementView` pane.
- **VoiceOver order across the strip** (Close → prominent → ring → actions) and across the fold's two halves.
