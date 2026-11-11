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
    /// "Pushed-screen chrome"). Dark, default Dynamic Type: the chrome rule does not vary with either.
    ///
    /// Serialized because the hold is a process-wide `UserDefaults` key.
    @MainActor
    @Suite(.serialized)
    struct WorkoutDetailSnapshots {
        private static let variant = SnapshotVariant.all[0]
        private static let height: CGFloat = 844

        private func render(
            workoutID: UUID,
            environment: SampleEnvironment,
            held: Bool,
            unlike: Snapshot.SettledFrames? = nil
        ) async throws -> Snapshot.SettledFrames {
            let defaults = UserDefaults.standard
            let key = "slowLoads"
            let previous = defaults.object(forKey: key)
            // Far longer than the settle below.
            if held { defaults.set(600_000, forKey: key) } else { defaults.removeObject(forKey: key) }
            defer {
                if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            let view = NavigationStack { WorkoutDetailView(workoutID: workoutID) }
            if held {
                return try #require(
                    await Snapshot.renderSettled(
                        view,
                        variant: Self.variant,
                        width: 390,
                        height: Self.height,
                        environment: environment,
                        settle: .seconds(1),
                        topPoints: 80
                    )
                )
            }
            // The loaded frame waits for the off-main load (50 workouts of history) to land: a frame identical to the
            // held one is the placeholder, and a settled frame has no animation left, so it also serves the chrome check.
            let loaded = try #require(
                await Snapshot.renderSettledContent(
                    view,
                    variant: Self.variant,
                    width: 390,
                    height: Self.height,
                    environment: environment,
                    unlike: unlike?.atSettle
                )
            )
            return Snapshot.SettledFrames(atSettle: loaded, stable: loaded)
        }

        @Test
        func loadingAndLoadedShareTheChrome() async throws {
            let environment = try SnapshotFixtures.requireEnvironment()
            let finished = try environment.container.mainContext.fetch(Workout.allFinished)
            let newest = try #require(finished.max { $0.startedAt < $1.startedAt })

            let loading = try await render(workoutID: newest.id, environment: environment, held: true)
            let loaded = try await render(workoutID: newest.id, environment: environment, held: false, unlike: loading)

            // The bar's glass varies per simulator, so the references skip it; the chrome check below compares it in-run.
            // The loading frame's spinner phase is time-based, so a 72 pt square around it is masked out. It is centred in
            // the content area below the bar: (188, 445) pt in the 390 x 844 frame.
            let spinner = CGRect(x: 188 - 36, y: 445 - 36, width: 72, height: 72)
            Snapshot.assert(
                png: loading.atSettle,
                named: "loading",
                variant: Self.variant,
                excludingTop: 80,
                excluding: spinner
            )
            Snapshot.assert(png: loaded.atSettle, named: "loaded", variant: Self.variant, excludingTop: 80)
            // The chrome check takes the draws after each bar stopped animating (`renderSettled`), not a fixed sleep.
            // The hosted frame has no status bar, so the inline bar ends at ~80 pt and the first card starts right under it.
            Snapshot.assertSameChrome(loading.stable, loaded.stable, topPoints: 80)
            // The two states must really differ below the chrome, or the hold did nothing.
            #expect(
                Snapshot.difference(between: loading.atSettle, and: loaded.atSettle) != nil,
                "the loading and loaded frames are identical: the detail load was not held"
            )
        }

        /// The loaded screen of a workout carrying the full Health fixture: the Health tiles, the heart-rate chart and
        /// its zone bar. The fixture is stored on the shared sample workout for the render only.
        @Test
        func loadedWithHealth() async throws {
            let environment = try SnapshotFixtures.requireEnvironment()
            let finished = try environment.container.mainContext.fetch(Workout.allFinished)
            let newest = try #require(finished.max { $0.startedAt < $1.startedAt })
            WorkoutDetailDemo.applyFullFixture(to: newest)
            defer { newest.clearHealth() }

            let loaded = try await render(workoutID: newest.id, environment: environment, held: false)
            Snapshot.assert(png: loaded.atSettle, named: "loadedWithHealth", variant: Self.variant, excludingTop: 80)
        }
    }
}
