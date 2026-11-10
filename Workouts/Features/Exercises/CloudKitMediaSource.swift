//
//  CloudKitMediaSource.swift
//  Workouts
//

import CloudKit
import OSLog
import WorkoutsKit

/// The one CloudKit call the media source makes, so tests can stand in for the public database.
nonisolated protocol RecordFetching: Sendable {
    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?,
        configuration: CKOperation.Configuration
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>]
}

extension CKDatabase: RecordFetching {
    nonisolated func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?,
        configuration: CKOperation.Configuration
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        try await configuredWith(configuration: configuration) { database in
            try await database.records(for: ids, desiredKeys: desiredKeys)
        }
    }
}

/// Exercise videos from CloudKit's **public** database (see `docs/port/media.md`).
///
/// One `ExerciseMedia` record per exercise, with `recordName` equal to the media `sourceId` and `videoLight` /
/// `videoDark` `CKAsset` fields. The container's environment follows the build: simulator and Xcode runs read
/// Development, TestFlight and App Store builds read Production. Public reads work without an iCloud account, so
/// `CKContainer.accountStatus` is deliberately never consulted.
nonisolated struct CloudKitMediaSource: MediaSource {
    static let containerIdentifier = "iCloud.com.ericribeiro.Workouts"
    static let recordType = "ExerciseMedia"

    private static let logger = Logger(subsystem: "com.ericribeiro.Workouts", category: "MediaSource")

    private let database: any RecordFetching

    init(database: some RecordFetching = CKContainer(identifier: Self.containerIdentifier).publicCloudDatabase) {
        self.database = database
    }

    func fetchVideo(sourceId: String, scheme: MediaScheme) async throws -> URL? {
        try await fetchVideo(sourceId: sourceId, scheme: scheme, allowsCellular: true)
    }

    func fetchVideo(sourceId: String, scheme: MediaScheme, allowsCellular: Bool) async throws -> URL? {
        let configuration = Self.operationConfiguration(allowsCellular: allowsCellular)
        let recordID = CKRecord.ID(recordName: sourceId)
        do {
            // Ask for one asset at a time so a dark-mode fetch never downloads both videos.
            if let url = try await assetURL(of: Self.assetKey(scheme), in: recordID, configuration: configuration) {
                return url
            }
            guard scheme == .dark else { return nil }
            return try await assetURL(of: Self.assetKey(.light), in: recordID, configuration: configuration)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Thrown, not nil: "no video" and "could not reach it" differ to a bulk download, which retries the latter.
            Self.logger.error("Fetching video \(sourceId, privacy: .public) failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// The CloudKit configuration for one video fetch: Wi-Fi-only fetches are also lower priority.
    static func operationConfiguration(allowsCellular: Bool) -> CKOperation.Configuration {
        var configuration = CKOperation.Configuration()
        configuration.allowsCellularAccess = allowsCellular
        configuration.qualityOfService = allowsCellular ? .userInitiated : .utility
        return configuration
    }

    private static func assetKey(_ scheme: MediaScheme) -> String {
        scheme == .dark ? "videoDark" : "videoLight"
    }

    /// The downloaded file of one asset field, or nil when the record has no such asset.
    private func assetURL(
        of key: String,
        in recordID: CKRecord.ID,
        configuration: CKOperation.Configuration
    ) async throws -> URL? {
        // `record(for:)` has no `desiredKeys`, and a record fetch downloads every asset it returns.
        let results = try await database.records(for: [recordID], desiredKeys: [key], configuration: configuration)
        guard let result = results[recordID] else { return nil }
        return (try result.get()[key] as? CKAsset)?.fileURL
    }
}
