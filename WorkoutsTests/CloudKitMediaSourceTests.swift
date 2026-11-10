import CloudKit
import Foundation
import Testing
import WorkoutsKit

@testable import Workouts

struct CloudKitMediaSourceTests {
    @Test func cellularAllowedFetchesAtUserInitiatedPriority() {
        let configuration = CloudKitMediaSource.operationConfiguration(allowsCellular: true)
        #expect(configuration.allowsCellularAccess == true)
        #expect(configuration.qualityOfService == .userInitiated)
    }

    @Test func wifiOnlyFetchesBlockCellularAndRunAtUtilityPriority() {
        let configuration = CloudKitMediaSource.operationConfiguration(allowsCellular: false)
        #expect(configuration.allowsCellularAccess == false)
        #expect(configuration.qualityOfService == .utility)
    }

    @Test func lightRecordReturnsTheLightAssetURL() async throws {
        let light = try Self.tempFile()
        let fake = FakeRecordFetcher(assets: ["videoLight": light])
        let url = try await CloudKitMediaSource(database: fake).fetchVideo(sourceId: "bench", scheme: .light)
        #expect(url == light)
        #expect(fake.requestedKeys == [["videoLight"]])
    }

    @Test func darkRecordReturnsTheDarkAssetWithoutAskingForLight() async throws {
        let dark = try Self.tempFile()
        let fake = FakeRecordFetcher(assets: ["videoDark": dark, "videoLight": try Self.tempFile()])
        let url = try await CloudKitMediaSource(database: fake).fetchVideo(sourceId: "bench", scheme: .dark)
        #expect(url == dark)
        #expect(fake.requestedKeys == [["videoDark"]])
    }

    @Test func darkFallsBackToLightWhenTheDarkAssetIsMissing() async throws {
        let light = try Self.tempFile()
        let fake = FakeRecordFetcher(assets: ["videoLight": light])
        let url = try await CloudKitMediaSource(database: fake).fetchVideo(sourceId: "bench", scheme: .dark)
        #expect(url == light)
        #expect(fake.requestedKeys == [["videoDark"], ["videoLight"]])
    }

    @Test func lightMissingReturnsNilWithoutAFallback() async throws {
        let fake = FakeRecordFetcher(assets: ["videoDark": try Self.tempFile()])
        let url = try await CloudKitMediaSource(database: fake).fetchVideo(sourceId: "bench", scheme: .light)
        #expect(url == nil)
        #expect(fake.requestedKeys == [["videoLight"]])
    }

    @Test func darkAndLightBothMissingReturnsNil() async throws {
        let fake = FakeRecordFetcher(assets: [:])
        let url = try await CloudKitMediaSource(database: fake).fetchVideo(sourceId: "bench", scheme: .dark)
        #expect(url == nil)
    }

    @Test func absentRecordResultReturnsNil() async throws {
        let fake = FakeRecordFetcher(assets: [:], omitsRecord: true)
        let url = try await CloudKitMediaSource(database: fake).fetchVideo(sourceId: "bench", scheme: .light)
        #expect(url == nil)
    }

    @Test func unknownItemReturnsNil() async throws {
        let fake = FakeRecordFetcher(assets: [:], failure: CKError(.unknownItem))
        let url = try await CloudKitMediaSource(database: fake).fetchVideo(sourceId: "gone", scheme: .light)
        #expect(url == nil)
    }

    @Test func perRecordUnknownItemReturnsNil() async throws {
        let fake = FakeRecordFetcher(assets: [:], recordFailure: CKError(.unknownItem))
        let url = try await CloudKitMediaSource(database: fake).fetchVideo(sourceId: "gone", scheme: .light)
        #expect(url == nil)
    }

    @Test func networkFailureIsRethrown() async {
        let fake = FakeRecordFetcher(assets: [:], failure: CKError(.networkFailure))
        await #expect {
            try await CloudKitMediaSource(database: fake).fetchVideo(sourceId: "bench", scheme: .light)
        } throws: { error in
            (error as? CKError)?.code == .networkFailure
        }
    }

    @Test func perRecordNetworkFailureIsRethrown() async {
        let fake = FakeRecordFetcher(assets: [:], recordFailure: CKError(.networkFailure))
        await #expect {
            try await CloudKitMediaSource(database: fake).fetchVideo(sourceId: "bench", scheme: .light)
        } throws: { error in
            (error as? CKError)?.code == .networkFailure
        }
    }

    @Test func cancelledTaskThrowsCancellationError() async {
        let fake = FakeRecordFetcher(
            assets: ["videoLight": URL(fileURLWithPath: "/tmp/x.mp4")],
            honorsCancellation: true
        )
        let task = Task {
            await Task.yield()
            return try await CloudKitMediaSource(database: fake).fetchVideo(sourceId: "bench", scheme: .light)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func wifiOnlyPassesTheUtilityConfigurationToTheDatabase() async throws {
        let fake = FakeRecordFetcher(assets: ["videoLight": try Self.tempFile()])
        _ = try await CloudKitMediaSource(database: fake).fetchVideo(
            sourceId: "bench",
            scheme: .light,
            allowsCellular: false
        )
        #expect(fake.configurations.first?.allowsCellularAccess == false)
        #expect(fake.configurations.first?.qualityOfService == .utility)
    }

    private static func tempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        try Data("video".utf8).write(to: url)
        return url
    }
}

/// Stands in for the public database: serves one record carrying only the requested asset keys it has.
private final class FakeRecordFetcher: RecordFetching, @unchecked Sendable {
    private let assets: [String: URL]
    private let failure: (any Error)?
    private let recordFailure: (any Error)?
    private let omitsRecord: Bool
    private let honorsCancellation: Bool
    private let lock = NSLock()
    private var keys: [[String]] = []
    private var configs: [CKOperation.Configuration] = []

    var requestedKeys: [[String]] { lock.withLock { keys } }
    var configurations: [CKOperation.Configuration] { lock.withLock { configs } }

    init(
        assets: [String: URL],
        failure: (any Error)? = nil,
        recordFailure: (any Error)? = nil,
        omitsRecord: Bool = false,
        honorsCancellation: Bool = false
    ) {
        self.assets = assets
        self.failure = failure
        self.recordFailure = recordFailure
        self.omitsRecord = omitsRecord
        self.honorsCancellation = honorsCancellation
    }

    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?,
        configuration: CKOperation.Configuration
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        if honorsCancellation { try Task.checkCancellation() }
        lock.withLock {
            keys.append(desiredKeys ?? [])
            configs.append(configuration)
        }
        if let failure { throw failure }
        guard let id = ids.first, !omitsRecord else { return [:] }
        if let recordFailure { return [id: .failure(recordFailure)] }
        let record = CKRecord(recordType: CloudKitMediaSource.recordType, recordID: id)
        for key in desiredKeys ?? [] {
            if let url = assets[key] { record[key] = CKAsset(fileURL: url) }
        }
        return [id: .success(record)]
    }
}
