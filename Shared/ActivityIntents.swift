import AppIntents
import Foundation

/// What the Live Activity buttons ask the app to do. The app registers one at launch (``ActivityIntentRouter``); it
/// owns the engine, which the extension cannot see.
protocol ActivityIntentHandling: AnyObject {
    /// Resumes the persisted workout first when the engine has none, then ends the running rest.
    func skipRest() throws
    /// Resumes first, then moves the running rest by `seconds`; with no rest running (an over rest a cold launch
    /// already forgot), a positive amount starts one from now, as it does on a warm over rest.
    func addRest(seconds: Int) throws
    /// Resumes first, then checks the set with `id` (a no-op when it is gone or already checked).
    func completeSet(id: UUID) throws
    /// Pushes what the action changed to the system (the Live Activity content, the rest notification) and returns once
    /// it has taken it. The intents await this before they return: the system may suspend the app the moment they do,
    /// and a debounced update would never run.
    func flush() async
}

/// Where the intents find the app. `LiveActivityIntent`s run in the **app** process, so the handler is set there; in the
/// extension process it stays nil and `perform()` does nothing.
enum ActivityIntentRouter {
    static var handler: (any ActivityIntentHandling)?

    /// Hops to the main actor, runs `body` on the registered handler, then awaits its ``ActivityIntentHandling/flush()``;
    /// does nothing without a handler. Errors (an empty set refused by the engine, a save failure) are swallowed: a
    /// button in a Live Activity has nowhere to show them, and the activity re-renders from the engine's real state
    /// either way (so the flush runs after a failure too).
    nonisolated static func run(_ body: @MainActor @Sendable (any ActivityIntentHandling) throws -> Void) async {
        await runOnMain(body)
    }

    @MainActor
    private static func runOnMain(_ body: @MainActor @Sendable (any ActivityIntentHandling) throws -> Void) async {
        guard let handler else { return }
        try? body(handler)
        await handler.flush()
    }
}

/// Skip the running rest.
nonisolated struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip rest"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await ActivityIntentRouter.run { try $0.skipRest() }
        return .result()
    }
}

/// Add seconds to the running rest (the Live Activity button passes 30).
nonisolated struct AddRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add rest time"
    static let isDiscoverable = false

    @Parameter(title: "Seconds")
    var seconds: Int

    init() { seconds = 30 }

    init(seconds: Int) { self.seconds = seconds }

    func perform() async throws -> some IntentResult {
        let seconds = seconds
        await ActivityIntentRouter.run { try $0.addRest(seconds: seconds) }
        return .result()
    }
}

/// Check the set the Live Activity points at. The id travels as a string: it is the `WorkoutSet.id` UUID.
nonisolated struct DoneSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Done set"
    static let isDiscoverable = false

    @Parameter(title: "Set")
    var setID: String

    init() { setID = "" }

    init(setID: UUID) { self.setID = setID.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: setID) else { return .result() }
        await ActivityIntentRouter.run { try $0.completeSet(id: id) }
        return .result()
    }
}
