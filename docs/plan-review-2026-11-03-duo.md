Applied to PLAN.md and the screen specs on 2026-11-03; kept for the rationale.

# Plan review: remaining web-isms on the iPhone Duo (2026-11-03)

Scope: `docs/PLAN.md` §2–3 and phases 2–5, `docs/port/screens/*.md`, judged against
`docs/port/duo-layout.md` and the reference photos (`ref-*.png`: Claude, Flighty, Fitness; `duo-closed-*.png`:
the web app). The bottom-pill fix is taken as done. Findings are ranked by how often Eric would see them.
Confidence: **A** = Apple rule in `duo-layout.md`, **P** = observed in a photo, **J** = judgment.

What the photos settle (used throughout): on the closed display *every* control is in the trailing strip, as
icon-only glass circles (Claude: list, ring, ⋯; Flighty: avatar, ⋯, tab capsule, then **search below the tab
bar**; Fitness: avatar, tab capsule). Toolbar items render as symbols, never as text, and a custom view fits
(Claude's progress ring). On the **open wide** display the toolbar is *still* a trailing vertical strip
(Claude: list/ring/⋯ at the right edge beside the sidebar; Flighty: the map tool group); only open-tall gets
horizontal bars (`duo-layout.md` pose table). Prominent in-content actions sit at the **top** of a panel
(Flighty's `+ Add Friend` chip row), never at its foot. The only bottom-anchored surface anywhere is Claude's
text composer, i.e. a keyboard-adjacent input.

## Findings

### 1. The rest bar is a bottom bar (high; P + J)
Plan §2 "Rest UI": `safeAreaBar(edge: .bottom)` with countdown and −10 s / +10 s / Skip as glass buttons; task
2.3. This is the web dock's shape with a different API: a glass strip pinned to the bottom edge of the closed
display, where no reference app has one. Its one native justification (stacks with the keyboard) only holds
while the keyboard is up. Replace §2 "Rest UI" with: "Rest controls live in the bars. While a rest runs the
logging screen's toolbar gains a `ToolbarItemGroup` of **Skip** (`forward.end`) and **+10 s** (`goforward.10`)
below the timer item, which the strip stacks vertically like Flighty's map tool group; **−10 s** goes to
overflow (`visibilityPriority` low). While the keyboard is up, the keyboard `ToolbarItemGroup` (horizontal by
Apple's rule) prepends the countdown and Skip. Tapping the timer item opens the ring sheet (finding 11). No
`safeAreaBar`, no bottom glass." Task 2.3 → "Rest toolbar group and minimise". On the inner display the ring
countdown is already in the arrangement view's secondary pane, so nothing is lost there.

### 2. The countdown items must survive an icon-only strip, on both displays (high; A + P)
Plan §2 "Minimised workout" and task 2.4: closed → "a glass pill with the timer glyph and the rest countdown";
open → only "a card pinned at the bottom of the sidebar". Two problems. (a) `duo-layout.md`: text items "stay
horizontal and eat space"; the photos show every strip item as a 44 pt symbol circle. A pill with "0:59"
beside a glyph is the web's header pill. (b) The open display has a trailing strip too (Claude open-wide
photo), and the sidebar card vanishes whenever the sidebar is hidden or the phone is open-tall. Replace with:
"One `ToolbarItem` carries the active workout in every width: a `ProgressView(timerInterval:)` ring with
`Text(timerInterval:)` inside in caption size (the status strip already shows numbers inside a ring — the
battery `55`), elapsed time when no rest runs; the system places it in the strip when closed or open-wide and in
the top bar when open-tall. No `.glassEffect()`: toolbar items are already glass. The `tabViewSidebarBottomBar`
card is additive, shown only when the sidebar is visible." The same ring is the logging screen's own timer item
(§2 "the header keeps the web's timer button"). Note for 2.4: toolbar items do not inherit on push, so the
modifier is applied by a shared `ViewModifier` on every screen's root, not "on every tab".

### 3. Minimise: no grab handle, no drag, no "tap any tab" (high; A + J)
§3 Logging screen: "drag down or tap the chevron to minimise"; task 2.3 "chevron/drag minimise";
`active-workout.md` §3 keeps the web's grab handle, 1/3-height threshold and velocity rule. A `fullScreenCover`
has no interactive dismissal; the drag would be a hand-built gesture reproducing the PWA's. `duo-layout.md`:
"Back/Close at the top, prominent actions (Done) next." Replace with: "Minimise is the cover's Close-slot item,
`Button("Minimise", systemImage: "chevron.down")` at the top of the strip, Finish (`checkmark`, prominent)
next; no handle, no drag, no tab-tap (there is no tab bar under a cover)." Also replace the web's name row (name
+ bare ⋯ + "Nov 3 · 0:33"): `navigationTitle(name)` + `navigationSubtitle("Nov 3 · 0:33")` with
`toolbarTitleMenu` carrying Rename and Discard Workout. **+ Add Exercise** becomes a toolbar item (`plus`) and
the last row of the table, not a web button at the foot.

### 4. ⋯ menus everywhere, but the ellipsis belongs to the system (high; A)
`duo-layout.md`: overflow is the system's `ToolbarOverflowMenu`, "reserve the ellipsis for it." The specs still
carry a ⋯ on the Exercises list (`Show retired`), History cards and detail ("keep a visible ⋯ Menu too for
parity"), template cards, folder headers, the editor name row. The web's Exercises screenshot shows exactly
this (`+` and `⋯` beside the title). Replace, per screen: toolbar actions are plain items with symbol **and**
title and let the system overflow them — Workout: Settings (`gearshape`), Add (`plus`, a `Menu`: New Template /
New Folder); Exercises: New Exercise (`plus`), Show Retired (`eye`, a toggle item); History: Calendar
(`calendar`); exercise detail: Edit (`pencil`, custom only); workout detail: Edit (`pencil`), Save as Template
(`doc.on.doc`), Delete (`trash`, destructive). Row and card actions go to `contextMenu` + `swipeActions` only;
folder actions to `contextMenu` on the header. Content-level block menus inside the set table (per-exercise)
may keep `ellipsis.circle` — they are content, not a bar. Add this item table to §2 "Navigation and layout".

### 5. Template preview: Start Workout at the top, not pinned at the foot (medium-high; P + A)
§3 and `workout.md` §5: "Start Workout pinned at its foot" (the web photo). Flighty puts its prominent action
at the top of the panel; the strip takes Close and Edit as vertical items ("sheets on the outer display get
vertical bars by default"). Replace with: "Sheet toolbar: Close (`xmark`) then Edit (`pencil`) in the strip;
content: title, 'Last performed', a `.borderedProminent` **Start Workout** (`play.fill`) capsule directly under
it (Flighty's `+ Add Friend`), then the exercise rows with an `info.circle` accessory for the peek. Nothing is
bottom-anchored." Medium detent stays (see keeps).

### 6. Exercises list and picker carry the web's search chrome (medium; P + J)
`exercises.md` §5 and task 3.1/4.1: inline search field, `Any Body Part` / `Any Category` chips, a sort button,
and an A-Z rail ("check the iOS 27 API"). The web photo shows the rail jammed against the status strip — the
trailing edge is the system's. Flighty shows where search goes: `.searchable` and the system places a search
circle at the bottom of the strip. Replace with: "`.searchable` only (no inline field); body part and category
as two `Menu` pills at the top of the list (Flighty's chip row, observed) or `searchScopes` if ≤ 4 values; no
sort control while Name A-Z is the only sort; **no A-Z rail** — SwiftUI has no section index and the trailing
edge is reserved. Picker: **Add (N)** and **Superset** are the sheet's toolbar items
(`Button("Add 3", systemImage: "plus")`, `rectangle.stack`), not a bottom capsule; Cancel in the Close slot."

### 7. Grid columns come from width, not size class (medium; A + J)
§2 and `duo-layout.md`: "2 columns on compact and 4 on regular". Fitness's 4-column grid is centred on the
display because it has no sidebar; ours sits beside Claude-style sidebar, so the fold crosses the content area
off-centre, and when the split view pins the sidebar to the fold (partially open) the grid gets half a display.
Replace with: "Columns are an even number derived from the grid's own width via `onGeometryChange` —
`max(2, 2 * floor(width / (2 * minCard)))` — so a sidebar-open inner display gets 2, a full-width one 4; with
`.includeInactive` reserved regions the gap around the hinge is widened." Keep "even" as the invariant.

### 8. Template editor: one presentation, fold-safe on the inner display (medium; A)
PLAN §3 says the editor "pushes within the tab"; `workout.md` §5 says `fullScreenCover` on compact and a
"side detail pane … set tables capped at 540 pt" on regular (open question 2). Push is right (Mail's model:
one more level beside the sidebar) and the cover is the web layer. A pushed single-column editor on the
inner display, though, spreads the Set | Previous | lbs | Reps table across the fold in the book pose
("keep each view entirely on one side of the division"). Replace `workout.md` §5 and task 3.4 with: "Pushed in
both widths; on regular width the body is the same `ArrangementView(primary: SetTable, secondary: exercise
pane)` as the logging screen (task 2.6), so the table never straddles the division. No width cap — fixed
widths are forbidden." Close open question 2. Apply the same to the past-workout editor (`history.md` §5:
"`.fullScreenCover` / sheet" → pushed from the workout detail).

### 9. Toolbar budget on the closed display (medium; P)
Claude shows three items above the status area, Flighty two plus the tab bar. With finding 4 the Workout tab
carries Settings, Add and the ring; the logging cover carries Minimise, Finish, timer ring, Skip, +10 s and an
Add Exercise — six. Add to §2: "Task screens set `toolbarVerticalCompressionBehavior(.prefersToolbarItems)`;
items are ordered Close → prominent → state (ring) → actions, since the bottom overflows first; nothing below
the ring may be something Eric needs mid-set."

### 10. Small web leftovers (low)
- `history.md` §3: goal "target button" on the chart header opening a stepper sheet → the goal lives in
  Settings only; the chart header is plain (J).
- `history.md` §5 "toast → a brief banner" → `sensoryFeedback(.success)` and the sheet dismissing; no banner (J).
- Exercise detail hero video under a vertical bar: `.backgroundExtensionEffect()` (A).
- Rest adjust is −10/+10 in-app but Skip/+30 s in the Live Activity and notification (§2). Pick one pair for
  every surface; +30 s matches the Island (J).
- `active-workout.md` §5 "Dock: `.safeAreaInset(edge: .bottom)`" and "Regular → a button in the sidebar/rail"
  are stale; point the spec at PLAN §2 "Minimised workout" (A).
- `+ Add Set` as a full-width grey capsule per block → a plain trailing row `Label("Add Set", systemImage:
  "plus")`, Reminders-style (J).

## Keep as is
- **`fullScreenCover` for the logging screen** (§2): a modal task like a Fitness+ session; a sheet cannot be
  full-width on regular width, which the arrangement view needs. Only its drag (finding 3) was the web-ism.
- **Card grid on compact** (§2, 3.2): Fitness closed is exactly this, 2 columns, dark and light.
- **Medium-detent template preview** (§2, 3.3): system sheet with system vertical bars; keep it with the
  Start placement from finding 5. The sidebar-only template `Tab`s cover the open display.
- **Segmented About / History / Charts / Records** (4.2) and the 1M/3M/6M/1Y/All range control: Health's own
  idiom, horizontal in content where Flighty's chip row sits; four segments fit beside the strip (web photo).
- **Rest timer ring sheet** (`active-workout.md`): keep as the idle preset picker and the expanded running
  view, opened from the timer item; Clock's ring + buttons under it. It is a sheet, so it gets vertical bars
  (Close in the strip); −10/+10/Skip stay in content under the ring.
- **Settings as a gear item + `tabViewSidebarBottomBar` `Form` sheet** (§2): Fitness's avatar above the tab
  capsule closed, Claude's avatar at the sidebar foot open.
- **Sidebar `TabSection` per folder, `.sectionActions` New Template** (3.6): Claude's Recents list.
- **Keyboard `ToolbarItemGroup`** (2.1): Apple keeps keyboard bars horizontal.
- **`confirmationDialog`s**, **Live Activity**, **semantic colours following the system appearance**,
  **large titles with full-height content** (Flighty, Fitness photos).
