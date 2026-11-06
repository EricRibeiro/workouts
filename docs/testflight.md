# TestFlight uploads

Builds uploaded with `./dev testflight --upload` (cadence: AGENTS.md "TestFlight cadence"). Newest last.

| Build | Commit | Contents |
|---|---|---|
| 202611041648 | 5e48dce + testflight wip | First build: Phases 2–5 so far, 3.6 menus, sidebar |
| 202611041802 | 2c9c28c | Phase 3 review fixes (rest Off/Default, palette, note sheet, sidebar edit), Phase 4 fixes, logging block menu |
| 202611041841 | 4b7d514 | No app sidebar: tabs in the strip, two-pane Exercises with search; destructive haptics |
| 202611041908 | c82506c | Animated list thumbnails (start/end cross-fade) |
| 202611041935 | 1ad820d | Half-open bench mode (pane + rest above the hinge, table below) |
| 202611042033 | d2cffc0 | iCloud + Time Sensitive entitlements (data still local); no overlapping empty states on the open Duo |
| 202611042208 | d9d82aa | Exercise videos from CloudKit (detail hero, Settings > Download all videos); list thumbnails fade cleanly between poses |
| 202611042330 | 4757239 | Fold pass: focus/scroll survive folds, editors bench-style, History two columns on the fold, wider Exercises list, no video edge lines, AX filter pills |
| 202611050004 | 5d3ff27 | Info button on the open Duo, past-workout editor at AX sizes, focused set clears the keyboard toolbar, "Update Template?" as an alert |
| 202611050007 | d94003a | Stars behind the finish summary, success haptic on every finish |
| 202611050017 | 55bac68 | Stars actually fall (dense field, 4.5 s) |
| 202611050026 | 28affbc | Exercise video starts without a dark frame |
| 202611050043 | 5bde2fb | Exercise detail splits across the fold when shown full width |
| 202611050152 | d70f097 | New app icon; confirmations no longer float with a stray arrow; video without player controls (flicker fix v2); contrast and VoiceOver fixes |
| 202611050200 | 77333d0 | Fitness fields on workouts (store migration); resume button shows a stopwatch, not a second figure |
| 202611050207 | dc0baa5 | HealthKit capability (read-only reader, no UI yet) |
| 202611050247 | 4bfd921 | Exercise chips no longer overlap the next section |
| 202611050346 | 54e53c9 | Apple Fitness toggle in Settings (off by default); full Fitness capture (calories, HR, effort, zones, weather) — no on-screen card yet |
| 202611050545 | 532f347 | Fitness on screen (workout detail card, kcal in History), backfill of past workouts, Settings gear on every tab, faster Exercises/History/detail opening |
| 202611050626 | 3f0f47f | Review fixes: import guard, Fitness opt-in re-check, first rest notification, save rollbacks, Live Activity off |
| 202611050706 | d376c65 | Countdown stays above the keyboard, one set numbering, checkable rows look checkable, screens refresh after import |
| 202611050754 | 04b4e24 | Review fixes: saves on field exit, "Workouts" copy, card dates, large titles across poses, no dead band on exercise detail |
| 202611050836 | ea74e7f | Native timers for the rest ring, resume button and hero cross-fade; all 7.6 review fixes in |
| 202611051256 | 8b18459 | Coloured rest ring, no rest caption in workouts, Exercise Info sheet during a workout |
| 202611051341 | 18e81b6 | Ring+dumbbell resume control, Live Activity redesign, info sheet polish, one-line names |
| 202611051529 | f9b32c6 | Apple Health blended into the workout (header stats, heart-rate chart, History bpm), health data fixes, shared info sheet, tab tap expands the sheet |
| 202611060122 | 6580187 | Out of band (Eric, gate skipped; last full UI run 91/93, both failures fixed since): quality-review fixes, 1:00 default rest, appearance setting, exercise video card + full-width info sheet without ✕, Tools/duo |
| 202611060155 | f0c3a0e | Out of band (Eric, gate skipped): exercise videos mix with other audio (no more pausing music) |
| 202611060253 | 652ff32 | Gated (sharded full UI run, 16 min, no flaky): self-maintaining simulator pool, sharded UI suite, audit stability fixes (tooling + tests; app unchanged since 202611060155) |
| 202611060339 | 9dda747 | Gated (full UI run 93 passed, 4 skipped; 1 shard under load): the workout strip shows only Minimise and Finish while a set is being edited |
| 202611060428 | e87716c | Gated (sharded full UI run 100 passed, 0 flaky, 16 min): one-row expanded Island, ticking narrow Island, single lock-screen bar, header returns after scrolling, keep/remove videos, History pull to refresh, superset bands in the heart-rate chart |
| 202611060631 | e3d9d78 | Gated (sharded full UI run 125 passed, 0 flaky, 27 min on 2 shards): bug review rounds 1–2 (≈46 fixes: engine, templates, history/import, Health, media, Live Activity taps and lifecycle, rest actions, set table), test-gap work (intent, schema, snapshot and audit coverage) |
| 202611060720 | cdac2fb | Gated (sharded full UI run 127 passed, 0 flaky, 16 min): bug review rounds 3–4 (template value updates by kind, Live Activity current set, Previous per row, warm-ups from plan, superset reorder, workout links, importer hardening, picker New) |
| 202611061428 | a668089 | Gated (sharded full UI run 127 passed, 1 flaky, 17 min): past-workout and template editors open full screen |
