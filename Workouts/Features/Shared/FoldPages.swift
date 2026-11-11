//
//  FoldPages.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// Two pages that anchor on the hinge. At regular width with a vertical fold division inside, the leading page fills the
/// container from its leading edge to the division and the trailing page from the division to the trailing edge, each in its
/// own vertical `ScrollView`, so the hinge is the only gutter and the two halves may differ in width. Otherwise (the closed
/// Duo, a fold along the other axis, a plain window) both pages stack in one `ScrollView`. Only the outer edges get `margin`;
/// the placement is `FoldPlacement.pageFrames`.
struct FoldPages<Leading: View, Trailing: View>: View {
    var margin: CGFloat = 16
    var spacing: CGFloat = 20
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The pages' frames in this view's own coordinate space, nil unless a vertical division lies inside it. Inactive regions
    /// count, so the pages already sit on the hinge when the Duo is open flat.
    @State private var frames: FoldPlacement.PageFrames?

    var body: some View {
        Group {
            if horizontalSizeClass == .regular, let frames {
                ZStack(alignment: .topLeading) {
                    page(leading, frame: frames.leading)
                    page(trailing, frame: frames.trailing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: spacing) {
                        leading
                        trailing
                    }
                    .padding(.horizontal, margin)
                    .padding(.bottom)
                }
            }
        }
        // Measured on a background view: on the page container itself the division is not reported.
        .background {
            Color.clear
                .onGeometryChange(for: FoldPlacement.PageFrames?.self) { proxy in
                    let width = proxy.size.width
                    return FoldPlacement.pageFrames(
                        total: width,
                        division: FoldPlacement.columnGap(
                            divisions: proxy.reservedRegions(kind: .division, options: .includeInactive).map(\.frame),
                            width: width
                        ),
                        margin: margin
                    )
                } action: {
                    frames = $0
                }
        }
    }

    private func page(_ content: some View, frame: FoldPlacement.PageFrame) -> some View {
        ScrollView {
            content.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom)
        }
        .frame(width: frame.width)
        .offset(x: frame.x)
    }
}

#if DEBUG
    /// Numbered coloured cards, so a page's width, scroll and edges show in every Duo pose.
    private struct FoldPagesCards: View {
        let count: Int
        let hue: Double

        var body: some View {
            VStack(spacing: 12) {
                ForEach(1...count, id: \.self) { number in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hue: hue, saturation: 0.55, brightness: 0.7))
                        .frame(height: 120)
                        .overlay {
                            Text("\(number)")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Card \(number)")
                }
            }
        }
    }

    /// Two tall stacks on the container, for the gallery (`-preview FoldPages`) and the preview: 6 leading cards, 14 trailing.
    struct FoldPagesDemo: View {
        var body: some View {
            FoldPages {
                FoldPagesCards(count: 6, hue: 0.1)
            } trailing: {
                FoldPagesCards(count: 14, hue: 0.6)
            }
        }
    }

    #Preview("Fold pages") {
        FoldPagesDemo()
    }
#endif
