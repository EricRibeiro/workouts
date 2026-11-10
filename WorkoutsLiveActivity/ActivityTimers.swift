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

/// The narrow Island's time line under the glyph: the rest countdown while one runs (accent), else the workout's
/// elapsed time. Both are `Text(timerInterval:)`, so the system ticks them with no ActivityKit pushes. Hours are folded
/// into minutes ("65:20", never "1:05:20") to stay about five characters wide.
///
/// Apple Fitness's "45min" is deliberately not used: it is whole minutes, and the only text the system updates on its
/// own in whole minutes is `SystemFormatStyle.DateOffset`, which renders the words ("45 minutes", "1 hour, 5 minutes";
/// no abbreviation option) and wraps or truncates in this strip. A static "45min" would go stale between activity
/// updates, which the app cannot send while suspended.
struct ActivityCompactTimerText: View {
    let state: WorkoutActivityState

    var body: some View {
        Group {
            if state.isRestRunning(restOver: false), let range = state.countdownRange() {
                Text(timerInterval: range, countsDown: true, showsHours: false)
                    .foregroundStyle(ActivityStyle.accent)
            } else {
                // Counts up from the start; the far end only bounds the range (a year, far beyond any workout).
                Text(
                    timerInterval: state.startedAt...state.startedAt.addingTimeInterval(31_536_000),
                    countsDown: false,
                    showsHours: false
                )
                .foregroundStyle(.primary)
            }
        }
        .font(.caption2.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .multilineTextAlignment(.center)
        .activityTimerAccessibility(for: state)
    }
}
