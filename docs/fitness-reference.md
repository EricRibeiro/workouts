# Apple Fitness as a visual reference, in the simulator

Apple's Fitness app ships in the iOS 27.2 simulator and reads the simulator's Health store. A debug seeder fills that
store with months of history, and the Xcode MCP's device-interaction tools drive Fitness, so an agent can study its
screens without anyone's phone. First done 2026-11-10; the screenshots in `docs/fitness-reference/`
are from that run (1x; re-run for full resolution).

## Populate a simulator (about 3 minutes)

1. Any pool simulator will do: the `./dev` commands below take this checkout's session lease and keep using that one
   simulator (`./dev sims` names it), until `./dev release` or ten idle minutes.
2. Seed: `./dev run -- -seedHealthHistory 200`
   - `Workouts/Features/Health/HealthHistorySeeder.swift`, DEBUG only. The day count is optional (default 200, 1...400).
   - It writes, per day: hourly steps, walking distance and active energy, one resting-energy sample; weekly VO2 max;
     and a weekday routine (Mon/Wed/Fri Functional Strength, Tue Indoor Cycle, Sat Outdoor Run and Sun Outdoor Walk with
     GPS routes around High Park, Thu rest, 15% skipped), each with per-minute heart rate, energy, distance and an
     effort score.
   - Deterministic, and it deletes its own earlier data first (metadata key `WorkoutsDuoSeedHistory`), so re-running
     is safe. `-seedHealth` (one workout ending now, `HealthSeeder.swift`) is independent and can be combined.
3. The first run shows the Health permission sheet, which must be answered by hand or through the MCP: tap
   "Select All", scroll to the bottom, "Continue", then on the next page pick a range and "Allow". The seed starts
   once the sheet is answered.
4. Confirm it finished (200 days take about 5 seconds):
   `xcrun simctl spawn <udid> log show --last 3m --predicate 'subsystem == "com.ericribeiro.Workouts" AND category == "HealthHistorySeeder"' --style compact`
   ends with `HealthHistorySeeder: done 143 workouts, 17272 samples`.
5. Open Fitness: `xcrun simctl launch <udid> com.apple.Fitness`. A fresh simulator walks through onboarding once
   (Continue, Continue past the personal details, Set Move Goal, Don't Allow notifications, Continue, Continue, Don't
   Allow contacts). If Fitness was already open, terminate and relaunch it so it reloads.

## Drive it

- `DeviceInteractionStartSession` with the simulator's UDID (no workspace needed), then `DeviceInteractionSynthesize`:
  `t x y` taps, `t x1 y1 f x2 y2 0.3` swipes, `w 2` waits; coordinates are points (the closed Duo is 466 x 678). Each call
  returns a 1x screenshot and an accessibility hierarchy with hit points. End with `DeviceInteractionEndSession`.
- For a 3x screenshot of the current screen: `./dev screenshot <path>`.
- The trailing strip holds the back button (417, 198) and the tabs: Summary (417, 472), Fitness+ (417, 522),
  Workout (417, 572), Sharing (417, 622).
- A Summary card opens its detail when tapped; the Sessions list is behind the chevron in the Sessions card's header.

## What the seed lights up, and what it cannot

| Fitness surface | Result |
|---|---|
| Move ring, today | Filled from seeded active energy |
| Steps, Step Distance cards and charts | Filled |
| Sessions list, filters, month sections | Filled (143 workouts over 200 days) |
| Workout detail: summary grid, heart-rate chart | Filled |
| Outdoor workout: place name, route map, pace, elevation, Workout Details sheet | Filled |
| Calendar | Workout dots on past days; the past days' rings stay empty (summaries are not backfilled) |
| Exercise and Stand rings | Never: a phone with no watch shows Move only, and those types cannot be written |
| Trends | Shows the simulator's own demo numbers (addressed to "Alexis"), not the seed |
| Effort on a workout, Training Load, Awards | Not shown, although an effort score is written and related |
| Fitness+, Sharing | Need an account; empty |

For those rows, use screenshots from a real phone.

## What Fitness looks like (the rules worth copying)

- Black page, `#1C1C1E`-like cards, large continuous corners, two-column card grid.
- One accent, lime (about `#C4F861` on a phone, `#A6FF00` in onboarding): selected chip and tab, symbols, primary
  button fill with a black label, secondary button label on a dark capsule.
- A metric is a medium-weight number with its unit in small caps, glued on, in the metric's colour: `311CAL`, `5.46KM`,
  `5'30''/KM`. Label above in white regular.
- One colour per metric everywhere: time yellow, calories pink-red, heart rate orange-red, distance blue, pace cyan,
  steps purple, the headline metric of a session lime.
- Card title: white semibold, with a grey circled chevron when the card drills in. Section headers sit outside cards
  in bold white.
- Session row: a dark tinted circle with the workout symbol in lime, the type in regular white, the headline metric
  large in lime, the day in grey at the trailing bottom.
- Workout detail: large white title over a faint symbol backdrop, the headline metric in lime, date range and source
  app in grey, then a "Workout Details" two-column grid and a dotted heart-rate chart with a small-caps coloured
  caption (`137 BPM AVG`).
- Activity rings are Apple's: never draw concentric rings for anything but Move, Exercise and Stand.

## Files

`docs/fitness-reference/`: `01`-`02` Summary, `04` Sessions, `05`-`08` Outdoor Run detail and its Workout Details
sheet, `09`-`10` Functional Strength detail, `11` ring detail, `12` calendar, `13` Workout tab, `14` Trends (demo data).
