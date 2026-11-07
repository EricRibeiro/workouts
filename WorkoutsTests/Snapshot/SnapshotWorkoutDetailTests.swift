import Foundation
import SwiftData
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The pushed workout detail in its two states, hosted in a `NavigationStack` like the real push: the loading frame
    /// (the detail load held by the DEBUG `slowLoads` seam, PLAN 7b.4) and the loaded screen. Both are recorded, and
    /// `Snapshot.assertSameChrome` requires their navigation bar and title to be identical (PLAN 7b.5, DECISIONS.md
    /// "Pushed-screen chrome"). Light, default Dynamic Type: the chrome rule does not vary with either.
    ///
    /// Serialized because the hold is a process-wide `UserDefaults` key.
    @MainActor
    @Suite(.serialized)
    struct WorkoutDetailSnapshots {
        private static let variant = SnapshotVariant.all[0]
        private static let height: CGFloat = 844

        private func render(workoutID: UUID, environment: SampleEnvironment, held: Bool) async throws -> Data {
            let defaults = UserDefaults.standard
            let key = "slowLoads"
            let previous = defaults.object(forKey: key)
            // Far longer than the settle below.
            if held { defaults.set(600_000, forKey: key) } else { defaults.removeObject(forKey: key) }
            defer {
                if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            return try #require(
                await Snapshot.renderSettling(
                    NavigationStack { WorkoutDetailView(workoutID: workoutID) },
                    variant: Self.variant,
                    width: 390,
                    height: Self.height,
                    environment: environment,
                    // The loaded frame waits for the off-main load (50 workouts of history) to land.
                    settle: held ? .seconds(1) : .seconds(3)
                )
            )
        }

        @Test
        func loadingAndLoadedShareTheChrome() async throws {
            let environment = try SnapshotFixtures.requireEnvironment()
            let finished = try environment.container.mainContext.fetch(Workout.allFinished)
            let newest = try #require(finished.max { $0.startedAt < $1.startedAt })

            let loading = try await render(workoutID: newest.id, environment: environment, held: true)
            let loaded = try await render(workoutID: newest.id, environment: environment, held: false)

            Snapshot.assert(png: loading, named: "loading", variant: Self.variant)
            Snapshot.assert(png: loaded, named: "loaded", variant: Self.variant)
            // The hosted frame has no status bar, so the inline bar ends at ~80 pt and the first card starts right under it.
            Snapshot.assertSameChrome(loading, loaded, topPoints: 80)
            // The two states must really differ below the chrome, or the hold did nothing.
            #expect(
                Snapshot.difference(between: loading, and: loaded) != nil,
                "the loading and loaded frames are identical: the detail load was not held"
            )
        }
    }
}
