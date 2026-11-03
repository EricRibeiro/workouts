# Open questions for Eric

Collected from every file in `docs/port/` (2026-11-03). Answer inline or in chat; the answer then goes back into the source file and the item is removed here.


## data-model.md

1. Keep the **Strong CSV import** (`source = strong`)? It is documented in web `strong.md`, outside these sources. If not, drop `Workout.source` (it only distinguishes `app` from `strong`) and the `assisted` rationale for it.
2. **Exercise media**: bundle none, thumbnails only, or download on demand? Which media fields stay (animation, both thumbs, dark/light video, `mediaExtra`), and do `alternates` and `sourceUrl` matter for an English-only local app (D11)?
3. **Library refresh**: frozen per app release, or re-seedable from a remote file later? Does `retired` still matter if there is no scraper?
4. **Settings shape**: one typed row (risk: two devices create two rows under CloudKit) or key/value? Keep `keepScreenOn` (a web Wake Lock; native equivalent undecided) and the unspecified dashboard widget layout?
5. **Number types**: Decimal vs Double for `weight`, `barWeight`, `distanceM`, `rpe`, given CloudKit-backed SwiftData; D7 needs as-entered values like `17.25` to survive exactly.
6. Is `TemplateFolder.collapsed` shared state across devices, or per-device UI state?
7. Hard rule of one in-progress workout, and should a forgotten one be auto-finished or discardable?
8. Weekly buckets: confirm the device time zone and Monday week start (web uses the server's zone).

## layout-and-style.md

1. Settings: a normal fourth `Tab`, or a separate sidebar section / toolbar button (`ui.md:249`)?
2. Active-workout bar: in-app `.tabViewBottomAccessory` beside the Live Activity, or Live Activity only?
3. Compact details (exercise, history, template preview): push (native default) or the web's modal sheet?
4. Keep the in-app Appearance (System/Light/Dark) setting, or follow the system?
5. The web's dense scale (more sets on the closed screen): accept Dynamic Type only, or is a row-density
   requirement for the set table wanted?
6. Deep links (`/exercises/{id}` etc.): needed for widgets/notifications, or in-app navigation state only?
7. Inner-display sidebar: only the four tabs, or also the detail pane's Close/Edit (toolbar territory natively)? Card radius (web 28): keep or system shapes?

## screens/workout.md

1. `PLAN.md:143` lists a Templates-level **⋯ (reorder, collapse all)**; `ui.md:149` says compact has **no
   Templates-level menu** and no "collapse all" exists in SWP. Add Collapse All / Reorder Folders at that level?
2. Open Duo: editor over the whole split view (web: full-screen layer with its own detail pane) or in the detail
   column beside the list?
3. Card grid or plain list rows on compact width?
4. What name does Duplicate give the copy? Sources only show `duplicateTemplate(id, newId())` (`store.ts:126`).
5. Should the `collapsed` flag sync across devices via CloudKit, or be per-device?
6. Rest options: `ui.md:156` says "Default, Off, 0:30 ... 5:00"; code lists 0:30, 1:00, 1:30, 2:00, 3:00, 5:00
   (TE:59-63). Is the code list authoritative? 7. Should an unsaved editor draft survive relaunch (web: no, `ui.md:152`)?

## screens/active-workout.md

- Start empty: the web sources never describe the entry point or its default name. Where does it live and what is it called?
- PR count in the summary: the web summary has none (only duration, volume, sets, exercises, ordinal); `POLISH.md` idea 5 proposes
  deltas. Show a PR count anyway (computed how, per `data-model.md`)?
- RPE: stored on sets (`rpe`) but no entry UI exists in the web app; build one (off by default, per exercise, `POLISH.md:451`) or skip?
- Set-row editing of a "time" weight type: the web varies columns by `weight_type`; confirm native supports time/distance now or later.
- Open-Duo layout: set table + exercise detail (PLAN.md:204) or table + History (POLISH idea 3)? Does Rest Timer stay a sheet?
- Superset rest: web starts a rest on every check; POLISH idea 4 proposes only after the last exercise of the round. Keep web behaviour?
- Notification copy: just "Rest over" (POLISH.md:152) or include the next set ("Set 3 · 27.5 lb × 8", POLISH idea 6)?

## screens/history.md

- PLAN.md 173 says the card menu offers "edit,
  duplicate as template, save as template, and delete" but ui.md/HistoryPage.tsx:191-193 shows only
  Edit, Save as Template, Delete. Is there a "duplicate as template" distinct from Save as Template?
- Should we add "Repeat workout" (start a new workout prefilled from a past one)? The web has none.
- PLAN.md 173 lists a card **set count**; the card UI (HistoryPage.tsx:62-69) shows duration, volume and
  PRs only, though `setCount` is in the payload. Show it?
- Where should the weekly goal live on iPhone (chart button and Settings both, as in the web)?
- Keep Settings a fourth tab (PLAN.md 189: side column on the open screen) on compact too?
- Weekly chart is 8 weeks fixed; PLAN.md 188 lists later charts (weekly volume, sets per muscle group,
  PR feed). In scope for the port?

## screens/exercises.md

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
