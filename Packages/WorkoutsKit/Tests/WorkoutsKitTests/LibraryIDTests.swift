import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct LibraryIDTests {
    @Test func namespaceIsPinned() {
        #expect(LibraryID.namespace.uuidString == "F10FF714-3B99-4302-9CBC-74E1768044BE")
    }

    /// Cross-checked against Python's `uuid.uuid5` and the id `scripts/build-library` writes to `library.json`.
    @Test func pinnedValue() {
        let id = LibraryID.id(source: "smartworkout", sourceID: "01259ee3-bdff-47c4-b7dc-e5283ea89e01")
        #expect(id.uuidString == "E099A38C-550B-5FB7-840A-02A19A2E9BDA")
    }

    @Test func isDeterministicAndDistinguishesInputs() {
        let a = LibraryID.id(source: "smartworkout", sourceID: "abc")
        #expect(a == LibraryID.id(source: "smartworkout", sourceID: "abc"))
        #expect(a != LibraryID.id(source: "smartworkout", sourceID: "abd"))
        #expect(a != LibraryID.id(source: "other", sourceID: "abc"))
    }

    @Test func setsVersion5AndRFC4122Variant() {
        for sourceID in ["a", "b", "01259ee3-bdff-47c4-b7dc-e5283ea89e01", ""] {
            let bytes = LibraryID.id(source: "smartworkout", sourceID: sourceID).uuid
            #expect(bytes.6 >> 4 == 0x5)
            #expect(bytes.8 >> 6 == 0b10)
        }
    }
}
