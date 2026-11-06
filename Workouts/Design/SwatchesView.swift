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
        /// For a fill colour: the glyph colour that goes on it. A fill is never text, so its sample shows that pairing
        /// instead of the fill itself as text (which fails contrast by design).
        var onFill: Color?
        var id: String { name }
    }

    private var swatches: [Swatch] {
        [
            Swatch(name: "Accent", color: .accentColor),
            Swatch(name: "Ok", color: .ok),
            Swatch(name: "Ok fill", color: .okFill, onFill: .onOkFill),
            Swatch(name: "Danger", color: .danger),
        ] + SetKind.allCases.map { Swatch(name: "Set kind: \($0.rawValue)", color: $0.color) }
            + (1...6).map { Swatch(name: "Superset \($0)", color: .superset($0)) }
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
                            .foregroundStyle(swatch.onFill ?? swatch.color)
                            .padding(.horizontal, swatch.onFill == nil ? 0 : 6)
                            .background(
                                swatch.onFill == nil ? .clear : swatch.color,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
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
