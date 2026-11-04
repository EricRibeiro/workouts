# Phase 2 review (Fable, 2026-11-04) — code + UI (task 2.11)

Slop test: **pass**. Scores: conformance 4, hierarchy/layout 3, colour/appearance 2, type/content 3, states/resilience 2.
Evidence PNGs were in the session scratchpad (`review2/`).

| ID | P | Finding | Fix | Status |
|---|---|---|---|---|
| R-01 | P1 | Rest end in the foreground is silent (`onRestEndedInForeground` never assigned; no haptic/flash) | From the ring's 1 s loop: `.sensoryFeedback(.success)` + ok tint for the grace; same in the resume ring | fixed |
| R-02 | P1 | Refused check (empty set) gives no feedback | `toggleCheck` returns Bool; `.sensoryFeedback(.error)`, `.symbolEffect(.wiggle)`, danger stroke ~0.4 s | fixed |
| R-03 | P1 | Picker/Exercises rows collapse at AX sizes (thumbnail scales to ~200 pt) | Cap thumbnail scale; hide it at accessibility sizes | fixed (filter pills truncate at AX: polish) |
| R-04 | P1 | Placeholder digits invisible (`.tertiary` on `.quaternary`) | Prompt `.secondary`; lighter cell fill if 6.3 audit fails | fixed |
| R-05 | P2 | Finish/discard save failure leaves the context dirty; Retry walks deleted models | `context.rollback()` on throw in finish/discard/begin; kit test with a throwing context | fixed |
| R-06 | P2 | `try?` swallows save errors across the cover, rest, sources | Shared `@Observable SaveErrors` + one alert on cover root and RootView | fixed |
| R-07 | P2 | Empty Workout while one runs: no "Workout in progress" dialog; failed start presents a dead-end cover | Don't present on failure now; dialog joins 3.3 | fixed |
| R-08 | P2 | `SettingsStore()` created ad hoc; keep-screen-on read once | One injected store in the environment; `.onChange` for keepScreenOn | open |
| R-09 | P2 | Checked rows read as disabled; glyph hard-codes black | Checked cells clear fill; `okFill` asset; glyph asset colour | fixed |
| R-10 | P2 | Every keystroke → Live Activity update + notification reschedule | Coalesce ~300 ms in both `track`s | fixed |
| R-11 | P2 | `.timeSensitive` needs the Time Sensitive entitlement on device | Add to the TestFlight checklist (7.x) | plan |
| R-12 | P2 | "Update Template?" finish dialog in spec, in no task | Add to 3.3/3.4 | plan |
| R-13 | P3 | Resume ring reads as a third action | `ToolbarSpacer(.fixed)` before it: own glass group, still last | fixed |
| R-14 | P3 | `.system(size: 48/56)` don't scale | Text styles + minimumScaleFactor | fixed |
| R-15 | P3 | Spacing/radius literals differ per view | `Design/Spacing.swift`; sweep in 5.8 | later |
| R-16 | P3 | Elapsed subtitle via TimelineView preference | `Text(startedAt, style: .timer)` | open |
| R-17 | P3 | `finishSummary()` scans history twice for the dialog | `finishDialog()` with counts only | fixed |
| R-18 | P3 | Cover flashes "No workout in progress" while dismissing | Keep last content while dismissing | open |
| R-19 | P3 | Extension accent is `Color.blue` | Shared asset catalog in `Shared/` | later |

Open, unverified: open-tall pose; draft/focus across a live fold (re-prove in 6.2). Keyboard group at AX overflows into the
system overflow (acceptable). Judgment-call amendments: JC10 (secondary prompt, fill if audit fails), JC12 (refusal feedback was
still missing → R-02), JC19 (spacer, not visibilityPriority).
