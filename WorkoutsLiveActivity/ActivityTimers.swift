import SwiftUI
import WorkoutsKit

/// Dates the views need from a ``WorkoutActivityState``. Every timer is rendered by the system from these dates, never
/// from a counter, and ranges are clamped so a rest that already ended (the app is suspended and cannot update) shows
/// 0:00 instead of trapping on an inverted range.
extension WorkoutActivityState {
    /// `now...restEndsAt`, collapsed to `now...now` (0:00) once the rest is over; nil when no rest runs.
    func countdownRange(now: Date = .now) -> ClosedRange<Date>? {
        guard let end = restEndsAt else { return nil }
        return now...max(now, end)
    }

    /// The whole rest, start to end, for the progress ring. Falls back to 60 s when the total is unknown.
    func restRange() -> ClosedRange<Date>? {
        guard let end = restEndsAt else { return nil }
        let total = TimeInterval(max(1, restTotal ?? 60))
        return end.addingTimeInterval(-total)...end
    }
}

/// The rest countdown, or the elapsed workout time when no rest runs.
struct ActivityTimerText: View {
    let state: WorkoutActivityState
    var alignment: TextAlignment = .trailing

    var body: some View {
        Group {
            if let range = state.countdownRange() {
                Text(timerInterval: range, countsDown: true)
                    .accessibilityLabel("Rest remaining")
            } else {
                Text(state.startedAt, style: .timer)
                    .accessibilityLabel("Workout time")
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(alignment)
    }
}

/// Caption under the timer: what the number means.
struct ActivityTimerCaption: View {
    let state: WorkoutActivityState

    var body: some View {
        Text(state.isResting ? "Rest" : "Elapsed")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
