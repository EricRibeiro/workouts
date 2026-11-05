//
//  RestArc.swift
//  Workouts
//

import SwiftUI

/// The draining arc the ring items and the bench header draw (the rest timer's running button, the resume control): a faint track
/// and the remaining fraction from 12 o'clock, clockwise, no digits, optionally with an SF Symbol centred inside. Drawn with
/// `Image(size:renderer:)` so the item can stay a `Label` with an `Image` icon, which is what the closed Duo moves into the
/// trailing strip.
enum RestArc {
    /// `tint` colours the arc and track: callers pass the accent colour while a rest runs and the ok colour while a
    /// finished rest sits in its grace; nil follows the foreground style. `glyph` is an SF Symbol name drawn centred at about
    /// half the ring size in the same tint (nil draws the bare ring).
    static func image(
        fraction: Double,
        size: CGFloat,
        label: Text,
        tint: Color? = nil,
        glyph: String? = nil
    ) -> Image {
        let lineWidth: CGFloat = 2.5
        return Image(size: CGSize(width: size, height: size), label: label) { context in
            let rect = CGRect(origin: .zero, size: context.clipBoundingRect.size)
                .insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            var track = context
            track.opacity = 0.25
            track.stroke(Path(ellipseIn: rect), with: tint.map { .color($0) } ?? .foreground, style: style)
            if let glyph {
                var symbol = context.resolve(Image(systemName: glyph))
                symbol.shading = tint.map { .color($0) } ?? .foreground
                let box = rect.width / 2
                let scale = min(box / max(1, symbol.size.width), box / max(1, symbol.size.height))
                let drawn = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                context.draw(
                    symbol,
                    in: CGRect(
                        x: rect.midX - drawn.width / 2,
                        y: rect.midY - drawn.height / 2,
                        width: drawn.width,
                        height: drawn.height
                    )
                )
            }
            guard fraction > 0 else { return }
            var arc = Path()
            arc.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: rect.width / 2,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 + 360 * fraction),
                clockwise: false
            )
            context.stroke(arc, with: tint.map { .color($0) } ?? .foreground, style: style)
        }
    }
}
