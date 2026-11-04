import Foundation
import Testing

@testable import WorkoutsKit

@Suite("ActiveWorkoutError descriptions")
struct ActiveWorkoutErrorTests {
    @Test("every case reads as a short sentence through localizedDescription")
    func descriptions() {
        let cases: [ActiveWorkoutError] = [
            .workoutInProgress(name: "Push Day"), .noActiveWorkout, .emptySet, .nothingLogged, .notInActiveWorkout,
            .invalidOrder,
        ]
        for error in cases {
            let text = error.localizedDescription
            #expect(!text.isEmpty)
            #expect(!text.contains("ActiveWorkoutError"), "\(text)")
            #expect(text.hasSuffix("."))
        }
    }

    @Test("the in-progress error names the running workout")
    func namesWorkout() {
        #expect(ActiveWorkoutError.workoutInProgress(name: "Push Day").localizedDescription.contains("Push Day"))
    }
}
