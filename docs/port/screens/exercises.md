# Exercises tab

Citations: `ui.md` etc. are the web app's `app/docs/`; `POLISH.md` is the web repo's.
## 1. Purpose

Browse the exercise library (~1,000 scraped SmartWorkout exercises plus your own custom ones), find one, and open
its detail: what it is (About), what you did with it (History), how it trended (Charts) and your bests (Records).
The same list, search and filters, with checkmarks instead of best sets, is the exercise picker used by the
template editor and the active workout. Library content is read-only; only custom exercises are editable.

## 2. Data shown

- **List** = every exercise, retired included, loaded once; filtering, search and sorting are local (`ui.md:127`).
  Order: by the name shown, case/accent-insensitive, id as tiebreak (`logic.ts:28`). Sections by first letter
  (A-Z, accent-stripped, `#` for anything else, sorted last). The current letter's header sticks while scrolling.
- **Row** (fixed 56px in the web app): thumbnail tile (`start.png`/`end.png` frames; letter tile when there is no
  media), name, `Retired` / `Custom` tags after the name, body-part label as the second line, and the **best set
  of the exercise's most recent session** on the right (`api.md:34`; computed by `records.BestSet`, warm-ups and
  unchecked sets never count, `records.md:13`). Display unit = the setting. Formats (`history/format.ts:18`):
  `25 lb (×10)` weight and reps; `12 reps` reps without weight; timed sets use `formatBest` (e.g. `45 s`,
  `1:30`); empty for an exercise never performed. PLAN says "best/last set"; the shipped value is best-of-latest.
- **Filter vocabulary.** Only two filters exist: body part and category (= equipment). Weight type and muscles are
  *not* filters (weight type appears only in the form; muscles only in About). Chips read `Any Body Part` /
  `Any Category` until set, then show the chosen label. Body part options come from `meta.bodyParts` plus `Other`
  (custom exercises); `Other` is listed only if some exercise uses it (`ExerciseFilters.tsx:62`). Equipment is an
  open vocabulary: labels for the source's 11 categories, plus keys used by exercises with a humanised label
  (`schema.md:91`, `scrape.md:55`). Sheet titles: `Body Part`, `Category`, `Sort By`.
- **Sort sheet** offers only `Name (A-Z)` (`logic.ts:24`, `ui.md:131`). PLAN.md:177 promised name / most used /
  last performed; not built.
- **Retired** = a library exercise missing from the latest complete import (`schema.md:35`); hidden unless
  ⋯ > `Show retired` (a checkmark item in a menu labelled "Exercise options"); still openable by id.
- **Detail header**: full wrapping name; segments `About`, `History`, `Charts`, `Records`.
- **About** (top to bottom, each block omitted when empty): media card; retired notice "This exercise is no longer
  in the library; its history is kept."; body-part line, plus ` · Library name: X` when the shown name differs from
  the library name on a non-custom exercise; `Instructions` (numbered), `Tips`, `Common mistakes`, `Overview`
  (description), `Muscles` with `Primary` / `Secondary` chips, `Equipment` chips, `Also known as` (aliases), credit
  "Exercise content: SmartWorkout" linking `sourceUrl`. Muscle intensity map is 0-100: **>= 70 primary, 1-69
  secondary, 0 dropped**, strongest first; 70 is our choice, not the source's (`ui.md:144`). Missing labels are
  made from the key ("chest_upper" becomes "Chest upper"). Mechanics, laterality, `usedCount` and tags are in
  the data but not displayed. **Alternatives/recommended are not displayed either** (`api.md:15` serves them
  resolved and non-retired; `About` never renders them).
- **Media** (`scrape.md:39-47`): per exercise `animation.gif`, `start.png`, `end.png`, `video-dark.mp4`,
  `video-light.mp4`, optional extras. The UI uses only `video-light` (poster `start.png`), the thumbs, and the
  gif/poster as an image fallback; `video-dark` is not referenced by the files read.
- **History tab**: sessions newest first, completed sets only, weights as entered in the session's own unit.
  Per session: short date, workout name, trophy + PR count when > 0, numbered sets with `W` warm-up, `D` drop,
  `F` failure markers (normal sets count 1, 2, ...; markers do not consume numbers). 20 per page (limit 1-100).
- **Charts tab**: one point per session. Metric chips and default by weight type (`ExerciseTabs.tsx:155`):
  strength (`barbell`, `dumbbell`, `machine`, `weighted`, unknown): `Est. 1RM` (default), `Max weight`, `Volume`,
  `Total reps`, `Best reps`; `bodyweight`/`unweighted`/`band`: `Best reps` (default), `Total reps`, `Max weight`,
  `Volume`; `assisted`: `Max weight` relabelled `Least assistance` (default), `Best reps`, `Total reps`. Ranges
  `1M`, `3M` (default), `6M`, `1Y`, `All`. Formulas (`records.md:23-33`): Epley `w * (1 + reps / 30)`; Brzycki
  `w * 36 / (37 - reps)`; reps above 12 are clamped to 12 and flagged low confidence ("from over 12 reps"); a
  confident estimate always beats a low-confidence one. Weight-valued charts show the unit suffix; rounding is
  to the nearest 0.5 for converted/computed values (`records.md:19`). Assisted: lower is better, no e1RM/volume.
- **Records tab**: rows `Estimated 1RM`, `Heaviest weight` (assisted: `Least assistance`), `Best set volume`
  (`value unit (weight × reps)`), `Longest duration`, each with its date; then table `Reps at weight` (assisted:
  `Reps at assistance`) with columns `Weight`/`Assistance`, `Reps`, `Date`, one row per distinct weight, heaviest
  first (assisted: least assistance first); weight 0 shows `Bodyweight`. Which records exist per weight type:
  `records.md:74-86`. Ties keep the earlier session; only strictly beating a record replaces it.

## 3. Interactions

- Type in `Search` → live filter; every whitespace-separated word must appear in the name or in some alias,
  case, accents and extra spaces ignored (`ui.md:127`, `logic.ts:49`). Matches substrings of words.
- Tap `Any Body Part` / `Any Category` → single-choice sheet, check on current, picking closes; first row resets.
- Sort button (`Sort`) → `Sort By` sheet. ⋯ (`More`) → `Show retired`. `+` (`New exercise`) → New Exercise form.
- Tap a row → opens its detail; regular width shows it in the split's detail column (§5).
- **New Exercise** form (title `New Exercise`, `Cancel` / `Save`): `Name` (required, max 120, placeholder
  "Exercise name"; error "Give the exercise a name."), `Body part` (required, `Choose...`; "Pick a body part."),
  `Equipment` (multi-toggle chips), `Weight type` (labels: `Weight and reps` = weighted, `Barbell`, `Dumbbell`,
  `Machine`, `Bodyweight`, `Assisted bodyweight (less is better)`, `Band`, `Reps or time only` = unweighted;
  default weighted), `Notes and instructions` (placeholder "One step per line", saved as `instructions`),
  `Weight unit` (`Default (lb)`, `lb`, `kg`), `Bar` (`Default`, `No bar`, `Olympic bar (45 lb / 20 kg)`,
  `EZ bar`, `Custom weight`; `Bar weight (unit)` field 0-1000 when Custom), `Rest timer (seconds)` (blank =
  "Default"; whole number 0-3600, comma decimals accepted; error "Rest timer is a whole number of seconds, 0 to
  3600."). Unit/bar/rest are stored as the exercise's override and are what a *new* row starts from
  (`schema.md:54`, `ui.md:132`). Client makes the UUID. Aliases start empty. Saved exercise is upserted into the
  list without a refetch.
- **Edit**: only on a custom exercise, from the `Edit` item beside `Close` (absent, not disabled, on library
  exercises). Same form titled `Edit Exercise`; edits name, body part, equipment, weight type, notes, unit, bar,
  rest. No delete or archive of a custom exercise appears in the sources read.
- **Rename / override of library exercises**: the UI is gone (`ui.md:132`, POLISH E1 `POLISH.md:345`; PLAN.md:186
  still lists it). The server still accepts `override` (`name`, `unit`, `barType`, `barWeight`+`barUnit`,
  `restSeconds`; `api.md:14`) and one already stored still applies. **A rename appends the stored name to
  `aliases` so search still finds it**; the re-import never touches overrides (`schema.md:44`).
- **Sticky note**: not editable on this tab. Edited from a template's exercise menu (`Add Sticky Note` /
  `Edit Sticky Note`, or tap the yellow band): sheet `Sticky Note`, hint "Shown on this exercise in every
  template", multiline, max 2,000 chars, `Remove Sticky Note` clears; saved immediately on Save, one per exercise,
  not part of the template save (`TemplateEditor.tsx:325,627`, `ui.md:157`, `api.md:25`).
- **Picker variant** (`templates/ExercisePicker.tsx`; same list, search, filters, sort, A-Z, but no `Show retired`
  and no best-set slot): `multi` sheet "Add Exercises": rows are checkboxes, `Add (N)` capsule (disabled at 0),
  `Add as superset`/`Superset` needs 2+; `single` (Replace Exercise): tapping a row picks it and closes. `New`
  (accent text beside search) opens the form; the saved exercise is auto-ticked (multi) or picked (single). An
  unticked row has a `?` button (`About <name>`) opening the detail as a modal over the picker, where session,
  chart point and record rows are plain text, not links. Filters/search are kept only while the sheet lives.
- In Exercises, sessions, chart-readout dates and record rows link to that workout in History (`/history/{id}`).
- Detail tabs reload when a workout is saved/edited/deleted or a setting changes. The video autoplays muted,
  looping, unless reduced motion is on; the button toggles `Play video` / `Pause video`.

## 4. States

- List: `Loading...` while fetching (cached answer shown first, then fresh); error "Could not load the exercises."
  with `Try again`; `No exercises yet.` (empty library); `No exercises match.` (filters/search). Best-set slots
  stay empty if their request fails or nothing was performed.
- Detail: `Loading...`; "That exercise does not exist." (404) / "Could not load the exercise."
- Media: thumb/animation only = image; neither = no card, muted "No video for this exercise".
- History: "No history yet. Log a workout with this exercise to see it here."; `Show older` button when more pages.
- Charts: "Nothing to plot for {metric} in this range."; readout defaults to the newest point.
- Records: "No records yet. Log a workout with this exercise to set some." In-progress workout: no special state
  here; best sets and tabs refresh after a workout is saved.

## 5. Native mapping

- Compact (closed Duo): `NavigationStack` with an inset `List` of letter sections; detail pushed. Regular
  (open Duo inner display): `NavigationSplitView` (list | detail) with `List(selection:)` and no column-width
  modifiers (the system sizes columns and keeps them off the fold); `ContentUnavailableView` "Select an exercise" as
  the empty detail (Mail's "No Message Selected").
- Search: `.searchable` only (no inline field), over name + aliases, own normalisation (all-words,
  accent-insensitive, not `localizedStandardContains` alone); the system places the search circle at the foot of
  the trailing strip (Flighty). Body part and category as two `Menu` pills at the top of the list (Flighty's chip
  row) or `searchScopes` if there are 4 values or fewer. No sort control while Name A-Z is the only sort. **No A-Z
  rail**: SwiftUI has no section index and the trailing edge is reserved for the system; do not rebuild `AlphaIndex`.
- Toolbar: New Exercise (`plus`) and Show Retired (`eye`, a toggle item), each with symbol and title, left to the
  system's overflow; no ⋯ `Menu`. `Retired`/`Custom` stay small row tags. Detail: Edit (`pencil`, custom only).
- Picker variant: **Add (N)** (`Button("Add 3", systemImage: "plus")`) and **Superset** (`rectangle.stack`) are the
  sheet's toolbar items, not a bottom capsule; Cancel sits in the Close slot.
- Detail: segmented `Picker` for About / History / Charts / Records. Charts: **Swift Charts** line + point marks
  with `chartXSelection` for the readout; metric chips and a range segmented control. Records as a `Grid`.
- Media: `AVPlayer` muted, looping, honouring Reduce Motion, with the poster frame (the hero uses
  `.backgroundExtensionEffect()` under a vertical bar); thumbnails as a still image (optionally crossfading
  start/end frames). Custom form: sheet with `Form`; picker variant: sheet with
  multi-selection `List`; sticky note: sheet with `TextEditor`.
- Workout links in the detail navigate to the History tab's workout detail.

## 6. Dropped or changed on purpose

- Virtualised list, container queries: native `List` covers them. The hand-built A-Z rail is dropped outright (no
  native section index; search replaces it).
- Client store, Cache API, `/api/*` calls: SwiftData instead.
- Server `q` substring search (`schema.md:89`): not used by the UI; only the all-words client rule carries over.
- Single-option `Sort By` sheet and the A-Z rail's scrub gesture: only if more sorts return (question 3).

## 7. Open questions

1. Bundle or download media? `scrape.md:17`: the first 20 exercises came to 4.7 MB each (95 MB, mostly the 3 MB
   GIF), "the full snapshot is about 5 GB". Which of `animation.gif`, `start.png`/`end.png`, `video-light.mp4`
   (and `video-dark.mp4`) ship in the app, and from where (on-demand download, CloudKit asset, bundled subset)?
2. Library content is read-only (POLISH E1) but PLAN.md:186 still lists overrides. Native: any UI to rename a
   library exercise or set its unit/bar/rest default, or custom exercises only?
3. Should the three promised sorts (name, most used, last performed) return, or is `Name (A-Z)` final?
4. Show alternatives/recommended in About (data exists; the web never renders it)?
5. Charts: Epley/Brzycki switch was in PLAN.md:184 but the web follows the `e1rmFormula` setting only. Keep that?
6. Sticky notes are editable only from templates. Add editing (and display) in the exercise detail?
7. Can a custom exercise be deleted or archived (nothing in the sources)? What of "merge duplicates" (later)?
8. Does the `rename appends the stored name to aliases` rule (`schema.md:44`) append the *library* name (as
   `libraryName` suggests) or the previous override? Confirm.
9. Keep the SmartWorkout credit and the muscle threshold of 70?
