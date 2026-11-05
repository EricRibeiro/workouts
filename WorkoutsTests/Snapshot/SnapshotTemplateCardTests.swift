import Foundation
import SwiftData
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// A Workout-tab template card at the width of one grid column on the closed Duo.
    @MainActor
    struct TemplateCardSnapshots {
        @Test(arguments: SnapshotVariant.all)
        func card(variant: SnapshotVariant) throws {
            let environment = try SnapshotFixtures.requireEnvironment()
            let context = environment.container.mainContext
            let templates = try context.fetch(
                FetchDescriptor<Template>(sortBy: [SortDescriptor(\Template.position), SortDescriptor(\Template.name)])
            )
            let template = try #require(templates.first)
            let finished = try context.fetch(Workout.allFinished)
            let summary = TemplateCardSummary.make(for: template, finishedWorkouts: finished, now: SnapshotFixtures.now)
            Snapshot.assert(
                SnapshotTemplateCardHost(template: template, summary: summary),
                named: "card",
                variant: variant,
                width: 220,
                environment: environment
            )
        }
    }
}
