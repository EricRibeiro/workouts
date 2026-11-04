//
//  RestArc.swift
//  Workouts
//

import SwiftUI

/// The thin draining arc both ring items draw (the rest timer's running button and the resume control): a faint track
/// and the remaining fraction from 12 o'clock, clockwise, no digits. Drawn with `Image(size:renderer:)` so the item can
/// stay a `Label` with an `Image` icon, which is what the closed Duo moves into the trailing strip.
enum RestArc {
    static func image(fraction: Double, size: CGFloat, label: Text) -> Image {
        let lineWidth: CGFloat = 2
        return Image(size: CGSize(width: size, height: size), label: label) { context in
            let rect = CGRect(origin: .zero, size: context.clipBoundingRect.size)
                .insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            var track = context
            track.opacity = 0.25
            track.stroke(Path(ellipseIn: rect), with: .foreground, style: style)
            guard fraction > 0 else { return }
            var arc = Path()
            arc.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: rect.width / 2,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 + 360 * fraction),
                clockwise: false
            )
            context.stroke(arc, with: .foreground, style: style)
        }
    }
}
