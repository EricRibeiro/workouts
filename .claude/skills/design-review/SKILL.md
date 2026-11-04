---
name: design-review
description: Critique a finished screen or a phase's screens against the HIG, DECISIONS.md and the Duo, from screenshots and source, and hand back a severity-ranked findings table the orchestrator turns into worker tasks. Read-only; never fixes. Use at the end of each UI phase (PLAN 2.11, 3.8, 4.7, 5.8) or when Eric says a screen looks off.
---

# Design review

A review is one read-only pass that answers "would a fluent iPhone user trust this screen, or pause at it?" and
lists what to change, in order. It never edits code: findings become bite-sized tasks for workers, taste questions go
to Eric. The authority is Apple's HIG, then `docs/DECISIONS.md` and `AGENTS.md`; nothing below overrides either, and
a finding that would re-litigate a settled decision is dropped, not filed.

The method is distilled from two sources, adapted for SwiftUI: the native branch of
[impeccable](https://github.com/pbakaus/impeccable) (Apache 2.0: its iOS slop test, five-dimension native audit,
cognitive-load checklist and polish triage) and the state inventory of
[Design with Intent](https://github.com/ghaida/intent) (CC0). Neither is installed; their web tooling (detector, hooks,
browser modes) reads only web markup, and the rest conflicts with system chrome. Do not fetch them during a review.

## 1. Evidence first

Gather before judging, and batch: one look per configuration, fix-list in hand, not a screenshot per thought.

- `./dev shot <png> -- -preview <Name>` for every screen in scope, closed portrait, **light and dark**
  (`xcrun simctl ui booted appearance dark|light`), at the default size and `accessibility-extra-large`
  (`xcrun simctl ui booted content_size …`; reset to `medium` after). One open-wide capture per screen via `./dev fold open`
  (skill `verify-ui`), then `./dev fold closed`.
- Read the screen's source files and the shared components it uses (`Workouts/Design`, `Features/Shared`).
- Read the DECISIONS headings the screen cites and PLAN section 3's paragraph for it. That paragraph is the brief; the
  review judges the build against it, not against a different idea of the screen.

## 2. The slop test (verdict, first line of the report)

Pass/fail, stated once: does this read as a native iOS 27 screen or as a ported website? Tells for "ported":
reinvented bars or back affordances, bottom pills or floating chrome, web-shaped buttons, hand-placed glass, an icon
that is not an SF Symbol, hard-coded point sizes, colours from hex instead of the asset catalog or semantic styles,
a sheet where a push belongs or a push where a sheet belongs. Tells for "native": system components with the system's
spacing, one tint, large titles that collapse, every toolbar item a symbol the strip can stack, content that respects
the safe areas and the fold.

## 3. Five dimensions, scored 0–4

Score each; 0 = broken, 2 = partial, 4 = nothing to fix. Keep the key finding per row to one line.

1. **Platform conformance.** System controls (`Menu`, `Picker`, `confirmationDialog`, `contextMenu`, `swipeActions`,
   `ContentUnavailableView`) where the web had custom ones; toolbar items placed by the system and never by hand;
   zoom transitions on card/row → detail; `Form` for settings-shaped content; no `UIScreen`, idiom or orientation reads.
2. **Hierarchy and layout.** One primary action per screen, obvious; tight groups, generous separation, more space above a
   section header than below; spacing from the system's defaults or one shared constant, never a different literal per
   view; grids derive columns from their own width; nothing straddles the fold or sits under the strip; rows and cells
   hit 44 pt; the large title collapses on scroll.
3. **Colour and appearance.** Text and placeholders ≥ 4.5:1 in both appearances (a "Previous" value shown as a prompt is
   content, so it reads like content, not like a hint); meaning carried by the semantic asset colours only (accent, ok,
   danger, warm-up, set-kind, superset) and never by raw opacity; one tint for interactive elements; cards separate by
   fill, no rims; dark mode designed, not inverted; superset colours distinguishable from each other and from ok/danger.
4. **Type and content.** Text styles only (`.largeTitle` … `.caption2`), SF, no fixed sizes; the real copy fits at
   `accessibility3` (`ViewThatFits`, truncation where the web truncated); numerals in set cells and tables are monospaced
   digits; copy is the web's (`docs/port/screens/`), controls name their action, errors name the problem and the recovery.
5. **States and resilience.** The inventory below is complete for the screen; nothing is a dead end; every action gives
   feedback (haptic, dismissal, change on screen); destructive actions sit behind the decided dialogs.

Accessibility proper (VoiceOver order, Dynamic Type audit, contrast audit) and the pose matrix are **not** rescored
here: route them to Apple's `accessibility-*-specialist` skills and PLAN 6.2 / 6.3, and note only what you saw in passing.

## 4. State inventory

For each screen list the states it can be in and what the user sees, can do, and how they get out. A state the build
already draws needs no row; a missing one is a finding.

Empty (no templates, no history, no search hit, no Previous, no PRs yet, library search with the parser unavailable) ·
Loading (media download; everything else is local and must not spin) · Error (save failed → the alert with Retry; media
unavailable) · Success (finish, save as template, import: the decided haptic + dismissal, no banners) · Offline
(CloudKit off, no network: nothing changes) · Disabled (Finish with nothing checked, empty set cannot be checked, Add (N)
with 0 selected) · Overflow (615 workouts, 1,038 exercises, 6 custom presets, 40-character names, 20 sets, 4 supersets) ·
First run (permission prompt timing, the "Allow Live Activities" banner).

## 5. The user in the gym

The reader is Eric between sets: one hand, sweating, the closed display, the keyboard over its lower half, ten seconds
of attention. At each decision point count what is visible: more than four choices is a finding, more than one
primary action is a finding, anything the user must remember from a previous screen is a finding. Then walk the
same path at `accessibility-extra-large` and in dark, where contrast and truncation show first.

## 6. Report

Findings table, severity first, then the dimension scores and the slop verdict repeated. Each row:

```
| P | Screen · file:line | What (evidence: png) | Rule (HIG page / DECISIONS heading) | Fix at the narrowest level | Taste? |
```

- **P0** blocks the task · **P1** a HIG or DECISIONS violation, fix before the phase closes · **P2** an inconsistency
  with a workaround · **P3** polish. Keep P3s few.
- Classify every fix: *missing token* (add it to `Design/`), *one-off* (replace with the shared component), *conceptual*
  (the screen differs from its PLAN paragraph: a task, maybe a question), *local defect* (a one-line change). Fix the cause
  at the narrowest correct level; never a system abstraction for one exception.
- **Taste?** marks what only Eric can settle (a colour, a card shape, copy). Those become one batched question, not
  tasks.
- Refinement preserves: a fix keeps the screen's identity, copy and everything outside its row. If the concept is
  wrong, say so as one conceptual finding; do not smuggle a redesign through polish rows.

Never file: custom chrome, bottom bars, hand-placed `.glassEffect()`, web idioms, a remote package, anything DECISIONS
settles, or "add animation" without a state change that needs it. The orchestrator turns P0–P2 rows into tasks
(one row, one worker, one proving command) and ticks the review task with the scores line.
