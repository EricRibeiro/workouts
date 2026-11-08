#if DEBUG
    import SwiftUI

    /// The read side of the Health fixture's lookup counter (`-uiTesting` only): a zero-size, non-hittable accessibility
    /// element in the root overlay, identifier `debug.health.lookups`, value the number of `workouts(in:)` lookups the
    /// fixture source has answered. A test asserts `0` to prove a lookup never ran, however slow it would have been.
    private struct HealthLookupProbe: ViewModifier {
        func body(content: Content) -> some View {
            if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                content.overlay {
                    // The count changes off the main actor without any observed property changing.
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        Color.clear
                            .frame(width: 0, height: 0)
                            .allowsHitTesting(false)
                            .accessibilityElement()
                            .accessibilityIdentifier("debug.health.lookups")
                            .accessibilityLabel("Health lookups")
                            .accessibilityValue(String(HealthFixtureLookups.count))
                    }
                }
            } else {
                content
            }
        }
    }

    extension View {
        /// Hosts the `debug.health.lookups` probe; a no-op outside `-uiTesting`.
        func healthLookupProbe() -> some View {
            modifier(HealthLookupProbe())
        }
    }
#endif
