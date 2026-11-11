import Foundation
import SwiftUI
import Testing
import WorkoutsKit

@testable import Workouts

extension SnapshotTests {
    /// The Live Activity views (compiled into the test bundle from `WorkoutsLiveActivity/`): the expanded Island row,
    /// the compact and minimal presentations, the closed Duo's narrow compact stack and the Lock Screen banner. The
    /// Island is always black, so the Island cases render in dark mode only, on a black shape sized like the system's
    /// region, over a lighter backdrop so the shape shows. The Lock Screen banner is dark in every device appearance (a dark
    /// card and the dark colour scheme pinned by the view), so it is compared in dark and under a light appearance, where
    /// it must stay dark.
    ///
    /// States are built from the real clock, half a second inside the second the timers should show (elapsed 1520.5 s, rest
    /// 74.5 s left), so the system-drawn timers (read once, at render) never flip to a neighbouring second.
    @MainActor
    struct LiveActivitySnapshots {
        private static let dark = SnapshotVariant(name: "dark", colorScheme: .dark, dynamicTypeSize: .large)
        private static let light = SnapshotVariant(name: "large-light", colorScheme: .light, dynamicTypeSize: .large)

        /// The Lock Screen banner's variants: the standard large dark one (`SnapshotVariant.all`) and a light appearance.
        private static let lockScreenVariants: [SnapshotVariant] =
            SnapshotVariant.all.filter { $0.dynamicTypeSize == .large } + [light]

        private static func set(number: Int = 3, isEmpty: Bool = false) -> WorkoutActivitySet {
            WorkoutActivitySet(
                setID: UUID(),
                exerciseName: "Bench Press (Barbell)",
                number: number,
                count: 4,
                weight: 27.5,
                unit: .lb,
                reps: 8,
                isEmpty: isEmpty
            )
        }

        /// Logging: no rest; `elapsed` seconds since the start.
        private static func working(elapsed: TimeInterval = 1_520.5) -> WorkoutActivityState {
            WorkoutActivityState(
                workoutName: "Push Day",
                startedAt: Date.now.addingTimeInterval(-elapsed),
                setsDone: 5,
                setsTotal: 14,
                current: set()
            )
        }

        /// Resting: about 1:15 left of 2:00.
        private static func resting() -> WorkoutActivityState {
            WorkoutActivityState(
                workoutName: "Push Day",
                startedAt: Date.now.addingTimeInterval(-1_520.5),
                restEndsAt: Date.now.addingTimeInterval(74.5),
                restTotal: 120,
                setsDone: 5,
                setsTotal: 14,
                current: set()
            )
        }

        /// The rest ended 6 s ago and the next set is due.
        private static func restOver() -> WorkoutActivityState {
            WorkoutActivityState(
                workoutName: "Push Day",
                startedAt: Date.now.addingTimeInterval(-1_620.5),
                restEndsAt: Date.now.addingTimeInterval(-6),
                restTotal: 120,
                setsDone: 5,
                setsTotal: 14,
                current: set()
            )
        }

        // MARK: Frames

        /// A black Island shape with `content` inside, on a gray backdrop.
        private struct Island<Content: View>: View {
            let width: CGFloat
            let height: CGFloat
            var corner: CGFloat = 44
            @ViewBuilder let content: Content

            var body: some View {
                content
                    .frame(width: width, height: height)
                    .background(.black, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.28))
            }
        }

        /// The expanded Island's one row, as `WorkoutLiveActivity` lays it out: controls leading, the time trailing.
        private struct Expanded: View {
            let state: WorkoutActivityState
            let restOver: Bool

            var body: some View {
                Island(width: 366, height: 84, corner: 40) {
                    HStack(spacing: 8) {
                        ExpandedControlsView(state: state, restOver: restOver)
                        ExpandedTimerView(state: state, restOver: restOver)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }

        /// The compact Island: leading and trailing regions either side of the sensor gap.
        private struct Compact: View {
            let state: WorkoutActivityState
            let restOver: Bool

            var body: some View {
                Island(width: 250, height: 37, corner: 18.5) {
                    HStack(spacing: 0) {
                        CompactLeadingContent(state: state, restOver: restOver, isLimited: false)
                            .frame(width: 44)
                        Spacer(minLength: 0)
                        CompactTrailingContent(state: state, restOver: restOver, isLimited: false)
                            .frame(width: 60)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }

        // MARK: Expanded

        @Test func expandedWorking() {
            Snapshot.assert(
                Expanded(state: Self.working(), restOver: false),
                named: "expanded-working",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        @Test func expandedWorkingHour() {
            Snapshot.assert(
                Expanded(state: Self.working(elapsed: 3_620.5), restOver: false),
                named: "expanded-working-hour",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        @Test func expandedResting() {
            Snapshot.assert(
                Expanded(state: Self.resting(), restOver: false),
                named: "expanded-resting",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        @Test func expandedRestOver() {
            Snapshot.assert(
                Expanded(state: Self.restOver(), restOver: true),
                named: "expanded-rest-over",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        // MARK: Compact and minimal

        @Test func compactWorking() {
            Snapshot.assert(
                Compact(state: Self.working(), restOver: false),
                named: "compact-working",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        @Test func compactRestOver() {
            Snapshot.assert(
                Compact(state: Self.restOver(), restOver: true),
                named: "compact-rest-over",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        /// The closed Duo's narrow, vertical Island: the whole presentation is the leading stack. Only the no-rest case is
        /// snapshotted: while a rest runs (or is over) the stack holds a `ProgressView` ring, which the app-hosted render
        /// draws as an animated activity indicator instead of the widget ring, so it would prove nothing and could flake.
        @Test func limitedWidthWorking() {
            Snapshot.assert(
                Island(width: 56, height: 84, corner: 28) {
                    CompactLeadingContent(state: Self.working(), restOver: false, isLimited: true)
                },
                named: "limited-working",
                variant: Self.dark,
                width: 80,
                engine: .hostedFitting
            )
        }

        /// Same limit as above: only the glyph-only minimal view (no ring) is snapshotted.
        @Test func minimalWorking() {
            Snapshot.assert(
                Island(width: 48, height: 37, corner: 18.5) {
                    MinimalView(state: Self.working(), restOver: false)
                },
                named: "minimal-working",
                variant: Self.dark,
                width: 80,
                engine: .hostedFitting
            )
        }

        // MARK: Lock Screen

        /// The banner over a wallpaper-ish backdrop, tinted like `WorkoutLiveActivity` does.
        private struct Banner: View {
            let state: WorkoutActivityState
            let restOver: Bool

            var body: some View {
                LockScreenActivityView(state: state, restOver: restOver)
                    .background(
                        ActivityStyle.backgroundTint,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .tint(ActivityStyle.accent)
                    .padding(12)
                    .background(Color(white: 0.12))
            }
        }

        @Test(arguments: lockScreenVariants)
        func lockScreenWorking(variant: SnapshotVariant) {
            Snapshot.assert(
                Banner(state: Self.working(), restOver: false),
                named: "lock-working",
                variant: variant,
                engine: .hostedFitting
            )
        }

        @Test(arguments: lockScreenVariants)
        func lockScreenResting(variant: SnapshotVariant) {
            Snapshot.assert(
                Banner(state: Self.resting(), restOver: false),
                named: "lock-resting",
                variant: variant,
                engine: .hostedFitting
            )
        }

        @Test(arguments: [dark, light])
        func lockScreenRestOver(variant: SnapshotVariant) {
            Snapshot.assert(
                Banner(state: Self.restOver(), restOver: true),
                named: "lock-rest-over",
                variant: variant,
                engine: .hostedFitting
            )
        }

        // MARK: Through the builder functions

        /// `WorkoutLiveActivity`'s static presentation functions, the bodies of the `ActivityConfiguration` closures, fed
        /// `(state, isStale)` as WidgetKit does. A stale rest-in-progress state reads as rest over.
        private struct ViaBuilder: View {
            let state: WorkoutActivityState
            let isStale: Bool

            var body: some View {
                Island(width: 366, height: 84, corner: 40) {
                    HStack(spacing: 8) {
                        WorkoutLiveActivity.expandedLeading(state: state, isStale: isStale)
                        WorkoutLiveActivity.expandedTrailing(state: state, isStale: isStale)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }

        private struct CompactViaBuilder: View {
            let state: WorkoutActivityState
            let isStale: Bool

            var body: some View {
                Island(width: 250, height: 37, corner: 18.5) {
                    HStack(spacing: 0) {
                        WorkoutLiveActivity.compactLeading(state: state, isStale: isStale)
                            .frame(width: 44)
                        Spacer(minLength: 0)
                        WorkoutLiveActivity.compactTrailing(state: state, isStale: isStale)
                            .frame(width: 60)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }

        @Test func builderExpandedWorking() {
            Snapshot.assert(
                ViaBuilder(state: Self.working(), isStale: false),
                named: "builder-expanded-working",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        @Test func builderExpandedResting() {
            Snapshot.assert(
                ViaBuilder(state: Self.resting(), isStale: false),
                named: "builder-expanded-resting",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        @Test func builderExpandedStale() {
            Snapshot.assert(
                ViaBuilder(state: Self.resting(), isStale: true),
                named: "builder-expanded-stale",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        @Test func builderExpandedRestOver() {
            Snapshot.assert(
                ViaBuilder(state: Self.restOver(), isStale: false),
                named: "builder-expanded-rest-over",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        @Test func builderCompactWorking() {
            Snapshot.assert(
                CompactViaBuilder(state: Self.working(), isStale: false),
                named: "builder-compact-working",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        @Test func builderCompactStale() {
            Snapshot.assert(
                CompactViaBuilder(state: Self.resting(), isStale: true),
                named: "builder-compact-stale",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        @Test func builderMinimalWorking() {
            Snapshot.assert(
                Island(width: 48, height: 37, corner: 18.5) {
                    WorkoutLiveActivity.minimal(state: Self.working(), isStale: false)
                },
                named: "builder-minimal-working",
                variant: Self.dark,
                width: 80,
                engine: .hostedFitting
            )
        }

        @Test func builderLockScreenWorking() {
            Snapshot.assert(
                WorkoutLiveActivity.lockScreen(state: Self.working(), isStale: false)
                    .background(
                        ActivityStyle.backgroundTint,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .tint(ActivityStyle.accent)
                    .padding(12)
                    .background(Color(white: 0.12)),
                named: "builder-lock-working",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        @Test func builderLockScreenStale() {
            Snapshot.assert(
                WorkoutLiveActivity.lockScreen(state: Self.resting(), isStale: true)
                    .background(
                        ActivityStyle.backgroundTint,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .tint(ActivityStyle.accent)
                    .padding(12)
                    .background(Color(white: 0.12)),
                named: "builder-lock-stale",
                variant: Self.dark,
                engine: .hostedFitting
            )
        }

        /// The ring cases animate outside WidgetKit, so they are only checked for rendering, not pixels.
        @Test func builderRingCasesRender() {
            let resting = Self.resting()
            let views: [AnyView] = [
                AnyView(WorkoutLiveActivity.compactLeading(state: resting, isStale: false)),
                AnyView(WorkoutLiveActivity.compactTrailing(state: resting, isStale: false)),
                AnyView(WorkoutLiveActivity.minimal(state: resting, isStale: false)),
                AnyView(WorkoutLiveActivity.minimal(state: resting, isStale: true)),
                AnyView(WorkoutLiveActivity.lockScreen(state: resting, isStale: false)),
            ]
            for view in views {
                #expect(ImageRenderer(content: view.frame(width: 200, height: 100)).uiImage != nil)
            }
        }

        @Test func builderKeylineTintFollowsStaleness() {
            #expect(WorkoutLiveActivity.keylineTint(state: Self.resting(), isStale: false) == ActivityStyle.accent)
            #expect(WorkoutLiveActivity.keylineTint(state: Self.resting(), isStale: true) == ActivityStyle.ok)
            #expect(WorkoutLiveActivity.keylineTint(state: Self.working(), isStale: true) == ActivityStyle.accent)
        }
    }
}
