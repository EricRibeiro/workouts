//
//  RingProgressStyle.swift
//  Workouts
//

import SwiftUI

/// A circular ring that shows `fractionCompleted` as an arc starting at 12 o'clock over a faint full track, with the
/// progress view's current-value label centred inside. Fed `remaining / total` it shrinks like Clock's timer ring.
///
/// Custom on purpose: the system circular style crashed the preview shell once layout modifiers were applied here.
struct RingProgressStyle: ProgressViewStyle {
    var lineWidth: CGFloat = 3
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(1, max(0, configuration.fractionCompleted ?? 0))
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            configuration.currentValueLabel
        }
        .padding(lineWidth / 2)
    }
}
