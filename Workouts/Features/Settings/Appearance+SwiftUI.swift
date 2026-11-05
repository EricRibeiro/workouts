//
//  Appearance+SwiftUI.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

extension Appearance {
    /// `nil` follows the system; the kit's `Appearance` stays free of SwiftUI.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
