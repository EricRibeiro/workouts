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
            let summary = TemplateCardSummary.make(
                for: template,
                finishedWorkouts: finished,
                maxLines: 3,
                now: SnapshotFixtures.now
            )
            Snapshot.assert(
                SnapshotTemplateCardHost(template: template, summary: summary),
                named: "card",
                variant: variant,
                width: 220,
                environment: environment
            )
        }

        /// The regular card (open Duo): about 408 pt wide, six lines with their sets, the last session's duration.
        @Test(arguments: [SnapshotVariant.all[0]])
        func regularCard(variant: SnapshotVariant) throws {
            let environment = try SnapshotFixtures.requireEnvironment()
            let context = environment.container.mainContext
            let templates = try context.fetch(
                FetchDescriptor<Template>(sortBy: [SortDescriptor(\Template.position), SortDescriptor(\Template.name)])
            )
            let template = try #require(templates.max { ($0.exercises ?? []).count < ($1.exercises ?? []).count })
            let finished = try context.fetch(Workout.allFinished)
            let summary = TemplateCardSummary.make(
                for: template,
                finishedWorkouts: finished,
                maxLines: 6,
                now: SnapshotFixtures.now
            )
            Snapshot.assert(
                SnapshotTemplateCardHost(template: template, summary: summary, size: .regular),
                named: "regularCard",
                variant: variant,
                width: 440,
                environment: environment
            )
        }

        /// A compact-class card as wide as a closed-landscape Duo column (270 pt): three lines, the sets shown on a
        /// card wide enough for them.
        @Test(arguments: [SnapshotVariant.all[0]])
        func wideCompactCard(variant: SnapshotVariant) throws {
            let environment = try SnapshotFixtures.requireEnvironment()
            let context = environment.container.mainContext
            let templates = try context.fetch(
                FetchDescriptor<Template>(sortBy: [SortDescriptor(\Template.position), SortDescriptor(\Template.name)])
            )
            let template = try #require(templates.max { ($0.exercises ?? []).count < ($1.exercises ?? []).count })
            let finished = try context.fetch(Workout.allFinished)
            let summary = TemplateCardSummary.make(
                for: template,
                finishedWorkouts: finished,
                maxLines: 3,
                now: SnapshotFixtures.now
            )
            Snapshot.assert(
                SnapshotTemplateCardHost(template: template, summary: summary, size: .compact),
                named: "wideCompactCard",
                variant: variant,
                width: 302,
                engine: .hostedFitting,
                environment: environment
            )
        }

        /// A card with a superset: the bar hangs in the card's padding and the names keep the title's edge.
        @Test(arguments: [SnapshotVariant.all[0]])
        func supersetCard(variant: SnapshotVariant) throws {
            let environment = try SnapshotFixtures.requireEnvironment()
            let context = environment.container.mainContext
            let templates = try context.fetch(
                FetchDescriptor<Template>(sortBy: [SortDescriptor(\Template.position), SortDescriptor(\Template.name)])
            )
            let template = try #require(templates.max { ($0.exercises ?? []).count < ($1.exercises ?? []).count })
            let exercises = (template.exercises ?? []).sorted { $0.position < $1.position }
            try #require(exercises.count >= 3)
            // The shared sample store is restored so no other suite sees the superset.
            let original = exercises.map(\.supersetGroup)
            defer { for (exercise, group) in zip(exercises, original) { exercise.supersetGroup = group } }
            exercises[1].supersetGroup = 1
            exercises[2].supersetGroup = 1
            let finished = try context.fetch(Workout.allFinished)
            let summary = TemplateCardSummary.make(
                for: template,
                finishedWorkouts: finished,
                maxLines: 4,
                now: SnapshotFixtures.now
            )
            Snapshot.assert(
                SnapshotTemplateCardHost(template: template, summary: summary),
                named: "supersetCard",
                variant: variant,
                width: 220,
                engine: .hostedFitting,
                environment: environment
            )
        }
    }
}
