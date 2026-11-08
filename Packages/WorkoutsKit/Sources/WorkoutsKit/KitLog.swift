import Foundation
import os

/// The kit's loggers, one category per area, under the app's subsystem. For failures that are deliberately not shown to the
/// user (a stored blob that no longer decodes reads as "no data") but must not vanish silently.
nonisolated enum KitLog {
    static let subsystem = "com.ericribeiro.Workouts"
    static let health = Logger(subsystem: subsystem, category: "KitHealth")
    static let engine = Logger(subsystem: subsystem, category: "KitEngine")
    static let library = Logger(subsystem: subsystem, category: "KitLibrary")
}
