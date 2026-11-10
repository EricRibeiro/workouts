# CloudKit sync: test gap research (2026-11-09)

Read-only. Nothing was run except `xccov` over `.build/results/latest-test.xcresult`.

## 1 Current state

- **Container.** `ModelContainer.workouts(inMemory:cloudKit:)` (`Packages/WorkoutsKit/Sources/WorkoutsKit/Model/Schema.swift:65-85`) picks `.automatic` only for an on-disk store (`CloudKitChoice.resolve`, `:56-58`). Every kit test goes through `makeTestContainer()` = `inMemory: true, cloudKit: false` (`Tests/WorkoutsKitTests/Support/TestSupport.swift:20-22`), so no test ever builds a store with CloudKit options.
- **Remote-change wiring sits in the app target and is untested.** `WorkoutsApp.observeRemoteChanges` (`Workouts/App/WorkoutsApp.swift:169-189`) and the P8-04 filter `ForeignHistoryCheck` (`:192-215`, `private`, author `"app"` at `:23`, set at `:85`) have no test: no test file references `fetchHistory`, `author` or `ForeignHistory`. `WorkoutsApp.swift` is 43% covered overall (130/302 lines).
- **Kit tests drive the engine directly.** `ActiveWorkoutEngineRemoteChangeTests.swift:66-95` mutates through a second `ModelContext` on the same in-memory container, then calls `engine.reloadAfterRemoteChange()` by hand. `RemoteChangeObserver` (`Model/RemoteChangeObserver.swift:13-81`) is tested on its own with a custom notification name and a manual clock (`CloudKitReadinessTests.swift:208-290`). Nothing chains real notification → `shouldFire` → handler.
- **Mirror events.** `CloudSyncMonitor` (`Workouts/App/CloudSyncMonitor.swift:73-88`) maps `NSPersistentCloudKitContainer.Event` to the kit value `CloudSyncEvent` (`Model/CloudSyncStatus.swift:17-33`). `CloudSyncStatusTests` covers the fold and the labels. That seam already exists; only the 15-line `map` functions are untested.
- **Schema rules.** `CloudKitSchemaRulesTests.swift:28-60` walks `Schema` metadata (optional or defaulted attributes, no `.unique`, optional relationships with inverses) over every migration-plan version (P8-06 fix). It checks SwiftData's description of the model, not Core Data's CloudKit validator on the generated `NSManagedObjectModel`.
- **Media.** `CloudKitMediaSource` (`Workouts/Features/Exercises/CloudKitMediaSource.swift:16-69`) is 11.8% covered (6/51). Only `operationConfiguration` is tested (`WorkoutsTests/CloudKitMediaSourceTests.swift`). `MediaSource` is already a protocol with fakes (`MediaStoreTests.swift:6`, `BulkVideoDownloadTests.swift:8,32`, `FixtureMediaSource` behind `-mediaSource fixture`, `ExerciseMedia.swift:14`).
- **Manual proof.** `docs/cloudkit.md` step 4 plus "Checking that sync runs". The silent push was "not observed within 3 minutes, so relaunch the reader", and the "test-account session can lapse (`accountStatus=Temporarily Unavailable`)".
- **The pool is hostile to signed-in sims.** `./dev` erases clones automatically: `sim_heal` on crash loops (`dev:931-938`) and `sim_erase_poster_buildup` under `sims --prune` (`dev:1105-1121`). `iPhone Duo 2` is a clone, so either path silently signs it out of iCloud. New clones come from `simctl clone` of the original (`dev:1139`). Whether a cloned iCloud session stays valid is unverified (see 4).

## 2 Options

### A. Offline CloudKit model validation (kit or WorkoutsTests)
**Mechanism.** Build `NSManagedObjectModel.makeManagedObjectModel(for: SchemaV2.models)`. Load it into an `NSPersistentCloudKitContainer` on a temporary on-disk store with `cloudKitContainerOptions`, then call `initializeCloudKitSchema(options: .dryRun)`. Core Data's mirroring delegate rejects a CloudKit-incompatible model when the store loads ("CloudKit integration requires…"). `.dryRun` builds the records without uploading.
```swift
@Test func modelLoadsUnderCloudKitMirroring() throws {
    let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: SchemaV2.models))
    let url = URL.temporaryDirectory.appending(path: "\(UUID()).sqlite")
    let container = NSPersistentCloudKitContainer(name: "Check", managedObjectModel: model)
    let d = NSPersistentStoreDescription(url: url)
    d.cloudKitContainerOptions = .init(containerIdentifier: "iCloud.com.ericribeiro.Workouts")
    container.persistentStoreDescriptions = [d]
    var loadError: Error?
    container.loadPersistentStores { _, e in loadError = e }   // synchronous for a non-async description
    #expect(loadError == nil)
    try container.initializeCloudKitSchema(options: .dryRun)
}
```
**Proves:** Apple's own validator accepts the model SwiftData generates, which covers what the metadata walk can miss (attribute types after SwiftData's transformation, composite/Codable attributes, inverse mapping). **Cannot:** it says nothing about the server schema, Production deploys or sync behaviour. **Unknown:** whether `.dryRun` needs an account or entitlement. `swift test` runs unsigned in `xctest` with no account, so the mirror's setup fails asynchronously. The load-time check is the robust part. If `.dryRun` throws `notAuthenticated` there, keep only the load assertion, or move the test to WorkoutsTests (signed, but the pool sims have no account either). **Cost:** 1-2 h including a spike. **Flakiness:** low if it stays offline. Watch for background mirror tasks logging after the test ends, and remove the store files in a `defer`.

### B. Two on-disk containers + persistent history, end to end in WorkoutsTests
**Mechanism.** Move `ForeignHistoryCheck` (and the wiring in `observeRemoteChanges`) into the kit as a public type. Open two `ModelContainer`s on the *same* temp sqlite URL (on disk, `cloudKitDatabase: .none`). Container 1 is the app with `author = "app"`. Container 2 writes with `author = "NSCloudKitMirroringDelegate.import"`, which mimics the mirror. `NSPersistentStoreRemoteChange` is posted for cross-coordinator writes once history tracking is on, which SwiftData enables by default for on-disk stores.
```swift
let url = URL.temporaryDirectory.appending(path: "\(UUID()).store")
let app = try ModelContainer.workouts(at: url)      // new test-only overload
let mirror = try ModelContainer.workouts(at: url)
app.mainContext.author = "app"
let fired = Counter()
let observer = RemoteChangeObserver(debounce: .zero, clock: manual,
    shouldFire: ForeignHistoryCheck(context: app.mainContext).hasForeignTransactions) { fired.n += 1 }
observer.start()
let m = ModelContext(mirror); m.author = "NSCloudKitMirroringDelegate.import"
m.insert(Workout(name: "Elsewhere", startedAt: .now)); try m.save()
// await scheduleCount ≥ 1, advance clock → fired.n == 1, engine adopts "Elsewhere"
try engine.startEmpty() // local save → advance → fired.n unchanged (P8-04)
```
**Proves:** the real notification path, the P8-04 author filter, and P8-01/02/03 driven by a true cross-coordinator merge instead of a hand call. This is the closest offline stand-in for "a remote change arrives". **Cannot:** CloudKit conflict resolution, record ordering, push delivery, schema. **Cost:** 3-4 h (adds a URL overload on `workouts(...)` and moves the class). **Flakiness:** medium-low. Remote-change notifications are asynchronous, so await `scheduleCount` as `CloudKitReadinessTests` already does and never sleep.

### C. Mirror-event mapping seam
Events cannot be constructed, so do what the code already does: keep the logic on the kit value `CloudSyncEvent`. Make `CloudSyncMonitor.map(endDate:type:succeeded:error:)` take plain fields (the `Event` overload forwards to it), then add three cases to `CloudSyncStatusTests` (started events are ignored, `@unknown` → setup, error text carried). **Cost:** 0.5 h. **Proves** the mapping only. Low value, but it costs almost nothing.

### D. CloudKitMediaSource: `CKDatabase` seam vs recorded fixture
A protocol `RecordFetching { func records(for:desiredKeys:) async throws -> [CKRecord.ID: Result<CKRecord, Error>] }` with `CKDatabase` conforming lets a fake test the remaining logic: dark falls back to light, `.unknownItem` → nil, other errors rethrown, cancellation kept. Fake records with `CKAsset(fileURL:)` are constructible. **Proves:** branch logic, roughly 40 lines → around 90% coverage. **Cannot:** that the record type and field names match the Console (`ExerciseMedia`, `videoLight`/`videoDark`), or `configuredWith`. A recorded fixture adds nothing over the fake, because CloudKit has no record/replay layer. The real contract check is a *read-only* scripted probe: `xcrun cktool query-records --database-type public --record-type ExerciseMedia --limit 1` under `./dev ck-schema` style `op run`. That uses a management token, not a user session (cktool supports public-database record queries; verify the flags with `man cktool`). **Cost:** 1.5 h for the seam, 1 h for the probe. **Flakiness:** none for the seam, network for the probe.

### E. `./dev sync-check` (scripted two-sim, human-run)
**Mechanism.** Reserve two pool sims marked "icloud" and exempt them from `sim_heal`, poster erase and reaping. Then: `run` A with `-seedSampleData` plus a new `-syncProbe <uuid>` flag that inserts one custom exercise named after the UUID. `xcrun simctl icloud_sync B` (a real simctl verb: "Trigger iCloud sync on a device"). Relaunch B (the doc says pushes do not arrive). Poll B's unified log for a new DEBUG line, e.g. `SyncProbe seen <uuid>` printed by a `-expectSyncProbe <uuid>` handler in `observeRemoteChanges`, with a timeout of about 180 s. Polling the log avoids XCUITest and TreeDump entirely. Pre-flight: read `accountStatus` from a `-logAccountStatus` flag and fail fast with "re-enter the test account password on <sim>".
```bash
cmd_sync_check() {
  local a="iPhone Duo" b="iPhone Duo 2" id; id=$(uuidgen)
  for s in "$a" "$b"; do DEV_SIM="$s" cmd_run -- -logAccountStatus; done
  check_account "$a" && check_account "$b" || die "sync-check: test account lapsed; sign in again in Settings"
  DEV_SIM="$a" cmd_run -- -syncProbe "$id"
  for i in $(seq 1 18); do
    xcrun simctl icloud_sync "$(udid "$b")"; DEV_SIM="$b" cmd_run -- -expectSyncProbe "$id"
    log_since 15s "$b" | grep -q "SyncProbe seen $id" && { echo "sync-check: ok after $((i*10))s"; return; }
    sleep 10
  done; die "sync-check: $id not on $b after 180s"
}
```
**Proves:** real Development-environment export and import between two installs. **Cannot:** push-driven live merge, Production, or phone behaviour. It is also unsuitable for `check` or unattended runs. **Cost:** 4-6 h, plus pool-exemption work. **Flakiness:** high. Apple forum reports say simulator CloudKit pushes are unreliable and sync is triggered by relaunch or suspend. Session lapse needs a human. Erase and clone resets wipe the sign-in.

## 3 Recommendation

1. **B now** (high confidence it works; it is the biggest proof gain). It turns the untested app-target wiring and the P8-04 filter into a kit-level end-to-end test, and moves logic out of `WorkoutsApp`.
2. **A now, after a 30-min spike** (medium confidence on `.dryRun` without an account). Keep at least the load-time assertion; it fails fast on a non-additive or invalid model change before any Console step.
3. **D seam + C** (high confidence, cheap). Brings `CloudKitMediaSource` off 12%. Add the cktool public-record probe to `./dev ck-schema` as a manual check.
4. **E as a human-run script, not a gate** (low-medium confidence it passes unattended). First exempt the two iCloud sims from automatic erase, heal and reaping. That fix is worth doing even without the script, because it is the likeliest cause of a surprise "Not signed in".
5. **Leave manual:** push-driven live merge, Production deploy (the Management API refuses Production writes, `docs/cloudkit.md` step 3), phone + second device.

## 4 Open questions for Eric

- May the kit gain a `ModelContainer.workouts(at: URL)` overload (test use only) and take over `ForeignHistoryCheck` from the app target?
- Should `iPhone Duo` / `iPhone Duo 2` leave the auto-erase and heal pool, or should a third dedicated "iCloud" sim be created outside it?
- Is a 3-minute human-run `./dev sync-check` worth adding, or is the runbook enough until a second real device exists?
- Does the test account have 2FA? It is the usual cause of simulator session lapses.

## Sources

- [initializeCloudKitSchema(options:)](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/initializecloudkitschema(options:))
- [Creating a Core Data model for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit)
- [Apple sample: cloudkit-sample-coredatasync](https://github.com/apple/cloudkit-sample-coredatasync)
- [Forums: trigger sync manually in Simulator](https://developer.apple.com/forums/thread/122967)
- [Forums: CloudKit sync not getting updates (push needs a real device)](https://developer.apple.com/forums/thread/118413)
- [Forums: failed to sync user keys in simulator](https://developer.apple.com/forums/thread/711852)
- [fatbobman: initializeCloudKitSchema in development/tests](https://fatbobman.com/en/snippet/resolving-incomplete-icloud-data-sync-in-ios-development-using-initializecloudkitschema/)
- `xcrun simctl help icloud_sync` (local, Xcode 27.2): "Trigger iCloud sync on a device."
