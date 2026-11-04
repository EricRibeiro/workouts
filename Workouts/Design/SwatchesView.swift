//
//  SwatchesView.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// Every semantic colour with its name, for checking light and dark side by side.
struct SwatchesView: View {
    private struct Swatch: Identifiable {
        let name: String
        let color: Color
        var id: String { name }
    }

    private var swatches: [Swatch] {
        [
            Swatch(name: "Accent", color: .accentColor),
            Swatch(name: "Ok", color: .ok),
            Swatch(name: "Ok fill", color: .okFill),
            Swatch(name: "Danger", color: .danger),
        ] + SetKind.allCases.map { Swatch(name: "Set kind: \($0.rawValue)", color: $0.color) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(swatches) { swatch in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(swatch.color)
                            .frame(height: 64)
                        Text(swatch.name)
                            .font(.subheadline)
                        Text("Aa 135 lb")
                            .font(.headline)
                            .foregroundStyle(swatch.color)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(swatch.name)
                }
            }
            .padding()
        }
        .background(.background)
    }
}

#Preview("Light") {
    SwatchesView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SwatchesView()
        .preferredColorScheme(.dark)
}
