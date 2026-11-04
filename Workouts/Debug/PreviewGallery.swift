//
//  PreviewGallery.swift
//  Workouts
//

#if DEBUG
    import SwiftData
    import SwiftUI
    import WorkoutsKit

    /// A named screen the gallery can host. The raw value is the name passed as `-preview <Name>`.
    enum GalleryEntry: String, CaseIterable, Identifiable {
        case gallery = "Gallery"
        case root = "Root"
        case history = "History"
        case workout = "Workout"
        case exercises = "Exercises"
        case settings = "Settings"
        case activeWorkoutCover = "ActiveWorkoutCover"
        case swatches = "Swatches"

        var id: String { rawValue }

        /// Every entry except the index itself.
        static var browsable: [GalleryEntry] { allCases.filter { $0 != .gallery } }

        @ViewBuilder
        var view: some View {
            switch self {
            case .gallery: GalleryIndex()
            case .root: RootView()
            case .history: HistoryView()
            case .workout: WorkoutView()
            case .exercises: ExercisesView()
            case .settings: SettingsView()
            case .activeWorkoutCover: ActiveWorkoutCover(minimise: {})
            case .swatches: SwatchesView()
            }
        }
    }

    /// Debug root chosen by the launch argument `-preview <Name>`: hosts the same views as the `#Preview`s on the
    /// sample container (built once). Register every new screen as a `GalleryEntry` in the same change.
    enum PreviewGallery {
        /// The name following `-preview` in the launch arguments, if any.
        static func requestedName(in arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
            guard let index = arguments.firstIndex(of: "-preview"), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        /// The one sample container every entry shares.
        private static let container = Result { try ModelContainer.preview(catalog: LibraryCatalog.bundled(in: .main)) }

        @ViewBuilder
        static func host(_ name: String) -> some View {
            switch container {
            case .failure(let error):
                ContentUnavailableView(
                    "Could not build the sample container",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            case .success(let container):
                if let entry = GalleryEntry(rawValue: name) {
                    entry.view.modelContainer(container)
                } else {
                    ContentUnavailableView(
                        "Unknown preview \"\(name)\"",
                        systemImage: "questionmark.square.dashed",
                        description: Text(
                            "Valid names: " + GalleryEntry.allCases.map(\.rawValue).joined(separator: ", ")
                        )
                    )
                    .accessibilityIdentifier("gallery.unknown")
                }
            }
        }
    }

    /// Browsable list of every gallery entry (`-preview Gallery`).
    struct GalleryIndex: View {
        var body: some View {
            NavigationStack {
                List(GalleryEntry.browsable) { entry in
                    NavigationLink(entry.rawValue) {
                        entry.view
                    }
                    .accessibilityIdentifier("gallery.\(entry.rawValue)")
                }
                .navigationTitle("Gallery")
            }
            .accessibilityIdentifier("screen.gallery")
        }
    }

    #Preview {
        PreviewGallery.host("Gallery")
    }
#endif
