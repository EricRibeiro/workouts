//
//  FilterMenu.swift
//  Workouts
//

import SwiftUI

/// One capsule `Menu` pill with a checkmarked single choice; the first item resets to "Any".
struct FilterMenu: View {
    let title: String
    let anyLabel: String
    let identifier: String
    @Binding var selection: String?
    let keys: () -> [String]
    let label: (String) -> String

    var body: some View {
        let current = selection.map(label) ?? anyLabel
        Menu {
            Picker(title, selection: $selection) {
                Text(anyLabel).tag(String?.none)
                ForEach(keys(), id: \.self) { key in
                    Text(label(key)).tag(Optional(key))
                }
            }
        } label: {
            Label(current, systemImage: "chevron.up.chevron.down")
                .labelStyle(PillLabelStyle())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(selection == nil ? .secondary : .accentColor)
        .accessibilityLabel("\(title): \(current)")
        .accessibilityIdentifier(identifier)
    }
}

private struct PillLabelStyle: LabelStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title.lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            configuration.icon.imageScale(.small)
        }
        .font(.subheadline)
    }
}
