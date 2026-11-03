# Workout tab (folders, templates, template editor)

Sources: web `PLAN.md:141-171`, `app/docs/ui.md:149-166`, `app/docs/schema.md` "Templates", and
`ui/src/features/templates/` (`StartWorkoutPage.tsx` = SWP, `TemplatePreview.tsx`, `TemplateEditor.tsx` = TE,
`Dialogs.tsx`, `model.ts`). The in-progress workout is `active-workout.md`; the editor is one shared component,
so only template-mode behaviour is specified here. Tab title is "Workout" (`POLISH.md` T1; was "Start Workout").

## 1. Purpose

Where every workout starts. Templates live in collapsible folders; tap a template to preview it, **Start Workout**
begins a workout from it, **Edit** opens the template editor. There is **no Quick Start and no empty workout**
(`PLAN.md:142`): a workout always starts from a template (exercises can still be added during it). The tab also
owns folder and template management.

## 2. Data shown

- **Folder**: name (max 120 chars, SWP:271), `collapsed` flag, order. Header text `"<name> (<count>)"`, e.g.
  "PPL Livmore (3)" (SWP:211).
- **Template**: name (new = "New Template", `model.ts:362`), note, folder, `position` within its folder (new =
  end of folder; reads order by position, then name, then id), exercises.
- **Card**: name; exercise names clamped to 3 lines, or "No exercises" (SWP:135); "Last performed" with a clock
  icon **only when one exists**. Web: 2-column grid (`PLAN.md:146`).
- **lastPerformed** = max `startedAt` over finished workouts of the template, else over finished workouts with
  the same name (case-insensitive; imported history is not linked). In-progress workouts never count
  (`schema.md`). Display (`model.ts:458-469`): same day/future "Today"; "Yesterday"; 2-13 days "N days ago";
  14-59 days "N weeks ago" (floor of days/7); 60+ days a locale date (year, short month, day).
- **Template exercise row**: library exercise, `superset_group` (small int; equal = one superset), `unit` (lb/kg,
  stored as typed), `bar_type` (`olympic`/`ez`/`none`/`custom`, default olympic) + `bar_weight` (custom, in the
  row's unit), rest seconds (null = Default), note, sets.
- **Set**: kind `normal`/`warmup`/`drop`/`failure`, weight, reps, time. Blank weight/reps = absent; at most 2
  decimals; numbers are text while editing ("17." must survive) and parsed on save (`ui.md:153`).
- **Previous** column (also in the template editor): same set index of the exercise's last performance, muted,
  "-" if none (`ui.md:154`).
- **Sticky note** belongs to the **exercise**, shows (yellow band) in every template using it, saved immediately,
  not with the template save (`schema.md`).
- Names, thumbnails, body parts come from the exercise library. Preview rows: `N × Name`, body part, thumbnail.

## 3. Interactions

**Page**
- `+ Template` ("New Template") -> no folders: "New Folder" prompt then editor in it; else sheet "Add Template to
  Folder" preselecting the last-used folder (`workouts:last-folder`, set on add/save; else first) -> editor in
  "New Template" mode (SWP:158). New-folder glyph ("New Folder") -> text sheet, field "Name".
- Folder header tap -> collapse/expand; flag flips at once, saved behind. Card tap -> preview (`/workout/{id}`).
- Card menu ("<name> options"): **Edit**, **Duplicate**, **Move to Folder** (folder picker; lands **last** in the
  target, `store.ts:130`), **Delete** (destructive): confirm "Delete <name>?" / "The template is deleted. Workouts
  you did from it stay in your history." / "Delete Template".
- Folder menu ("<name> options"): **Rename Folder** (text sheet "Rename Folder"), **Reorder Templates** (only if
  >1 template in it), **Reorder Folders** (only if >1 folder), **Delete Folder** (last, destructive) (SWP:111-114).
  Reorder sheets: rows with "Move <name> up"/"down" buttons.
- **Delete folder** (never orphans, `schema.md`): empty -> confirm "Delete <name>?" / "The folder is empty." /
  "Delete Folder". With templates -> action sheet "Delete <name>?": "<name> has N template(s). Move it/them to
  another folder, or delete it/them with the folder."; actions **"Move to <other folder>"** (one per other folder,
  keeps order, appended), destructive **"Delete Folder and N templates"** ("1 template"), Cancel. Only folder ->
  message "<name> is your only folder and has N template(s). Every template lives in a folder, so it goes/they go
  with it. Workouts you did from it/them stay in your history." and one destructive "Delete Folder and
  Template(s)" (`Dialogs.tsx:355-378`). Deleted templates' workouts stay (`template_id` -> NULL).
- **Preview** (header: close, **Edit**): row "?" opens exercise detail ("About <name>"); empty template shows
  "This template has no exercises yet." and **Start Workout** is **disabled**. Start with a workout already active
  -> action sheet "Workout in progress": "You are in the middle of “<name>”. Resume it, or discard it and start
  the new one." -> **Resume Workout** (recommended) / **Discard and Start New** (destructive) / Cancel
  (`ActiveWorkout.tsx:122-135`). Otherwise it begins immediately.

**Editor** (title "New Template"/"Edit Template"; close + **Save**; name menu "Template options")
- Name menu: **Edit Template Name** (sheet "Template Name"), **Add Note**/**Edit Note** (sheet "Note", "Remove Note").
- **Add Exercise** -> picker "Add Exercise": multi-select; **Add (N)** adds plain, **Superset** (needs >=2) adds
  them as one new group; Any Body Part / Any Category / sort, A-Z index, **New** custom exercise (auto-ticked).
  Empty: "No exercises yet. Add one to start building the template."
- **Reorder exercises**: drag the grip left of the name (arrow keys too) (`ui.md:155`).
- Exercise menu ("Exercise options"): Add/Edit Note; **Add/Edit Sticky Note** (sheet "Sticky Note", label "Shown on
  this exercise in every template", "Remove Sticky Note"); **Add Warm-up Sets**; **Update Rest Timers**;
  **Replace Exercise** (one-pick picker; sets, note, rest stay); **Create Superset**/**Edit Superset** (hidden with
  one exercise); **Preferences** > **Weight Unit** ("Pounds (lbs)"/"Kilograms (kgs)"), **Bar Type** ("Olympic Bar",
  "EZ Bar", "No Bar", "Custom Bar..." -> sheet "Custom Bar"); **Remove Exercise** (TE:324-340).
- **Sets table**: `Set | Previous | lbs/kgs | Reps | —` (completion cell is a locked dash in a template). Columns by
  weight type: weight x reps; bodyweight "+lbs"; assisted "-lbs"; reps-only and timed show Reps and "Time (s)"
  (`ui.md:154`). Set cell tap cycles normal -> W -> D -> F -> normal (`model.ts:136`); the number counts **only
  normal sets**; W/D/F show as letters in kind colours. **+ Add Set** copies the last set (a warm-up becomes a
  working set). Delete a set: swipe left (>48 pt, mostly horizontal) or hold its number 500 ms -> red Delete.
- **Add Warm-up Sets** (`ui.md:160-162`): from the first non-warm-up set with weight W: empty bar x 10, then 40% x 8,
  60% x 5, 80% x 3 of W, each rounded to the plate step (5 lb / 2.5 kg). Bars: Olympic 45 lb / 20 kg, EZ 15 lb /
  7 kg, none, custom. A step not above the previous (or the bar), or reaching W, is omitted: 100 lb -> 45, 60, 80;
  a 45 lb set on the 45 lb bar -> none. Ramp goes ahead of working sets and **replaces** existing warm-ups.
- **Supersets** (`ui.md:164-166`): members share a group number; colours by first appearance, six tokens `--ss-1`..
  `--ss-6`, wrapping. Sheet: Cancel / "Create Superset"|"Edit Superset" / Save (disabled until pick differs); rows
  show their group's bar; tap toggles; footer "Select two or more exercises to create a superset". Save gathers
  members next to each other where the first was; a group of <2 dissolves; removing one of a pair dissolves it.
  Groups renumber 1, 2, 3 on save (`schema.md`).
- **Unit per row**: Weight Unit relabels, never converts (D7). **New rows** start from the exercise's override
  (unit, bar, rest) if any; else lb, an Olympic bar for barbells (none otherwise), three empty sets (`ui.md:158`).
- **Rest**: sheet "Rest Timer", one value per exercise: Default, Off, 0:30, 1:00, 1:30, 2:00, 3:00, 5:00
  (TE:59-63); shown as caption "Rest timer: 2:00" under the name.
- **Save** -> unchanged and not new: just closes; else saves the whole template; failure keeps the editor open
  with the message (fallback "Could not save the template."). **Close** when dirty -> "Discard changes?" / "Your
  changes to this template have not been saved." / "Discard Changes" / "Keep Editing". Dirty = differs from what
  opened (typing a value and reverting is clean).

## 4. States

- Workout in progress: Start Workout shows the Resume/Discard sheet; the rest is unaffected. Loading: skeleton. Load error: "Could not load the templates." + "Try again". Write error: dismissible banner
  (message + "Dismiss") and the list re-reads so the screen matches the store.
- No folders: "No templates yet. Create a folder, then add a template."
- Folder with no templates: header only. Template with no exercises: "No exercises", Start disabled. Regular
  width, nothing selected: "Select a template". Link to a deleted template -> back to the list.

## 5. Native mapping

- Root: regular width (open Duo) `NavigationSplitView` with the folder/template list and the template preview in
  the detail column ("Select a template" placeholder), mirroring web's expanded list + preview panes (`ui.md:150`);
  compact (closed Duo) a `NavigationStack` list with the preview as a **medium-detent sheet**, Start Workout
  pinned at its foot (`IOS.md` C5). Selection and an open editor draft live in model state: width can change mid
  session and the draft must survive a fold (`ui.md:151`).
- Folders: `List` with a `Section` per folder, header `"<name> (<count>)"`, collapsible (expansion persisted),
  trailing ⋯ `Menu` (Rename Folder, Reorder Templates, Reorder Folders, Delete Folder). Templates as rows or a card
  grid; keep name, 3-line exercise list, Last performed.
- Reorder: edit mode with `.onMove` (or iOS 27 `.reorderable`) for templates within a folder and for folders; the
  "Reorder Templates"/"Reorder Folders" menu entries enter edit mode, replacing the web's up/down sheets.
- Template row: swipe actions (trailing Delete destructive, Duplicate, Move to Folder) plus a `contextMenu` and ⋯
  `Menu` with Edit, Duplicate, Move to Folder, Delete.
- Destructive confirmations as `confirmationDialog` with message and Cancel: Delete Template, Delete Folder (empty),
  Delete Folder with templates (per-folder "Move to ..." actions + destructive delete-all), Discard Changes,
  Workout in progress (Resume / Discard and Start New). Rename, New Folder: alert or small sheet with a text field;
  folder pickers: sheet or `Menu`.
- Editor: compact -> `fullScreenCover` (not a pushed route; web `ui.md:151`). Regular width -> same editor with a
  side detail pane showing the selected exercise's video/instructions, set tables capped at 540 pt (web
  `ui.md:151`); whether it shares the screen with the list is an open question. Exercise ⋯ = `Menu` with a nested
  Preferences `Menu`. Exercise reorder: drag handle / `.onMove`. Per-set Delete: swipe action (replaces long-press).
- Numeric entry: native keypad with Next/Done toolbar replaces web's NumPad (`POLISH.md` C3/C5). `sensoryFeedback`
  on card press and Start Workout (HP1). SwiftData persistence; `@AppStorage` for last-used folder.

## 6. Dropped or changed on purpose

- Quick Start / empty workout and unfiled templates ("My Templates"): gone by decision (2026-11-02, migration 0007).
- Distance and time-and-distance weight types are "(later)" on web (`PLAN.md:161`): out of scope here.
- Up/down reorder sheets: web notes "drag can replace it later" (SWP); native uses drag/edit mode.
- Exercise-header chart pill: removed on web (`IOS.md` C2a); the name opens the detail whose tabs include Charts.
- Web plumbing not carried over: server write-then-reread, `beforeunload` guard, glass header scroll timeline,
  `useGridColumns`, IndexedDB.

## 7. Open questions

1. `PLAN.md:143` lists a Templates-level **⋯ (reorder, collapse all)**; `ui.md:149` says compact has **no
   Templates-level menu** and no "collapse all" exists in SWP. Add Collapse All / Reorder Folders at that level?
2. Open Duo: editor over the whole split view (web: full-screen layer with its own detail pane) or in the detail
   column beside the list?
3. Card grid or plain list rows on compact width?
4. What name does Duplicate give the copy? Sources only show `duplicateTemplate(id, newId())` (`store.ts:126`).
5. Should the `collapsed` flag sync across devices via CloudKit, or be per-device?
6. Rest options: `ui.md:156` says "Default, Off, 0:30 ... 5:00"; code lists 0:30, 1:00, 1:30, 2:00, 3:00, 5:00
   (TE:59-63). Is the code list authoritative? 7. Should an unsaved editor draft survive relaunch (web: no, `ui.md:152`)?
