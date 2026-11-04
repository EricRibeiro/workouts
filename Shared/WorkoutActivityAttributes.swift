import ActivityKit
import Foundation
import WorkoutsKit

/// The ActivityKit wrapper around the kit's Codable state. A member of both the app and the `WorkoutsLiveActivity`
/// extension target (the app requests and updates the activity, the extension renders it), so keep it free of
/// app-only types.
struct WorkoutActivityAttributes: ActivityAttributes {
    typealias ContentState = WorkoutActivityState

    /// The in-progress workout the activity belongs to; never changes while the activity runs.
    var workoutID: UUID

    init(workoutID: UUID) {
        self.workoutID = workoutID
    }

    init(_ info: WorkoutActivityStaticInfo) {
        self.workoutID = info.workoutID
    }
}
