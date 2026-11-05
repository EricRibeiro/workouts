//
//  ExerciseMedia.swift
//  Workouts
//

import AVKit
import SwiftUI
import WorkoutsKit

/// The app's one `MediaStore`: bundled thumbnails always, videos from CloudKit's public database (see
/// `docs/port/media.md`) except in UI-test runs, which have no network and keep the thumbnail cross-fade.
enum ExerciseMedia {
    /// Whether a video can be fetched at all: not a UI-test run.
    static let canStreamVideo: Bool = !ProcessInfo.processInfo.arguments.contains("-uiTesting")

    static let store = MediaStore(
        source: canStreamVideo ? CloudKitMediaSource() : nil,
        bundle: .main,
        cacheDirectory: .cachesDirectory
    )
}

/// A muted, looping `AVPlayer` over a local file (`AVPlayerLooper` keeps the loop gapless).
@MainActor
@Observable
final class LoopingPlayer {
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper

    init(url: URL) {
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        player = queue
    }
}

/// AVKit's player with a clear backdrop that fills its bounds. SwiftUI's `VideoPlayer` paints a black backdrop and
/// letterboxes (`.resizeAspect`), so when the hero's fractional size lands off the pixel grid the sliver of backdrop
/// shows as a thin dark line down each side of the 16:9 clip. `VideoPlayer` exposes neither knob, hence the wrapper.
private struct ClearVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    /// Called on the main actor whenever `AVPlayerViewController.isReadyForDisplay` changes: true once the first
    /// video frame can be drawn, so the owner can keep something else showing until then.
    let onReadyForDisplay: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .clear
        context.coordinator.observe(controller, onReadyForDisplay)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        context.coordinator.onReadyForDisplay = onReadyForDisplay
    }

    @MainActor
    final class Coordinator {
        var onReadyForDisplay: (Bool) -> Void = { _ in }
        private var observation: NSKeyValueObservation?

        func observe(_ controller: AVPlayerViewController, _ callback: @escaping (Bool) -> Void) {
            onReadyForDisplay = callback
            observation = controller.observe(\.isReadyForDisplay, options: [.initial, .new]) {
                [weak self] controller, _ in
                let ready = controller.isReadyForDisplay
                Task { @MainActor in self?.onReadyForDisplay(ready) }
            }
        }
    }
}

/// The hero of the exercise detail: the exercise video when the cache has (or can fetch) one, else the bundled start
/// frame, cross-fading to the end frame unless Reduce Motion is on. A muted caption when there is no media at all.
struct ExerciseMediaHeader: View {
    let info: ExerciseInfo
    let library: LibraryExercise?
    /// The embedded pane draws a rounded card; the pushed detail runs edge to edge and extends under the bars.
    let embedded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var video: LoopingPlayer?
    /// The player has a frame to show; until then the stills stay up so the swap never shows an empty hero.
    @State private var videoReady = false
    @State private var showsEnd = false
    @State private var heroCap: CGFloat = .infinity

    private var startURL: URL? { info.isCustom ? nil : ExerciseMedia.store.thumbnailURL(for: info.id, phase: .start) }
    private var endURL: URL? { info.isCustom ? nil : ExerciseMedia.store.thumbnailURL(for: info.id, phase: .end) }

    var body: some View {
        if startURL == nil && library?.hasVideos != true {
            Label("No video for this exercise", systemImage: "video.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .accessibilityIdentifier("exerciseDetail.noMedia")
        } else {
            hero
                .task(id: colorScheme) { await loadVideo() }
                .task(id: animatesStills) { await crossfade() }
                .onAppear { if !reduceMotion { video?.player.play() } }
                .onDisappear { video?.player.pause() }
        }
    }

    /// The stills trade places only while they are what the person sees.
    private var animatesStills: Bool { !reduceMotion && !videoReady }

    @ViewBuilder
    private var hero: some View {
        // The stills stay underneath; the player sits on top, invisible until it can draw a frame, then fades in
        // (a plain swap with Reduce Motion). Swapping them in one pass left a frame with neither on screen.
        let frame = ZStack {
            frames
                .accessibilityHidden(videoReady)
            if let video {
                ClearVideoPlayer(player: video.player) { videoReady = $0 }
                    .opacity(videoReady ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: videoReady)
                    .accessibilityLabel("Exercise video")
                    .accessibilityIdentifier("exerciseDetail.video")
                    .accessibilityHidden(!videoReady)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: heroCap)
        .background {
            // `containerRelativeFrame` only sets an exact size, so a probe measures the cap (35 % of the container's
            // height) and the hero takes it as a maximum. One rule in every pose; the closed Duo stays under it.
            Color.clear
                .containerRelativeFrame(.vertical) { height, _ in height * 0.35 }
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    heroCap = $0
                }
        }
        if embedded {
            frame
                .clipShape(.rect(cornerRadius: 12))
                .padding(.horizontal)
        } else {
            frame
                .backgroundExtensionEffect()
        }
    }

    private var frames: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            if let startURL {
                AsyncImage(url: startURL) {
                    $0.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
            }
            if let endURL {
                AsyncImage(url: endURL) {
                    $0.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .opacity(showsEnd ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsEnd ? "Exercise end position" : "Exercise start position")
        .accessibilityIdentifier("exerciseDetail.frames")
    }

    private func loadVideo() async {
        video = nil
        videoReady = false
        guard ExerciseMedia.canStreamVideo, let library, library.hasVideos else { return }
        let scheme: MediaScheme = colorScheme == .dark ? .dark : .light
        guard let url = try? await ExerciseMedia.store.video(for: library.sourceId, scheme: scheme) else { return }
        let looping = LoopingPlayer(url: url)
        video = looping
        if !reduceMotion { looping.player.play() }
    }

    /// The poor-man's animation while no video is playing: start and end frames trade places every 1.5 s.
    private func crossfade() async {
        if !videoReady { showsEnd = false }
        guard animatesStills, endURL != nil, !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.6)) { showsEnd.toggle() }
        }
    }
}

/// Settings' "Download all videos": prefetches every library video for one colour scheme, Wi-Fi only, in the
/// background. It outlives the Settings sheet (closing it does not stop the download); switching the toggle off does.
@MainActor
@Observable
final class BulkVideoDownload {
    static let shared = BulkVideoDownload()

    /// Videos handled so far and the total, nil while idle or finished.
    private(set) var progress: (done: Int, total: Int)?
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    /// Starts unless a download is already running or videos are off (UI-test runs). Cached videos count as done at once.
    func start(sourceIDs: [String], scheme: MediaScheme) {
        guard task == nil, ExerciseMedia.canStreamVideo, !sourceIDs.isEmpty else { return }
        progress = (0, sourceIDs.count)
        task = Task { [weak self] in
            await ExerciseMedia.store.prefetch(sourceIDs: sourceIDs, scheme: scheme, allowsCellular: false) {
                done,
                total in
                Task { @MainActor in
                    if let self, self.task != nil { self.progress = (done, total) }
                }
            }
            guard !Task.isCancelled else { return }
            self?.task = nil
            self?.progress = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        progress = nil
    }
}
