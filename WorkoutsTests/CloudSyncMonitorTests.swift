import CoreData
import Foundation
import Testing
import WorkoutsKit

@testable import Workouts

struct CloudSyncMonitorTests {
    private static let end = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Failure: LocalizedError {
        var errorDescription: String? { "quota exceeded" }
    }

    @Test func eventWithoutEndDateIsIgnored() {
        for type in [NSPersistentCloudKitContainer.EventType.setup, .import, .export] {
            #expect(CloudSyncMonitor.map(endDate: nil, type: type, succeeded: false, error: nil) == nil)
        }
    }

    @Test func importSuccessMapsToImportRecords() {
        let event = CloudSyncMonitor.map(endDate: Self.end, type: .import, succeeded: true, error: nil)
        #expect(event == CloudSyncEvent(kind: .importRecords, succeeded: true, endedAt: Self.end))
    }

    @Test func exportSuccessMapsToExportRecords() {
        let event = CloudSyncMonitor.map(endDate: Self.end, type: .export, succeeded: true, error: nil)
        #expect(event == CloudSyncEvent(kind: .exportRecords, succeeded: true, endedAt: Self.end))
    }

    @Test func setupMapsToSetup() {
        let event = CloudSyncMonitor.map(endDate: Self.end, type: .setup, succeeded: true, error: nil)
        #expect(event?.kind == .setup)
    }

    @Test func failureCarriesTheErrorText() {
        let event = CloudSyncMonitor.map(endDate: Self.end, type: .export, succeeded: false, error: Failure())
        #expect(event?.succeeded == false)
        #expect(event?.kind == .exportRecords)
        #expect(event?.errorDescription == "quota exceeded")
    }

    @Test func importFailureWithoutAnErrorHasNoDescription() {
        let event = CloudSyncMonitor.map(endDate: Self.end, type: .import, succeeded: false, error: nil)
        #expect(event?.succeeded == false)
        #expect(event?.errorDescription == nil)
    }

    @Test func unknownTypeMapsToSetup() {
        let unknown = NSPersistentCloudKitContainer.EventType(rawValue: 99) ?? .setup
        let event = CloudSyncMonitor.map(endDate: Self.end, type: unknown, succeeded: true, error: nil)
        #expect(event?.kind == .setup)
    }
}
