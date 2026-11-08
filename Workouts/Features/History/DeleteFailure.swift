//
//  DeleteFailure.swift
//  Workouts
//

import Foundation
import WorkoutsKit

/// A failed workout delete, as the History list's alert needs it: which entry Retry deletes again, and what to tell the
/// user. The detail view keeps only ``message(for:)``, since it has one workout.
struct DeleteFailure {
    let entry: HistoryEntry
    let message: String

    /// The alert text for a failed delete. The store was rolled back, so the workout is unchanged.
    static func message(for error: Error) -> String {
        "Could not delete the workout: \(error.localizedDescription). It is still here and nothing is lost."
    }
}
