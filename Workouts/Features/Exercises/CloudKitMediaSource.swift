//
//  CloudKitMediaSource.swift
//  Workouts
//

import CloudKit
import OSLog
import WorkoutsKit

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

    func fetchVideo(sourceId: String, scheme: MediaScheme) async throws -> URL? {
        try await fetchVideo(sourceId: sourceId, scheme: scheme, allowsCellular: true)
    }

    func fetchVideo(sourceId: String, scheme: MediaScheme, allowsCellular: Bool) async throws -> URL? {
        var configuration = CKOperation.Configuration()
        configuration.allowsCellularAccess = allowsCellular
        configuration.qualityOfService = allowsCellular ? .userInitiated : .utility
        let database = CKContainer(identifier: Self.containerIdentifier).publicCloudDatabase
        let recordID = CKRecord.ID(recordName: sourceId)
        do {
            return try await database.configuredWith(configuration: configuration) { database in
                // Ask for one asset at a time so a dark-mode fetch never downloads both videos.
                if let url = try await Self.assetURL(of: Self.assetKey(scheme), in: recordID, database: database) {
                    return url
                }
                guard scheme == .dark else { return nil }
                return try await Self.assetURL(of: Self.assetKey(.light), in: recordID, database: database)
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("Fetching video \(sourceId, privacy: .public) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func assetKey(_ scheme: MediaScheme) -> String {
        scheme == .dark ? "videoDark" : "videoLight"
    }

    /// The downloaded file of one asset field, or nil when the record has no such asset.
    private static func assetURL(of key: String, in recordID: CKRecord.ID, database: CKDatabase) async throws -> URL? {
        // `record(for:)` has no `desiredKeys`, and a record fetch downloads every asset it returns.
        let results = try await database.records(for: [recordID], desiredKeys: [key])
        guard let result = results[recordID] else { return nil }
        return (try result.get()[key] as? CKAsset)?.fileURL
    }
}
