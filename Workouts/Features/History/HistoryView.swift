//
//  HistoryView.swift
//  Workouts
//

import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Workouts Yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("Finished workouts will appear here.")
            )
            .navigationTitle("History")
        }
        .accessibilityIdentifier("screen.history")
    }
}

#Preview {
    HistoryView()
}
