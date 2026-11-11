//
//  FoldPages.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// Two pages side by side in their own vertical `ScrollView`s. At regular width they are two equal columns across the full
/// width (outer `margin`, `spacing` between), the hinge ignored, as long as each column is at least `minimumColumn` wide; the
/// Duo open flat therefore reads as one surface. While the hinge is an active vertical division (the half-folded book pose)
/// the pages instead anchor on it: the leading page runs to the division, the trailing page starts after it
/// (`FoldPlacement.pageFrames`). Otherwise (compact width, a narrow container) both pages stack in one `ScrollView`. The two
/// column cases are the same view tree, so folding the Duo keeps each page's scroll position.
struct FoldPages<Leading: View, Trailing: View>: View {
    var margin: CGFloat = 16
    var spacing: CGFloat = 20
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    /// The narrowest a page may get before the pages stack instead.
    static var minimumColumn: CGFloat { 320 }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The pages' frames in this view's own coordinate space, nil when the pages stack.
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
                    let division = FoldPlacement.columnGap(
                        divisions: proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame),
                        width: width
                    )
                    if division != nil {
                        return FoldPlacement.pageFrames(total: width, division: division, margin: margin)
                    }
                    return FoldPlacement.equalPageFrames(
                        total: width,
                        margin: margin,
                        spacing: spacing,
                        minimumPage: Self.minimumColumn
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
