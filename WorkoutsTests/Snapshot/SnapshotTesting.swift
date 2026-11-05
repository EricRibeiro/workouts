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
        let suite = URL(filePath: filePath).deletingPathExtension().lastPathComponent
        let directory = testsDirectory.appending(path: "__Snapshots__").appending(path: suite)
        let reference = directory.appending(path: "\(name)-\(variant.name).png")
        let actual = directory.appending(path: "\(name)-\(variant.name).actual.png")

        guard let png = render(view, variant: variant, width: width, engine: engine, environment: environment) else {
            Issue.record("Could not render \(name)-\(variant.name)", sourceLocation: sourceLocation)
            return
        }

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
            if let problem = difference(between: png, and: expected) {
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
        let content: AnyView
        if let environment {
            content = AnyView(framed.sampleEnvironment(environment))
        } else {
            content = AnyView(framed)
        }
        switch engine {
        case .image: return renderImage(content, width: width)
        case .hostedFitting: return renderHosted(content, variant: variant, width: width, height: nil)
        case .hosted(let height): return renderHosted(content, variant: variant, width: width, height: height)
        }
    }

    private static func renderImage(_ content: AnyView, width: CGFloat) -> Data? {
        let renderer = ImageRenderer(content: AnyView(content.fixedSize(horizontal: false, vertical: true)))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return renderer.uiImage?.pngData()
    }

    /// Hosts the view in a window of the running app's scene, lets it lay out and settle, and draws the hierarchy.
    private static func renderHosted(_ content: AnyView, variant: SnapshotVariant, width: CGFloat, height: CGFloat?)
        -> Data?
    {
        guard
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return nil }
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .systemBackground
        let fitted = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        let size = CGSize(width: width, height: height ?? ceil(fitted.height))
        // The window takes the scene's size (the Duo's closed display is narrower than a phone), so the hosted view gets
        // its own fixed frame inside a container instead of the window's bounds.
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = variant.colorScheme == .dark ? .dark : .light
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        defer { window.isHidden = true }
        container.addChild(controller)
        controller.view.frame = CGRect(origin: .zero, size: size)
        container.view.addSubview(controller.view)
        controller.didMove(toParent: container)
        controller.view.layoutIfNeeded()
        // Lists and navigation bars populate on the next run loop turns.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            controller.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        return image.pngData()
    }

    // MARK: Comparison

    /// Nil when the images match within tolerance, else why not.
    static func difference(between actual: Data, and expected: Data) -> String? {
        guard let a = pixels(actual), let e = pixels(expected) else { return "an image could not be decoded" }
        guard a.width == e.width, a.height == e.height else {
            return "size \(a.width)x\(a.height) px, reference \(e.width)x\(e.height) px"
        }
        var differing = 0
        for index in stride(from: 0, to: a.bytes.count, by: 4) {
            for channel in 0..<4
            where abs(Int(a.bytes[index + channel]) - Int(e.bytes[index + channel])) > channelThreshold {
                differing += 1
                break
            }
        }
        let total = a.width * a.height
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
