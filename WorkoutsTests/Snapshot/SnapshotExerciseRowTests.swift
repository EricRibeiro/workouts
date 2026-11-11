import Foundation
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// Exercise names: the list row's wrapping of a very long library name (no letter per line at accessibility sizes, the
    /// thumbnail dropped) and the active workout header's one-line truncation.
    @MainActor
    struct ExerciseRowSnapshots {
        private static let longName = "Lever Seated Hammer Grip Shoulder Press"

        private func info(_ name: String, custom: Bool = false) -> ExerciseInfo {
            ExerciseInfo(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000E001") ?? UUID(),
                name: name,
                bodyPart: "Shoulders",
                weightType: .machine,
                isCustom: custom
            )
        }

        @Test(arguments: SnapshotVariant.all)
        func longName(variant: SnapshotVariant) {
            Snapshot.assert(
                ExerciseRow(info: info(Self.longName), subtitle: "Shoulders · Strength", trailing: "100 kg × 8")
                    .padding(.horizontal, 16),
                named: "long-name",
                variant: variant
            )
        }

        /// "Full Exercise Names" on: a one-line name and a wrapping name stacked, both rows the same height, the short
        /// name centred with its subtitle.
        @Test(arguments: SnapshotVariant.all)
        func fullNames(variant: SnapshotVariant) {
            Snapshot.assert(
                VStack(spacing: 0) {
                    ExerciseRow(
                        info: info("Bench Press"),
                        subtitle: "Chest · Strength",
                        trailing: "80 kg × 5",
                        fullNames: true
                    )
                    Divider()
                    ExerciseRow(
                        info: info(Self.longName),
                        subtitle: "Shoulders · Strength",
                        trailing: "100 kg × 8",
                        fullNames: true
                    )
                }
                .padding(.horizontal, 16),
                named: "full-names",
                variant: variant
            )
        }

        /// The default: a long name is cut to one line at the tail, so both rows have the natural one-line height
        /// (at accessibility sizes the name wraps instead).
        @Test(arguments: SnapshotVariant.all)
        func oneLine(variant: SnapshotVariant) {
            Snapshot.assert(
                VStack(spacing: 0) {
                    ExerciseRow(
                        info: info("Bench Press"),
                        subtitle: "Chest · Strength",
                        trailing: "80 kg × 5"
                    )
                    Divider()
                    ExerciseRow(
                        info: info(Self.longName),
                        subtitle: "Shoulders · Strength",
                        trailing: "100 kg × 8"
                    )
                }
                .padding(.horizontal, 16),
                named: "one-line",
                variant: variant
            )
        }

        /// The active workout's exercise header (`SetTable.nameLabel`, private to its view): the shared line-limit modifier on
        /// a long name beside the chevron that must stay visible after truncation. One line with an ellipsis at the default
        /// size, two lines at accessibility sizes.
        @Test(arguments: SnapshotVariant.all)
        func nameLineLimit(variant: SnapshotVariant) {
            let header = HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Self.longName + " (Plate Loaded)")
                    .exerciseNameLineLimit()
                    .layoutPriority(0)
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .font(.title3.bold())
            .padding(.horizontal, 16)
            Snapshot.assert(header, named: "name-line-limit", variant: variant)
        }

        @Test(arguments: SnapshotVariant.all)
        func customTag(variant: SnapshotVariant) {
            Snapshot.assert(
                ExerciseRow(info: info("Sled Push", custom: true), subtitle: "Legs · Strength", trailing: "40 kg × 20")
                    .padding(.horizontal, 16),
                named: "custom-tag",
                variant: variant
            )
        }
    }
}
