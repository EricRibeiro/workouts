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
                // Fill the row so a sibling (the picker's info button) sits at the trailing edge, not after the text.
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
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

/// A small capsule tag after the name (`Custom`, `Retired`). Decorative: the row's label already names it. The text
/// is primary (11pt text tinted over its own 15% tint misses 4.5:1); only the capsule carries the tint.
private struct ExerciseTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: .capsule)
            .fixedSize()
    }
}

/// The bundled thumbnail: the start frame, cross-fading to the end frame and back on a loop like the web app's list
/// (`ThumbnailCrossfade` holds the timing). A symbol stands in when there is no media (custom exercises).
///
/// Performance with 1,038 rows: the `List` only builds rows near the screen, so only those load images (`AsyncImage`,
/// the end frame only when it will animate) and only those run a clock. There is no timer per row: each visible
/// `TimelineView(.animation)` is driven by the display link, which stops while the row is off screen, and every row
/// derives its opacity from the same absolute clock (`ThumbnailCrossfade.endOpacity(at:)`), so rows stay in step
/// however they scrolled in. Reduce Motion shows the start frame alone and never loads the end frame.
struct ExerciseThumbnail: View {
    /// A library exercise id, or nil for a custom exercise.
    let id: UUID?
    let baseHeight: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(id: UUID?, height: CGFloat = 36) {
        self.id = id
        baseHeight = height
    }

    /// Reduce Motion, and UI tests (`-uiTesting`, which need still frames: the 30 fps cross-fade kept every list with
    /// thumbnails from ever settling for a screenshot), hold the start frame.
    private var animates: Bool { !reduceMotion && !Self.freezesStills }
    private static let freezesStills = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    /// Scaling is capped so a large Dynamic Type size cannot blow the thumbnail up (rows hide it at accessibility sizes).
    private var height: CGFloat { baseHeight * min(scale, 1.4) }

    var body: some View {
        Group {
            if let id, let startURL = Self.media.thumbnailURL(for: id, phase: .start) {
                frames(start: startURL, end: animates ? Self.media.thumbnailURL(for: id, phase: .end) : nil)
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

    @ViewBuilder
    private func frames(start: URL, end: URL?) -> some View {
        if let end {
            // 30 fps is plenty for a 64 pt opacity fade and halves the per-frame work of the visible rows.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let endOpacity = ThumbnailCrossfade.endOpacity(at: context.date.timeIntervalSinceReferenceDate)
                // The frames are transparent PNGs, so the start frame fades out as the end frame fades in; laying the
                // end frame over a fully opaque start frame would show both poses at once.
                ZStack {
                    image(start).opacity(1 - endOpacity)
                    image(end, placeholder: .clear).opacity(endOpacity)
                }
            }
        } else {
            image(start)
        }
    }

    /// The end frame's placeholder is clear so a still-loading frame never tints the start frame while it fades in.
    private func image(_ url: URL, placeholder: Color = .secondary.opacity(0.12)) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            placeholder
        }
    }

    /// Only the bundled thumbnails are read, so there is no video source and the cache folder is never used here.
    private static let media = MediaStore(
        source: nil,
        bundle: .main,
        cacheDirectory: .cachesDirectory
    )
}
