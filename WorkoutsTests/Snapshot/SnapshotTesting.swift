import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Workouts

/// One rendering of a view: a colour scheme at a Dynamic Type size. Its `name` is the reference file's suffix.
struct SnapshotVariant: Sendable, CustomTestStringConvertible {
    let name: String
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize

    var testDescription: String { name }

    /// UIKit's category for `dynamicTypeSize`, set on hosted windows so the real-window path matches the SwiftUI environment.
    var contentSizeCategory: UIContentSizeCategory {
        switch dynamicTypeSize {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }

    /// Default size and the accessibility size the app's own previews check, each in light and dark.
    static let all: [SnapshotVariant] = [
        SnapshotVariant(name: "large-light", colorScheme: .light, dynamicTypeSize: .large),
        SnapshotVariant(name: "large-dark", colorScheme: .dark, dynamicTypeSize: .large),
        SnapshotVariant(name: "ax3-light", colorScheme: .light, dynamicTypeSize: .accessibility3),
        SnapshotVariant(name: "ax3-dark", colorScheme: .dark, dynamicTypeSize: .accessibility3),
    ]
}

/// Pixel-compares a SwiftUI view against a reference PNG in `WorkoutsTests/__Snapshots__/<Suite>/<name>-<variant>.png`.
///
/// - Plain components render with `ImageRenderer` (`.image`) at scale 3: the width is proposed and the height left
///   natural, on a system background, so clipping and truncation show up as pixels. `ImageRenderer` cannot draw
///   UIKit-backed views (`TextField` and `List` come out as yellow placeholders, `NavigationStack` can trap on teardown),
///   so views holding any of those use `.hostedFitting` (a real window, height from the content) or `.hosted(height:)`
///   (a fixed-size screen) via `UIHostingController`.
/// - A pixel differs when any channel is off by more than 8/255; the snapshot passes with at most 0.05% differing
///   pixels. Renders on one simulator are identical in practice, so the slack only covers antialiasing noise; a changed
///   digit or a moved or clipped label is well over it (0.5% hid a one-character change in a large component).
/// - A mismatch or a missing reference writes `<name>-<variant>.actual.png` next to the reference (git-ignored) and
///   fails. `SNAPSHOT_RECORD=1 ./dev test <Suite>` writes the references instead and fails once per image, so a recording
///   run is never green by accident.
@MainActor
enum Snapshot {
    enum Engine {
        case image
        case hostedFitting
        case hosted(height: CGFloat)
    }

    static let scale: CGFloat = 3
    static let channelThreshold = 8
    static let maxDifferingFraction = 0.0005

    /// True when the runner was given `SNAPSHOT_RECORD` (`./dev test` forwards it as `TEST_RUNNER_SNAPSHOT_RECORD`).
    static var isRecording: Bool {
        let value = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] ?? ""
        return !value.isEmpty && value != "0"
    }

    /// `WorkoutsTests/`, found from this file's own path (the simulator reads the host file system).
    private static let testsDirectory = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Renders `view` in `variant` and compares it with the reference named `name`. The suite folder is the calling file's
    /// name, so the file `SnapshotExerciseRowTests.swift` records under `__Snapshots__/SnapshotExerciseRowTests/`.
    static func assert<Content: View>(
        _ view: Content,
        named name: String,
        variant: SnapshotVariant,
        width: CGFloat = 390,
        engine: Engine = .image,
        environment: SampleEnvironment? = nil,
        filePath: String = #filePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let png = render(view, variant: variant, width: width, engine: engine, environment: environment) else {
            Issue.record("Could not render \(name)-\(variant.name)", sourceLocation: sourceLocation)
            return
        }
        assert(png: png, named: name, variant: variant, filePath: filePath, sourceLocation: sourceLocation)
    }

    /// Compares (or records) an already rendered PNG against the reference `name`-`variant`; see `assert(_:named:...)`.
    static func assert(
        png: Data,
        named name: String,
        variant: SnapshotVariant,
        excludingTop topPoints: CGFloat = 0,
        filePath: String = #filePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let suite = URL(filePath: filePath).deletingPathExtension().lastPathComponent
        let directory = testsDirectory.appending(path: "__Snapshots__").appending(path: suite)
        let reference = directory.appending(path: "\(name)-\(variant.name).png")
        let actual = directory.appending(path: "\(name)-\(variant.name).actual.png")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if isRecording {
                try png.write(to: reference)
                try? FileManager.default.removeItem(at: actual)
                Issue.record(
                    "Recorded \(reference.path()). Re-run without SNAPSHOT_RECORD to compare.",
                    sourceLocation: sourceLocation
                )
                return
            }
            guard let expected = try? Data(contentsOf: reference) else {
                try png.write(to: actual)
                Issue.record(
                    "No reference at \(reference.path()). Actual written to \(actual.path()); record with SNAPSHOT_RECORD=1.",
                    sourceLocation: sourceLocation
                )
                return
            }
            if let problem = difference(between: png, and: expected, excludingTop: topPoints) {
                try png.write(to: actual)
                let message: String =
                    "\(name)-\(variant.name) differs from its reference: \(problem). "
                    + "Reference \(reference.path()), actual \(actual.path())."
                Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
            } else {
                try? FileManager.default.removeItem(at: actual)
            }
        } catch {
            Issue.record("Snapshot file error for \(name)-\(variant.name): \(error)", sourceLocation: sourceLocation)
        }
    }

    // MARK: Rendering

    static func render<Content: View>(
        _ view: Content,
        variant: SnapshotVariant,
        width: CGFloat,
        engine: Engine,
        environment: SampleEnvironment?
    ) -> Data? {
        let content = frame(view, variant: variant, width: width, environment: environment)
        switch engine {
        case .image: return renderImage(content, width: width)
        case .hostedFitting:
            guard let hosted = host(content, variant: variant, width: width, height: nil) else {
                return nil
            }
            // Lists and navigation bars populate on the next run loop turns. The main actor is held meanwhile, so
            // nothing MainActor-isolated (a `.task`) runs: use `renderSettling` for a view that loads data.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
            return capture(hosted)
        case .hosted(let height):
            guard let hosted = host(content, variant: variant, width: width, height: height) else {
                return nil
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
            return capture(hosted)
        }
    }

    /// Like `render` with `.hosted(height:)`, but waits `settle` by suspending (`Task.sleep`) instead of spinning the run
    /// loop, so the view's own `.task` loads run and land before the frame is drawn.
    static func renderSettling<Content: View>(
        _ view: Content,
        variant: SnapshotVariant,
        width: CGFloat,
        height: CGFloat,
        environment: SampleEnvironment?,
        settle: Duration
    ) async -> Data? {
        let content = frame(view, variant: variant, width: width, environment: environment)
        guard let hosted = host(content, variant: variant, width: width, height: height) else {
            return nil
        }
        try? await Task.sleep(for: settle)
        return capture(hosted)
    }

    /// A hosted frame drawn twice: `atSettle` is the draw after the fixed settle (what `renderSettling` returns, spinner
    /// phase and all), `stable` the first later draw whose bar matches the draw before it.
    struct SettledFrames {
        let atSettle: Data
        let stable: Data
    }

    /// Like `renderSettling`, then keeps drawing the hosted frame every `interval` until its top `topPoints` (the bar) are
    /// pixel-identical in two consecutive draws. The bar's Liquid Glass and its toolbar items animate on their own clock
    /// (475 px of the bar still change between the draws at 1.0 s and 1.25 s after the window appears), so a fixed sleep
    /// can capture them mid-animation, depending on machine load. Fails (and returns the last draw) if the bar has not
    /// stopped after `limit`, so a never-settling bar is reported instead of compared.
    static func renderSettled<Content: View>(
        _ view: Content,
        variant: SnapshotVariant,
        width: CGFloat,
        height: CGFloat,
        environment: SampleEnvironment?,
        settle: Duration,
        topPoints: CGFloat,
        interval: Duration = .milliseconds(250),
        limit: Duration = .seconds(10),
        sourceLocation: SourceLocation = #_sourceLocation
    ) async -> SettledFrames? {
        let content = frame(view, variant: variant, width: width, environment: environment)
        guard let hosted = host(content, variant: variant, width: width, height: height) else {
            return nil
        }
        defer { hosted.window.isHidden = true }
        try? await Task.sleep(for: settle)
        guard let atSettle = draw(hosted) else { return nil }
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        var previous = atSettle
        while clock.now < deadline {
            try? await Task.sleep(for: interval)
            guard let next = draw(hosted) else { return nil }
            if bandDifference(previous, next, topPoints: topPoints) == 0 {
                return SettledFrames(atSettle: atSettle, stable: next)
            }
            previous = next
        }
        Issue.record(
            "The top \(Int(topPoints)) pt never stopped changing within \(limit)",
            sourceLocation: sourceLocation
        )
        return SettledFrames(atSettle: atSettle, stable: previous)
    }

    /// Like `renderSettling`, then keeps drawing every `interval` until two consecutive draws are pixel-identical over the
    /// whole frame and the frame differs from `unlike` (the held or placeholder frame), so a `.task` load that lands late
    /// under machine load is waited for instead of captured half-done. Fails (and returns the last draw) after `limit`.
    static func renderSettledContent<Content: View>(
        _ view: Content,
        variant: SnapshotVariant,
        width: CGFloat,
        height: CGFloat,
        environment: SampleEnvironment?,
        settle: Duration = .seconds(1),
        unlike: Data? = nil,
        interval: Duration = .milliseconds(250),
        limit: Duration = .seconds(10),
        sourceLocation: SourceLocation = #_sourceLocation
    ) async -> Data? {
        let content = frame(view, variant: variant, width: width, environment: environment)
        guard let hosted = host(content, variant: variant, width: width, height: height) else {
            return nil
        }
        defer { hosted.window.isHidden = true }
        try? await Task.sleep(for: settle)
        guard var previous = draw(hosted) else { return nil }
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while clock.now < deadline {
            try? await Task.sleep(for: interval)
            guard let next = draw(hosted) else { return nil }
            let steady = bandDifference(previous, next, topPoints: nil) == 0
            if steady, unlike.map({ bandDifference(next, $0, topPoints: nil) > 0 }) ?? true {
                return next
            }
            previous = next
        }
        Issue.record(
            "The frame never settled on content different from the held frame within \(limit)",
            sourceLocation: sourceLocation
        )
        return previous
    }

    /// Pixels in the top `topPoints` of two draws (the whole frame when nil) that differ in any channel at all.
    private static func bandDifference(_ a: Data, _ b: Data, topPoints: CGFloat?) -> Int {
        guard let x = pixels(a), let y = pixels(b), x.width == y.width else { return Int.max }
        let rows = topPoints.map { Int($0 * scale) } ?? Int.max
        let end = min(rows, x.height, y.height) * x.width * 4
        var count = 0
        for index in stride(from: 0, to: end, by: 4) {
            if (0..<4).contains(where: { x.bytes[index + $0] != y.bytes[index + $0] }) { count += 1 }
        }
        return count
    }

    private static func frame<Content: View>(
        _ view: Content,
        variant: SnapshotVariant,
        width: CGFloat,
        environment: SampleEnvironment?
    ) -> AnyView {
        let framed =
            view
            .frame(width: width)
            .background(Color(.systemBackground))
            .dynamicTypeSize(variant.dynamicTypeSize)
            .environment(\.colorScheme, variant.colorScheme)
            .environment(\.locale, Locale(identifier: "en_US"))
            // The finish stars would otherwise differ per frame; this draws their static Reduce Motion scatter.
            .environment(\.staticCelebration, true)
            .transaction { $0.animation = nil }
        if let environment {
            return AnyView(framed.sampleEnvironment(environment))
        }
        return AnyView(framed)
    }

    private static func renderImage(_ content: AnyView, width: CGFloat) -> Data? {
        let renderer = ImageRenderer(
            content: AnyView(content.fixedSize(horizontal: false, vertical: true))
        )
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return renderer.uiImage?.pngData()
    }

    /// A view hosted in a window, waiting to be drawn.
    private struct Hosted {
        let window: UIWindow
        let controller: UIHostingController<AnyView>
        let size: CGSize
    }

    /// Hosts the view in a window of the running app's scene and lays it out; the caller lets it settle, then `capture`s.
    private static func host(
        _ content: AnyView,
        variant: SnapshotVariant,
        width: CGFloat,
        height: CGFloat?
    ) -> Hosted? {
        guard
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return nil }
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .systemBackground
        // Measure under the variant's traits: the controller is detached, so UIKit-backed cells would use the ambient ones.
        controller.overrideUserInterfaceStyle = variant.colorScheme == .dark ? .dark : .light
        controller.traitOverrides.preferredContentSizeCategory = variant.contentSizeCategory
        let fitted = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        let size = CGSize(width: width, height: height ?? ceil(fitted.height))
        // The window takes the scene's size (the Duo's closed display is narrower than a phone), so the hosted view gets
        // its own fixed frame inside a container instead of the window's bounds.
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = variant.colorScheme == .dark ? .dark : .light
        window.traitOverrides.preferredContentSizeCategory = variant.contentSizeCategory
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        container.addChild(controller)
        controller.view.frame = CGRect(origin: .zero, size: size)
        container.view.addSubview(controller.view)
        controller.didMove(toParent: container)
        controller.view.layoutIfNeeded()
        return Hosted(window: window, controller: controller, size: size)
    }

    /// Draws the hosted hierarchy and takes the window down.
    private static func capture(_ hosted: Hosted) -> Data? {
        defer { hosted.window.isHidden = true }
        return draw(hosted)
    }

    /// Draws the hosted hierarchy once and leaves the window up.
    private static func draw(_ hosted: Hosted) -> Data? {
        hosted.controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let size = hosted.size
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            hosted.controller.view.drawHierarchy(
                in: CGRect(origin: .zero, size: size),
                afterScreenUpdates: true
            )
        }
        return image.pngData()
    }

    /// Per-channel tolerance for the chrome comparison. The Liquid Glass capsules of the bar sample the content beneath them,
    /// so on some simulator clones the glass interior shifts by a few tens of levels between the loading and the loaded
    /// frame (3705 px at row 104 on one clone) while the bar is the same. Glyphs (title, button symbols) are high contrast
    /// against the glass: a missing, moved or re-rendered one flips pixels by 100+ levels, far over this, so a looser
    /// threshold absorbs the sampled glass and still fails on any change to the title or buttons.
    static let chromeChannelThreshold = 48

    /// Fails unless the top `topPoints` of two renderings (the navigation bar and title of a pushed screen) match: the
    /// chrome of the loading frame must be the chrome of the loaded one, so it neither pops in nor changes (PLAN 7b.5).
    /// Compared with `chromeChannelThreshold`, not the strict `channelThreshold`, to tolerate glass sampling.
    static func assertSameChrome(
        _ loading: Data,
        _ loaded: Data,
        topPoints: CGFloat = 120,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let a = pixels(loading), let b = pixels(loaded) else {
            Issue.record("assertSameChrome: an image could not be decoded", sourceLocation: sourceLocation)
            return
        }
        guard a.width == b.width else {
            Issue.record(
                "assertSameChrome: widths differ (\(a.width) vs \(b.width) px)",
                sourceLocation: sourceLocation
            )
            return
        }
        let rows = min(Int(topPoints * scale), a.height, b.height)
        var differing = 0
        var firstRow: Int?
        for row in 0..<rows {
            for column in 0..<a.width {
                let index = (row * a.width + column) * 4
                for channel in 0..<4
                where abs(Int(a.bytes[index + channel]) - Int(b.bytes[index + channel])) > chromeChannelThreshold {
                    differing += 1
                    firstRow = firstRow ?? row
                    break
                }
            }
        }
        let total = rows * a.width
        guard Double(differing) / Double(max(1, total)) > maxDifferingFraction else { return }
        let evidence = writeChromeEvidence(loading: loading, loaded: loaded, topPoints: topPoints)
        let message: String =
            "The top \(Int(topPoints)) pt (navigation bar and title) of the loading frame differs from the loaded frame: "
            + "\(differing) of \(total) pixels, first at row \(firstRow ?? 0) px. "
            + "Chrome must not wait for data; see DECISIONS.md, Pushed-screen chrome. Evidence: \(evidence)"
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
    }

    /// Writes both frames and a diff mask (red = differs by more than `chromeChannelThreshold`, the rest of the loading
    /// frame faded) of a failed chrome check to a fresh temp directory, and returns its path for the failure message.
    static func writeChromeEvidence(loading: Data, loaded: Data, topPoints: CGFloat) -> String {
        guard let a = pixels(loading), let b = pixels(loaded), a.width == b.width else {
            return "none (the frames could not be compared)"
        }
        let rows = min(Int(topPoints * scale), a.height, b.height)
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "chrome-diff-\(UUID().uuidString.prefix(8))"
        )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try loading.write(to: directory.appending(path: "loading.png"))
            try loaded.write(to: directory.appending(path: "loaded.png"))
            var mask = [UInt8](repeating: 255, count: a.width * rows * 4)
            for row in 0..<rows {
                for column in 0..<a.width {
                    let index = (row * a.width + column) * 4
                    let differs = (0..<4).contains {
                        abs(Int(a.bytes[index + $0]) - Int(b.bytes[index + $0])) > chromeChannelThreshold
                    }
                    for channel in 0..<3 {
                        mask[index + channel] =
                            differs ? (channel == 0 ? 255 : 0) : UInt8(128 + Int(a.bytes[index + channel]) / 2)
                    }
                }
            }
            let data = Data(mask)
            if let provider = CGDataProvider(data: data as CFData),
                let space = CGColorSpace(name: CGColorSpace.sRGB),
                let image = CGImage(
                    width: a.width,
                    height: rows,
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: a.width * 4,
                    space: space,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                ),
                let png = UIImage(cgImage: image).pngData()
            {
                try png.write(to: directory.appending(path: "diff-mask.png"))
            }
            return directory.path()
        } catch {
            return "could not be written (\(error))"
        }
    }

    // MARK: Comparison

    /// Nil when the images match within tolerance, else why not. `excludingTop` skips the top points of both images: the
    /// Liquid Glass of a navigation bar samples per-simulator lighting, so a bar is compared frame to frame within one run
    /// (`assertSameChrome`), not against a stored reference (tests review r1 P1-1).
    static func difference(between actual: Data, and expected: Data, excludingTop topPoints: CGFloat = 0) -> String? {
        guard let a = pixels(actual), let e = pixels(expected) else { return "an image could not be decoded" }
        guard a.width == e.width, a.height == e.height else {
            return "size \(a.width)x\(a.height) px, reference \(e.width)x\(e.height) px"
        }
        let skipped = min(Int(topPoints * scale), a.height)
        var differing = 0
        for index in stride(from: skipped * a.width * 4, to: a.bytes.count, by: 4) {
            for channel in 0..<4
            where abs(Int(a.bytes[index + channel]) - Int(e.bytes[index + channel])) > channelThreshold {
                differing += 1
                break
            }
        }
        let total = a.width * (a.height - skipped)
        let fraction = Double(differing) / Double(max(1, total))
        guard fraction > maxDifferingFraction else { return nil }
        let percent = (fraction * 100).formatted(.number.precision(.fractionLength(2)))
        return "\(differing) of \(total) pixels differ (\(percent)%, limit \(maxDifferingFraction * 100)%)"
    }

    private static func pixels(_ png: Data) -> (width: Int, height: Int, bytes: [UInt8])? {
        guard let image = UIImage(data: png)?.cgImage, image.width > 0, image.height > 0 else { return nil }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (width, height, bytes) : nil
    }
}
