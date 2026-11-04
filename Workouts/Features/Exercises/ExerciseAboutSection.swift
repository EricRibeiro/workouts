//
//  ExerciseAboutSection.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The About segment (`docs/port/screens/exercises.md` section 2, "About"): every block is omitted when it has nothing
/// to show. Library content comes from the catalog; a custom exercise contributes its own instructions.
struct ExerciseAboutSection: View {
    let info: ExerciseInfo
    let library: LibraryExercise?
    let labels: LibraryLabels
    /// The custom exercise's own steps (empty for library exercises).
    let customInstructions: [String]

    private var instructions: [String] { library?.instructions ?? customInstructions }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if info.isRetired { retiredNotice }
            bodyPartLine
            numbered("Instructions", instructions, identifier: "instructions")
            bulleted("Tips", library?.tips ?? [], identifier: "tips")
            bulleted("Common mistakes", library?.mistakes ?? [], identifier: "mistakes")
            overview
            muscles
            chips("Equipment", info.equipment.map { ExerciseFilter.equipmentLabel($0, labels: labels) })
            chips("Also known as", info.aliases)
            credit
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Blocks

    private var retiredNotice: some View {
        let text =
            info.isCustom
            ? "This exercise is archived; its history is kept."
            : "This exercise is no longer in the library; its history is kept."
        return Label(text, systemImage: "archivebox")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityIdentifier("exerciseDetail.about.retired")
    }

    @ViewBuilder
    private var bodyPartLine: some View {
        let label = ExerciseFilter.bodyPartLabel(info.bodyPart, labels: labels)
        if !info.bodyPart.isEmpty, !label.isEmpty {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Body part, \(label)")
                .accessibilityIdentifier("exerciseDetail.about.bodyPart")
        }
    }

    @ViewBuilder
    private func numbered(_ title: String, _ items: [String], identifier: String) -> some View {
        if !items.isEmpty {
            section(title) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1).")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .accessibilityHidden(true)
                            Text(item)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Step \(index + 1), \(item)")
                    }
                }
            }
            .accessibilityIdentifier("exerciseDetail.about.\(identifier)")
        }
    }

    @ViewBuilder
    private func bulleted(_ title: String, _ items: [String], identifier: String) -> some View {
        if !items.isEmpty {
            section(title) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("•")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(item)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(item)
                    }
                }
            }
            .accessibilityIdentifier("exerciseDetail.about.\(identifier)")
        }
    }

    @ViewBuilder
    private var overview: some View {
        if let text = library?.description, !text.isEmpty {
            section("Overview") { Text(text) }
                .accessibilityIdentifier("exerciseDetail.about.overview")
        }
    }

    @ViewBuilder
    private var muscles: some View {
        let split = LibraryMuscles.split(library?.muscles ?? [:], labels: labels)
        if !split.primary.isEmpty || !split.secondary.isEmpty {
            section("Muscles") {
                VStack(alignment: .leading, spacing: 12) {
                    if !split.primary.isEmpty { chipGroup("Primary", split.primary) }
                    if !split.secondary.isEmpty { chipGroup("Secondary", split.secondary) }
                }
            }
            .accessibilityIdentifier("exerciseDetail.about.muscles")
        }
    }

    @ViewBuilder
    private func chips(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            section(title) { FlowLayout(spacing: 8) { chipViews(items) } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), \(items.joined(separator: ", "))")
        }
    }

    private func chipGroup(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            FlowLayout(spacing: 8) { chipViews(items) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) muscles, \(items.joined(separator: ", "))")
    }

    private func chipViews(_ items: [String]) -> some View {
        ForEach(items, id: \.self) { item in
            Text(item)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground), in: .capsule)
        }
    }

    @ViewBuilder
    private var credit: some View {
        if let library, let url = URL(string: library.sourceUrl), !library.sourceUrl.isEmpty {
            Link("Exercise content: SmartWorkout", destination: url)
                .font(.footnote)
                .accessibilityLabel("Exercise content: SmartWorkout, opens the source page")
                .accessibilityIdentifier("exerciseDetail.about.credit")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Wraps its subviews onto as many lines as the width needs (chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}
