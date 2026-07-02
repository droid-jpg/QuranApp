import AVFoundation
import Combine

/// Lightweight one-shot player for short audio clips — a single word or a single
/// ayah in the review session. Deliberately separate from AudioService so it never
/// touches the main player's queue or the Now Playing / lock-screen state.
@MainActor
final class ClipPlayer: ObservableObject {
    static let shared = ClipPlayer()

    @Published private(set) var playingURL: URL?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    private init() {}

    func play(_ url: URL) {
        stop()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        playingURL = url
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        p.play()
    }

    func stop() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player?.pause()
        player = nil
        playingURL = nil
    }

    func isPlaying(_ url: URL) -> Bool { playingURL == url }

    private func finish() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player = nil
        playingURL = nil
    }
}

/// Plays a sub-range `[fromMs, toMs]` of an audio file, optionally muting a window
/// `[muteFromMs, muteToMs]` inside it. The fill-in-the-blank review drill uses it to
/// play an ayah with the hidden word silenced, then the full ayah once the answer is
/// shown. Timestamps are global offsets into the file (the QDC chapter recording).
/// Like `ClipPlayer` it stays off the main audio queue and lock-screen state.
@MainActor
final class GapClipPlayer: ObservableObject {
    static let shared = GapClipPlayer()

    /// True while a range is playing — drives the review card's play/stop button.
    @Published private(set) var isActive = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var rangeEnd: Double = 0
    private var muteStart: Double = 0
    private var muteEnd: Double = 0
    private var muted = false
    private var token = 0   // invalidates stale seek completions across calls

    private init() {}

    /// Play `[fromMs, toMs]` of `url`. When a mute window is supplied, the audio is
    /// silenced while playback is inside `[muteFromMs, muteToMs]`.
    func play(url: URL, fromMs: Int, toMs: Int, muteFromMs: Int? = nil, muteToMs: Int? = nil) {
        stop()
        token &+= 1
        let myToken = token

        rangeEnd = Double(toMs) / 1000.0
        if let mf = muteFromMs, let mt = muteToMs, mt > mf {
            muteStart = Double(mf) / 1000.0
            muteEnd   = Double(mt) / 1000.0
            muted = true
        } else {
            muted = false
        }

        let p = AVPlayer(playerItem: AVPlayerItem(url: url))
        p.automaticallyWaitsToMinimizeStalling = false
        player = p
        isActive = true

        let interval = CMTime(seconds: 0.02, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }

        let start = CMTime(seconds: Double(fromMs) / 1000.0, preferredTimescale: 600)
        let startSeconds = Double(fromMs) / 1000.0
        p.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor [weak self] in
                guard let self, self.token == myToken, self.player === p else { return }
                self.tick(startSeconds)   // set initial volume before audio starts
                p.play()
            }
        }
    }

    private func tick(_ seconds: Double) {
        guard let player else { return }
        if muted {
            player.volume = (seconds >= muteStart && seconds < muteEnd) ? 0 : 1
        }
        if seconds >= rangeEnd { stop() }
    }

    func stop() {
        token &+= 1
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        isActive = false
    }
}
