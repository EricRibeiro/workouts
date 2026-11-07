import Foundation

/// `-slowLoads <ms>` (Debug builds only): holds the async loads behind the pushed screens (workout detail, the History
/// summary, the exercise detail's derivations, the template preview's last-performed index) for that long, so a UI test
/// can look at the first frame of a push while the content is still loading (PLAN 7b.4). A no-op without the argument and
/// in Release, where the body compiles away.
enum SlowLoads {
    /// Sleeps for the launch argument's milliseconds; returns at once when it is absent. A cancelled task wakes early.
    static func delay() async {
        #if DEBUG
            let milliseconds = UserDefaults.standard.integer(forKey: "slowLoads")
            guard milliseconds > 0 else { return }
            try? await Task.sleep(for: .milliseconds(milliseconds))
        #endif
    }
}
