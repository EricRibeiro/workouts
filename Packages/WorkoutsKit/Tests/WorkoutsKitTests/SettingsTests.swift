import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct SettingsTests {
    @Test func defaultsOnEmptyBackend() {
        let store = SettingsStore(backend: InMemoryBackend())
        #expect(store.defaultUnit == .lb)
        #expect(store.defaultRestSeconds == 60)
        #expect(store.weeklyGoal == 3)
        #expect(store.e1rmFormula == .epley)
        #expect(store.restPresets.isEmpty)
        #expect(store.keepScreenOn)
        #expect(!store.downloadAllVideos)
        #expect(!store.healthEnrichmentEnabled)
        #expect(store.appearance == .system)
    }

    @Test func writeThroughPersistsAndFreshStoreReadsItBack() {
        let backend = InMemoryBackend()
        let store = SettingsStore(backend: backend)
        store.defaultUnit = .kg
        store.defaultRestSeconds = 120
        store.weeklyGoal = 5
        store.e1rmFormula = .brzycki
        store.restPresets = [45, 150]
        store.keepScreenOn = false
        store.downloadAllVideos = true
        store.healthEnrichmentEnabled = true
        store.appearance = .dark

        #expect(backend.object(forKey: SettingsKey.appearance.rawValue) as? String == "dark")
        #expect(backend.object(forKey: SettingsKey.defaultUnit.rawValue) as? String == "kg")
        #expect(backend.object(forKey: SettingsKey.e1rmFormula.rawValue) as? String == "brzycki")
        #expect(backend.object(forKey: SettingsKey.restPresets.rawValue) as? [Int] == [45, 150])

        let fresh = SettingsStore(backend: backend)
        #expect(fresh.defaultUnit == .kg)
        #expect(fresh.defaultRestSeconds == 120)
        #expect(fresh.weeklyGoal == 5)
        #expect(fresh.e1rmFormula == .brzycki)
        #expect(fresh.restPresets == [45, 150])
        #expect(!fresh.keepScreenOn)
        #expect(fresh.downloadAllVideos)
        #expect(fresh.healthEnrichmentEnabled)
        #expect(fresh.appearance == .dark)
    }

    @Test func everyKeyIsWrittenUnderItsOwnName() {
        let backend = InMemoryBackend()
        let store = SettingsStore(backend: backend)
        store.defaultUnit = .kg
        store.defaultRestSeconds = 60
        store.weeklyGoal = 4
        store.e1rmFormula = .brzycki
        store.restPresets = [30]
        store.keepScreenOn = false
        store.downloadAllVideos = true
        store.healthEnrichmentEnabled = true
        store.appearance = .light
        for key in SettingsKey.allCases {
            #expect(backend.object(forKey: key.rawValue) != nil, "\(key) not written")
        }
        #expect(SettingsKey.allCases.count == 9)
    }

    @Test func invalidStoredValuesFallBack() {
        let backend = InMemoryBackend([
            SettingsKey.defaultUnit.rawValue: "stone",
            SettingsKey.e1rmFormula.rawValue: "lombardi",
            SettingsKey.defaultRestSeconds.rawValue: 99_999,
            SettingsKey.weeklyGoal.rawValue: 0,
            SettingsKey.keepScreenOn.rawValue: "maybe",
            SettingsKey.downloadAllVideos.rawValue: 7.5,
            SettingsKey.restPresets.rawValue: "nope",
            SettingsKey.appearance.rawValue: "sepia",
        ])
        let store = SettingsStore(backend: backend)
        #expect(store.defaultUnit == .lb)
        #expect(store.e1rmFormula == .epley)
        #expect(store.defaultRestSeconds == 60)
        #expect(store.weeklyGoal == 3)
        #expect(store.keepScreenOn)
        #expect(!store.downloadAllVideos)
        #expect(store.restPresets.isEmpty)
        #expect(store.appearance == .system)
    }

    /// Launch arguments (`-defaultRestSeconds 90`, `-keepScreenOn NO`) land in the defaults as strings.
    @Test func numbersAndFlagsAreReadFromLaunchArgumentText() {
        let backend = InMemoryBackend([
            SettingsKey.defaultRestSeconds.rawValue: "90",
            SettingsKey.weeklyGoal.rawValue: "5",
            SettingsKey.keepScreenOn.rawValue: "NO",
            SettingsKey.downloadAllVideos.rawValue: "YES",
            SettingsKey.healthEnrichmentEnabled.rawValue: "1",
        ])
        let store = SettingsStore(backend: backend)
        #expect(store.defaultRestSeconds == 90)
        #expect(store.weeklyGoal == 5)
        #expect(!store.keepScreenOn)
        #expect(store.downloadAllVideos)
        #expect(store.healthEnrichmentEnabled)
        let outOfRange = InMemoryBackend([SettingsKey.defaultRestSeconds.rawValue: "99999"])
        #expect(SettingsStore(backend: outOfRange).defaultRestSeconds == 60)
    }

    @Test func wrongTypedEnumValuesFallBack() {
        let backend = InMemoryBackend([SettingsKey.defaultUnit.rawValue: 3])
        #expect(SettingsStore(backend: backend).defaultUnit == .lb)
        let appearance = InMemoryBackend([SettingsKey.appearance.rawValue: 2])
        #expect(SettingsStore(backend: appearance).appearance == .system)
    }

    @Test func storedRestPresetsAreSanitized() {
        let backend = InMemoryBackend([
            SettingsKey.restPresets.rawValue: [0, 45, 45, 4000, 60, 75, 100, 110, 120, 130, 140]
        ])
        #expect(SettingsStore(backend: backend).restPresets == [45, 60, 75, 100, 110, 120])
    }

    @Test func inMemoryBackendRoundTripsAndClears() {
        let backend = InMemoryBackend(["a": 1])
        #expect(backend.object(forKey: "a") as? Int == 1)
        backend.set("x", forKey: "b")
        #expect(backend.object(forKey: "b") as? String == "x")
        backend.set(nil, forKey: "b")
        #expect(backend.object(forKey: "b") == nil)
    }

    @Test func userDefaultsBackendRoundTrip() throws {
        let suite = "SettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let backend = UserDefaultsBackend(defaults)
        #expect(backend.object(forKey: SettingsKey.weeklyGoal.rawValue) == nil)

        let store = SettingsStore(backend: backend)
        store.weeklyGoal = 6
        store.defaultUnit = .kg
        store.restPresets = [20, 200]
        store.keepScreenOn = false

        let fresh = SettingsStore(backend: UserDefaultsBackend(defaults))
        #expect(fresh.weeklyGoal == 6)
        #expect(fresh.defaultUnit == .kg)
        #expect(fresh.restPresets == [20, 200])
        #expect(!fresh.keepScreenOn)
        #expect(defaults.integer(forKey: SettingsKey.weeklyGoal.rawValue) == 6)
    }
}
