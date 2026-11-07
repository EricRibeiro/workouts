#if DEBUG
    import Foundation
    import OSLog
    import UIKit

    /// `-logHinge`: reports the hinge as the app sees it (a `UIHingeInteraction` on each window), so `duo hinge --app`
    /// can compare the app's truth with the device tool's hinge read (docs/plan-device-tool.md, C.4). Debug builds only.
    ///
    /// Every status change is logged at `.notice` as `hinge status=<name> angle=<whole degrees>` under subsystem
    /// `com.ericribeiro.Workouts`, category `hinge`; `hinge status=unavailable` (no angle) when the window leaves a
    /// hierarchy that provides hinge updates. Names: `unknown`, `closed`, `partiallyOpen`, `fullyOpen`.
    enum HingeLogger {
        private static let logger = Logger(subsystem: "com.ericribeiro.Workouts", category: "hinge")
        private static var observer: NSObjectProtocol?
        private static var installed = Set<ObjectIdentifier>()
        private static var lastStatus: String?

        /// Starts watching windows when the launch arguments contain `-logHinge`; a no-op otherwise.
        @MainActor
        static func installIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-logHinge"), observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeVisibleNotification,
                object: nil,
                queue: .main
            ) { note in
                guard let window = note.object as? UIWindow else { return }
                MainActor.assumeIsolated { install(on: window) }
            }
        }

        @MainActor
        private static func install(on window: UIWindow) {
            guard installed.insert(ObjectIdentifier(window)).inserted else { return }
            window.addInteraction(
                UIHingeInteraction { _, update in
                    log(update.hinge)
                }
            )
        }

        @MainActor
        private static func log(_ hinge: UIHinge?) {
            let status = hinge.map { name($0.status) } ?? "unavailable"
            // The handler also fires on every angle tick; only a status change is a line.
            guard status != lastStatus else { return }
            lastStatus = status
            let message =
                hinge.map { "hinge status=\(status) angle=\(Int(($0.angle * 180 / .pi).rounded()))" }
                ?? "hinge status=\(status)"
            logger.notice("\(message, privacy: .public)")
        }

        private static func name(_ status: UIHinge.Status) -> String {
            switch status {
            case .closed: "closed"
            case .partiallyOpen: "partiallyOpen"
            case .fullyOpen: "fullyOpen"
            default: "unknown"
            }
        }
    }
#endif
