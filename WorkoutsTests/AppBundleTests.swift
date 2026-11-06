import AVFAudio
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

    /// The app (the test host) mixes with other audio, so a silent exercise video never pauses the person's music.
    @Test func audioSessionMixesWithOtherAudio() {
        let session = AVAudioSession.sharedInstance()
        #expect(session.category == .ambient)
        #expect(session.categoryOptions.contains(.mixWithOthers))
    }
}
