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

extension WorkoutActivityState {
    /// Plain-string accessibility label for the timer: what it measures.
    var timerAccessibilityLabel: String { isResting ? "Rest remaining" : "Workout time" }

    /// Plain-string accessibility value for the timer, computed from the state at render time ("ends at 8:42 PM",
    /// "started at 7:58 PM"). Never a `Text(timerInterval:)` or `.timer`/`.relative` style: SwiftUI encodes accessibility
    /// text for the system, and a resolvable (live-updating) segment in it crashes the extension with an
    /// uncaught NSException in `CodableAttributedString.encode`.
    var timerAccessibilityValue: String {
        if let end = restEndsAt {
            return "ends at \(end.formatted(date: .omitted, time: .shortened))"
        }
        return "started at \(startedAt.formatted(date: .omitted, time: .shortened))"
    }
}

extension View {
    /// Collapses a view that draws a live timer or progress into one accessibility element with static strings. The
    /// visual children (resolvable text, timer-driven `ProgressView`) are ignored, so none of it is ever encoded.
    func activityTimerAccessibility(for state: WorkoutActivityState) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(state.timerAccessibilityLabel)
            .accessibilityValue(state.timerAccessibilityValue)
    }
}

/// The rest countdown, or the elapsed workout time when no rest runs. One accessibility element with static
/// strings; the drawn timer itself is invisible to accessibility.
struct ActivityTimerText: View {
    let state: WorkoutActivityState
    var alignment: TextAlignment = .trailing

    var body: some View {
        Group {
            if let range = state.countdownRange() {
                Text(timerInterval: range, countsDown: true)
            } else {
                Text(state.startedAt, style: .timer)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(alignment)
        .activityTimerAccessibility(for: state)
    }
}

/// Caption under the timer: what the number means.
struct ActivityTimerCaption: View {
    let state: WorkoutActivityState

    var body: some View {
        Text(state.isResting ? "Rest" : "Elapsed")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)  // the timer element's label already says it
    }
}
