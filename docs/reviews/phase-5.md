# Phase 5 review (Fable, 2026-11-04) — History + Settings, code + UI (task 5.8)

Slop test: **pass**. Scores: conformance 4, hierarchy/layout 3, colour/appearance 3, type/content 2, states/resilience 3.
Kit timing: HistoryList.entries over the 553-workout fixture 0.88 s (macOS debug, in-memory).

| ID | P | Finding | Fix | Status |
|---|---|---|---|---|
| R5-01 | P1 | Workout detail re-folds full history on every body evaluation | `@State` filled in `.task(id:)`; `make` takes only this workout's exercise sessions | open |
| R5-02 | P1 | Weekly chart x labels overprint at AX sizes | `collisionResolution: .greedy` / every other label at AX | fixed |
| R5-03 | P2 | History list and dashboard each fold all sessions on main | Build sessions once, pass to both | open |
| R5-04 | P2 | Row swipe/context menus lack Edit and Save as Template | Add both | open |
| R5-05 | P2 | Detail cards use a different fill/radius | `dashboardCardStyle()` | open |
| R5-06 | P2 | Spacing/radius literals everywhere (with R-15) | `Design/Spacing.swift` + sweep per folder | later (Phase 6 sweep) |
| R5-07 | P2 | Calendar day numbers collide at AX sizes | lineLimit + minimumScaleFactor or cap Dynamic Type at xxxLarge | fixed |
| R5-08 | P2 | Duration is a 0–1440 Stepper (HIG: small increments) | Number TextField + stepper (reverses JC32) | open |
| R5-09 | P3 | Trophy/label gap in History rows | HStack instead of Label | open |
| R5-10 | P3 | History builds `SettingsStore()` ad hoc | `@Environment(SettingsStore.self)` | open |
| R5-11 | P3 | Editor rounds duration, rows floor it | Floor in the draft; test | open |
| R5-12 | P3 | "1 / 3 workout" | "workouts this week" | fixed |
| R5-13 | P3 | PR lines lack digit grouping | Grouping formatter | open |
| R5-14 | P3 | Below-goal bars by raw opacity | `accentSoft` asset, with R5-06 | later |
| R5-15 | P3 | Save as Template glyph reads "download" | `doc.on.doc` | open |
| R5-16 | P3 | iCloud row copy is developer-speak (reverses JC18 copy) | "iCloud sync arrives in a later version." | fixed |
| R5-17 | P3 | Dashboard cards in a row not equal height (JC24 premise wrong) | `.frame(maxHeight: .infinity, alignment: .top)` | fixed |
| R5-18 | P3 | Row title styles differ across tabs | `.headline` everywhere (ExerciseRow) | fixed |

Not filed: empty History drops the chart (native idiom); trash not red in the strip (system); set labels per JC30.
