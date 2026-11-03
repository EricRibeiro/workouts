import Foundation
import SwiftData

/// A note that belongs to an exercise (library or custom) and follows it into every template and workout.
/// One per `exerciseID`, enforced by the app (CloudKit forbids unique constraints).
@Model
public final class StickyNote {
    public var id: UUID = UUID()
    public var exerciseID: UUID = UUID()
    public var text: String = ""
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(), exerciseID: UUID = UUID(), text: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.exerciseID = exerciseID
        self.text = text
        self.updatedAt = updatedAt
    }
}
