import AVFoundation
import Combine
import MediaPlayer

@MainActor
class AudioService: ObservableObject {
    /// Ayah counts for all 114 surahs — used to auto-continue playback.
    private static let surahAyahCounts: [Int: Int] = [
        1:7,   2:286, 3:200, 4:176, 5:120, 6:165, 7:206, 8:75,  9:129, 10:109,
        11:123,12:111,13:43, 14:52, 15:99, 16:128,17:111,18:110,19:98, 20:135,
        21:112,22:78, 23:118,24:64, 25:77, 26:227,27:93, 28:88, 29:69, 30:60,
        31:34, 32:30, 33:73, 34:54, 35:45, 36:83, 37:182,38:88, 39:75, 40:85,
        41:54, 42:53, 43:89, 44:59, 45:37, 46:35, 47:38, 48:29, 49:18, 50:45,
        51:60, 52:49, 53:62, 54:55, 55:78, 56:96, 57:29, 58:22, 59:24, 60:13,
        61:14, 62:11, 63:11, 64:18, 65:12, 66:12, 67:30, 68:52, 69:52, 70:44,
        71:28, 72:28, 73:20, 74:56, 75:40, 76:31, 77:50, 78:40, 79:46, 80:42,
        81:29, 82:19, 83:36, 84:25, 85:22, 86:17, 87:19, 88:26, 89:30, 90:20,
        91:15, 92:21, 93:11, 94:8,  95:8,  96:19, 97:5,  98:8,  99:8,  100:11,
        101:11,102:8, 103:3, 104:9, 105:5, 106:4, 107:7, 108:3, 109:6, 110:3,
        111:5, 112:4, 113:5, 114:6
    ]

    @Published var isPlaying = false
    @Published var currentAyah: Int? = nil
    @Published var currentSurah: Int = 0
    @Published var currentSurahName: String = ""
    @Published var progress: Double = 0
    @Published var isWordLooping = false
    @Published var playbackRate: Float = 1.0
    private var currentItemDuration: Double = 0

    // AVQueuePlayer lets us pre-queue the next ayah so iOS advances
    // automatically when the app is in the background — replaceCurrentItem
    // on a plain AVPlayer doesn't reliably restart audio from background.
    private let player = AVQueuePlayer()
    private var playerItem: AVPlayerItem?       // currently playing item
    private var preloadedItem: AVPlayerItem?    // pre-queued item (strong ref so we can observe it)
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    // Chapter-level player for word loops (quranicaudio.com full-chapter file).
    private var chapterPlayer: AVPlayer?
    private var chapterItem: AVPlayerItem?
    private var chapterTimeObserver: Any?
    private var loadedChapterUrl: URL?

    @Published private(set) var loopSettings = LoopSettings()
    private var totalAyahs: Int = 0
    private var repeatCounter = 0

    // Word-loop boundaries — global seconds into the chapter audio file.
    private var wordLoopStart: Double = 0
    private var wordLoopEnd: Double = 0
    private var isSeeking = false

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        setupPlayerTimeObserver()
        setupRemoteCommandCenter()
    }

    // MARK: - Normal per-ayah playback

    func play(surah: Int, startAyah: Int, loop: LoopSettings, totalAyahs: Int, surahName: String = "") {
        stopWordLoopInternal()
        currentSurah = surah
        currentSurahName = surahName
        loopSettings = loop
        self.totalAyahs = totalAyahs
        repeatCounter = 0
        loadItem(ayah: startAyah)
    }

    // MARK: - CarPlay / lock-screen navigation helpers

    func skipToNextAyah() {
        guard let ayah = currentAyah, ayah < totalAyahs else { return }
        stopWordLoopInternal()
        repeatCounter = 0
        loadItem(ayah: ayah + 1)
    }

    func skipToPreviousAyah() {
        guard let ayah = currentAyah, ayah > 1 else { return }
        stopWordLoopInternal()
        repeatCounter = 0
        loadItem(ayah: ayah - 1)
    }

    func setLoopSingleAyah(_ on: Bool) {
        loopSettings = on
            ? LoopSettings(mode: .single, startAyah: currentAyah ?? 1,
                           endAyah: currentAyah ?? 1, repeatCount: 0)
            : LoopSettings(mode: .off, startAyah: 1, endAyah: 1, repeatCount: 0)
    }

    func togglePlayPause() {
        if isWordLooping {
            if isPlaying { chapterPlayer?.pause(); isPlaying = false }
            else         { chapterPlayer?.play();  isPlaying = true  }
        } else {
            guard player.currentItem != nil else { return }
            if isPlaying { player.pause(); isPlaying = false }
            else         { player.play();  isPlaying = true  }
        }
    }

    func stop() {
        stopWordLoopInternal()
        clearPlayerItem()
        isPlaying = false
        currentAyah = nil
        progress = 0
    }

    func updateLoop(_ settings: LoopSettings) {
        loopSettings = settings
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying && !isWordLooping {
            player.rate = rate
        }
    }

    // MARK: - Word loop (chapter audio, accurate global timestamps)

    func startWordLoop(
        surah: Int,
        ayah: Int,
        chapterUrl: URL,
        wordStartMs: Int,
        wordEndMs: Int
    ) {
        wordLoopStart = Double(wordStartMs) / 1000.0
        wordLoopEnd   = Double(wordEndMs)   / 1000.0
        currentSurah  = surah
        currentAyah   = ayah
        isSeeking     = false
        isWordLooping = true

        player.pause()

        if loadedChapterUrl != chapterUrl || chapterPlayer == nil {
            teardownChapterPlayer()
            loadedChapterUrl = chapterUrl
            chapterItem = AVPlayerItem(url: chapterUrl)
            chapterPlayer = AVPlayer(playerItem: chapterItem)
            chapterPlayer?.automaticallyWaitsToMinimizeStalling = false
            observeChapterTime()
        }

        seekChapterToWordStart()
        chapterPlayer?.play()
        isPlaying = true
    }

    func stopWordLoop() {
        guard isWordLooping else { return }
        stopWordLoopInternal()
        if player.currentItem != nil {
            player.play()
            isPlaying = true
        } else {
            isPlaying = false
        }
    }

    // MARK: - Internal: per-ayah (AVQueuePlayer)

    /// Load an ayah by rebuilding the queue on the shared AVQueuePlayer.
    /// For sequential (.off) mode we pre-queue the next ayah so iOS can
    /// auto-advance in the background without a new play() call.
    private func loadItem(ayah: Int) {
        removeEndObserver()

        currentAyah = ayah
        isSeeking   = false

        // Tear down old queue and insert the new current item.
        player.removeAllItems()
        preloadedItem = nil

        let item = AVPlayerItem(url: audioURL(surah: currentSurah, ayah: ayah))
        playerItem = item
        player.insert(item, after: nil)

        // Pre-queue the natural follower for background-safe auto-advance.
        if loopSettings.mode == .off, ayah < totalAyahs {
            let next = AVPlayerItem(url: audioURL(surah: currentSurah, ayah: ayah + 1))
            player.insert(next, after: item)
            preloadedItem = next   // strong ref — we'll observe it in handleAyahEnd
        }

        observeAyahEnd()
        player.play()
        player.rate = playbackRate
        isPlaying = true
    }

    private func audioURL(surah: Int, ayah: Int) -> URL {
        let subfolder = Reciter.selected.subfolder
        let s = String(format: "%03d", surah)
        let a = String(format: "%03d", ayah)
        return URL(string: "https://everyayah.com/data/\(subfolder)/\(s)\(a).mp3")!
    }

    private func clearPlayerItem() {
        removeEndObserver()
        player.pause()
        player.removeAllItems()
        playerItem    = nil
        preloadedItem = nil
    }

    // Observe the end of the CURRENT item.
    // queue:.main guarantees the handler runs on the main thread.
    // MainActor.assumeIsolated calls handleAyahEnd() synchronously — no Task is
    // created, so the cooperative scheduler cannot defer execution while backgrounded.
    // This is essential: handleAyahEnd() must queue the next-next item immediately
    // or AVQueuePlayer will empty after two ayahs and stop.
    private func observeAyahEnd() {
        guard let item = playerItem else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleAyahEnd() }
        }
    }

    private func removeEndObserver() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
    }

    private func handleAyahEnd() {
        guard let ayah = currentAyah else { return }
        removeEndObserver()

        switch loopSettings.mode {

        case .off:
            if ayah < totalAyahs {
                let nextAyah = ayah + 1
                currentAyah = nextAyah

                playerItem    = preloadedItem ?? player.currentItem
                preloadedItem = nil

                observeAyahEnd()

                if nextAyah < totalAyahs {
                    let nextNext = AVPlayerItem(url: audioURL(surah: currentSurah, ayah: nextAyah + 1))
                    player.insert(nextNext, after: player.items().last)
                    preloadedItem = nextNext
                }

                if loopSettings.listenAndRepeat, currentItemDuration > 0 {
                    // Pause for the same duration as the ayah just played, then resume.
                    player.pause()
                    isPlaying = false
                    let rawDelay = loopSettings.listenRepeatDelay.rawValue
                    let delay = rawDelay < 0 ? currentItemDuration : rawDelay
                    let rate  = playbackRate
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(delay))
                        guard let self, self.loopSettings.listenAndRepeat, !self.isPlaying else { return }
                        self.player.play()
                        self.player.rate = rate
                        self.isPlaying = true
                        self.updateNowPlayingInfo()
                    }
                }

                updateNowPlayingInfo()
            } else if currentSurah < 114,
                      let nextCount = Self.surahAyahCounts[currentSurah + 1] {
                // Auto-continue to the next surah
                currentSurah    += 1
                currentSurahName = "Surah \(currentSurah)"
                totalAyahs       = nextCount
                repeatCounter    = 0
                loadItem(ayah: 1)
                updateNowPlayingInfo()
            } else {
                player.removeAllItems()
                isPlaying = false
                updateNowPlayingInfo()
            }

        case .single:
            // Single-ayah looping is a foreground feature; re-loading is fine.
            let max = loopSettings.repeatCount
            if max == 0 || repeatCounter < max - 1 {
                repeatCounter += 1
                loadItem(ayah: ayah)   // re-inserts same ayah with fresh observer
            } else {
                repeatCounter = 0
                player.removeAllItems()
                isPlaying = false
            }

        case .segment:
            if ayah < loopSettings.endAyah {
                loadItem(ayah: ayah + 1)
            } else {
                let max = loopSettings.repeatCount
                if max == 0 || repeatCounter < max - 1 {
                    repeatCounter += 1
                    loadItem(ayah: loopSettings.startAyah)
                } else {
                    repeatCounter = 0
                    player.removeAllItems()
                    isPlaying = false
                }
            }
        }
    }

    private func setupPlayerTimeObserver() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isWordLooping else { return }
                if let dur = self.player.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
                    self.progress = time.seconds / dur
                    self.currentItemDuration = dur
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    // MARK: - Internal: chapter / word loop

    private func observeChapterTime() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        chapterTimeObserver = chapterPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isWordLooping, !self.isSeeking else { return }
                if time.seconds >= self.wordLoopEnd {
                    self.seekChapterToWordStart()
                }
            }
        }
    }

    private func seekChapterToWordStart() {
        guard !isSeeking else { return }
        isSeeking = true
        let target = CMTime(seconds: wordLoopStart, preferredTimescale: 600)
        chapterPlayer?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSeeking = false
                if self.isWordLooping { self.chapterPlayer?.play() }
            }
        }
    }

    private func stopWordLoopInternal() {
        isWordLooping = false
        teardownChapterPlayer()
    }

    // MARK: - Remote Command Center + Now Playing Info

    private func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }
        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }
        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.skipToNextAyah() }
            return .success
        }
        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.skipToPreviousAyah() }
            return .success
        }
        cc.changeRepeatModeCommand.isEnabled = true
        cc.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.setLoopSingleAyah(e.repeatType == .one)
            }
            return .success
        }
    }

    func updateNowPlayingInfo() {
        guard let ayah = currentAyah else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let title = currentSurahName.isEmpty ? "Surah \(currentSurah)" : currentSurahName
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:             "Ayah \(ayah)",
            MPMediaItemPropertyAlbumTitle:        title,
            MPMediaItemPropertyArtist:            "Quran",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType:    MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let dur = player.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
            info[MPMediaItemPropertyPlaybackDuration]         = dur
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = dur * progress
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func teardownChapterPlayer() {
        if let obs = chapterTimeObserver {
            chapterPlayer?.removeTimeObserver(obs)
            chapterTimeObserver = nil
        }
        chapterPlayer?.pause()
        chapterPlayer    = nil
        chapterItem      = nil
        loadedChapterUrl = nil
    }
}
