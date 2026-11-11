import Foundation
import SwiftData
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

/// The deterministic inputs the snapshot suites share: the gallery's sample environment built at a fixed instant, so
/// dates, "5 days ago" texts and workout ids never depend on the day the tests run.
@MainActor
enum SnapshotFixtures {
    /// 2026-11-01 12:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_793_534_400)
    /// The references were recorded in Toronto; formatting through this calendar keeps them valid on a machine or
    /// simulator in another time zone.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto") ?? .gmt
        return calendar
    }()

    /// Built once per test run (seeding 50 workouts is the slow part).
    static let environment: SampleEnvironment? = try? SampleEnvironment(now: now)

    static func requireEnvironment() throws -> SampleEnvironment {
        try #require(environment, "the sample environment could not be built")
    }
}

/// Wraps a set row, which needs a `@FocusState` binding that only a parent view can own.
struct SnapshotSetRowHost: View {
    let rows: [SetRowModel]
    /// The row drawn as the one to do now (`SetRow.isNext`).
    var nextID: UUID?
    @FocusState private var focus: SetRowField?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                SetRow(
                    model: row,
                    isNext: row.id == nextID,
                    focus: $focus,
                    onCycleKind: {},
                    onApplyPrevious: {},
                    onCommitWeight: { _ in },
                    onCommitReps: { _ in },
                    onToggleCheck: { true },
                    onDelete: {}
                )
            }
        }
        .padding(.horizontal, 8)
    }
}

/// Wraps a template card, which needs a namespace that only a parent view can own.
struct SnapshotTemplateCardHost: View {
    let template: Template
    let summary: TemplateCardSummary
    var size: TemplateCard.Size = .compact
    @Namespace private var namespace

    var body: some View {
        TemplateCard(
            template: template,
            summary: summary,
            size: size,
            namespace: namespace,
            actions: TemplateCardActions(),
            open: {}
        )
        .padding(.horizontal, 16)
    }
}

/// Groups every snapshot suite so `./dev test SnapshotTests` runs them all (a test filter matches whole identifiers,
/// not prefixes). Each suite lives in `Snapshot<Name>Tests.swift`, whose name is also its `__Snapshots__` folder.
@Suite struct SnapshotTests {}
