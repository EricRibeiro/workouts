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

    /// The Live Activity needs the app to opt in; without the key `Activity.request` throws at run time.
    @Test func infoPlistSupportsLiveActivities() {
        #expect(Bundle.main.infoDictionary?["NSSupportsLiveActivities"] as? Bool == true)
    }

    /// The Live Activity widget extension ships inside the app, as a WidgetKit extension.
    @Test func liveActivityExtensionIsEmbeddedAsAWidgetKitExtension() throws {
        let plugIns = try #require(Bundle.main.builtInPlugInsURL)
        let appex = plugIns.appending(path: "WorkoutsLiveActivity.appex")
        let bundle = try #require(Bundle(url: appex), "no WorkoutsLiveActivity.appex in PlugIns")
        let point = (bundle.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
        #expect(point == "com.apple.widgetkit-extension")
    }

    /// The simulator build is ad-hoc signed with no embedded entitlements, so this reads the entitlements file from the
    /// source tree (`#filePath`): the capabilities the app declares for TestFlight, time-sensitive notifications included.
    @Test func entitlementsDeclareTimeSensitiveNotificationsAndCloudKit() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Workouts/Workouts.entitlements")
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(plist["com.apple.developer.usernotifications.time-sensitive"] as? Bool == true)
        #expect(plist["com.apple.developer.healthkit"] as? Bool == true)
        #expect(
            plist["com.apple.developer.icloud-container-identifiers"] as? [String] == [
                "iCloud.com.ericribeiro.Workouts"
            ]
        )
    }
}
