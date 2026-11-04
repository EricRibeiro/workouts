import Foundation
import SwiftData
import Testing

@testable import WorkoutsKit

@MainActor @Suite struct StickyNotesTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let id = UUID()

    init() throws {
        container = try ModelContainer.workouts(inMemory: true, cloudKit: false)
    }

    @Test func noNoteReadsNil() {
        #expect(StickyNotes.text(for: id, in: context) == nil)
    }

    @Test func setTrimsAndReads() throws {
        try StickyNotes.set("  Elbows in \n", for: id, in: context)
        #expect(StickyNotes.text(for: id, in: context) == "Elbows in")
    }

    @Test func setTwiceKeepsOneRow() throws {
        try StickyNotes.set("One", for: id, in: context)
        try StickyNotes.set("Two", for: id, in: context)
        #expect(StickyNotes.text(for: id, in: context) == "Two")
        #expect(try context.fetchCount(FetchDescriptor<StickyNote>()) == 1)
    }

    @Test func blankClears() throws {
        try StickyNotes.set("One", for: id, in: context)
        try StickyNotes.set("   ", for: id, in: context)
        #expect(StickyNotes.text(for: id, in: context) == nil)
        #expect(try context.fetchCount(FetchDescriptor<StickyNote>()) == 0)
    }

    @Test func clearLeavesOtherExercises() throws {
        let other = UUID()
        try StickyNotes.set("Mine", for: id, in: context)
        try StickyNotes.set("Theirs", for: other, in: context)
        try StickyNotes.clear(id, in: context)
        #expect(StickyNotes.text(for: id, in: context) == nil)
        #expect(StickyNotes.text(for: other, in: context) == "Theirs")
    }

    @Test func duplicatesCollapseOnSet() throws {
        context.insert(StickyNote(exerciseID: id, text: "A", updatedAt: Date(timeIntervalSince1970: 1)))
        context.insert(StickyNote(exerciseID: id, text: "B", updatedAt: Date(timeIntervalSince1970: 2)))
        try context.save()
        try StickyNotes.set("C", for: id, in: context)
        #expect(try context.fetchCount(FetchDescriptor<StickyNote>()) == 1)
        #expect(StickyNotes.text(for: id, in: context) == "C")
    }

    @Test func textIsCapped() throws {
        try StickyNotes.set(String(repeating: "x", count: 2500), for: id, in: context)
        #expect(StickyNotes.text(for: id, in: context)?.count == StickyNotes.maxLength)
    }
}
