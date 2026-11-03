import Foundation
import Observation

/// The one settings key list (DECISIONS "Data and sync"). Raw values are the storage keys.
public nonisolated enum SettingsKey: String, CaseIterable, Sendable {
    case defaultUnit
    case defaultRestSeconds
    case weeklyGoal
    case e1rmFormula
    case restPresets
    case keepScreenOn
    case downloadAllVideos
}

/// App settings, outside SwiftData. Loads from the backend on init; every property writes through on change. Stored
/// values that are missing, of the wrong type, or out of range (data-model.md "Settings") fall back to the default.
@Observable
public final class SettingsStore {
    public static let defaultUnitDefault: WeightUnit = .lb
    public static let defaultRestSecondsDefault = 90
    public static let weeklyGoalDefault = 3
    public static let e1rmFormulaDefault: E1RMFormula = .epley
    public static let restPresetsDefault: [Int] = []
    public static let keepScreenOnDefault = true
    public static let downloadAllVideosDefault = false

    /// Most custom rest presets kept.
    public static let maxRestPresets = 6

    @ObservationIgnored private let backend: any SettingsBackend

    public var defaultUnit: WeightUnit {
        didSet { backend.set(defaultUnit.rawValue, forKey: SettingsKey.defaultUnit.rawValue) }
    }

    /// Seconds, 0-3600.
    public var defaultRestSeconds: Int {
        didSet { backend.set(defaultRestSeconds, forKey: SettingsKey.defaultRestSeconds.rawValue) }
    }

    /// Workouts per week, 1-14.
    public var weeklyGoal: Int {
        didSet { backend.set(weeklyGoal, forKey: SettingsKey.weeklyGoal.rawValue) }
    }

    public var e1rmFormula: E1RMFormula {
        didSet { backend.set(e1rmFormula.rawValue, forKey: SettingsKey.e1rmFormula.rawValue) }
    }

    /// Custom rest durations in seconds, newest first: at most 6 distinct values, each 1-3600.
    public var restPresets: [Int] {
        didSet { backend.set(restPresets, forKey: SettingsKey.restPresets.rawValue) }
    }

    public var keepScreenOn: Bool {
        didSet { backend.set(keepScreenOn, forKey: SettingsKey.keepScreenOn.rawValue) }
    }

    /// Wi-Fi only (`media.md`).
    public var downloadAllVideos: Bool {
        didSet { backend.set(downloadAllVideos, forKey: SettingsKey.downloadAllVideos.rawValue) }
    }

    public init(backend: any SettingsBackend = UserDefaultsBackend()) {
        self.backend = backend

        func raw<T: RawRepresentable>(_ key: SettingsKey, as _: T.Type, default fallback: T) -> T
        where T.RawValue == String {
            (backend.object(forKey: key.rawValue) as? String).flatMap(T.init(rawValue:)) ?? fallback
        }
        func int(_ key: SettingsKey, in range: ClosedRange<Int>, default fallback: Int) -> Int {
            guard let value = backend.object(forKey: key.rawValue) as? Int, range.contains(value) else {
                return fallback
            }
            return value
        }

        defaultUnit = raw(.defaultUnit, as: WeightUnit.self, default: Self.defaultUnitDefault)
        defaultRestSeconds = int(.defaultRestSeconds, in: 0...3600, default: Self.defaultRestSecondsDefault)
        weeklyGoal = int(.weeklyGoal, in: 1...14, default: Self.weeklyGoalDefault)
        e1rmFormula = raw(.e1rmFormula, as: E1RMFormula.self, default: Self.e1rmFormulaDefault)
        restPresets = Self.sanitizedPresets(backend.object(forKey: SettingsKey.restPresets.rawValue))
        keepScreenOn = backend.object(forKey: SettingsKey.keepScreenOn.rawValue) as? Bool ?? Self.keepScreenOnDefault
        downloadAllVideos =
            backend.object(forKey: SettingsKey.downloadAllVideos.rawValue) as? Bool ?? Self.downloadAllVideosDefault
    }

    /// Keeps the valid (1-3600), distinct entries in order, at most 6; anything that is not `[Int]` becomes `[]`.
    static func sanitizedPresets(_ stored: Any?) -> [Int] {
        guard let stored = stored as? [Int] else { return Self.restPresetsDefault }
        var seen = Set<Int>()
        let valid = stored.filter { (1...3600).contains($0) && seen.insert($0).inserted }
        return Array(valid.prefix(Self.maxRestPresets))
    }
}
