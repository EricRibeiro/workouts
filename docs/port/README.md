# Port spec

What the native app must do, extracted from the web app
(`~/Projects/mac-os-compose-collection/workouts/`) so that a feature task never needs the web
repo in context. The web app is **reference, not law**: parity is the floor, native iPhone Duo
idioms win when they disagree (see `AGENTS.md` → Product decisions).

| File | Covers |
|---|---|
| `OPEN-QUESTIONS.md` | Questions for Eric (empty as of 2026-11-03; answers in `AGENTS.md` and `docs/PLAN.md`) |
| `media.md` | How thumbnails and videos are delivered |
| `data-model.md` | Entities, fields, invariants, derived numbers → SwiftData + WorkoutsKit |
| `layout-and-style.md` | Compact vs expanded layout, bars, tokens, motion → native mapping |
| `screens/workout.md` | Workout tab: folders, templates, template editor |
| `screens/active-workout.md` | The in-progress workout: sets, rest timer, dock, finish |
| `screens/history.md` | History tab: cards, calendar, charts, dashboard, settings |
| `screens/exercises.md` | Exercises tab: library, search, detail (About/History/Charts/Records) |

## How each screen file is written

Audience: an agent implementing that screen later, with only this file and `data-model.md` open.

Sections, in this order, each kept short (whole file ≤ 150 lines):

1. **Purpose** — one paragraph.
2. **Data shown** — which entities/fields, how sorted/filtered/grouped, computed values by name.
3. **Interactions** — a list; each item is `trigger → result`, including confirmations and undo.
4. **States** — empty, first-run, loading, error, in-progress-workout-present.
5. **Native mapping** — the SwiftUI structure to use (`NavigationSplitView`, `List`, sheets,
   `TabView`…), what differs between compact (closed Duo) and regular width (open Duo), and what
   native feature replaces a web workaround (Live Activity instead of a dock, system share sheet,
   haptics via `sensoryFeedback`, …).
6. **Dropped or changed on purpose** — web decisions we are not carrying over, with the reason.
7. **Open questions** — anything the source leaves ambiguous; phrase as a question for Eric.

Rules: facts come from the cited web files only; no invented features; no Swift code (prose and
names only); quote exact labels, units and numbers the web app uses (rest presets, formulas,
thresholds) so parity is checkable.

## Screenshots

`screenshots/` (local only, gitignored: they show real workout data; recapture with Playwright at
https://workouts.traefik.ca if missing) holds the web app as captured on 2026-11-03: `compact-<tab>.png` at 430×932 (closed
Duo / any iPhone) and `expanded-<tab>.png` at 867×669 (open Duo, landscape). They show the
streamlined flow to preserve, not pixels to copy; the native app uses system bars, sidebar and
Liquid Glass. Read one with the Read tool before building its screen.

`duo-closed-*.png` are real photos of the PWA on Eric's iPhone Duo, closed, portrait (2026-11-03):
the Workout tab, the template preview sheet, the exercise peek/detail sheets with the video loop, the
logging table empty and with a checked set, and the rest timer sheet. Note the device chrome: on the
closed display the status area is a **vertical strip on the trailing edge** (Island pill, clock,
battery), so the content is narrower than the panel and the safe area is asymmetric.

