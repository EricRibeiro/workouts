import Foundation
import Testing

@testable import WorkoutsKit

struct CloudSyncStatusTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func event(_ kind: CloudSyncEvent.Kind = .exportRecords, ok: Bool, at offset: TimeInterval, error: String? = nil)
        -> CloudSyncEvent
    {
        CloudSyncEvent(kind: kind, succeeded: ok, endedAt: now.addingTimeInterval(offset), errorDescription: error)
    }

    @Test func successSetsLastSuccessAndClearsError() {
        let failed = CloudSyncStatus(account: .available).applying(event(ok: false, at: -60, error: "boom"))
        #expect(failed.lastError == "boom")
        let ok = failed.applying(event(ok: true, at: -30))
        #expect(ok.lastSuccess == now.addingTimeInterval(-30))
        #expect(ok.lastError == nil)
    }

    @Test func failureKeepsLastSuccess() {
        let ok = CloudSyncStatus(account: .available).applying(event(ok: true, at: -30))
        let failed = ok.applying(event(ok: false, at: -10, error: "offline"))
        #expect(failed.lastSuccess == now.addingTimeInterval(-30))
        #expect(failed.lastError == "offline")
    }

    @Test func failureWithoutDescriptionStillSetsError() {
        let failed = CloudSyncStatus(account: .available).applying(event(ok: false, at: 0))
        #expect(failed.lastError != nil)
    }

    @Test func outOfOrderSuccessNeverMovesLastSuccessBack() {
        let status = CloudSyncStatus(account: .available)
            .applying(event(ok: true, at: -10))
            .applying(event(.importRecords, ok: true, at: -100))
        #expect(status.lastSuccess == now.addingTimeInterval(-10))
    }

    @Test func labelPerAccountState() {
        #expect(CloudSyncStatus(account: .off).label(now: now) == "Off")
        #expect(CloudSyncStatus(account: .unknown).label(now: now) == "Checking…")
        #expect(CloudSyncStatus(account: .noAccount).label(now: now) == "Not signed in")
        #expect(CloudSyncStatus(account: .restricted).label(now: now) == "Restricted")
        #expect(CloudSyncStatus(account: .unavailable).label(now: now) == "Unavailable")
    }

    @Test func availableLabels() {
        #expect(CloudSyncStatus(account: .available).label(now: now) == "Waiting for first sync")
        let synced = CloudSyncStatus(account: .available, lastSuccess: now.addingTimeInterval(-120))
        let label = synced.label(now: now)
        #expect(label.hasPrefix("Synced "))
        #expect(label.contains("2"))
        let errored = CloudSyncStatus(account: .available, lastSuccess: now, lastError: "boom")
        #expect(errored.label(now: now) == "Error")
    }

    @Test func footers() {
        #expect(CloudSyncStatus(account: .off).footer == "Sync is off in this build.")
        #expect(CloudSyncStatus(account: .noAccount).footer == "Sign in to iCloud in Settings to sync.")
        #expect(
            CloudSyncStatus(account: .available).footer
                == "Workouts, templates and custom exercises sync through your iCloud account."
        )
        #expect(CloudSyncStatus(account: .available, lastError: "Quota exceeded").footer == "Quota exceeded")
    }

    @Test func accountStateChangeKeepsHistory() {
        var status = CloudSyncStatus(account: .available).applying(event(ok: true, at: -5))
        status.account = .noAccount
        #expect(status.lastSuccess != nil)
        #expect(status.label(now: now) == "Not signed in")
    }
}
