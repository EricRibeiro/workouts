import Foundation

/// Minimal key-value storage under `SettingsStore`: `UserDefaults` now, `NSUbiquitousKeyValueStore` if a second device
/// appears (DECISIONS "Data and sync"). Values are property-list types (`String`, `Int`, `Bool`, `[Int]`).
public protocol SettingsBackend {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

/// `UserDefaults`-backed storage. Inject a `UserDefaults(suiteName:)` in tests.
public struct UserDefaultsBackend: SettingsBackend {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func object(forKey key: String) -> Any? {
        defaults.object(forKey: key)
    }

    public func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

/// Dictionary-backed storage for tests and previews. A reference type so a "fresh store on the same backend" sees
/// earlier writes.
public final class InMemoryBackend: SettingsBackend {
    private var values: [String: Any]

    public init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    public func object(forKey key: String) -> Any? {
        values[key]
    }

    public func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }
}
