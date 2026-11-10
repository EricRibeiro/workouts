# Health real-store proof: cadence and unit seam

Read-only research. No simulator, no `./dev` test command, no file edits. Not run, so unverified: whether the grant survives `xcodebuild test`'s reinstall, and the runtime figures below (estimated from the test's waits).

## 1 Current state

- **Coverage.** `HealthKitSource.swift` is 0.00% (0/288) in the last full ui-test bundle (`xccov`, `.build/results/latest-ui-test.xcresult`). `HealthSeeder.swift` is 2.44%. `HealthFixture` 97%, `HealthEnrichmentService` 84%, `HeartRateChart` 82%.
- **Where the reader is used.** Only `HealthKitIntegrationUITests` reaches `HealthKitSource`, through `-seedHealth -healthReal -preview WorkoutDetail`. `WorkoutDetailView.swift:773-792` builds `HealthKitSource()`, requests read authorization and enriches over the last 60 minutes. `-uiTesting` otherwise forces `source: nil` (`HealthEnrichmentService.swift:73`). No other test touches the real store.
- **The test** (`WorkoutsUITests/HealthKitIntegrationUITests.swift:10-14`) skips unless `HEALTH_INTEGRATION` is set.
  - Sheet driver (`:50-83`): up to 3 pages inside a 90 s deadline, in process `com.apple.HealthPrivacyService`, matching private ids like `UIA.Health.AuthSheet.AllCategoryButton` and a "Past 30 Days" label.
  - It is idempotent: a sim that already granted shows no sheet, `answered` is 0, and the card appears.
  - Assertions: 300 kcal, average heart rate in 90-160, "effort 8". A 20 s wait on the card.
- **Dev script.**
  - `dev:304` sets `TEST_RUNNER_HEALTH_INTEGRATION=1` only when `$1` starts with `HealthKitIntegration`.
  - The unfiltered run is sharded over free pool sims (`dev:307`) and the suite is in it but skips.
  - `dev:316-320` writes `.build/ui-test.stamp` (`commit/clean/flaky`) only for an unfiltered pass; `tf_ui_gate` (`dev:1166`) checks it for `testflight --upload`.
  - A filtered run uses one sim, and `run_tests` (`dev:270`) overwrites `latest-ui-test.xcresult`. Running the Health test therefore clobbers the full-run coverage bundle.
  - Nothing records when the Health test last passed. The last change to the reader was 2026-11-05 (39613f1).
- **Why it is excluded.** The code only says "drives the Health Access sheet(s)" (and `docs/port/healthkit.md:142-147`: "keep out of `./dev check`").
  - Sheet fragility is the real reason: private identifiers, an iOS 27 data-range page, and Allow hidden until a swipe.
  - A shared-state risk is small. The seeder deletes only objects tagged `WorkoutsDuoSeed`, and every other UI test runs on fixtures.
  - Runtime is also small (about 1 minute, estimated: launch, seed, up to 3 pages at about 3-8 s each, then the card wait).
  - The grant resets on uninstall (doc, observed). Whether the install that `xcodebuild test-without-building` does clears it was never verified (`healthkit.md:46`).

## 2 Options

### A. Dedicated Health sim plus a path-scoped "last real-store pass" stamp (cadence)
- **Mechanism.**
  - Pin the test to one clone via the existing `DEV_SIM_UDID` and a new `HEALTH_SIM_UDID` default. `sim_resolve` honors the override (`dev:108`), and `sim_grab` takes the lock.
  - Keep that clone out of `ui_pick_sims`, e.g. a name outside `sim_pool_names` such as "iPhone Duo Health", created with `simctl clone`. Shards then never see it, and its Health store and grant stay put.
  - Stamp `commit=` when the filtered run passes with zero skips.
  - `tf_ui_gate` also fails if the reader's files changed since the stamped commit.
- **Sketch.**
```bash
HS=".build/health-test.stamp"; HEALTH_PATHS=(Workouts/Features/Health/HealthKitSource.swift
  Workouts/Features/Health/HealthSeeder.swift Workouts/Workouts.entitlements WorkoutsUITests/HealthKitIntegrationUITests.swift)
# cmd_ui_test, after a passing filtered run: only if the totals show 0 skipped
if [[ "${1:-}" == HealthKitIntegration* && $skipped -eq 0 ]]; then
  printf 'commit=%s\nwhen=%s\n' "$(git rev-parse HEAD)" "$(date -u +%FT%TZ)" >"$HS"; fi
# tf_ui_gate
c=$(sed -n 's/^commit=//p' "$HS" 2>/dev/null)
if [[ -z "$c" ]] || ! git diff --quiet "$c" HEAD -- "${HEALTH_PATHS[@]}"; then
  die "testflight: Health reader changed since the last real-store pass: ./dev ui-test HealthKitIntegrationUITests (DEV_SKIP_UI_GATE=1 overrides)"; fi
```
  The skip count comes from `xcresulttool get test-results summary`, which `run_tests` already calls; a skipped run exits 0, so the stamp must check it.
- **Proves.** The reader still matches the SDK, predicates and units on real HealthKit, and that was true at a known commit. The gate fires only when Health files change, so it rarely costs anything.
- **Cannot prove.** Anything about Eric's Watch data, or the real prompt wording. Whether the sheet driver survives the next iOS.
- **Cost.** About 2 h (stamp, gate, sim naming, docs). One more clone, roughly 5-10 GB. If the grant does not persist, the sheet is still driven each run, as today.
- **Flakiness.** The test fails on sheet changes, not on logic, and the gate is run on demand, so a flake blocks only a Health-touching upload.
- **Sources.** `dev:104-135`, `dev:1166-1180`; the grant resets on uninstall: [WWDC16 209](https://nonstrict.eu/wwdcindex/wwdc2016/209/).

### B. Make the sheet a non-issue
- **Interruption monitor.** `addUIInterruptionMonitor` only fires when a system alert blocks an interaction with the app under test. The Health sheet is a separate process (`com.apple.HealthPrivacyService`, observed) and the test's explicit driver already handles it, so a monitor adds nothing.
  - The one library that automates this ([XCTHealthKit](https://github.com/StanfordBDHG/XCTHealthKit/blob/main/Sources/XCTHealthKit/XCTest%2BHealthKit.swift)) also drives the sheet by hand, matching `Health Access` / `Turn On All` / `Allow` in `com.apple.Health`. Its source says nothing on persistence or the iOS 27 range page.
- **Persistent grant.** Apple forums say HealthKit does not re-prompt once answered ([thread 787407](https://developer.apple.com/forums/thread/787407)), and reinstall resets it, so a dedicated clone only helps if the test runner's install keeps it.
- **Cheap check, about 10 minutes of Eric's time.** On a clone, run the filtered test twice and read the `answered` count from the failure message or a print. If the second run answers 0, the sheet is a first-run-only cost.

### C. Unit seam over the store (HealthKitSource in WorkoutsTests)
- **Mechanism.** Add `protocol HealthStoreReading` (app target, HealthKit-importing) with: `workouts(in:limit:)`, `workout(id:)`, `heartRateSamples(start:end:)`, `effortSamples(for:)`, `routeLocations(for:)`, `earliestPermittedSampleDate()`, `earliestAuthorizedDate()`, `requestRead(_:)`. `HealthKitSource.init(store: some HealthStoreReading)`; a live `HKHealthStore` adapter conforms.
- **Cheaper first cut, no protocol.** Make the pure helpers `internal` and test them in `WorkoutsTests`:
  - `map(_:)` (`:307`, takes `HKError(.errorAuthorizationDenied)` etc.), `kind(of:)` (`:298`), `quantity(_:in:)` (`:163`), `text(_:)` (`:263`), and the unit choice in `statistic` via `HKQuantityType.is(compatibleWith:)` (`:234-249`).
  - Pull the arithmetic out of `summary` into a pure function: total energy `active + basal`, HR offset `max(0, t - start)`, humidity conversion, rated-over-estimated effort choice.
  - About 100-120 of the 288 executable lines. Needs no fake store.
- **Proves.** Mapping, error translation, unit and fallback rules, and the HR-offset and humidity regressions listed in the PLAN (×100 humidity, zero-based zones, re-based offsets).
- **Cannot prove (real store only).**
  - Predicate semantics (`predicateForSamples` window, `predicateForObject(with:)`, `predicateForObjects(from:)`).
  - `workout.statistics(for:)` and `allStatistics`, which have no public initializer (a constructed `HKWorkout` returns nil).
  - `zoneGroup`, `workoutActivities`, the effort relationship query, route streaming, and the authorization sheet.
- **Cost.**
  - Helpers-only: 2-3 h; also lifts the 0% to an honest 25-35%.
  - Full protocol: 6-8 h, because the fake needs `HKWorkout`/`HKQuantitySample` values built with deprecated convenience initializers, and the most valuable lines still can't be exercised.
- **Flakiness.** None; runs in about 1 s inside `./dev test`.
- **Sources.** `healthkit.md:118-128` (why the kit stays HealthKit-free; the same constraints apply to constructed `HKWorkout`s).

### D. Fold into every ui-test run or a weekly schedule
Every run: unattended, but it adds about 1 min plus sheet flake to a roughly 8-minute sharded run and the full run would need `TEST_RUNNER_HEALTH_INTEGRATION` plus a sim that survives a sheet crash. A weekly job runs against a stale commit and does not tie to uploads. Neither beats A for a one-person repo.

## 3 Recommendation
1. **Option A, a gate on change, not on a clock.** `testflight --upload` blocks only when `HealthKitSource.swift`, `HealthSeeder.swift`, the entitlements or the test changed since the last passing real-store run. Pin that run to a dedicated Health clone (so the grant and seed persist) and skip the stamp when anything skipped. Also have the Health run save its xcresult under its own name so it stops clobbering `latest-ui-test.xcresult`. This is the one cadence change.
2. **Unit seam, helpers-only version of C.** Make `map`, `kind`, `quantity`, `text`, the unit selection and the summary arithmetic testable and add a `HealthKitSourceMappingTests` suite. Defer the full store protocol: it buys little because the high-risk lines need the real store.
3. **Run the persistence check from B first** (10 minutes). If the second run answers 0 sheets, say so in `docs/port/healthkit.md` and trim `answerHealthSheets`' deadline from 90 s to about 30 s.

## 4 Open questions for Eric
- Is a hard block on `testflight --upload` right, or a warning with `DEV_SKIP_UI_GATE`-style override only?
- OK to create a sixth, non-pool "iPhone Duo Health" clone (disk), or reuse "iPhone Duo 5"?
- Should the Health run's coverage count toward the project's coverage numbers (needs a merged bundle) or stay separate?
- I used one `web-fetch` helper agent to read the XCTHealthKit source, which the dispatcher notes discourage; nothing it returned was actionable beyond the cited facts.
