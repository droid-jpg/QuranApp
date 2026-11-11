import AVFoundation
import Combine

/// Lightweight one-shot player for short audio: a whole clip (one ayah in the
/// review session) or a `[fromMs, toMs]` range of a longer file (a word in Word
/// by word, or a review ayah with one word silenced). Deliberately separate from
/// `AudioService`, so it never touches the main player's queue or the Now
/// Playing / lock-screen state. One clip at a time: a new one stops the last.
///
/// Range timestamps are global offsets into the file (the QDC chapter recording).
@MainActor
final class ClipPlayer: ObservableObject {
    static let shared = ClipPlayer()

    /// The file being played, nil when idle. Drives the play/stop buttons.
    @Published private(set) var playingURL: URL?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var statusWatch: AnyCancellable?
    private var rangeEnd: Double?
    private var muteStart: Double = 0
    private var muteEnd: Double = 0
    private var muted = false
    private var token = 0   // invalidates stale seek completions across calls

    private init() {}

    var isActive: Bool { playingURL != nil }

    func isPlaying(_ url: URL) -> Bool { playingURL == url }

    /// Play a whole file.
    func play(_ url: URL) {
        start(url: url, fromMs: nil, toMs: nil, muteFromMs: nil, muteToMs: nil)
    }

    /// Play `[fromMs, toMs]` of `url`. With a mute window, the audio is silenced
    /// while playback is inside `[muteFromMs, muteToMs]`.
    func play(url: URL, fromMs: Int, toMs: Int, muteFromMs: Int? = nil, muteToMs: Int? = nil) {
        start(url: url, fromMs: fromMs, toMs: toMs, muteFromMs: muteFromMs, muteToMs: muteToMs)
    }

    func stop() {
        token &+= 1
        teardown()
    }

    // MARK: Internal

    private func start(url: URL, fromMs: Int?, toMs: Int?, muteFromMs: Int?, muteToMs: Int?) {
        stop()
        let myToken = token

        rangeEnd = toMs.map { Double($0) / 1000.0 }
        if let mf = muteFromMs, let mt = muteToMs, mt > mf {
            muteStart = Double(mf) / 1000.0
            muteEnd   = Double(mt) / 1000.0
            muted = true
        } else {
            muted = false
        }

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = false
        player = p
        playingURL = url

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        // A clip that can't load must not leave the button on "Stop".
        statusWatch = item.publisher(for: \.status)
            .filter { $0 == .failed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { if self?.token == myToken { self?.stop() } }
            }

        guard let fromMs else {
            p.play()
            return
        }

        let interval = CMTime(seconds: 0.02, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        let startSeconds = Double(fromMs) / 1000.0
        p.seek(to: CMTime(seconds: startSeconds, preferredTimescale: 600),
               toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            let player = self
            Task { @MainActor in
                guard let self = player, self.token == myToken, self.player === p else { return }
                self.tick(startSeconds)   // set the initial volume before audio starts
                p.play()
            }
        }
    }

    private func tick(_ seconds: Double) {
        guard let player else { return }
        if muted {
            player.volume = (seconds >= muteStart && seconds < muteEnd) ? 0 : 1
        }
        if let end = rangeEnd, seconds >= end { stop() }
    }

    private func teardown() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        statusWatch = nil
        player?.pause()
        player = nil
        playingURL = nil
        rangeEnd = nil
        muted = false
    }
}
