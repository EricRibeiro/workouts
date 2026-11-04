//
//  ExercisePickerView.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// Reusable single-select exercise picker for Add and Replace (task 2.1a). Present it in a sheet; on regular width the
/// presenter names `presentationPlacement(.center)`. Tapping a row calls `onPick` and closes the sheet.
///
/// Reads the `ExerciseStore` from the environment. Search, body part and category are kept only while the sheet lives.
struct ExercisePickerView: View {
    let title: String
    let onPick: (ExerciseInfo) -> Void

    @Environment(ExerciseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var bodyPart: String?
    @State private var category: String?

    init(title: String = "Add Exercise", onPick: @escaping (ExerciseInfo) -> Void) {
        self.title = title
        self.onPick = onPick
    }

    var body: some View {
        let results = ExerciseFilter.results(in: store, query: query, bodyPart: bodyPart, category: category)
        NavigationStack {
            List {
                filterRow
                ForEach(results) { info in
                    ExercisePickerRow(info: info, labels: store.catalog.labels) {
                        onPick(info)
                        dismiss()
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search exercises")
            .accessibilityIdentifier("picker.search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("picker.cancel")
                }
            }
        }
        .accessibilityIdentifier("screen.exercisePicker")
    }

    /// The two "Any ..." pills as the first list row, like a chip row.
    private var filterRow: some View {
        HStack(spacing: 8) {
            FilterMenu(
                title: "Body Part",
                anyLabel: "Any Body Part",
                identifier: "picker.filter.bodyPart",
                selection: $bodyPart,
                keys: { ExerciseFilter.bodyParts(in: store.all(), labels: store.catalog.labels) },
                label: { ExerciseFilter.bodyPartLabel($0, labels: store.catalog.labels) }
            )
            FilterMenu(
                title: "Category",
                anyLabel: "Any Category",
                identifier: "picker.filter.category",
                selection: $category,
                keys: { ExerciseFilter.categories(in: store.all(), labels: store.catalog.labels) },
                label: { ExerciseFilter.equipmentLabel($0, labels: store.catalog.labels) }
            )
            Spacer(minLength: 0)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

/// One capsule `Menu` pill with a checkmarked single choice; the first item resets to "Any".
private struct FilterMenu: View {
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
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(selection == nil ? .secondary : .accentColor)
        .accessibilityLabel("\(title): \(current)")
        .accessibilityIdentifier(identifier)
    }
}

private struct PillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title.lineLimit(1)
            configuration.icon.imageScale(.small)
        }
        .font(.subheadline)
    }
}

/// A light row: thumbnail, name, "Body part · Equipment". The whole row is the button.
private struct ExercisePickerRow: View {
    let info: ExerciseInfo
    let labels: LibraryLabels
    let action: () -> Void

    var body: some View {
        let subtitle = ExerciseFilter.subtitle(for: info, labels: labels)
        Button(action: action) {
            HStack(spacing: 12) {
                ExerciseThumbnail(id: info.isCustom ? nil : info.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtitle.isEmpty ? info.name : "\(info.name), \(subtitle)")
        .accessibilityIdentifier("picker.row.\(info.id.uuidString)")
    }
}

/// The bundled start-frame thumbnail, loaded lazily by `AsyncImage`; a symbol stands in when there is none (custom).
struct ExerciseThumbnail: View {
    /// A library exercise id, or nil for a custom exercise.
    let id: UUID?
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 36

    var body: some View {
        Group {
            if let id, let url = Self.media.thumbnailURL(for: id, phase: .start) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.12))
            }
        }
        .frame(width: height * 16 / 9, height: height)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    /// Only the bundled thumbnails are read, so the base URL and cache folder are never used here.
    private static let media = MediaStore(
        baseURL: MediaStore.baseURL(from: .main) ?? URL(filePath: "/"),
        bundle: .main,
        cacheDirectory: .cachesDirectory
    )
}

#if DEBUG
    #Preview {
        PreviewGallery.host("ExercisePicker")
    }
#endif
