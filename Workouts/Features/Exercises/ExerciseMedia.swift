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
                .task(id: reduceMotion) { await crossfade() }
                .onAppear { if !reduceMotion { video?.player.play() } }
                .onDisappear { video?.player.pause() }
        }
    }

    @ViewBuilder
    private var hero: some View {
        let frame = ZStack {
            if let video {
                VideoPlayer(player: video.player)
                    .accessibilityLabel("Exercise video")
                    .accessibilityIdentifier("exerciseDetail.video")
            } else {
                frames
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
        guard ExerciseMedia.canStreamVideo, let library, library.hasVideos else { return }
        let scheme: MediaScheme = colorScheme == .dark ? .dark : .light
        guard let url = try? await ExerciseMedia.store.video(for: library.sourceId, scheme: scheme) else { return }
        let looping = LoopingPlayer(url: url)
        video = looping
        if !reduceMotion { looping.player.play() }
    }

    /// The poor-man's animation while no video is playing: start and end frames trade places every 1.5 s.
    private func crossfade() async {
        showsEnd = false
        guard !reduceMotion, endURL != nil, !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
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
