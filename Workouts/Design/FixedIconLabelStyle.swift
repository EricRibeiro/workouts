//
//  FixedIconLabelStyle.swift
//  Workouts
//

import SwiftUI

/// A label whose icon sits in a fixed-width, centred slot, so stacked labels with different symbols (calendar,
/// medal.fill, flame.fill) start their titles at the same x.
struct FixedIconLabelStyle: LabelStyle {
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth = 22.0

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon
                .frame(width: iconWidth)
            configuration.title
        }
    }
}

extension LabelStyle where Self == FixedIconLabelStyle {
    static var fixedIcon: FixedIconLabelStyle { FixedIconLabelStyle() }
}
