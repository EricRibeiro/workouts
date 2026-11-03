//
//  ContentView.swift
//  Workouts
//
//  Created by Eric Ribeiro on 2026-11-03.
//

import SwiftUI
import WorkoutsKit

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Text("WorkoutsKit \(WorkoutsKit.version)")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
