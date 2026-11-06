import Foundation

/// Why a rest operation was refused.
public nonisolated enum RestTimerError: Error, Equatable, Sendable {
    /// A rest length outside 1...3600 seconds.
    case invalidDuration(Int)
    /// An adjustment other than -10, +10 or +30 seconds.
    case invalidAdjustment(Int)
}

/// The rest countdown as a value over the three persisted fields of the in-progress `Workout` (`restEndsAt`,
/// `restSeconds`, `restSetID`; DECISIONS "Active workout behaviour"). It stores an end date and a total, never a
/// counter: the UI renders `Text(timerInterval:)` from ``endsAt`` and everything here derives from `now`.
///
/// Operations mutate the value and read the injected clock; ``ActiveWorkoutEngine`` writes the result back to the
/// workout and saves.
public struct RestTimer {
    public nonisolated enum State: Equatable, Sendable {
        case idle
        /// Running, or over but not yet forgotten (see ``expiredGraceSeconds``). `setID` is the set whose check
        /// started it; nil for a rest started by hand.
        case running(endsAt: Date, total: Int, setID: UUID?)
    }

    /// The four presets the idle menu always offers; they are never stored as customs.
    public static let defaultPresets = [30, 60, 120, 180]
    /// Allowed rest lengths for a started timer and for a stored custom preset (`rest.ts`).
    public static let durationRange = 1...3600
    /// The only adjustments: -10 s and +10 s in the rest sheet, +30 s everywhere else.
    public static let allowedAdjustments = [-10, 10, 30]
    /// How long an over rest stays visible (pill flashes `0:00`) before ``tick()`` forgets it (`FLASH_MS`).
    public static let expiredGraceSeconds = 3
    /// How late (seconds) a wake-up may be after the rest ended and still buzz. Later means the app was suspended
    /// through the end, and the haptic would be for a rest that ended long ago.
    public static let buzzToleranceSeconds = 2.0

    /// Whether the success haptic should play for a rest ending at `endsAt` when the watcher woke at `wokeAt`.
    public static func shouldBuzz(endsAt: Date, wokeAt: Date) -> Bool {
        wokeAt.timeIntervalSince(endsAt) <= buzzToleranceSeconds
    }

    public private(set) var state: State
    private let now: () -> Date

    public init(state: State = .idle, now: @escaping () -> Date = Date.init) {
        self.state = state
        self.now = now
    }

    /// Reads the persisted fields of `workout`; idle unless both `restEndsAt` and `restSeconds` are set.
    public init(workout: Workout, now: @escaping () -> Date = Date.init) {
        if let endsAt = workout.restEndsAt, let total = workout.restSeconds {
            self.init(state: .running(endsAt: endsAt, total: total, setID: workout.restSetID), now: now)
        } else {
            self.init(state: .idle, now: now)
        }
    }

    // MARK: - Reading

    /// True unless idle (an over rest inside the grace still counts as present).
    public var isActive: Bool { state != .idle }

    /// When the rest ends, nil when idle.
    public var endsAt: Date? {
        if case .running(let endsAt, _, _) = state { return endsAt }
        return nil
    }

    /// The length the rest was started with, adjusted by ``adjust(by:)``; nil when idle.
    public var total: Int? {
        if case .running(_, let total, _) = state { return total }
        return nil
    }

    /// The set whose check started the rest, nil when idle or started by hand.
    public var setID: UUID? {
        if case .running(_, _, let setID) = state { return setID }
        return nil
    }

    /// Seconds left at `date`, never negative; 0 when idle.
    public func remaining(at date: Date) -> TimeInterval {
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(date))
    }

    /// True when a rest exists and its end time has been reached at `date`.
    public func isExpired(at date: Date) -> Bool {
        guard let endsAt else { return false }
        return date >= endsAt
    }

    // MARK: - Operations

    /// Starts a rest of `seconds` from now, replacing any running one.
    /// - Throws: ``RestTimerError/invalidDuration(_:)`` outside 1...3600; nothing changes.
    public mutating func start(seconds: Int, for setID: UUID? = nil) throws {
        guard Self.durationRange.contains(seconds) else { throw RestTimerError.invalidDuration(seconds) }
        state = .running(endsAt: now().addingTimeInterval(TimeInterval(seconds)), total: seconds, setID: setID)
    }

    /// Moves the end by `seconds` (-10, +10 or +30) and the total with it, so the ring keeps its proportions. A rest
    /// whose remaining time would reach 0 ends (`-10 s` clamps at 0). On an already-over rest, `+10`/`+30` restart
    /// from now with just that amount as the total. A no-op when idle.
    /// - Throws: ``RestTimerError/invalidAdjustment(_:)`` for any other amount; nothing changes.
    public mutating func adjust(by seconds: Int) throws {
        guard Self.allowedAdjustments.contains(seconds) else { throw RestTimerError.invalidAdjustment(seconds) }
        guard case .running(let endsAt, let total, let setID) = state else { return }
        let current = now()
        if current >= endsAt {
            if seconds > 0 {
                state = .running(
                    endsAt: current.addingTimeInterval(TimeInterval(seconds)),
                    total: seconds,
                    setID: setID
                )
            } else {
                state = .idle
            }
            return
        }
        let moved = endsAt.addingTimeInterval(TimeInterval(seconds))
        if moved <= current {
            state = .idle
        } else {
            state = .running(endsAt: moved, total: max(1, total + seconds), setID: setID)
        }
    }

    /// ``adjust(by:)``, except that an idle timer starts a rest of `seconds` from now (for no set) when `seconds` is
    /// positive. The notification's "+30 s" and the Live Activity's button use it: on a cold launch the relaunch
    /// restore (``clearIfExpired()``) has already forgotten the over rest they were pressed on, and pressing +30 s
    /// there must do what it does on a warm over rest, which restarts from now. A negative amount on an idle timer
    /// stays a no-op.
    /// - Throws: ``RestTimerError/invalidAdjustment(_:)`` for any other amount; nothing changes.
    public mutating func extendOrRestart(by seconds: Int) throws {
        guard Self.allowedAdjustments.contains(seconds) else { throw RestTimerError.invalidAdjustment(seconds) }
        if state == .idle, seconds > 0 {
            state = .running(endsAt: now().addingTimeInterval(TimeInterval(seconds)), total: seconds, setID: nil)
            return
        }
        try adjust(by: seconds)
    }

    /// Ends the rest now.
    public mutating func skip() {
        state = .idle
    }

    /// Forgets a rest that has been over for more than ``expiredGraceSeconds``. Returns true when it cleared.
    @discardableResult
    public mutating func tick() -> Bool {
        guard let endsAt, now() >= endsAt.addingTimeInterval(TimeInterval(Self.expiredGraceSeconds)) else {
            return false
        }
        state = .idle
        return true
    }

    /// Forgets a rest that is over at all (relaunch restore: the notification already fired). Returns true when it
    /// cleared.
    @discardableResult
    public mutating func clearIfExpired() -> Bool {
        guard isExpired(at: now()) else { return false }
        state = .idle
        return true
    }

    /// Writes the state into the three persisted fields of `workout` (nil when idle). Does not save.
    public func write(to workout: Workout) {
        switch state {
        case .idle:
            workout.restEndsAt = nil
            workout.restSeconds = nil
            workout.restSetID = nil
        case .running(let endsAt, let total, let setID):
            workout.restEndsAt = endsAt
            workout.restSeconds = total
            workout.restSetID = setID
        }
    }

    // MARK: - Custom presets

    /// `presets` after using a rest of `seconds`: newest first, no repeats, at most
    /// ``SettingsStore/maxRestPresets``. The four default presets and values outside 1...3600 leave the list as it
    /// is.
    public static func recording(_ seconds: Int, in presets: [Int]) -> [Int] {
        guard durationRange.contains(seconds), !defaultPresets.contains(seconds) else { return presets }
        let rest = presets.filter { $0 != seconds }
        return Array(([seconds] + rest).prefix(SettingsStore.maxRestPresets))
    }
}

// MARK: - Engine integration

extension ActiveWorkoutEngine {
    /// The rest timer of the in-progress workout (idle without one). Read-only snapshot; operate through the engine.
    public var restTimer: RestTimer {
        guard let workout = liveWorkout else { return RestTimer(now: now) }
        return RestTimer(workout: workout, now: now)
    }

    /// Starts a rest by hand (the ring menu: a preset or a custom), belonging to no set and replacing any running
    /// rest. A custom length (not one of the four defaults) is saved to `SettingsStore.restPresets`, newest first.
    /// - Throws: ``RestTimerError/invalidDuration(_:)``; ``ActiveWorkoutError/noActiveWorkout``.
    public func startRest(seconds: Int) throws {
        let workout = try activeWorkout()
        var timer = restTimer
        try timer.start(seconds: seconds)
        try apply(timer, to: workout)
        settings.restPresets = RestTimer.recording(seconds, in: settings.restPresets)
    }

    /// Moves the running rest by -10, +10 or +30 seconds (see ``RestTimer/adjust(by:)``). No-op without a rest.
    public func adjustRest(by seconds: Int) throws {
        let workout = try activeWorkout()
        var timer = restTimer
        try timer.adjust(by: seconds)
        try apply(timer, to: workout)
    }

    /// ``adjustRest(by:)`` for the background actions (notification "+30 s", Live Activity button): with no rest
    /// running, a positive amount starts a rest of that length from now (see ``RestTimer/extendOrRestart(by:)``).
    /// - Throws: ``RestTimerError/invalidAdjustment(_:)``; ``ActiveWorkoutError/noActiveWorkout``.
    public func extendOrRestartRest(by seconds: Int) throws {
        let workout = try activeWorkout()
        var timer = restTimer
        try timer.extendOrRestart(by: seconds)
        try apply(timer, to: workout)
    }

    /// Ends the rest (Skip).
    public func skipRest() throws {
        let workout = try activeWorkout()
        var timer = restTimer
        timer.skip()
        try apply(timer, to: workout)
    }

    /// Call periodically (or on foreground): forgets a rest that has been over longer than
    /// ``RestTimer/expiredGraceSeconds``. Returns true when it cleared one.
    @discardableResult
    public func tickRest() throws -> Bool {
        let workout = try activeWorkout()
        var timer = restTimer
        guard timer.tick() else { return false }
        try apply(timer, to: workout)
        return true
    }

    /// Writes `timer` into `workout` and saves, only when the persisted fields change.
    func apply(_ timer: RestTimer, to workout: Workout) throws {
        guard timer.state != RestTimer(workout: workout, now: now).state else { return }
        timer.write(to: workout)
        try commit(workout, nil)
    }

    /// `check`: starts the rest of the row's length for `set`, replacing any running one (superset sets too: every
    /// check). 0 = Off starts nothing and leaves a running rest alone. The caller saves.
    func startRest(afterChecking set: WorkoutSet, in row: WorkoutExercise, workout: Workout) throws {
        // nil = Default (follows Settings now, not when the row was made); 0 = Off.
        let seconds = min(row.restSeconds ?? settings.defaultRestSeconds, RestTimer.durationRange.upperBound)
        guard seconds > 0 else { return }
        var timer = restTimer
        try timer.start(seconds: seconds, for: set.id)
        timer.write(to: workout)
    }

    /// Clears the rest when it belongs to one of `setIDs` ("Uncheck cancels the rest that set started"; removing
    /// the sets does the same). A rest started by hand is left running. The caller saves.
    func cancelRest(ownedBy setIDs: Set<UUID>, workout: Workout) {
        guard let id = workout.restSetID, setIDs.contains(id) else { return }
        var timer = restTimer
        timer.skip()
        timer.write(to: workout)
    }
}
