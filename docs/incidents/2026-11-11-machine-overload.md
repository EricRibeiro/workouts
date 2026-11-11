# 2026-11-11: machine overloaded by simulator work run in parallel

## What happened

The orchestrating agent (Claude, session on the `fitness-skin` worktree) started a full `./dev ui-test` (three simulator
shards) and, while it ran, dispatched worker agents that each built the app and drove a simulator of their own. It also left
two simulators booted after it had finished with them: `iPhone Duo 4` (used to capture Apple's Fitness app) and
`iPhone Duo Health` (booted the day before for the Health upload gate, and outside the pool's idle sweep).

Eric noticed and asked: "do we have 1000+ simulator process running? is that normal?"

Measured at 12:35:

- 1,583 CoreSimulator processes across 6 booted simulators (about 260 per simulator, which is normal for one booted
  simulator; six at once was the problem).
- Load average 82 / 146 / 132 (1, 5 and 15 minutes).
- Four simulators in use (three shards, one worker), two idle.

The same pattern ran for most of the day, not only at that moment: earlier batches had put four simulator workers beside
each other, and one beside a full run.

## Impact

- **Time.** One worker took over an hour of wall time for a task sized at minutes, outlived its 55-minute limit, and had
  to be interrupted and its measurement redone by the orchestrator. Others stalled or were cut off before finishing.
- **Unreliable results.** The full UI run that overlapped the workers ended `FAILED`. Three failures were real (an
  accessibility audit on the template cards), but the run also had tests that failed and passed on retry under load
  (`LoggingBlockMenuUITests/testNameOpensExerciseSheetAndHeaderHasNoRestCaption()`, and "no Exercises tab" failures in
  `ExerciseListUITests` and `ExerciseHeroUITests`), which makes a run harder to trust.
- **Lost status.** A worker's filtered `./dev ui-test` overwrote `.build/ui-test.progress` while the full run was going, so
  the full run's progress could not be read from it.
- **Eric's machine** was close to unusable for other work during those periods.
- Nothing shipped as a result: no TestFlight build came from an overloaded run.

## Cause

The orchestrator dispatched every piece of a batch at once to save wall time, and treated "each worker has its own
simulator" as sufficient isolation. It did not check the load or the booted simulators before dispatching, and did not shut
down simulators it had booted outside the pool.

## Why the existing safeguard did not hold

The rule already existed. On 2026-11-09 the same agent recorded in its memory notes: "Never run building or testing workers
beside a full `./dev ui-test`", after the same pile-up made audit tests fail with `-902 "Invalid target app"`. The note
lived only in the agent's private memory, was one bullet among several tooling traps, and nothing made the agent read it at
the moment of dispatch. It was not in `AGENTS.md`, which is the contract every session and worker loads.

## What changed

- `AGENTS.md`, "Working in bite-sized tasks", now carries the rule "Keep the machine usable: one heavy thing at a time":
  a full `./dev ui-test` runs alone; while it runs only non-simulator work is dispatched; at most two simulator workers at
  once; a batch is ordered with kit and docs work first and simulator proofs last; simulators booted outside the pool's
  idle sweep are shut down per device when done; `./dev sims` and `uptime` are checked before dispatching; briefs are sized
  for the 30-tool-call worker limit.
- The two idle simulators were shut down (`xcrun simctl shutdown <udid>` for each), bringing the count to four simulators
  and about 1,100 processes; the load average fell to about 8 once the full run finished.
- The agent's memory note records the recurrence and points at the `AGENTS.md` rule.

## How to notice it earlier

- Before every dispatch that builds or uses a simulator: `./dev sims` (who holds what, what is booted) and `uptime`. A
  load average above the machine's core count means stop and wait.
- A worker that has run several times its expected duration is a symptom of load, not of a hard task: check the load
  before waiting longer.
- `.build/ui-test.progress` showing a filtered run's `done:` line while a full run is supposed to be going means two runs
  are sharing the checkout.

## Enforced by `dev`

The rule is a gate, not only words. A full, unfiltered `./dev ui-test` holds a machine-wide marker
(`workouts-dev-full-ui.lock` in the cache directory: pid, checkout, start time and the pattern of its shard processes).
The marker follows the work, not the shell that claimed it: it is live while that pid or any of its shard test processes
exists, a `kill` of the main shell stops the shards before the marker is released, and a marker older than
`DEV_FULL_RUN_MAX_MIN` (90) with no shard process is stale. Stale markers are moved aside and re-checked before removal,
so a new run's marker is never deleted by a late reader.

- **No simulator command beside a full run.** While the marker is live, every other command that builds for or drives a
  simulator exits 75 with one line saying who is running and for how long. Kit tests, lint, status commands and TestFlight
  are never gated.
- **A full run starts alone.** It exits 75, naming each simulator and holder, when another process holds a pool simulator.
- **At most two busy simulators.** Outside a full run, a simulator command (plain `build` included) exits 75 when
  `DEV_MAX_BUSY_SIMS` (2) other pool simulators are held now or were used in the last `DEV_BUSY_WINDOW_SEC` (120)
  seconds; the count is taken again after the lock, so simultaneous starts cannot all pass.
- **A load warning**, never a failure, when the 1-minute load average is above twice the CPU count.

The gates refuse; they do not queue, so a worker fails fast instead of outliving its time limit. The exception is
`./dev check`, the commit gate: its lint, kit and duo tests run at once, and its simulator steps wait for the gate (up to
`DEV_GATE_WAIT_SEC`, 1800 for `check`, 0 elsewhere), so work can still be committed during a full run. `./dev sims` and
`./dev ui-status` show a running full run. `DEV_ALLOW_BESIDE_FULL_RUN=1` and `DEV_MAX_BUSY_SIMS=0` override, for a
deliberate exception.

A related hole found the same day is closed too: a UI test that crashed the app on its first attempt and passed on the
retry was reported as "flaky under load" and the run stamped as a pass (a SwiftData trap in the template card, on
deleting a folder). A first-attempt failure whose text says the app crashed now fails the run, with no stamp, whatever
the retry does.
