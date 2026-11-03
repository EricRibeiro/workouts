# Layout and style
> The breakpoints and pose sizes below describe the PWA, which had no sidebar or vertical bars.
> For native layout use `duo-layout.md` (Apple's guidance); this file is kept for the web's
> navigation structure, visual system and the native-mapping table.

Sources, under `~/Projects/mac-os-compose-collection/workouts/`: `ui.md` = `app/docs/ui.md`, `PLAN.md`,
`IOS.md`, `router.ts` = `app/ui/src/router.ts`. Sections 1-3 and 5 are web facts (1 CSS px = 1 pt,
`ui.md:35`); section 4 is the recommended native mapping, not a web fact.

## 1. The two layouts (web facts)

Chosen by **width alone** (CSS `@media`, no device sniffing; `ui.md:18`); breakpoint `--bp-expanded` 600 px.

| | Compact (< 600 px) | Expanded (>= 600 px) |
|---|---|---|
| Navigation | floating bottom tab capsule | one column on the **right** edge (`.barcol`) |
| Exercises | one column; detail = full-height modal sheet | list left, detail right, inline |
| Modal sheets (New, filters) | rise from the bottom | float in the middle |
| Title | 34 px large title | same; smaller if also short (< 700 px tall) |

Measured poses, installed, DPR 3 (`ui.md:7-14`):

| Pose | Viewport | Layout | Safe-area t/r/b/l |
|---|---|---|---|
| Closed portrait | 373x678 | compact | 0/0/34/0 |
| Closed landscape | 594x457 | compact | 0/0/34/0 |
| Open landscape | 867x669 | expanded | 0/0/34/0 |
| Open portrait | 669x951 | expanded | 82/0/34/0 |

- 34 = home indicator; 82 = status strip, inside the viewport on open portrait only. On closed and open
  landscape the strip is **outside** the viewport (`ui.md:16`, `ui.md:31`).
- Height is a second axis: the **dense scale** applies below 700 px tall (`--bp-short`): closed portrait,
  closed landscape, open landscape. Open portrait keeps the full scale (`ui.md:50`).
- Expanded column, top to bottom (`ui.md:249-257`): the topmost **detail** layer's controls (Close, Edit) when it has more than Close; the three tabs; Settings in its own capsule. Icon-only, 44 px items, 56 px wide + right inset. Compact has **no** side column: tried and removed, since the closed screen's status strip is outside the viewport (`ui.md:248`, `PLAN.md:204`).
- List panes: Exercises 42% of the width beside the column, clamp 240-360 px (40% landscape: 324 px at
  867x669 with a 487 px detail; 257 px at 669x951) (`ui.md:23`). Workout list pane at 669x951:
  `clamp(260px, min(50%, 100% - 340px), 480px)` (`ui.md:261`).
- **Fold, unfold and rotate keep state**: same DOM restyled; search, filters, scroll, selected exercise
  (it is the URL) and the playing video survive (`ui.md:27`).
- Every screen: tap targets >= 44 px, inputs >= 16 px, all four safe-area insets honoured (`ui.md:29`).

## 2. Navigation structure (web facts)

Four tabs, in order (`router.ts:15-20`; glyphs `IOS.md:79`, `TabBar.tsx:7-12`):

| # | Label | Path | Glyph |
|---|---|---|---|
| 1 | History | `/history` | `clock.arrow.circlepath` |
| 2 | Workout | `/workout` | `figure.strengthtraining.traditional` (not `+`) |
| 3 | Exercises | `/exercises` | `dumbbell.fill` |
| 4 | Settings | `/settings` | `gearshape.fill` |

`/` and unknown paths replace to `/workout` (`ui.md:121`). The compact capsule shows all four with labels; the expanded column shows
the first three as tabs and Settings in a capsule of its own (`ui.md:249`) - same four destinations.

Sub-routes (`router.ts:30-48`): `/exercises/{uuid}` exercise detail; `/workout/{uuid}` template preview;
`/history/{uuid}` past-workout detail. Each is a modal sheet when compact, the right pane when expanded.
The compact template preview is a **medium-detent** sheet (grabber, up to `min(62dvh, 560px)`, Start Workout
pinned at the foot) (`ui.md:82`). Settings has no sub-route. The template editor, active-workout screen and
past-workout edit are full-screen `.editor` layers, not routes (`ui.md:110`).

Push vs sheet: opening a detail **pushes** a history entry and closing goes back (after a deep link or reload, replaces with the tab root); tab links **replace** (`ui.md:121`). Sheets: details (compact), New forms, filters, pickers, rest-timer, preview. Every confirmation is an **action sheet**: Finish, Resume/Discard, Update Template, delete-folder, discard-edits (`ui.md:80`). Menus are 250 px popovers (`ui.md:68`). Compact: a sheet and its scrim **cover** the tab capsule and dock; expanded: the column stays above the scrim by design (`ui.md:117`). The dock (active-workout bar, only while a workout runs) sits above the tab capsule (`ui.md:69`).

**Pages stay mounted** (`ui.md:123`): a visited tab stays mounted and hidden (`visibility: hidden` +
`inert`), keeping scroll position and state (search, filters, open detail) across tab switches. Tapping the
**active** tab returns to its top level (closing a detail); if already there it scrolls smoothly to the top
(`ui.md:92`). Any tab tap minimises a running workout to its dock (`TabBar.tsx:35`).

## 3. Visual system (web facts, exact values)

**Palette.** Dark is default (`ui.md:35`, `IOS.md:69`): `--bg` #000, `--surface` #1c1c1e, `--field` #2c2c2e,
`--field-2` #3a3a3c, `--seg-active` #636366, `--bg-deep` #000; text #fff / rgba(235,235,245,.6) / .3 / .18;
`--accent` #0a84ff, `--ok` #30d158, `--danger` #ff453a, `--kind-warmup` #ffd60a. Fills are **lighter** than
the page (iOS dark elevation). Light (iOS grouped look): `--bg` #f2f2f7, white cards, accent fill #007aff,
accent text #0066d6, text >= 4.5:1 on `--bg`; ok/danger checked against #34c759 / #ff3b30. Appearance setting
System / Light / Dark, a per-device preference (`ui.md:67`). Cards separate by fill alone, no rim
(`ui.md:68`, `IOS.md:25`).

**Type scale** full / dense (< 700 px tall) (`ui.md:37-48`): `--fs-title` 34/28 large title; `--fs-h1` 28/22
editor name; `--fs-h2` 22/20 big numbers; `--fs-h3` 20/17 section headers, card names; `--fs-lg` 17/16 row
titles, buttons, set cells; `--fs-md` 16/16 inputs; `--fs-sm` 15/14 second lines, filters; `--fs-xs` 13/12
labels, hints; `--fs-cap` 12/11 chart counts; `--fs-tab` 10/10 tab labels. Section headers are bold title-3,
title case, 24 px above / 8 below, not uppercase footnotes (`IOS.md:27`, `IOS.md:117`).

**Dense overrides** (`ui.md:50`): `--row-h` 56->44, `--thumb` 44->38, `--field-h` 40->36, `--ctl-h` 36->32, `--ctl-sm-h` 30->28, icons 20/22/24->18/20/22, `--gap-5/6` 24/32->16/24.
**Controls** (`ui.md:52`): `--touch` 44, `--ctl-h` 36, `--ctl-sm-h` 30, `--seg-h` 32, `--field-h` 40, `--row-h` 56, `--thumb` 44, `--letter-h` 28; tab capsule `--tab-item` 58 (50 dense), `--tab-ico` 26 (22), `--bar-pad` 4, 8 px above the home-indicator inset (`ui.md:69`); page bar row 44 (40 dense).

**Radii** (`ui.md:54`): `--r-xs` 4, `--r-key` 5, `--r-cell` 8, `--r-sm` 10, `--r-md` 14, `--r-lg` 24 (inset
groups, action sheets, menus, cards), `--r-xl` 28 (big cards, capsules), `--r-sheet` 38 (sheet/editor
corners), capsule 999.

**Spacing and separators.** Spacing is `--gap-N` tokens; only `--gap-5/6` (24/32) are valued here. Hairlines (`--line`): list rows inset past the thumbnail, letter headers full-width (`ui.md:70`); menus hairline-separated, destructive items in a last group behind an 8 px separator; Settings rows inset from the label with 13 px muted footers (`IOS.md:115`).

**Translucent bars** (`ui.md:68`). Glass is the one material of *floating* chrome only (tab capsule, dock,
side-column groups, menus, toasts, round glass icon buttons): fill (light #fff @78%, dark `--surface` @62%)
under `blur(28px) saturate(1.6) brightness(1.06)` light / `blur(24px) saturate(1.8) brightness(1.08)` dark,
specular rim, sheen, two-layer shadow. **Edge-attached bars** (collapsed page bar, sheet head, editor
header) get fill, blur and a bottom rim only, and **fade in once content scrolls under them**. In-content
controls (search, filter chips, sort button) are plain `--field-2` fills, not glass.

**Segmented control** (`ui.md:68`, `ui.md:71`): `--field-2` track, 3 px padding, 2 px gap, `--seg-active`
thumb that slides over `--dur-2`, no slide on first placement. Used for the exercise-detail tabs
(About/History/Charts/Records) and Settings pickers; the chart-range control has no thumb.

**Haptics** (`ui.md:62`). Only a finger tap on a switch vibrates, hence layered `HapticSwitch`es. Fire on:
Settings on/off toggle; the set's check; every keypad key; Finish; template card; Start Workout; rest-timer
button and every rest-sheet control; **tabs** in both layouts; Finish / Update-Template sheet buttons;
summary Done; Add Set; Add Exercise; the set-kind button (tap and long-press). The rest-over alert cannot
vibrate (no tap) and stays with the push alarm.

**Motion** (`ui.md:73-86`). `--dur-1` 120 ms (state changes), `--dur-2` 220 ms (menus, rows, leaving
sheets), `--dur-3` 380 ms (sheets and screens rising), `--ease-out`, `--ease-spring`. In: sheet and editor
rise, scrim fades, menu scales from its anchor corner, toasts slide; an expanded floating sheet fades and
grows from 0.96, a pane sheet does not animate. Out: View Transition; a tab switch only cross-fades
(`--dur-1`). Drag a full sheet away by its head: release past 1/3 of its height or > 0.5 px/ms dismisses,
else springs back, scrim fading with the pull (`ui.md:83`). Deleted set folds its height away; checked
set tints over `--dur-1`. Press (touch): scale `--press-scale` 0.96 + dim `--press-dim` 0.75; rows and
cards go `--field-2`. The large title **collapses into the page bar** over the first 40 px
(`--collapse-range`) of scroll while the bar glass fades in (`ui.md:90`). Reduced motion turns everything
off except that scroll-linked collapse. Page bar: right-aligned bare accent glyphs (`+`, `...` on
Exercises; calendar on History), start slot reserved for Back only.

## 4. Native mapping (recommended)

> **Historical; `PLAN.md` §2 wins.** Rows below that still say four `Tab`s, `.tabViewBottomAccessory` /
> `.safeAreaInset(edge: .bottom)`, or two-pane tabs (incl. Workout) are superseded: three tabs and no fourth for
> Settings, no bottom surface (the minimised workout is a ring toolbar item), `NavigationSplitView` only for
> Exercises (History and Workout are single columns).

Principle: the system supplies Dynamic Type, Liquid Glass, tab/sidebar adaptation, haptics, detents,
collapsing titles and transitions. Port structure and content, not pixels (`AGENTS.md` Product decisions:
native idiom wins; Code conventions: size classes only, never `UIScreen`/idiom/orientation).

| Web mechanism | Native / Duo behaviour |
|---|---|
| Bottom capsule vs right column at 600 px | One `TabView` with `.tabViewStyle(.sidebarAdaptable)` and four `Tab`s. Compact width -> tab bar, regular -> sidebar; on the Duo inner display the system may place bars vertically, so never hardcode an edge. Both are system Liquid Glass. |
| `useExpanded()` | `horizontalSizeClass`; `GeometryReader` only if a pane width is truly needed. Open/close/rotate is a size-class change mid-session, as width is on the web. |
| Two-pane tabs (list + detail) | `NavigationSplitView` in the Exercises tab only (regular -> list \| detail, compact -> stack with a push); History and Workout are single columns that push. The inner-display behaviour is the web's expanded table in section 1. |
| Pages stay mounted; URL routes; tap-active-tab | `TabView` retains tab state; give each tab its own selection/path in `@State` or an `@Observable` model (not derived from layout), so fold/unfold keeps the selected exercise, search text and scroll. Routes become typed selection values (deep links: Q6). Re-tapping the active tab pops to root/top by default; verify. |
| Glass capsule, dock, glass buttons, menus, toasts | System default bars/controls: `.toolbar`, `Menu`, `confirmationDialog`. Do not re-create `--glass-*`. |
| Dock above the tab bar | A Live Activity / Dynamic Island for the running workout and rest timer, plus in-app `.tabViewBottomAccessory` (or `.safeAreaInset(edge: .bottom)` where an accessory does not fit) for resume/minimise. The dock was the web's only surface. |
| Large title collapse + page bar | `ScrollView`/`List` + `.navigationTitle` (large); actions in `.toolbar`. |
| Segmented control | `Picker` with `.pickerStyle(.segmented)`. |
| Action sheets | `confirmationDialog` (system orders recommended/destructive/Cancel). |
| Sheets, medium detent, drag-away | `.sheet` + `.presentationDetents([.medium, .large])` + drag indicator; preview uses `.medium` when compact. |
| Popover menus | `Menu` / `contextMenu`; `role: .destructive` for the last group. |
| View Transition, sheet rise | System. List -> detail via `.navigationTransition(.zoom)` with `matchedTransitionSource` (template card -> preview, History card -> detail, exercise row -> detail); `matchedGeometryEffect` only within one view. |
| Haptics | `.sensoryFeedback` on the events listed in section 3; no hidden-control trick. System controls (toggles, pickers, tab change) already provide theirs. |
| Type scale, dense scale | Dynamic Type text styles (the web sizes are the iOS defaults: 34 largeTitle, 28 title, 22 title2, 20 title3, 17 body/headline, 16 callout, 15 subheadline, 13 footnote, 12 caption). Dense scale not carried; accessibility sizes must not clip set rows. |

**Web tokens NOT carried over (the system provides them):** all `--fs-*` and the dense scale; `--glass-*`,
`--bar-bg`, `--on-glass-*`; `--r-*` as fixed radii (system shapes; keep the card radius only if decided,
Q7); `--safe-*`, `--top-inset`, `--col-reserve`, `--bar-h`, `--tabbar-h`, `--tab-*`, `--page-bar-h`,
`--page-row-h`, `--title-shrink`, `--collapse-range`; `--dur-*`, `--ease-*`, `--press-*`; fixed control
heights (`--ctl-*`, `--field-h`, `--row-h`; keep >= 44 pt hit areas); `HapticSwitch`; the z-index table;
`--bp-*`; the `theme-color` meta. **Kept as design intent:** accent blue, ok/danger/warmup colours,
set-kind colours, cards by fill, bold title-case section headers, one accent ring for the "current card"
open in the split view (`ui.md:68`).

## 5. Decisions in IOS.md that still apply

- Target the latest iOS (Liquid Glass); glass chrome stays (`IOS.md:21-23`).
- Cards separate by fill alone, no rim (25, 70). Labels on the tab bar; Workout uses the strength figure, not `+` (26, 81). No per-exercise chart pill: the name opens the detail with its Charts tab (26, 90). Section headers bold title-3, title case (27, 117).
- Neutral iOS dark palette; fills lighter than the base, never sunken (41-42, 69). Bare accent `...` glyphs in content, filled pill only for a primary action (44, 90-91). Menus: trailing symbol, hairlines, destructive group last (45, 92).
- Every confirmation is an action sheet, no filled red/green buttons (46, 93).
- Sheet header: X in a glass circle left, centred title, secondary action as accent text, primary as the
  prominent capsule (35, 89).
- Template preview: medium-detent sheet when compact, right pane when expanded (52, 94).
- Set numbers without a pill, W/D/F in kind colours (49, 102); cells lighter than the page, focus is a
  tinted fill (103); header meta one muted line "Nov 3 · 0:00" (105).
- Settings: inset grouped lists with footers, value+chevron row for default rest timer, joined stepper for
  weekly goal, plain "Device check" row (48, 114-116).
- Exercise thumbnails: letter tile with the image covering it (51, 118); filter chips are menu buttons that
  show the value once set; sort is a round glyph button (51, 119); media placeholder with `play.fill` (106).
- Summary: one `checkmark.circle.fill` in ok-green, not three stars (52, 127).
- Do not change: set-row grid, check-off, rest-timer logic, dock behaviour (142). Already iOS: collapsing titles, A-Z index, segmented control, swipe-to-delete, spring sheets, drag-to-dismiss (29-35).

## 6. Open questions for Eric

1. Settings: a normal fourth `Tab`, or a separate sidebar section / toolbar button (`ui.md:249`)?
2. Active-workout bar: in-app `.tabViewBottomAccessory` beside the Live Activity, or Live Activity only?
3. Compact details (exercise, history, template preview): push (native default) or the web's modal sheet?
4. Keep the in-app Appearance (System/Light/Dark) setting, or follow the system?
5. The web's dense scale (more sets on the closed screen): accept Dynamic Type only, or is a row-density
   requirement for the set table wanted?
6. Deep links (`/exercises/{id}` etc.): needed for widgets/notifications, or in-app navigation state only?
7. Inner-display sidebar: only the four tabs, or also the detail pane's Close/Edit (toolbar territory natively)? Card radius (web 28): keep or system shapes?
