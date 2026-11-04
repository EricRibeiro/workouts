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

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(id: info.isCustom ? nil : info.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
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

    private var height: CGFloat { baseHeight * scale }

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
