# Notes design review (2026-11-07)

Read-only pass (skill `design-review`) over every notes surface, asked by Eric: does the notes implementation read as
iOS 27, does it blend with the app and the system, should it live somewhere else. Evidence: `./dev shot` of the gallery
screens and a seeded active workout, closed portrait light/dark/`accessibility-extra-large`, one open-wide capture of
the logging screen (PNGs under the session scratchpad `…/scratchpad/notes/`, session-local; file names cited below).
The two editor sheets could not be screenshotted without a tap driver (no MCP); they are judged from source.

**Slop verdict: pass.** Every notes surface is a system component: `Form` sheets with system toolbar items, SF Symbols,
the `stickyNote` asset colour, text styles only, `presentationPlacement(.center)` on regular width. Nothing reads as
a ported web control. What does not pass is *completeness and consistency*: four note kinds, two editor components, one
note kind with no writer at all, and one editor that cannot reach notes it displays.

## 1. What exists

| Kind | Belongs to | Written | Read | Entry |
|---|---|---|---|---|
| **Sticky note** (`StickyNote`, `StickyNotes` in the kit; 2,000 chars, one per exercise, blank = removed) | the exercise, so every template and workout | `StickyNoteView` (`Workouts/Features/Exercises/StickyNoteView.swift:13`) in the exercise detail and the logging pane, button "Add/Edit Sticky Note"; block menu "Sticky Note…" (`SetTable.swift:226`) | yellow band under the exercise name in every `SetTable` (`SetTable.swift:195-204`: template editor, logging screen, past-workout editor) and in the detail/pane (`StickyNoteView.swift:31`) | `StickyNoteEditor` sheet: `Form` + `TextEditor(minHeight: 140)`, footer "Shown on this exercise in every template", Remove row, Save/Cancel, swipe blocked when dirty (`StickyNoteView.swift:75-139`) |
| **Block note** (`TemplateExercise.note` / `WorkoutExercise.note`) | one exercise in one template or workout | block menu "Note…" (`SetTable.swift:224`) → `BlockActionSheets.swift:97`; kit `TemplateDraft.setNote` / `ActiveWorkoutEngine+BlockEdits.swift:12` | secondary footnote under the header (`SetTable.swift:206-211`); History detail block (`WorkoutDetailView.swift:418`) | `NoteSheet` (`Workouts/Features/Shared/SetTable/NoteSheet.swift:12`): `Form` + `TextField(axis: .vertical).lineLimit(4...12)`, auto-focused, Save/Cancel, swipe blocked when dirty |
| **Template note** (`Template.note`) | the template | title menu "Edit Note…" (`TemplateEditor.swift:75`) → `NoteSheet` (`:117`) | `TemplatePreview.swift:98` (secondary subheadline under "Last performed"); **not shown in the editor itself** | `NoteSheet` |
| **Workout note** (`Workout.note`) | the finished workout | **nowhere.** The cover's title menu has Rename… and Discard Workout only (`ActiveWorkoutCover.swift:181-189`), the finish flow has no field, `PastWorkoutEditor` has none; only `Importer` and `SampleData` populate it | History detail header (`WorkoutDetailView.swift:276-280`) and its accessibility sentence (`WorkoutDetail.swift:161`) | — |

Not a surface: the Live Activity carries no notes (correct: glanceable state only). The custom-exercise form's "Notes
and instructions" (`CustomExerciseForm.swift:67`) is the exercise's instructions, not a note.

Evidence: `ExerciseDetail-light.png`, `-dark.png`, `-ax.png` (band + Edit button, all three fine); `SetTable-light/dark/ax.png`
(band in the table header); `TemplateEditor-light.png` (title menu chevron, no note on screen); `TemplatePreview-light.png`
("Chest, shoulders, triceps." as secondary text); `WorkoutDetail-light/dark.png` (demo workout has no note; the code path
is a secondary subheadline in the header card); `Cover-closed-light.png` and `Cover-open-wide.png` (band twice when open:
table and pane, the JC41 decision).

Decisions already settled (not re-litigated here): sticky note editable in the detail and shown twice when open (JC41);
block note is a multi-line sheet, not an alert (R3-15 / JC50); band colour is a token (R4-10); dirty sheets block swipe
(R4-19); the block menu may keep `ellipsis.circle` (DECISIONS → Toolbar items).

## 2. Verdict on blend and placement

**Blend with the system: good.** The sheets are the same shape Reminders and Calendar use for a secondary text field
(inline title, Cancel / confirm items, one `Form` section with a footer), the band is a filled rounded rect with no rim,
the plain note is the Reminders "notes line" (secondary text under the title). Dark mode is designed (amber token, primary
text on it, `ExerciseDetail-dark.png`). Dynamic Type works: the band wraps and keeps its padding at AX3 (`SetTable-ax.png`,
`ExerciseDetail-ax.png`). Accessibility labels exist on every element ("Sticky note: …", "Note", "<exercise> options").

**Blend with the app: partial.** The app has one idiom for every other edit (a sheet from a menu), and notes follow it,
but with two different editors that behave differently in the hand: `NoteSheet` autofocuses, has a placeholder and a
growing `TextField`; `StickyNoteEditor` does not autofocus (an extra tap in the gym), has no placeholder (an empty
140-pt white box in a `Form`), and uses a `TextEditor`. The menu names "Note…" and "Sticky Note…" sit next to each other
with nothing on screen explaining which is which; only the sticky editor's footer says. A fluent iPhone user pauses there.

**Should notes live somewhere else?** No — keep the sheet from the block menu as the *add* path, but add a *tap-to-edit*
path on the note itself, and give the two whole-object notes (template, workout) a visible home. Alternatives weighed:

| Alternative | For | Against | Call |
|---|---|---|---|
| **Sheet from the ⋯ menu (today)** | Clean table; keyboard never fights set cells; one-handed OK once open; matches every other block edit | Two taps to add, three to find; note kinds indistinguishable in the menu; an existing note is not an affordance | Keep as the add path |
| **Inline always-visible field under each exercise** (Strong / Hevy style) | One tap, most discoverable | 5–8 empty "Add a note" lines of noise per workout; focus traversal (Next/Done) mixes text with the number pad; on the closed Duo it costs a set row per exercise | Reject |
| **Tap the rendered note to edit** (web did this for the band) | Zero new chrome; the thing you see is the thing you edit; a sheet still handles typing | Needs a `Button` wrapper and a hint; nothing when the note is empty (menu stays) | **Adopt** (P2 below) |
| **Notes submenu / `ControlGroup` in the ⋯ menu** | Shortens the 9-item menu | One more tap for the most-used of the two; nested menus are rare in Apple's apps on iPhone | Reject; shorten instead by making the rendered note tappable, and consider `Menu` sections |
| **Per-set note** | Granular ("belt on this set") | New model field, a column the closed display cannot afford, not in the web; set kinds already carry the common cases | Not now |
| **Workout note in the finish summary** (Fitness post-workout / Health State of Mind idiom) | Reflection moment, one place, after the lift | Keyboard over the celebration sheet; one more step before Done; cannot add it the next day | Taste question for Eric (§4) |
| **Workout note in the cover's title menu and the past editor's title menu** | Same idiom as the template note; reachable mid-workout and afterwards | Hidden behind the title chevron (the same discoverability problem the template note has) | Adopt as the writer; pair with a visible line in the header |

## 3. Findings

| P | Screen · file:line | What (evidence) | Rule | Fix at the narrowest level | Taste? |
|---|---|---|---|---|---|
| P1 | History detail · `WorkoutDetailView.swift:276`, `ActiveWorkoutCover.swift:181`, `PastWorkoutEditor.swift` | `Workout.note` is rendered and spoken but **no native surface can write it**; only imports fill it. A field the user sees on imported history and can never add to new workouts is a dead end (state inventory → nothing is a dead end). | HIG Feedback / skill §4 | *Conceptual, one worker task*: add "Note…" (`note.text`) to the cover's `toolbarTitleMenu` and to the past-workout editor's title menu, both presenting `NoteSheet`; kit: `ActiveWorkoutEngine.setWorkoutNote(_:)` + `PastWorkoutDraft.note` round-trip with tests; show the note as a secondary line under the cover's subtitle region only when non-empty. Proof: `./dev kit` + `./dev ui-test` (one new flow in SetTableUITests or PastEditorUITests). | Where (§4 Q1) |
| P2 | Past-workout editor · `PastWorkoutEditor.swift:236` | `SetTable` is built without `blockActions`, so a block note shown in History (`WorkoutDetailView.swift:418`) cannot be fixed after the fact, while sets, name and date can. Inconsistent with the template editor and the live workout. | skill §3.5 consistency | *Local defect*: pass a `SetTableBlockActions` with `note` (and `stickyNote`) only in past mode; kit `PastWorkoutDraft.setNote(block:text:)` + test. Proof: `./dev kit PastWorkoutDraft` + one UI test. | |
| P2 | Set table header · `SetTable.swift:195-211`; detail · `StickyNoteView.swift:31` | A rendered note is not an affordance: the band and the plain note are `Text`, so editing means finding the ⋯ menu and knowing which of two entries applies (`Cover-closed-light.png`: band + ⋯ at the far edge). The web let you tap the band. | HIG Buttons / Menus ("don't hide the only path to an action") | *One-off*: wrap the band and the block-note `Text` in `Button`s calling `actions.stickyNote(id)` / `actions.note(id)` when `blockActions` is non-nil (`.buttonStyle(.plain)`, `accessibilityHint("Edits the sticky note")`). The menu entries stay. Proof: `./dev test SnapshotTests/SetTable…` (no pixel change) + extend `SetTableUITests` with a band tap. | |
| P2 | Note editors · `NoteSheet.swift:32-34` vs `StickyNoteView.swift:97-103` | Two editors for one job: `NoteSheet` autofocuses, has a placeholder, grows 4–12 lines; `StickyNoteEditor` has no autofocus (one more tap one-handed), no placeholder (an empty white 140-pt box), a fixed `TextEditor`, and a footer. Neither tells the user the *scope* of the note except the sticky one. | skill §3.1 "system patterns", §5 one hand | *Shared component*: make `NoteSheet` the only editor — add `footer: Text?` and an optional `onRemove` row — and have `StickyNoteEditor` become a thin wrapper that supplies "Shown on this exercise in every template" and the Remove row; pass footers "Kept with this template" / "Kept with this workout" from the block callers. Keep the 2,000-char cap in `StickyNotes.set`. Proof: `./dev ui-test StickyNoteUITests` + `TemplateEditorUITests`. | Footer copy (§4 Q3) |
| P2 | Template editor · `TemplateEditor.swift:75,117` | The template note is edited from the title menu but **never shown in the editor** (`TemplateEditor-light.png`): no feedback that it exists or changed until the preview. Same hazard the P1 writer would inherit. | skill §3.5 every action gives feedback on screen | *Local defect*: render `draft.note` as a secondary `subheadline` line above the first block when non-empty (same style as `TemplatePreview.swift:98`), tappable to open the sheet. Proof: `./dev ui-test TemplateEditorUITests/…note…`. | |
| P2 | Block menu · `SetTable.swift:218-249` | Nine entries at one decision point (Exercise Info, Note, Sticky Note, Warm-up, Rest, Replace, Superset, Preferences, Remove) against the "more than four choices" rule; the two note rows are the only pair a user must tell apart by name alone. | skill §5 | *Local defect*: once the rendered note is tappable (row above), group the menu with `Section`s (notes · sets · exercise) so the eye scans three groups, and give "Sticky Note…" a distinct glyph (`pin` or `note`, see P3). No entry removed. Proof: `./dev shot` of the open menu via UI test attachment, or source review. | Glyph (§4 Q2) |
| P3 | Block menu · `SetTable.swift:226` | "Sticky Note…" always shows `note.text.badge.plus`, including when a sticky exists (the detail's button correctly swaps to `pencil`). | HIG SF Symbols: badges mean the action | *Local defect*: `stickyNote(for:) == nil ? "note.text.badge.plus" : "note.text"`, or one stable glyph. | |
| P3 | Set table band · `SetTable.swift:196` | No line limit: a 2,000-char sticky pushes the set rows a screen down on the closed display, and the same text is in the pane when open. | skill §4 Overflow | *Local defect*: `.lineLimit(3)` on the band in the table (full text in the detail/pane and in the editor); keep the full text in the accessibility label. | Limit (§4 Q4) |
| P3 | History detail header · `WorkoutDetailView.swift:276` | The workout note is the last line of the stats card in `.secondary`, below the numbers; a note like "Felt strong today." reads as a caption of the volume figure. | HIG Typography hierarchy | *Local defect*: move it out of the `LazyVGrid` card into its own line under the header (or above the first block) in `.subheadline` primary, as Reminders renders a note. Snapshot change intended. | Placement |

Dimension scores: Platform conformance **3** (system sheets and menus; the sticky editor is the one off-pattern input) ·
Hierarchy and layout **3** (band sits well under the name; the plain note is indistinguishable from the rest caption) ·
Colour and appearance **4** (token colour, primary text on it, designed dark) · Type and content **3** (text styles only; AX3
wraps; two inputs disagree on ergonomics) · States and resilience **2** (a note kind with no writer, a past editor that
cannot reach its notes, an empty editor with no placeholder).

### State inventory (notes only)

Empty: sticky — "Add Sticky Note" button, no band ✓; block/template/workout note — nothing shown ✓, writer in the menu ✓
(workout: missing, P1). Loading: n/a (SwiftData `@Query`, synchronous). Error: sticky save → "Could Not Save" alert ✓;
block/template notes ride the draft's save ✓. Success: dismissal, no banner ✓; Remove → `.warning` haptic ✓. Disabled: Save
always enabled (unchanged text saves the same value; acceptable). Overflow: 2,000-char cap ✓ enforced in `StickyNotes.set`
and the editor's `onChange`; display has no limit (P3). Duo: band twice when open, settled (JC41); sheets `.center` ✓.

## 4. Taste calls for Eric (one batched question)

1. **Where does the workout note get written?** (a) cover title menu + past editor title menu (same idiom as the template
   note, mid-workout and afterwards); (b) a "How did it go?" field on the finish summary (the Fitness/Health reflection
   moment, but a keyboard over the celebration and no later edit without (a)); (c) both. The review recommends (a), with
   (b) only if you want the prompt.
2. **Glyph for the sticky note.** `note.text` for both kinds is honest but identical; `pin` / `pin.fill` reads "sticks to the
   exercise" and separates the two menu rows at a glance. Band colour stays yellow either way.
3. **Footer copy** that names the scope: "Kept with this template" / "Kept with this workout" / "Shown on this exercise in
   every template" (web copy, kept). Or shorter: "This template only" / "This workout only" / "Every template".
4. **Band line limit in the set table**: 3 lines, or none (today). The detail/pane always shows the full text.
5. **Should the two note kinds merge in the UI?** Keep both (the model and web have both, and a cue like "retract the
   blades" is different from "machine 3 was taken, used dumbbells") — the review assumes yes and only unifies the editor.

## 5. Good as is

- The sticky band: token colour, filled shape without a rim, primary text, wraps at AX3, identical in the table, detail and
  pane, and the pane keeps the full "Edit Sticky Note" affordance with a 44-pt hit area (`StickyNoteView.swift:50`).
- `NoteSheet`'s shape (inline title, Cancel / checkmark, growing `TextField`, autofocus, dirty-guard on swipe) is exactly
  the system pattern; it should become the one editor.
- `StickyNotes` in the kit: trimmed, capped, duplicate-collapsing for CloudKit merges, rollback on a failed save, with
  tests — the persistence rules are right and testable without a simulator.
- Accessibility: every band and sheet is labelled ("Sticky note: …", "<exercise> options"), the History block reads its
  note into one sentence, and haptics follow DECISIONS (`.warning` on Remove).
- The plain block note as a secondary line under the exercise name is the Reminders idiom; nothing to redesign there.
- Live Activity stays note-free.
