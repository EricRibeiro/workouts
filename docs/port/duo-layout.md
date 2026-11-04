# iPhone Duo layout, from Apple

The viewport model for this app. Sources, fetched 2026-11-03: the HIG page "Designing for iPhone
Duo", the Technology Overview "Preparing your app for iPhone Duo", the `ReservedRegion` and Device
Hub docs, and Tech Talks 111461–111466. The web app's breakpoints in `layout-and-style.md` are
**not** a basis for native layout: the PWA had no sidebar and no vertical bars, so it saw less of
the panel than a native app gets. Where the two disagree, this file wins. Apple publishes no point
sizes for either display; design by size class, never by numbers.

## Displays, poses, size classes

| Pose | Display | Size classes (H × V) | Notes |
|---|---|---|---|
| Closed, portrait | outer | compact × regular | "wider and shorter than a traditional iPhone" |
| Closed, landscape | outer | compact × compact | normal iPhone orientation rules apply |
| Open, tall (portrait) | inner | regular × regular | "familiar iPhone size and aspect ratio"; the one pose with standard horizontal bars |
| Open, wide (landscape) | inner | regular × regular | |
| Partially open (book / laptop / tent / tabletop) | inner | regular × regular | the fold becomes an active **division** region |

- The inner display **does not honor supported interface orientations**; the app scales there.
  Support all four orientations (already set) because the phone can be stood up like a tent.
- The outer camera sits in the corner and is always visible; it expands into the Dynamic Island
  for Live Activities. The inner camera is under the display and only reserves space while active.
- Built with the iOS 27.1+ SDK (we use 27.2) the app runs edge to edge and gets vertical bars.

## The trailing vertical strip (outer display)

On the outer display the system stacks, top to bottom along the **trailing edge**: Dynamic Island,
status bar, toolbar items, tab bar. Rules that follow:

- "Follow the system's vertical layout for toolbars, tab bars, and navigation controls." "In
  general, don't override the default bar placement." Custom bars are ignored; use the navigation
  containers (`NavigationStack`/`NavigationSplitView` + `.toolbar`, `TabView`).
- Give every toolbar item a symbol **and** a title: icon items go vertical, text-only items stay
  horizontal and eat space. Group with `ToolbarItemGroup`; overflow is the system's
  (`ToolbarOverflowMenu`), so reserve the ellipsis for it.
- Vertical order: Back/Close at the top, prominent actions (Done) next; bottom items overflow
  upward first. On task screens (the logging screen) prefer
  `toolbarVerticalCompressionBehavior(.prefersToolbarItems)` so the tab bar minimises before the
  actions do.
- Safe areas are asymmetric by design: vertical bars add leading/trailing insets, horizontal bars
  top/bottom. Handle each side on its own; never mirror one inset. Interactive content stays inside
  the safe area; backgrounds may `.ignoresSafeArea()`; `.backgroundExtensionEffect()` extends a
  hero image under a vertical bar.
- Keyboard accessory bars stay horizontal. Sheets on the outer display get vertical bars by
  default; a sheet with a single Close button may opt out.

## The inner display

- Tab bar: we do **not** opt into the sidebar (JC52). A plain `TabView` keeps the tabs in the trailing strip on the inner display
  too. (For the record: `.defaultTabBarPlacement(.sidebar)` with `.sidebarAdaptable` gives a sidebar, expanded when open wide and
  collapsed behind a toggle when open tall; `.sidebarOnly` tabs leak into the 27.2 bar.) Apple: a sidebar is "best for
  information-dense apps"; ours has three destinations, and Exercises already has its own list column.
- Split views expand on the inner display and collapse on the outer; `NavigationSplitView`
  adjusts column widths and margins to the fold on its own. Show one more level of hierarchy
  than on the outer display (Mail's model), with the same functionality and element state.
- Sheets on the inner display: horizontal bars for centered/leading placement, vertical for
  trailing; choose with `presentationPlacement(_:)`. Sheets, popovers, alerts and menus move off
  the fold automatically.
- Grids: prefer an **even number of columns** so nothing straddles the fold; keep outer margins
  and widen the gap around the hinge (Apple's Fitness example). Our template grid
  derives an even column count from its own width (`DECISIONS.md`), not from the size class.
- New windows can only be created on the inner display; not something this app needs.

## The fold: reserved regions and arrangement views (iOS 27.1)

- `GeometryProxy.reservedRegions(kind:options:)` inside a `GeometryReader`/`onGeometryChange`
  returns `.occlusion` (cameras) and `.division` (the fold) regions with `frame`, `margins`,
  `isActive`. The division is active only when partially open; `frame.width < frame.height`
  means a vertical fold (book, content side by side), the opposite means laptop (stacked).
  Pass `.includeInactive` to reserve the space so layouts don't jump when it activates.
- "Keep each view entirely on one side of the division." Lists and scroll views don't split
  themselves; a row that crosses the fold is on us.
- `ArrangementView(primary:secondary:)`: splits horizontally when wider than tall, vertically when
  taller than wide (`.arrangementViewStyle(.split.axes(...))`), or overlays the primary on the
  secondary when fully open/closed and separates them across the fold when partially open
  (`.overlay`). Never inside a `List`/`ScrollView`/`NavigationSplitView`; navigation wraps it.
  **This is the logging screen on the inner display**: primary = set table, secondary = exercise
  pane (video, instructions, Previous, records). Half-open on a bench: the fold puts the table on
  the lower half (controls) and the exercise pane / rest countdown on the upper half (glanceable),
  which is exactly Apple's tabletop guidance.
- "Avoid extreme layout changes as people fold the device." Move only what must move; keep
  scroll position, selection and the active workout.
- `onHingeChange` (SwiftUI) / `UIHingeInteraction` (UIKit) report closed / partially open / fully
  open plus a continuous angle. For effects and live interactions only, never for layout.
- Still forbidden: `UIScreen.main` (ambiguous with two displays), idiom and orientation checks,
  fixed widths, `width - inset * 2`. Corners: `ConcentricRectangle`.

## Multitasking

Split View is 50/50 with each app's controls on its outer edge, so safe areas can flip sides;
Picture in Picture pins video at the top and shrinks the app vertically. Nothing to design for, but
nothing may break.

## Testing (Device Hub)

Device Hub's bezel buttons switch Closed / Partially Open / Open; Option-drag the slider for any
angle; rotate left, Option-click to rotate right; Device > Slow Animations to inspect transitions.
Apple's checklist, which `verify-ui` follows: both displays, closed/open/partially folded, rotate in
each; walk every view, sheet and popover; inspect vertical bars; find anything that lands in the
fold or positions awkwardly across a fold/open.

## Observed on real apps (Eric's Duo, 2026-11-03; `screenshots/ref-*.png`, local only)

Apps Eric likes the feel of: Claude, Flighty, Apple Fitness.

- **Closed display, every app**: the tab bar is a vertical Liquid Glass capsule at the bottom of
  the trailing strip; toolbar actions (avatar, ⋯, search, share) stack above it in the same column;
  Island and status on top. Content uses the full height. There is no bottom bar anywhere, so the
  web's bottom tab capsule and dock have no native counterpart. The minimised workout therefore
  lives in the bars: a ring toolbar item (resume control, shown on the open display's strip too)
  (the sidebar card of the 2026-11-03 decision was dropped with the sidebar, JC52).
- **Open wide, Claude**: leading sidebar (section list), content in the middle, toolbar actions
  in the trailing strip. Not our shell: we have no sidebar (JC52); our tabs stay in the strip.
- **Open wide, Flighty**: full-bleed map with a floating panel at the **leading** edge that carries
  its own **horizontal** tab bar, while the trailing strip holds the map toolbar. Apple's
  placement rule, seen live: leading/centered panels get horizontal bars, the trailing edge is
  vertical. Model for any floating pane over media.
- **Fitness**: a 2-column card grid when closed, mixed-width cards when open, vertical tab bar
  in both, dark mode. Direct model for the template grid and the History dashboard cards.

**Rules we derived**
- No bottom surfaces: nothing is pinned to the bottom edge but a keyboard-adjacent input.
- Icon-only strip items with symbol + title: toolbar items are glass symbols, never text pills.
- The ellipsis is the system's: overflow is `ToolbarOverflowMenu`, no hand-made ⋯ menus.
- Prominent action at the top of a panel: Start Workout sits under the title, like Flighty's `+ Add Friend`.
- Nothing straddles the fold: even grid columns from width, `ArrangementView` for editors on regular width.
- No fixed column widths; `NavigationSplitView` sizes to the fold.
- Dynamic Island exists only on the closed display.
