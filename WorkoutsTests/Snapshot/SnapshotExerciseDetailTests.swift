import Foundation
import SwiftData
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The exercise detail's History segment in its two states, hosted in a `NavigationStack` like the real push: the
    /// loading frame (the derivation held by the DEBUG `slowLoads` seam) and the loaded screen. About draws from the store
    /// at once, so only a data segment can show the loading state; it must be the redacted placeholder, never the "No
    /// history yet" empty state. The hero image is skipped (`heroPoints`): it swaps a thumbnail for the full-size picture
    /// whenever the media lands, so its pixels vary run to run; everything from the name down is compared.
    ///
    /// Serialized because the hold is a process-wide `UserDefaults` key.
    @MainActor
    @Suite(.serialized)
    struct ExerciseDetailSnapshots {
        private static let variant = SnapshotVariant.all[0]
        private static let heroPoints: CGFloat = 215

        private func render(exerciseID: UUID, environment: SampleEnvironment, held: Bool) async throws -> Data {
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
                    NavigationStack { ExerciseDetailView(exerciseID: exerciseID, initialSegment: .history) },
                    variant: Self.variant,
                    width: 390,
                    height: 844,
                    environment: environment,
                    settle: held ? .seconds(1) : .seconds(3)
                )
            )
        }

        @Test
        func historyShowsAPlaceholderWhileLoading() async throws {
            let environment = try SnapshotFixtures.requireEnvironment()
            let bench = try #require(environment.store.all().first { $0.name == "Barbell Bench Press" })

            let loading = try await render(exerciseID: bench.id, environment: environment, held: true)
            let loaded = try await render(exerciseID: bench.id, environment: environment, held: false)

            Snapshot.assert(
                png: loading,
                named: "history-loading",
                variant: Self.variant,
                excludingTop: Self.heroPoints
            )
            Snapshot.assert(png: loaded, named: "history-loaded", variant: Self.variant, excludingTop: Self.heroPoints)
            #expect(
                Snapshot.difference(between: loading, and: loaded, excludingTop: Self.heroPoints) != nil,
                "the loading and loaded frames are identical: the exercise load was not held"
            )
        }
    }
}
