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
    /// Whether the views show "rest over": the activity went stale at ``restEndsAt`` (the system re-renders then, with
    /// the app suspended) or the end has already passed at render time. False when no rest exists.
    func isRestOver(stale: Bool) -> Bool {
        restEndsAt != nil && (stale || isRestOver(at: .now))
    }

    /// A rest is counting down: one exists and it is not over.
    func isRestRunning(restOver: Bool) -> Bool { isResting && !restOver }

    /// Plain-string accessibility label for the timer: what it measures.
    func timerAccessibilityLabel(restOver: Bool) -> String {
        isRestRunning(restOver: restOver) ? "Rest remaining" : "Workout time"
    }

    /// Plain-string accessibility value for the timer, computed from the state at render time ("ends at 8:42 PM",
    /// "started at 7:58 PM"). Never a `Text(timerInterval:)` or `.timer`/`.relative` style: SwiftUI encodes accessibility
    /// text for the system, and a resolvable (live-updating) segment in it crashes the extension with an
    /// uncaught NSException in `CodableAttributedString.encode`.
    func timerAccessibilityValue(restOver: Bool) -> String {
        if isRestRunning(restOver: restOver), let end = restEndsAt {
            return "ends at \(end.formatted(date: .omitted, time: .shortened))"
        }
        return "started at \(startedAt.formatted(date: .omitted, time: .shortened))"
    }
}

extension View {
    /// Collapses a view that draws a live timer or progress into one accessibility element with static strings. The
    /// visual children (resolvable text, timer-driven `ProgressView`) are ignored, so none of it is ever encoded.
    func activityTimerAccessibility(for state: WorkoutActivityState, restOver: Bool = false) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(state.timerAccessibilityLabel(restOver: restOver))
            .accessibilityValue(state.timerAccessibilityValue(restOver: restOver))
    }
}

/// The rest countdown while one runs, else the elapsed workout time (also once the rest is over, which the rest of
/// the view says in words). One accessibility element with static strings; the drawn timer itself is invisible to
/// accessibility.
struct ActivityTimerText: View {
    let state: WorkoutActivityState
    var restOver = false
    var alignment: TextAlignment = .trailing

    var body: some View {
        Group {
            if state.isRestRunning(restOver: restOver), let range = state.countdownRange() {
                Text(timerInterval: range, countsDown: true)
            } else {
                Text(state.startedAt, style: .timer)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(alignment)
        .activityTimerAccessibility(for: state, restOver: restOver)
    }
}

/// Caption under the timer: what the number means.
struct ActivityTimerCaption: View {
    let state: WorkoutActivityState
    var restOver = false

    var body: some View {
        Text(state.isRestRunning(restOver: restOver) ? "Rest" : "Elapsed")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)  // the timer element's label already says it
    }
}
