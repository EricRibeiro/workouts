import Testing
@testable import WorkoutsKit

struct WorkoutsKitTests {
    @Test func versionString() {
        #expect(WorkoutsKit.version == "0.1.0")
    }
}
