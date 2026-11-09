import Foundation

/// What the iCloud account allows, as the Settings row shows it. Mapped from `CKAccountStatus` in the app target.
public nonisolated enum CloudAccountState: Sendable, Equatable {
    /// Sync is not compiled in or the store is local-only (tests, previews).
    case off
    /// The account has not been read yet.
    case unknown
    case available
    case noAccount
    case restricted
    /// Also covers `couldNotDetermine` and `temporarilyUnavailable`.
    case unavailable
}

/// One finished CloudKit mirroring event (setup, import or export), reduced to what the status needs.
public nonisolated struct CloudSyncEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case setup, importRecords, exportRecords
    }

    public var kind: Kind
    public var succeeded: Bool
    public var endedAt: Date
    public var errorDescription: String?

    public init(kind: Kind, succeeded: Bool, endedAt: Date, errorDescription: String? = nil) {
        self.kind = kind
        self.succeeded = succeeded
        self.endedAt = endedAt
        self.errorDescription = errorDescription
    }
}

/// The account state plus the newest sync outcome; a value type so the Settings copy is testable without CloudKit.
public nonisolated struct CloudSyncStatus: Sendable, Equatable {
    public var account: CloudAccountState
    public var lastSuccess: Date?
    public var lastError: String?

    public init(account: CloudAccountState = .unknown, lastSuccess: Date? = nil, lastError: String? = nil) {
        self.account = account
        self.lastSuccess = lastSuccess
        self.lastError = lastError
    }

    /// Folds in a finished event. Events can arrive out of order, so a success never moves `lastSuccess` backwards.
    public func applying(_ event: CloudSyncEvent) -> CloudSyncStatus {
        var next = self
        if event.succeeded {
            next.lastSuccess = max(lastSuccess ?? event.endedAt, event.endedAt)
            next.lastError = nil
        } else {
            next.lastError = event.errorDescription ?? "Sync failed."
        }
        return next
    }

    /// The row's value.
    public func label(now: Date) -> String {
        switch account {
        case .off: "Off"
        case .unknown: "Checking…"
        case .noAccount: "Not signed in"
        case .restricted: "Restricted"
        case .unavailable: "Unavailable"
        case .available:
            if lastError != nil {
                "Error"
            } else if let lastSuccess {
                "Synced " + Self.relative(lastSuccess, to: now)
            } else {
                "Waiting for first sync"
            }
        }
    }

    /// `RelativeFormatStyle` cannot take a reference date, so `now` goes through the formatter to keep the label testable.
    private static func relative(_ date: Date, to now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// The sentence under the row.
    public var footer: String {
        switch account {
        case .off: "Sync is off in this build."
        case .unknown: "Checking your iCloud account."
        case .noAccount: "Sign in to iCloud in Settings to sync."
        case .restricted: "iCloud is restricted on this device."
        case .unavailable: "iCloud is not available right now. Sync resumes when it is."
        case .available:
            lastError ?? "Workouts, templates and custom exercises sync through your iCloud account."
        }
    }
}
