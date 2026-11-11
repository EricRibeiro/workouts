import Testing

@testable import WorkoutsKit

@Suite struct SetProgressTests {
    @Test func nextIndexIsTheFirstUnchecked() {
        #expect(SetProgress(checked: [false, false, false]).nextIndex == 0)
        #expect(SetProgress(checked: [true, true, false]).nextIndex == 2)
        #expect(SetProgress(checked: [true, false, true, false]).nextIndex == 1)
        #expect(SetProgress(checked: [true, true]).nextIndex == nil)
        #expect(SetProgress(checked: []).nextIndex == nil)
    }
}
