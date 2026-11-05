//
//  StartWorkoutFlow.swift
//  Workouts
//

import SwiftUI
import WorkoutsKit

/// Starting a workout while one may already run (`workout.md` section 3, Preview; `active-workout.md` section 3, "Start
/// while one runs"). Start Workout on a template and Empty Workout both go through ``begin(_:engine:errors:present:)``:
/// with nothing running the workout starts and ``present`` opens its cover; with one running the "Workout in progress"
/// dialog asks whether to resume it or discard it and start the new one. Nothing is ever discarded without that choice.
@Observable
final class StartWorkoutFlow {
    /// What the person asked to start.
    enum Source {
        case empty
        case template(Template)
    }

    /// The question being asked: what was requested, and the name of the workout in the way.
    struct Blocked: Identifiable {
        let id = UUID()
        let source: Source
        let runningName: String
    }

    fileprivate var blocked: Blocked?
    /// Counts started workouts; drives the `.impact` haptic.
    fileprivate(set) var startCount = 0
    /// Counts discards of the running workout; drives the `.warning` haptic on the dialog's owner.
    fileprivate(set) var discardCount = 0

    private var engine: ActiveWorkoutEngine?
    private var errors: SaveErrors?
    private var present: () -> Void = {}

    /// Starts `source`, or asks first when a workout is already running. `present` runs once a workout is behind the
    /// cover (a started one, or the one the person chose to resume).
    func begin(
        _ source: Source,
        engine: ActiveWorkoutEngine?,
        errors: SaveErrors?,
        present: @escaping () -> Void
    ) {
        guard let engine else { return }
        self.engine = engine
        self.errors = errors
        self.present = present
        if let running = engine.workout {
            blocked = Blocked(source: source, runningName: running.name)
        } else {
            start(source)
        }
    }

    fileprivate func resume() {
        present()
    }

    fileprivate func discardAndStart(_ source: Source) {
        guard let engine else { return }
        do {
            try engine.discard()
            discardCount += 1
        } catch {
            errors?.report(error)
            return
        }
        start(source)
    }

    private func start(_ source: Source) {
        guard let engine else { return }
        do {
            switch source {
            case .empty: try engine.startEmpty()
            case .template(let template): try engine.start(from: template)
            }
        } catch {
            errors?.report(error)
        }
        // Never present the cover without a workout behind it (a failed start would leave a dead end).
        guard engine.workout != nil else { return }
        startCount += 1
        present()
    }
}

extension View {
    /// Presents the "Workout in progress" dialog driven by `flow`.
    func startWorkoutFlow(_ flow: StartWorkoutFlow) -> some View {
        modifier(StartWorkoutDialog(flow: flow))
    }
}

private struct StartWorkoutDialog: ViewModifier {
    @Bindable var flow: StartWorkoutFlow

    func body(content: Content) -> some View {
        content
            // An alert, not a dialog: starts come from a menu item, a template card's menu and a preview sheet, none of
            // which is on screen by then, so a popover's arrow would have nothing to point at.
            .alert(
                "Workout in progress",
                isPresented: Binding(get: { flow.blocked != nil }, set: { if !$0 { flow.blocked = nil } }),
                presenting: flow.blocked
            ) { blocked in
                Button("Resume Workout") { flow.resume() }
                    .accessibilityIdentifier("start.resume")
                Button("Discard and Start New", role: .destructive) { flow.discardAndStart(blocked.source) }
                    .accessibilityIdentifier("start.discardAndStart")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("start.cancel")
            } message: { blocked in
                Text(
                    "You are in the middle of “\(blocked.runningName)”. Resume it, or discard it and start the new one."
                )
            }
            .sensoryFeedback(.impact, trigger: flow.startCount)
            .sensoryFeedback(.warning, trigger: flow.discardCount)
    }
}
