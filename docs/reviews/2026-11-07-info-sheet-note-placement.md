# Exercise info sheet: where the sticky note lives (2026-11-07)

Read-only pass (skill `design-review`) on one question from Eric. The exercise info sheet (`ExerciseInfoSheet`, opened by
tapping an exercise name during a workout, from the block menu's Exercise Info, and from the template preview's ⓘ) opens at
the medium detent and shows, top to bottom: the full-width video card, the name, then the sticky note row ("Add Sticky
Note", or the yellow band with "Edit Sticky Note"). The segmented control (About · History · Charts · Records) sits under
that and is below the detent, invisible (Eric's screenshot, `93809d1a-image.png`; reproduced with
`./dev shot … -- -preview ExerciseInfoSheet`, closed portrait light: the medium shot ends at the band, the segments are
off-sheet; `-infoSheetDetent large` shows name → band → segments → "Chest" → Instructions).

**Settled by Eric, not re-litigated here:** the sticky row leaves that slot; the segmented control sits right under the
name at the medium detent; a segment tap grows the sheet to the large detent again (the behaviour commit `b8943dc`
removed, JC107). The open question is only where the sticky note (add, show, edit) goes instead.

Source read: `Workouts/Features/Shared/ExerciseInfoSheet.swift`, `Workouts/Features/Exercises/ExerciseDetailView.swift`
(`summary(_:)` at `:150-162` holds name → `StickyNoteView` → `Picker`; `sections(_:library:)` at `:166-182`),
`ExerciseAboutSection.swift`, `StickyNoteView.swift`, `SetTable.swift:195-204, 218-249` (band and block menu),
`ExercisePane.swift`, `docs/reviews/2026-11-07-notes-design.md`, PLAN 7.8a–d, DECISIONS "Active workout" / "Sheet
placement", JC41, JC75, JC85, JC107, JC108, `docs/port/duo-layout.md`.

## 1. Recommendation: the sticky note is the first block of the About tab

Move `StickyNoteView` out of the header (`summary`) and into the About segment, above the body-part line (after the
retired notice when there is one), in every host of `ExerciseDetailView`: the info sheet, the pushed detail on the
Exercises tab, and the embedded logging/editor pane. Nothing else about the note changes: same `StickyNoteView` (band +
Edit, or Add when none), same editor (7.8a folds it into `NoteSheet`), same block-menu entry, same band in the set table.

Why this placement:

- **It is content, not chrome.** A sticky note is the user's own text *about this exercise*; About is "everything about
  this exercise". Reference apps put user-authored text inside the content of the thing it annotates, not in the bar:
  Photos' caption under the photo, Contacts' Notes field in the card, Calendar's Notes row in the event. A toolbar glyph
  hides the text the user wants to glance at; a tab of its own gives one line a whole page.
- **It keeps the sheet Eric asked for.** At the medium detent: video, name, segmented control, and a sliver of About
  underneath (the yellow band or the Add row when the note is empty) as the "there is more" cue. The sheet stays bar-less
  (JC85: no ✕, grabber only, `toolbarVerticalBehavior(.disabled)`); nothing new lands over the video card on the closed Duo.
- **It fits what the sheet is for during a workout.** The sticky is already on the logging screen where the user is: the
  band under the exercise name in the set table (every mode, JC41, 3-line cap in 7.8b), and in the pane when open. The
  sheet is for the video and the reference; the note being first thing in About is one segment tap or one scroll away, and
  the restored grow-on-tap takes you there.
- **It helps the Duo poses.** The pushed detail at regular width is an `ArrangementView` whose primary is hero + name +
  (sticky) + segments and whose secondary is the selected segment (`ExerciseDetailView.swift:103-147`,
  `StackedPrimaryFitsContent`). With the note inside About, the primary shrinks to hero, name, segments: in the laptop
  (stacked) pose the content below the fold gets the rows back, and in book pose the note sits with the reading content on
  the right, where the eye is. The embedded pane is one scrolling column: the note moves a few rows down, still editable
  (JC41 holds). Nothing moves when the phone folds; only the size class changes.
- **One layout for every host**, so the three entry points keep looking identical (JC75's reason for the shared sheet), and
  the existing accessibility ids keep working.

Behaviour at the medium detent after the change, for the record: About is the default segment, so tapping "About" fires no
change and the sheet does not grow; scrolling the content at the medium detent is the system's expand gesture, and the
peeking band/Add row invites it. Tapping any other segment grows to large (restored hook).

## 2. Alternatives weighed

| Placement | For | Against | Call |
|---|---|---|---|
| **A. Toolbar item on the sheet** (`pin` / `note.text`, `.primaryAction`), band shown in About | One-tap add/edit from the medium detent, iOS 27 glass bar idiom | Re-introduces a navigation bar the sheet deliberately dropped (JC85), floating over the video card on the closed Duo where the sheet opted out of the vertical strip; a glyph cannot show the note, so the band still needs a home (this is additive to §1, not instead of it); the pushed detail already has an Edit item for custom exercises, two items in a bar with no title reads busy | Not now; see §5 taste 2 for the pushed detail only |
| **B. A fifth segment "Notes"** | Clear home, discoverable | Five labels in a segmented control at compact width on the closed Duo (the four already fill it, `sheet-large.png`); a page for one paragraph; the note disappears from About, which is where "how do I do this" is read | Reject |
| **C. Block menu only** (nothing in the detail) | Cleanest sheet | The Exercises tab's detail and the template preview's ⓘ have no block menu, so the sticky would have no writer there (`StickyNoteUITests` adds from the detail); "don't hide the only path to an action" | Reject |
| **D. Header slot only at the large detent** | Keeps the band near the name when there is room | The content would re-layout as the sheet is dragged (Apple: avoid layout changes as people fold or resize); the detail does not know the detent without new plumbing; the pushed detail and pane have no detent so the rule would differ per host | Reject |
| **E. Bottom of About** (after credit) | Reference first, your note last, Contacts-style | During a workout the note is the one line the user wrote for themself; after Instructions, Tips, Mistakes, Overview, Muscles, Equipment it is three screens down on the closed display | Taste (§5.1); the review says top |

## 3. Worker tasks

Order: T1 and T2 are independent of each other and of 7.8a; both land before 7.8b (which changes `StickyNoteView`'s band
and the block menu glyphs), or 7.8b rebases on them. Workers do not commit; the orchestrator runs `./dev check` plus the
suites listed, then `DEV_SKIP_UI_GATE=1 ./dev testflight --upload`.

### T1 — Sticky note moves into About (view)

Files: `Workouts/Features/Exercises/ExerciseDetailView.swift`, `Workouts/Features/Exercises/ExerciseAboutSection.swift`.

- `ExerciseAboutSection` gains a view slot for the note. Add a generic `Note: View` parameter with a `@ViewBuilder note:
  () -> Note` init argument (default `EmptyView` via an extension init), rendered after `retiredNotice` and before
  `bodyPartLine` inside the existing `VStack(spacing: 24)`. The status banner stays first; the user's note is the first
  content block.
- `ExerciseDetailView.summary(_:)` (`:150-162`) drops `StickyNoteView(exerciseID: info.id)` (`:153`); it becomes name/tags
  → `Picker`. `sections(_:library:)` `.about` passes `note: { StickyNoteView(exerciseID: info.id) }`.
- Update the three doc comments that list the sticky in the header: `:10-12` (type doc), `:103-107` (`layout` doc:
  "hero, name and segmented control are the primary; the selected segment's content, About leading with the sticky note,
  is the secondary"), `:149` (`summary` doc). `ExercisePane.swift:9-11` still reads "the editable sticky note": fine, it is.
- Padding: `sections` already gets `.padding(.horizontal)` in both call sites, so the band aligns with the segmented
  control; `StickyNoteView` keeps its own 12 pt inner padding and 12 pt corner (About's retired notice uses 20 pt; leave
  both, the band is a note, not a card).
- Accessibility ids are unchanged: `exerciseDetail.stickyNote`, `.stickyNote.text`, `.stickyNote.edit`;
  `exerciseDetail.segment`. VoiceOver order becomes name → tags → Section picker → sticky note → body part, which is the
  visual order.

Proof: `./dev test SnapshotTests` (no `ExerciseDetail` snapshot exists today, so expect no diff; if 7.8b adds one, re-record
there), then `./dev ui-test StickyNoteUITests` after T3's edits. Visual: `./dev shot <png> -- -preview ExerciseInfoSheet`
(medium: video, name, segments, a sliver of the band) and `-infoSheetDetent large`; `./dev shot … -- -preview
ExerciseDetail` closed portrait; one `./dev poses <dir> -- -preview ExerciseDetail` for the book and laptop poses (note on
the secondary side, nothing in the fold band). `./dev shot` reports "did not settle" while the video loops; the PNG is
still written and usable, or pass `-uiTesting` to freeze the stills.

### T2 — Segment tap grows the sheet again (restore b8943dc's removal)

Files: `Workouts/Features/Exercises/ExerciseDetailView.swift`, `Workouts/Features/Shared/ExerciseInfoSheet.swift`.

- Re-add exactly what `git show b8943dc -- Workouts/Features/Exercises/ExerciseDetailView.swift
  Workouts/Features/Shared/ExerciseInfoSheet.swift` removed: the `EnvironmentValues.onExerciseSegmentChange: (() -> Void)?`
  `@Entry`, the `@Environment(\.onExerciseSegmentChange) private var onSegmentChange` read, `.onChange(of: segment) {
  onSegmentChange?() }` on the `Picker` (after `.accessibilityIdentifier("exerciseDetail.segment")`), and in
  `ExerciseInfoSheet` `.environment(\.onExerciseSegmentChange) { detent = .large }` next to the `AppNavigation?.none` line.
  Restore the `detent` doc comment (`ExerciseInfoSheet.swift:19`): "Starts at half height; picking a segment means 'show
  me what is below', so it grows to full height. DEBUG can start it large."
- `onChange` ignores the initial value, so only a tap on a *different* segment grows the sheet; tapping the already selected
  About does nothing (expected; scrolling expands the sheet).

Proof: `./dev ui-test LoggingBlockMenuUITests/testNameOpensExerciseSheetAndHeaderHasNoRestCaption()` after T3.

### T3 — Tests

Files: `WorkoutsUITests/LoggingBlockMenuUITests.swift`, `WorkoutsUITests/StickyNoteUITests.swift`,
`WorkoutsUITests/ExerciseDetailUITests.swift` (optional assertion), `WorkoutsUITests/TemplatePreviewUITests.swift` (no change
needed: it taps History and only asserts the sessions appear, which still holds).

- `LoggingBlockMenuUITests.testNameOpensExerciseSheetAndHeaderHasNoRestCaption` (`:96-101`): restore the block b8943dc
  removed (medium top > 30 % of the window; tap `segment.buttons["History"]`; poll up to 5 s until `detail.frame.minY <
  mediumTop * 0.7`; assert), and add the regression Eric's screenshot shows, **before** the tap: at the medium detent the
  segmented control is on screen and hittable (`segment.isHittable`, `segment.frame.maxY < windowHeight`), and the sticky
  note is not between the name and the segments (`any["exerciseDetail.stickyNote"].frame.minY >= segment.frame.maxY`
  when it exists; the first block of the seeded active workout may or may not carry a note, so guard on `exists`).
- `StickyNoteUITests.testAddEditRemoveStickyNote`: the flow is unchanged (About is the default segment, the band sits
  under the segmented control on the closed display; if `edit.waitForExistence` fails on the outer display's height, add
  `app.swipeUp()` once). Add one proof that the note is About content: tap `History`, assert `exerciseDetail.stickyNote`
  is gone (`waitUntilGone()`), tap `About`, assert it is back.
- `ExerciseDetailUITests` (`:24-26`): optionally assert `any["exerciseDetail.stickyNote"].frame.minY >
  segment.frame.maxY` on the pushed detail, so the Exercises tab is covered as well as the sheet.
- No kit tests change (`StickyNotes` is untouched). Snapshot suites: none render `ExerciseDetailView`.

Proof: `./dev ui-test LoggingBlockMenuUITests` and `./dev ui-test StickyNoteUITests` (one sim each; the orchestrator runs
`ExerciseDetailUITests`, `TemplatePreviewUITests`, `CustomExerciseUITests`, `FirstFrameUITests`, `PerfDriverUITests` as
the touched suites, since all read `exerciseDetail.segment`).

### Docs (orchestrator, docs-only commit allowed)

- `docs/judgment-calls.md`: a new JC "Sticky note is the first block of About; the info sheet grows on a segment tap again
  (Eric, 2026-11-07)" that supersedes JC107 (leave JC107's text, mark it superseded) and corrects JC75's and JC85's
  parentheticals ("the rest of the content is one swipe or a segment tap away" is true again).
- `docs/PLAN.md:348`: restore "a segment tap grows it to large"; add the About placement to the 7.8 preamble so 7.8b's
  band work knows where the detail's band lives.
- `docs/DECISIONS.md` "Active workout": "exercise pane (video, instructions, Previous, records, sticky note)" still
  holds; no edit.

## 4. State inventory after the change (About tab only)

Empty: "Add Sticky Note" button is About's first row (tinted label, 44 pt hit area), body part under it. Present: yellow band
with the full text and "Edit Sticky Note" (7.8b may also make the band itself tappable, as in the set table; keep the Edit
label as the visible affordance either way). Retired exercise: archive banner first, then the note. Medium detent: a
sliver of the band or the Add row shows under the segments; no note-specific state. Large detent / pushed detail / pane:
full band. Duo open: pushed detail puts the band on the secondary side (book: right; laptop: below the fold); the pane shows
it under its own segments; the set table's band is unchanged, so the note is visible twice when open (JC41, settled).
Dynamic Type AX3: the band wraps as today (`ExerciseDetail-ax.png` in the notes review); its new neighbour is the
segmented control, which the system scrolls horizontally at AX sizes, no overlap. Error / success / haptics: unchanged
(`StickyNoteView` is moved, not edited).

## 5. Taste calls for Eric

1. **Top or bottom of About.** The review puts the note first (your own line before the library's text, two rows from the
   segments at the medium detent). Bottom reads more like Contacts' Notes field but buries it three screens down when
   closed.
2. **A `pin` toolbar item on the pushed detail (Exercises tab) as a shortcut** to the editor, in addition to the band in
   About. It costs nothing on the Duo (the pushed detail has a bar anyway: Back, and Edit for custom exercises) but gives
   the sticky two entry points on one screen. Not proposed for the sheet, which stays bar-less (JC85).
3. **Should About show "Add Sticky Note" when there is no note,** or stay purely reference until a note exists? The review
   keeps the Add row: the Exercises tab and the template preview's ⓘ sheet have no block menu, so without it there is no
   way to add a note from them.
4. **Band tap-to-edit in the detail** (7.8b makes the set-table band tappable): consistent to do the same here, with the
   Edit label kept. Decide with 7.8b.
