import Foundation
import Testing

struct AppBundleTests {
    @Test func bundleIdentifierMatchesProject() {
        #expect(Bundle.main.bundleIdentifier == "com.ericribeiro.Workouts")
    }

    @Test func displayNameIsPresent() {
        let displayName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
        #expect(displayName != nil)
        #expect(displayName?.isEmpty == false)
    }
}
