# Data model

Entities, invariants and derived numbers of the web app, for the SwiftData models and `WorkoutsKit`. Sources, all under `~/Projects/mac-os-compose-collection/workouts/`: `app/docs/schema.md` (S), `app/docs/records.md` (R), `PLAN.md` (P, D-numbers), `app/internal/store/migrations/NNNN_*.sql` (M), `app/docs/api.md` (settings keys). Types: UUID, String, Int, Bool, Date, Dec (a SQL `numeric(n,2)`), `[String]` (text[]). "Req" = NOT NULL in the web schema; a native model still needs a default for it (section 4). Every entity has a client-generated `id` UUID.

## 1. Entities

### Exercise (M0002, 0004)
Library or custom. Has `createdAt`, `updatedAt`.

| Field | Type | Req | Default | Notes |
|---|---|---|---|---|
| name | String | yes | none | non-blank |
| aliases, equipment, tags | [String] | yes | `[]` | equipment is an open vocabulary (S:91) |
| bodyPart | String | yes | none | non-blank; library keys: abs, back, biceps, chest, forearms, gluteus, legs, shoulders, triceps (P:67) |
| weightType | enum | yes | none | `barbell`, `bodyweight`, `dumbbell`, `machine`, `unweighted`, `weighted`, `assisted`, `band` (`band` added by 0004; `assisted` = lower is better) |
| mechanics | enum | yes | `''` | `''`, `compound`, `isolation` |
| laterality | enum | yes | `''` | `''`, `alternating`, `bilateral`, `unilateral` |
| muscles | [muscle key: Int 0..100] | yes | `{}` | intensity per muscle |
| description | String | yes | `''` | |
| instructions, tips, mistakes | [String] | yes | `[]` | |
| alternatives, recommended | [String] | yes | `[]` | the **source's** ids (`sourceId`), not exercise ids; resolved through (source, sourceId) on read |
| usedCount | Int | yes | 0 | `>= 0` |
| sourceCreatedAt | Date | no | nil | |
| mediaAnimation, mediaThumbStart, mediaThumbEnd, mediaVideoDark, mediaVideoLight | String | yes | `''` | snapshot-relative paths, `''` when absent; `mediaExtra` [String] default `[]` |
| sourceUrl | String | yes | `''` | |
| alternates | [lang: String] | yes | `{}` | language code to the same page in that language |
| source, sourceId | String | no | nil | both nil iff custom |
| custom | Bool | yes | false | true iff `source` and `sourceId` are both nil, else both set (CHECK, M0002:51) |
| retired | Bool | yes | false | hidden from the picker and list, still in history and fetchable by id |

Referenced RESTRICT by TemplateExercise and WorkoutExercise (never deleted, S:11). Owns 0..1 ExerciseOverride and 0..1 StickyNote (CASCADE: they only decorate it). Library rows are read-only (D9). List order: `lower(override name ?? name)` (S:89).

### ExerciseOverride (M0002)
One per exercise (PK = `exercise_id`). NULL = no override; replaced as a whole and deleted when empty (S:44). Fields: `name` String? (non-blank; library exercises only; a rename appends the stored name to `aliases`), `unit` `lb`|`kg`?, `barType` `olympic`|`ez`|`none`|`custom`?, `barWeight` Dec(7,2)? (`>= 0`), `barUnit` `lb`|`kg`?, `restSeconds` Int? (`>= 0`), `updatedAt` (req). It is what a **new** template/workout row starts from; changing a row never rewrites it (S:54).

### StickyNote (`exercise_sticky_notes`, M0002)
`text` String (req), `updatedAt`. One per exercise; follows it into every template and workout; saved immediately, not as part of a template save (S:57).

### LibraryMeta (M0002)
`kind` (`body_part`, `equipment`, `muscle`, `muscle_group`), `key`, `label`, all req, PK (kind, key); no `updatedAt`. Display labels, replaced on every import. A key with no row is labelled from the key itself ("iliopsoas" becomes "Iliopsoas") (S:31).

### TemplateFolder (M0003)
`name` String (req, non-blank), `position` Int (req, 0), `collapsed` Bool (req, false), `createdAt`, `updatedAt`. Has many Template.

### Template (M0003, 0007)
`folder` TemplateFolder (req since 0007), `name` (non-blank), `note` String (`''`), `position` Int (0; **per folder**), `createdAt`, `updatedAt`. Has many TemplateExercise (CASCADE). Order: position, then name, then id (ties and gaps tolerated, S:51). Deleting a template keeps its Workouts (their `template` becomes nil).

### TemplateExercise (M0003, 0005)
| Field | Type | Req | Default | Notes |
|---|---|---|---|---|
| template | Template | yes | none | CASCADE |
| exercise | Exercise | yes | none | RESTRICT |
| position | Int | yes | none | within the template |
| supersetGroup | Int | no | nil | small int `>= 0` |
| note | String | yes | `''` | |
| restSeconds | Int | no | nil | `>= 0` |
| unit | enum | yes | `lb` | `lb`, `kg`; the unit of every weight in this row's sets |
| barType | enum | yes | `olympic` | `olympic`, `ez`, `none`, `custom` |
| barWeight | Dec(8,2) | no | nil | `>= 0`; the custom bar, in the row's `unit` |
| updatedAt | Date | yes | now | |

### TemplateSet (M0003)
`templateExercise` (CASCADE), `position` Int (req), `kind` (req, default `normal`; `warmup`, `normal`, `drop`, `failure`), `weight` Dec(8,2)? (`>= 0`), `reps` Int? (`>= 0`), `durationS` Int? (`>= 0`), `distanceM` Dec(10,2)? (`>= 0`). No `updatedAt`: sets are replaced with their parent (S:8).

### Workout (M0003)
`template` Template? (nil when the template is deleted), `name` (req, non-blank), `note` (`''`), `startedAt` Date (req), `finishedAt` Date? (if set, `>= startedAt`), `source` (req, default `app`; `app`, `strong`), `createdAt`, `updatedAt`. Has many WorkoutExercise (CASCADE). History is ordered `startedAt` desc.

### WorkoutExercise (M0003, 0005)
Same fields and defaults as TemplateExercise (`position`, `supersetGroup`, `note`, `restSeconds`, `unit` default `lb`, `barType` default `olympic`, `barWeight`, `updatedAt`) with `workout` (CASCADE) instead of `template`, `exercise` (RESTRICT), plus `exerciseName` String (req): the name **at the time**, so history survives a rename or retirement; blank on save means "look up the library name with the override" (S:71). The exercise's `weightType` is read through `exercise`, not stored (S:84).

### WorkoutSet (M0003)
TemplateSet's fields (parent `workoutExercise`, CASCADE) plus `completed` Bool (req, false), `completedAt` Date?, `rpe` Dec(3,1)? (`1 <= rpe <= 10`). No `updatedAt`.

### Settings (M0001, api.md:10)
Web: `(key, value jsonb)` rows. Keys and defaults when unset (the server and UI share them):

| Key | Type / range | Default |
|---|---|---|
| defaultUnit | `lb`, `kg` | `lb` (D8) |
| defaultRestSeconds | Int 0-3600 | 90 |
| weeklyGoal | Int 1-14 | 3 (the goal line on workouts-per-week) |
| e1rmFormula | `epley`, `brzycki` | `epley` |
| restPresets | at most 6 distinct whole seconds, each 1-3600 (`[]` clears) | none; the UI stores them newest first and never stores the four presets it always offers |
| keepScreenOn | Bool | true (web Wake Lock while the workout screen is open) |

PLAN.md:133 also lists "dashboard widget layout"; api.md defines no such key.

## 2. Invariants

1. **Client UUIDs** for every row the app writes (D5, S:7), so a repeated save is idempotent. Library exercises use a UUIDv5 of `(source, sourceId)` (section 4).
2. **`updatedAt` on every user-editable row** (exercise, override, sticky note, folder, template, template/workout exercise, workout) for last-write-wins. Sets and LibraryMeta have none (S:8).
3. **Weights as entered** (D7, S:9, S:55): `weight` is the number typed; the unit lives on the parent exercise row. Switching a row from lb to kg relabels the numbers, never converts them. Conversion happens only inside aggregates.
4. **Nothing with history is deleted** (S:11): exercises are retired, not deleted; a Workout takes its exercises and sets with it; deleting a Template keeps its Workouts; WorkoutExercise keeps `exerciseName`.
5. **Every template is in a folder** (decision 2026-11-02, M0007: no unfiled group; the migration made one folder named "Templates" for any unfiled ones). A new template goes to the end of its folder. Deleting a folder (S:52): either its templates move to the end of a chosen folder in their order (positions stay distinct), or they are deleted (exercises and sets cascade, workouts stay), or the delete is refused when it still has templates and neither was chosen.
6. **Positions** (templates per folder, exercises per template/workout, sets per exercise) are order keys; gaps and ties are tolerated; reorder rewrites positions from the order given.
7. **`supersetGroup`**: nil or a small Int `>= 0`; exercises of one template (or workout) sharing a value are one superset and drive the coloured bars. The UI renumbers groups 1, 2, 3 in order of appearance on save; a group of one is meaningless and must never be produced (the server does not check, S:53).
8. **Bar**: `barType` in `olympic`, `ez`, `none`, `custom`, default `olympic`; `barWeight` is the `custom` bar, in the row's own `unit`, never converted. It is the first step of the warm-up ramp (S:54; the ramp is defined in web `ui.md`, outside this spec).
9. **Closed enums**: set kind `warmup|normal|drop|failure`; unit `lb|kg`; plus the enums in section 1.
10. **Ranges**: weight, reps, durationS, distanceM, barWeight, restSeconds, supersetGroup, usedCount `>= 0`; rpe 1...10; `finishedAt >= startedAt`; names non-blank.
11. **Custom iff no source** (see Exercise). Override `name` applies to library exercises only.
12. Override and sticky note belong to the **exercise**, not the template.

## 3. Derived numbers (never stored)

Pure functions for `WorkoutsKit`, computed from sets so editing an old workout keeps every number consistent (R:5). Inputs (R:7-11): `Set` (kind, weight, unit, reps, durationS, distanceM, completed); `Session` = one exercise in one workout (workoutId, time, exerciseId, weightType, sets); `Options` = formula `epley`|`brzycki` plus display unit (zero value = Epley in kg; any unit other than `lb` is kg).

**Counted set** (R:15): `completed` and not `warmup`; drop and failure count. "Warm-ups and unchecked sets never reach a best set, a volume, a chart or a record." Negative weight/reps clamp to 0.

**Units** (R:19-21): compare and sum in kg with exactly `0.45359237` kg per lb; same-unit conversion returns the value untouched. Weights are equal within 1e-6 kg (`100 lb` ties `45.359237 kg`; `17.5 lb` is lighter than `8 kg`). A set's own weight in its own unit is reported exactly as entered (`17.25 lb` stays `17.25`); anything converted or computed (other-unit weight, e1RM, volume) is rounded to the nearest **0.5** in the display unit (`Round05`). Rounding is display only: comparisons use unrounded kg.

**Weight types** (R:37-41): Strength = `barbell`, `dumbbell`, `machine`, `weighted` and any unknown type (weight = load); Rep types = `bodyweight`, `unweighted`, `band` (weight = optional added weight); Assisted = `assisted` (weight = assistance, **lower is better**).

**E1RM** (R:25-33): Epley (default) `w * (1 + reps / 30)`; Brzycki `w * 36 / (37 - reps)`, undefined from 37 reps (Epley used instead). 1 rep = the weight; 0 reps or weight <= 0 = 0. More than 12 reps (`LowConfidenceReps`) returns `lowConfidence = true` and feeds the formula reps **clamped at 12**: `50 x 36` = 70 (Epley) / 72 (Brzycki), `100 x 20` = 140 / 144. "A confident estimate always beats a low-confidence one, however large" (`betterE1RM`), in a session's best set, a chart point and the e1RM record, across sessions too (a later confident `50 x 5` replaces an older low-confidence `100 x 20` though 70 < 140); between two low-confidence values the larger wins. Only strength types have an e1RM.

**Best set** (`BestSet`, R:43-50) -> `Index` into the input sets, the set as logged, weight in display unit, `E1RM` (strength only, else 0), `LowConfidence`; none if no counted set.
- Strength: highest e1RM; ties: heavier weight, more reps, earlier set. A set needs weight > 0 and >= 1 rep; a session with none falls back to the rep-type rule.
- Rep types: most reps; ties: heavier added weight, earlier set. No reps anywhere (timed): longest duration, tie longer distance; no durations either: longest distance. Reps always beat durations.
- Assisted: "typical reps" = the **upper** median of reps of counted sets with >= 1 rep (`[4,8,8]` -> 8; `[1,8]` -> 8; `[8,10]` -> 10); keep sets with at least that many reps, pick the lowest assistance; ties: more reps, earlier set. No reps at all: duration rule.

**Volume** (R:54): `sum(weight x reps)` over counted sets, converted to the display unit, rounded to 0.5. A set with no weight adds nothing, so bodyweight volume is 0 (added weight counts); timed sets add nothing; assisted volume is 0. (S:72 states the same aggregate as "kg converted with 2.2046226218", the reciprocal of 0.45359237 to 10 digits; treat `0.45359237` as canonical.)

**Session summary** (`Summarize`, R:58): `Best`, `Volume`, `TotalReps` (reps over counted sets), `SetCount` (every completed set, warm-ups included: the `N x` of a History card), `Working` (number of counted sets).

**Chart series** (`ChartSeries`, R:62-72): one point per session, stable-sorted by time; a session with no counted set that has reps has no point for any metric. A metric that does not apply gives an empty series; an unknown metric gives nil.

| Metric | Value | Does not apply to |
|---|---|---|
| `e1rm` | best e1RM in the session (confident beats low); `LowConfidence` when from > 12 reps | rep types, assisted; unloaded sessions have no point |
| `maxWeight` | heaviest counted set with reps; **assisted: lowest assistance** | unloaded sessions of non-assisted types have no point |
| `volume` | session `Volume` | assisted |
| `totalReps` | reps over counted sets | |
| `bestReps` | most reps in one counted set | |

**Records** (`Records`, R:76-86): fold sessions in time order (input order irrelevant); a record changes only when beaten **strictly**, so the earlier session keeps a tie. Each record names the workout and time that set it.

| Record | Types | Meaning |
|---|---|---|
| `E1RM` | strength | best e1RM; the set is in Weight/Reps; confident beats low |
| `Heaviest` | strength; rep types (only if weight > 0); assisted | heaviest weight with >= 1 rep; **assisted: the least assistance** (`Inverted`) |
| `BestVolumeSet` | strength, rep types (added weight only) | best single set `weight x reps`, not session volume |
| `LongestDuration` | any | longest set with a duration, whether or not it also has reps (a plank logged as 1 rep, 60 s still sets it) |
| `RepsAtWeight` | all | one row per distinct weight (compared in kg): most reps at it, heaviest first (assisted: least assistance first) |

Assisted has no e1RM or volume record. In-session ties: e1RM by heavier weight then reps; heaviest by reps; volume by heavier weight.

**PRs in session** (`PRsInSession(history, session, opts)`, R:88-96) -> the records `session` newly set, ordered e1RM, heaviest, volume, reps, duration; the History card shows the count. Each PR has `Kind`, `Value` (e1RM, weight, volume, seconds; reps for the reps kind), `Weight`, `Reps`.
- History: only entries strictly **before** `session.Time`; an entry with the same workout and exercise ids as the session is ignored. Pass every session of the exercise, any order.
- "Equal is not a PR." The first session sets every record it can, except the reps PR of its heaviest set; a session with only warm-ups or unchecked sets sets none.
- Reps PRs use **dominance**: a set is a reps PR only if no earlier set had at least that weight (at most, for assisted) and at least those reps. `90 lb x 10` after `100 lb x 10` is not a PR, `90 x 11` is, `110 x 3` is. A session counts once for this kind, for its heaviest qualifying set.
- "One set is not two PRs": the weight that set the heaviest (assisted: least-assistance) PR in this session is skipped for the reps PR. `100 x 10` then `105 x 1` is `[heaviest]`; `110 x 3` and `90 x 12` after `100 x 10` is `[heaviest, repsAtWeight]`, reported for `90 x 12`; `100 x 12` after `100 x 10` is a reps PR. The first session of a barbell exercise with one working weight sets three kinds (e1RM, heaviest, volume). Bodyweight and band have no heaviest PR without added weight.
- A card's PR count uses all earlier performances of the exercise, so it never depends on where a page starts (S:81).

**Other derived values** (S): **Previous** (S:73): per exercise, the most recent entry (by `startedAt` desc, then position) with at least one completed set, and its completed sets in order, in that entry's unit; a workout where the exercise was only planned never hides an older real one. **Latest session per exercise** (S:82): newest entry with a completed non-warm-up set, for the Exercises list best sets. **Template `lastPerformed`** (S:56): max `startedAt` over the template's workouts, else over workouts with the same name (case-insensitive; imported history has no template link), finished workouts only. **Workouts per week** (api.md:35): ISO weeks (Monday start), oldest first, current week last, zero-filled, `weeks` 1-52, `goal` = `weeklyGoal`; the web cuts weeks in the server's time zone.

## 4. Local-first notes

- **Library import becomes a bundled/seeded library.** The web importer upserts a scraped snapshot (1,038 exercises, P:67) by `(source, sourceId)`, writes only changed content, retires exercises that left the source (only after a complete import), and never touches overrides (S:29-44). Natively, ship the library in the app and seed/refresh it. **Ids must stay stable**: library exercises take a UUIDv5 of `(source, sourceId)` under a fixed namespace (`store.ExerciseID`; a test pins one value "because history rows will point at these ids", S:7). Use one fixed namespace UUID, pin one value in a `WorkoutsKit` test, and never change it, or CloudKit-synced history points at the wrong exercises. (The web namespace value is not in the cited files; there is no web-to-native migration anyway, AGENTS.md.) Re-seeding must not overwrite overrides, sticky notes or custom exercises and must retire, not delete. Media: P:33 keeps ~3 GB of assets on the server; the app cannot bundle that (question 3).
- **Active workout becomes a persisted in-progress Workout.** The web keeps it on the phone, saved on every change, and writes the DB only on Finish with one idempotent PUT; the DB holds finished workouts only (D6, S:67). Natively it is a normal `Workout` with `finishedAt == nil`, saved on every change and surviving relaunch. It must be excluded from History lists, `lastPerformed` ("a workout in progress never counts", S:56), Previous, charts, records and PRs. The sources imply a single active workout but do not state a rule.
- **Sync becomes CloudKit.** The web's last-write-wins on `updated_at` plus client UUIDs maps over. Constraints:
  - all relationships optional (parent links like `Template.folder`, `TemplateExercise.template/exercise`, `Workout*.parent` are optional in the model though required by app logic);
  - a default for every non-optional stored property (the Default columns above); enums stored as raw strings with a default;
  - no `@Attribute(.unique)`, no unique constraints;
  - web uniques that become **app-enforced**: `UNIQUE (source, sourceId)` on exercises (identity is the UUIDv5 id; de-dupe by id on seed, since two devices seeding before a sync can both insert); one override and one sticky note per exercise (PK = `exercise_id`); one LibraryMeta per (kind, key); and the 409 rule that an exercise/set id belongs to one parent (S:50);
  - other web constraints are also app-enforced: RESTRICT deletes (an Exercise referenced by history), NOT NULL folder, all CHECKs (enums, ranges, non-blank, custom-iff-no-source, `finishedAt >= startedAt`);
  - the web's "replace parent and children whole in one transaction" PUT (S:48, 67) has no CloudKit equivalent; edit rows individually and stamp `updatedAt`.

## 5. Open questions for Eric

1. Keep the **Strong CSV import** (`source = strong`)? It is documented in web `strong.md`, outside these sources. If not, drop `Workout.source` (it only distinguishes `app` from `strong`) and the `assisted` rationale for it.
2. **Exercise media**: bundle none, thumbnails only, or download on demand? Which media fields stay (animation, both thumbs, dark/light video, `mediaExtra`), and do `alternates` and `sourceUrl` matter for an English-only local app (D11)?
3. **Library refresh**: frozen per app release, or re-seedable from a remote file later? Does `retired` still matter if there is no scraper?
4. **Settings shape**: one typed row (risk: two devices create two rows under CloudKit) or key/value? Keep `keepScreenOn` (a web Wake Lock; native equivalent undecided) and the unspecified dashboard widget layout?
5. **Number types**: Decimal vs Double for `weight`, `barWeight`, `distanceM`, `rpe`, given CloudKit-backed SwiftData; D7 needs as-entered values like `17.25` to survive exactly.
6. Is `TemplateFolder.collapsed` shared state across devices, or per-device UI state?
7. Hard rule of one in-progress workout, and should a forgotten one be auto-finished or discardable?
8. Weekly buckets: confirm the device time zone and Monday week start (web uses the server's zone).
