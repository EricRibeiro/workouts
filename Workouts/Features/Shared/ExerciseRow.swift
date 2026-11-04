//
//  ExerciseRow.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// The content of one exercise row, shared by the Exercises list and the exercise picker: thumbnail, name, subtitle
/// ("Body part · Category") and an optional secondary `trailing` text (the list's best set). It is only the label; the
/// caller wraps it in the button, link or selectable row and names the accessibility element.
struct ExerciseRow: View {
    let info: ExerciseInfo
    let subtitle: String
    var trailing: String = ""

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the decorative thumbnail goes (HIG) and the trailing text moves under the name, so the
        // name keeps the full row width instead of wrapping a letter per line.
        let compact = dynamicTypeSize.isAccessibilitySize
        HStack(spacing: 12) {
            if !compact { ExerciseThumbnail(id: info.isCustom ? nil : info.id) }
            if compact {
                VStack(alignment: .leading, spacing: 2) {
                    details
                    trailingText
                }
            } else {
                details
                Spacer(minLength: 0)
                trailingText
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(info.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if info.isCustom { ExerciseTag(text: "Custom", tint: .accentColor) }
                if info.isRetired { ExerciseTag(text: "Retired", tint: .secondary) }
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var trailingText: some View {
        if !trailing.isEmpty {
            Text(trailing)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
    }
}

extension ExerciseRow {
    /// "Custom, Retired" for the accessibility label; empty when the exercise has neither tag.
    static func tagText(for info: ExerciseInfo) -> String {
        [info.isCustom ? "Custom" : "", info.isRetired ? "Retired" : ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// A small capsule tag after the name (`Custom`, `Retired`). Decorative: the row's label already names it.
private struct ExerciseTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: .capsule)
            .fixedSize()
    }
}

/// The bundled start-frame thumbnail, loaded lazily by `AsyncImage`; a symbol stands in when there is none (custom).
struct ExerciseThumbnail: View {
    /// A library exercise id, or nil for a custom exercise.
    let id: UUID?
    let phase: MediaPhase
    let baseHeight: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    init(id: UUID?, phase: MediaPhase = .start, height: CGFloat = 36) {
        self.id = id
        self.phase = phase
        baseHeight = height
    }

    /// Scaling is capped so a large Dynamic Type size cannot blow the thumbnail up (rows hide it at accessibility sizes).
    private var height: CGFloat { baseHeight * min(scale, 1.4) }

    var body: some View {
        Group {
            if let id, let url = Self.media.thumbnailURL(for: id, phase: phase) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.12))
            }
        }
        .frame(width: height * 16 / 9, height: height)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    /// Only the bundled thumbnails are read, so the base URL and cache folder are never used here.
    private static let media = MediaStore(
        baseURL: MediaStore.baseURL(from: .main) ?? URL(filePath: "/"),
        bundle: .main,
        cacheDirectory: .cachesDirectory
    )
}
