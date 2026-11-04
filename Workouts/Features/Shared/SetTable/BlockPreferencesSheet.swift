//
//  BlockPreferencesSheet.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

extension BarType {
    /// The bar's name in pickers.
    var displayName: String {
        switch self {
        case .none: "No bar"
        case .olympic: "Olympic bar (45 lb / 20 kg)"
        case .ez: "EZ bar"
        case .custom: "Custom weight"
        }
    }
}

/// "Preferences…" from a block's header menu (task 3.6): the exercise's weight unit, bar (with the weight of a custom one) and
/// rest timer in a `Form`. Save reports the values and closes; Cancel drops them. Changing the unit does not convert the sets.
struct BlockPreferencesSheet: View {
    struct Values: Equatable {
        var unit: WeightUnit
        var barType: BarType
        var barWeight: Double?
        /// Seconds; nil for Off.
        var restSeconds: Int?
    }

    let exerciseName: String
    let onSave: (Values) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var unit: WeightUnit
    @State private var barType: BarType
    @State private var barWeightText: String
    @State private var rest: Int
    private let restOptions: [Int]

    /// Off (0), then the lengths of `RestTimerPickerSheet`; a current value outside them is kept as a row of its own.
    private static let standardRest = [0, 30, 60, 90, 120, 180, 300]

    init(exerciseName: String, initial: Values, onSave: @escaping (Values) -> Void) {
        self.exerciseName = exerciseName
        self.onSave = onSave
        _unit = State(initialValue: initial.unit)
        _barType = State(initialValue: initial.barType)
        _barWeightText = State(initialValue: initial.barWeight.map { Self.format($0) } ?? "")
        let current = max(initial.restSeconds ?? 0, 0)
        _rest = State(initialValue: current)
        restOptions = Self.standardRest.contains(current) ? Self.standardRest : (Self.standardRest + [current]).sorted()
    }

    /// The custom bar weight as typed: empty, a non-negative number, or something else.
    private enum BarWeight {
        case empty
        case value(Double)
        case invalid
    }

    private var barWeight: BarWeight {
        let text = barWeightText.trimmingCharacters(in: .whitespaces).replacing(",", with: ".")
        if text.isEmpty { return .empty }
        guard let value = Double(text), value >= 0, value.isFinite else { return .invalid }
        return .value(value)
    }

    private var isValid: Bool {
        if barType == .custom, case .invalid = barWeight { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Weight unit", selection: $unit) {
                        ForEach(WeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("preferences.unit")
                    Picker("Bar", selection: $barType) {
                        ForEach(BarType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .accessibilityIdentifier("preferences.bar")
                    if barType == .custom {
                        LabeledContent("Bar weight (\(unit.rawValue))") {
                            TextField("0", text: $barWeightText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel("Bar weight")
                                .accessibilityIdentifier("preferences.barWeight")
                        }
                    }
                    Picker("Rest timer", selection: $rest) {
                        ForEach(restOptions, id: \.self) { Text(Self.restTitle($0)).tag($0) }
                    }
                    .accessibilityIdentifier("preferences.rest")
                } header: {
                    Text(exerciseName)
                } footer: {
                    Text("Changing the unit does not convert the weights already entered.")
                }
            }
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("preferences.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: save)
                        .disabled(!isValid)
                        .accessibilityLabel("Save")
                        .accessibilityIdentifier("preferences.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("preferences.sheet")
    }

    private func save() {
        var weight: Double?
        if barType == .custom, case .value(let value) = barWeight { weight = value }
        onSave(Values(unit: unit, barType: barType, barWeight: weight, restSeconds: rest == 0 ? nil : rest))
        dismiss()
    }

    private static func restTitle(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}
