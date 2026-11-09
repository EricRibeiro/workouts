import CloudKit
import CoreData
import Foundation
import OSLog
import Observation
import WorkoutsKit

/// Feeds the Settings iCloud row: the account state from CloudKit plus the newest mirroring event from
/// `NSPersistentCloudKitContainer`. Disabled (in-memory stores, sync off) it observes nothing and reads "Off".
@Observable
@MainActor
final class CloudSyncMonitor {
    private(set) var status: CloudSyncStatus
    private let enabled: Bool
    private let containerIdentifier: String
    private var observers: [any NSObjectProtocol] = []
    private let log = Logger(subsystem: "com.ericribeiro.Workouts", category: "Sync")

    init(enabled: Bool, containerIdentifier: String) {
        self.enabled = enabled
        self.containerIdentifier = containerIdentifier
        status = CloudSyncStatus(account: enabled ? .unknown : .off)
    }

    func start() {
        guard enabled, observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                guard let event = notification.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                    let mapped = Self.map(event)
                else { return }
                MainActor.assumeIsolated { self?.apply(mapped) }
            }
        )
        observers.append(
            center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAccount() }
            }
        )
        refreshAccount()
    }

    func refreshAccount() {
        guard enabled else { return }
        let identifier = containerIdentifier
        Task {
            do {
                let account = try await CKContainer(identifier: identifier).accountStatus()
                status.account = Self.map(account)
            } catch {
                log.error("Could not read the iCloud account status: \(error.localizedDescription, privacy: .public)")
                status.account = .unavailable
            }
        }
    }

    private func apply(_ event: CloudSyncEvent) {
        status = status.applying(event)
        if !event.succeeded {
            log.error(
                "Sync \(String(describing: event.kind)) failed: \(event.errorDescription ?? "unknown", privacy: .public)"
            )
        }
    }

    /// Only finished events (an `endDate`) carry an outcome; a started one is ignored.
    nonisolated private static func map(_ event: NSPersistentCloudKitContainer.Event) -> CloudSyncEvent? {
        guard let endedAt = event.endDate else { return nil }
        let kind: CloudSyncEvent.Kind =
            switch event.type {
            case .setup: .setup
            case .import: .importRecords
            case .export: .exportRecords
            @unknown default: .setup
            }
        return CloudSyncEvent(
            kind: kind,
            succeeded: event.succeeded,
            endedAt: endedAt,
            errorDescription: event.error?.localizedDescription
        )
    }

    nonisolated private static func map(_ account: CKAccountStatus) -> CloudAccountState {
        switch account {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .couldNotDetermine, .temporarilyUnavailable: .unavailable
        @unknown default: .unavailable
        }
    }
}
