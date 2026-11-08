import Foundation
import Testing
import WorkoutsKit

@testable import Workouts

@MainActor
struct WorkoutDetailInputsTests {
    private func inputs(weightTypes: [UUID: WeightType]) -> WorkoutDetailInputs {
        WorkoutDetailInputs(
            workout: nil,
            newestEdit: nil,
            generation: 0,
            unit: .kg,
            formula: .epley,
            weightTypes: weightTypes
        )
    }

    /// The pushed detail reloads on a change of this value (`.task(id:)`), so editing a custom exercise's weight type
    /// has to change it, or volume, best set and PRs stay stale while the History list updates.
    @Test func aWeightTypeEditChangesTheInputs() {
        let exercise = UUID()
        let before = inputs(weightTypes: [exercise: .barbell])
        #expect(before != inputs(weightTypes: [exercise: .assisted]))
        #expect(before == inputs(weightTypes: [exercise: .barbell]))
    }
}
