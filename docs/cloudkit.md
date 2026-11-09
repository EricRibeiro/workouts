# CloudKit sync: schema deploy and the two-simulator proof (PLAN 8.1, 8.3)

Sync is on in the app (`WorkoutsApp.cloudKitEnabled`, JC126). Steps 1-4 below are done (two simulators with an iCloud
account, the schema deployed to Production); this file is the runbook for repeating them after a model change.

## How the environments work

- Debug builds (`./dev run`, Xcode) talk to the container's **Development** environment; TestFlight builds talk to
  **Production**. The two never share data, so simulator runs cannot touch the phone's records.
- The mirror infers record types (`CD_Workout`, `CD_Template`, …) in Development from the records it uploads, so a field
  that is nil in every uploaded record never reaches the schema. The Debug flag `-initializeCloudKitSchema` runs Apple's
  `NSPersistentCloudKitContainer.initializeCloudKitSchema` on the SwiftData model instead, which creates every type with
  every field (JC127). Production never creates types on its own: a TestFlight build syncs nothing until the schema is
  deployed there by hand. Deploying is additive and does not touch the public-database media type already in both
  environments (`docs/port/media.md`).
- Simulators have no iCloud account by default; with none, the mirror logs `CKAccountStatusNoAccount` (code 134400) at
  launch and the store works locally. That is the expected state of the pool today.

## Steps (Eric, server screen)

1. **Sign two simulators into iCloud** with the same Apple Account, a test account rather than Eric's own (a signed-in
   sim is a live session on the server's disk): Settings → Sign in, on `iPhone Duo` and `iPhone Duo 2`. Xcode 27 has no
   Simulator.app; the window comes from DeviceHub (Xcode.app → Contents → Applications). Done 2026-11-08.
2. **Create the Development schema** (done 2026-11-08; repeat after every model change):

   ```
   DEV_SIM="iPhone Duo" ./dev run -- -initializeCloudKitSchema
   ```

   The log (`log show --predicate 'process == "Workouts"'`) ends with `CloudKit schema initialized in Development`; the
   Console → container `iCloud.com.ericribeiro.Workouts` → Schema → Record Types (Development) lists the `CD_*` types.
3. **Deploy to Production**, in the CloudKit Console only: container → **Schema** → **Deploy Schema Changes…** → confirm.
   The Management API refuses production writes (`cktool import-schema`/`validate-schema` answer "endpoint not applicable
   in the environment 'production'", 2026-11-08), so no command can do this step. Reading is scripted: with a CloudKit
   *management* token (Console → account menu → Manage Tokens → Create Token; not the server-to-server key the media
   upload uses) stored in 1Password as the `management token` field of "Apple Cloud Kit for Workouts Duo":

   ```
   ./dev ck-schema diff
   ```

   exports both environments to `.build/cloudkit/` and names the record types Production still lacks (exit 1 until the
   deploy has run). `./dev ck-schema export [--env …]` writes one environment and lists its record types.

4. **Two-simulator proof** (passed 2026-11-08, Development): `DEV_SIM="iPhone Duo" ./dev run -- -seedSampleData`, then
   `DEV_SIM="iPhone Duo 2" ./dev run` on a sim that never held data; within about a minute B's Workout tab showed A's
   folders and templates. `log show` on B prints `Finished importing applying changes`; the
   `134417 already a pending request of type NSCloudKitMirroringExportRequest` lines beside it are the mirror
   coalescing its own export requests, not failures. Leave both sims closed-portrait afterwards.
5. **Upload** (orchestrator): `./dev testflight --upload` from the main checkout, logged in `docs/testflight.md`. Uploads
   were held until step 3 so the first synced build finds its schema.

## 8.3: the final import on the phone (done 2026-11-08)

`scripts/export-web` exported 553 workouts (last 2026-11-02), 3 templates, 1 folder and 0 custom exercises to iCloud Drive
as `Workouts/web-export-2026-11-08.json`, and Eric imported it on the phone the same day (Workout tab → gear → Settings →
**Import…** → Browse → iCloud Drive → Workouts). The importer matches by id and keeps the newer `updatedAt`, so running it
over data that is already there changes nothing. If the web app is used again, re-run the export and import once more;
the same rule applies.

## Checking that sync runs

- In the app: Workout tab → gear → **iCloud › Status** shows "Synced <when>" once the mirror has finished an import or export,
  "Waiting for first sync" before that, "Not signed in" without an iCloud account, and "Error" with the message in the footer
  (`CloudSyncMonitor`, PLAN 8.5). A first upload of 553 workouts takes minutes on Wi-Fi; the row updates by itself.
- On the phone: Settings → Apple Account → iCloud → **Manage Account Storage** (or Saved to iCloud → See All) lists Workouts Duo
  with a non-zero size once records are in the private database.
- In the CloudKit Console: sign in with the same Apple Account as the phone, pick **Production**, Records, Private Database,
  zone `com.apple.coredata.cloudkit.zone`, record type `CD_Workout`, Query Records. Another account's data is never visible.
- Sync between two devices needs both signed into the same Apple Account; the pool simulators use the test account, so they
  never see the phone's data. A two-simulator pass (2026-11-09: a custom exercise saved on `iPhone Duo` was in `iPhone Duo 2`'s
  store after a relaunch) proves export and import; the silent push that would wake the second simulator while it runs was not
  observed within 3 minutes, so relaunch the reader instead of waiting. The simulators' test-account session can lapse
  (`accountStatus=Temporarily Unavailable`, the row reads Unavailable); re-enter the password in the simulator's Settings app.

## Migrations from now on

With CloudKit on, schema changes must be additive (new optional attributes, new entities); never rename or remove a field
that shipped, and keep `SchemaV1`/`SchemaV2` frozen (PLAN risks). Every change needs the Development → Production deploy
above before its TestFlight upload.
