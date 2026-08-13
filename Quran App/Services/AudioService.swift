import AVFoundation
import Combine
import MediaPlayer

/// The playhead, published apart from `AudioService`.
///
/// The position ticks ten times a second. While it lived on `AudioService`
/// itself, every view observing that object — the whole reader, including each
/// loaded ayah, and the whole dashboard — re-rendered ten times a second, which
/// is what made the reader and the expanded player stutter. Only the handful of
/// views that actually draw a playhead observe this.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published fileprivate(set) var progress: Double = 0
    @Published fileprivate(set) var duration: Double = 0
}

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
    @Published var isWordLooping = false
    @Published var playbackRate: Float = 1.0

    /// Playhead + ayah length. Deliberately *not* `@Published` on this object:
    /// see `PlaybackClock`. Views that draw a scrubber observe `clock` directly.
    let clock = PlaybackClock()

    /// Fraction of the current ayah already played, 0…1.
    var progress: Double {
        get { clock.progress }
        set { clock.progress = newValue }
    }

    /// Duration of the ayah currently loaded, in seconds.
    private(set) var duration: Double {
        get { clock.duration }
        set { clock.duration = newValue }
    }

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
    private var lastNowPlayingUpdate: Date = .distantPast

    /// True while waiting out a Listen & Repeat gap between ayahs. A manual stop or
    /// pause clears it so the scheduled resume is cancelled.
    private var pausedForRepeat = false

    /// Position to restore once the ayah's real duration is known — set by
    /// `resume(_:)` so a saved listening session picks up mid-ayah.
    private var pendingSeekFraction: Double?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        setupPlayerTimeObserver()
        setupRemoteCommandCenter()
    }

    // MARK: - Normal per-ayah playback

    func play(surah: Int, startAyah: Int, loop: LoopSettings, totalAyahs: Int, surahName: String = "") {
        pausedForRepeat = false
        pendingSeekFraction = nil
        stopWordLoopInternal()
        currentSurah = surah
        currentSurahName = surahName
        loopSettings = loop
        self.totalAyahs = totalAyahs
        repeatCounter = 0
        loadItem(ayah: startAyah)
    }

    /// Start playback for a memorization preset (`.listen` / `.repeatAfter` /
    /// `.chain`), beginning at the loop's natural first ayah.
    func playLoop(surah: Int, settings: LoopSettings, totalAyahs: Int, surahName: String = "") {
        let start = settings.mode == .off ? 1 : settings.startAyah
        play(surah: surah, startAyah: start, loop: settings, totalAyahs: totalAyahs, surahName: surahName)
    }

    /// Pick up a saved listening session exactly where it stopped — same ayah, same
    /// loop shape, and (once the ayah has loaded and reported a duration) the same
    /// position inside it. Positions at the very edges are ignored: restoring to the
    /// last sliver of an ayah would just trip the end handler immediately.
    func resume(_ session: ListeningSession) {
        play(surah: session.surah, startAyah: session.ayah, loop: session.loop,
             totalAyahs: session.totalAyahs, surahName: session.surahName)
        if session.fraction > 0.02 && session.fraction < 0.95 {
            pendingSeekFraction = session.fraction
        }
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
            if isPlaying { player.pause(); isPlaying = false; ListeningSessionStore.shared.flush() }
            else         { player.play();  isPlaying = true  }
        }
    }

    func stop() {
        pausedForRepeat = false
        pendingSeekFraction = nil
        stopWordLoopInternal()
        clearPlayerItem()
        isPlaying = false
        currentAyah = nil
        progress = 0
        // The session itself survives a stop — that's the whole point of the
        // resume card; only the live playback is torn down.
        ListeningSessionStore.shared.flush()
    }

    /// Snapshot what's playing for Home's resume card. Cheap and throttled inside
    /// the store, so it's safe to call from the once-a-second playback tick.
    private func recordListeningSession() {
        guard let ayah = currentAyah, currentSurah > 0, totalAyahs > 0 else { return }
        ListeningSessionStore.shared.record(
            surah: currentSurah, surahName: currentSurahName, ayah: ayah,
            totalAyahs: totalAyahs, loop: loopSettings,
            fraction: progress, duration: duration
        )
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

    /// Seek within the ayah currently playing to a 0…1 fraction of its length.
    /// Used by the expanded/focus player's scrubber and waveform. No-op during a
    /// word loop (that player owns its own timeline).
    func seek(toFraction fraction: Double) {
        guard !isWordLooping, let item = player.currentItem else { return }
        let dur = item.duration.seconds
        guard dur.isFinite, dur > 0 else { return }
        let clamped = max(0, min(1, fraction))
        player.seek(to: CMTime(seconds: clamped * dur, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        progress = clamped
        updateNowPlayingInfo()
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
        item.preferredForwardBufferDuration = 6
        playerItem = item
        player.insert(item, after: nil)

        // Pre-queue the natural follower for background-safe auto-advance.
        // Skipped when Listen & Repeat is on: that mode pauses between ayahs, so a
        // seamless pre-queued follower would play through the pause.
        if loopSettings.mode == .off, !loopSettings.listenAndRepeat, ayah < totalAyahs {
            let next = AVPlayerItem(url: audioURL(surah: currentSurah, ayah: ayah + 1))
            next.preferredForwardBufferDuration = 6
            player.insert(next, after: item)
            preloadedItem = next   // strong ref — we'll observe it in handleAyahEnd
        }

        observeAyahEnd()
        // Pre-fetch next 3 ayahs to eliminate network buffering
        prefetchUpcoming(from: ayah, count: 3)
        player.play()
        player.rate = playbackRate
        isPlaying = true

        // Publish the new position straight away rather than waiting for the
        // once-a-second tick, so Home's resume card never lags a track behind.
        if currentSurah > 0, totalAyahs > 0 {
            ListeningSessionStore.shared.record(
                surah: currentSurah, surahName: currentSurahName, ayah: ayah,
                totalAyahs: totalAyahs, loop: loopSettings, fraction: 0, duration: 0
            )
        }
    }

    private func audioURL(surah: Int, ayah: Int) -> URL {
        let subfolder = Reciter.selected.subfolder
        // Check for a permanently downloaded copy first (offline playback)
        if let local = DownloadManager.shared.localURL(surah: surah, ayah: ayah, reciterSubfolder: subfolder) {
            return local
        }
        let s = String(format: "%03d", surah)
        let a = String(format: "%03d", ayah)
        // Check the prefetch cache (temp files downloaded ahead-of-time)
        let remoteURL = URL(string: "https://everyayah.com/data/\(subfolder)/\(s)\(a).mp3")!
        if let cached = AudioPrefetchCache.shared.cachedLocalURL(for: remoteURL) {
            return cached
        }
        return remoteURL
    }

    private func prefetchUpcoming(from ayah: Int, count: Int) {
        let subfolder = Reciter.selected.subfolder
        for i in 1...count {
            let next = ayah + i
            guard next <= totalAyahs else { break }
            let s = String(format: "%03d", currentSurah)
            let a = String(format: "%03d", next)
            let url = URL(string: "https://everyayah.com/data/\(subfolder)/\(s)\(a).mp3")!
            AudioPrefetchCache.shared.prefetch(url)
        }
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
                if loopSettings.listenAndRepeat {
                    // Pause on the ayah just heard so the reciter can repeat it, then
                    // load the next. currentAyah stays put during the pause so the
                    // reader keeps highlighting the ayah being repeated.
                    scheduleAfterRepeatPause { [weak self] in self?.loadItem(ayah: nextAyah) }
                } else {
                    // Seamless, background-safe advance using the pre-queued item.
                    currentAyah   = nextAyah
                    playerItem    = preloadedItem ?? player.currentItem
                    preloadedItem = nil
                    observeAyahEnd()
                    if nextAyah < totalAyahs {
                        let nextNext = AVPlayerItem(url: audioURL(surah: currentSurah, ayah: nextAyah + 1))
                        player.insert(nextNext, after: player.items().last)
                        preloadedItem = nextNext
                    }
                    updateNowPlayingInfo()
                }
            } else if currentSurah < 114,
                      let nextCount = Self.surahAyahCounts[currentSurah + 1] {
                // Auto-continue to the next surah
                currentSurah    += 1
                currentSurahName = "Surah \(currentSurah)"
                totalAyahs       = nextCount
                repeatCounter    = 0
                scheduleAfterRepeatPause { [weak self] in self?.loadItem(ayah: 1) }
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
                scheduleAfterRepeatPause { [weak self] in self?.loadItem(ayah: ayah) }
            } else {
                repeatCounter = 0
                player.removeAllItems()
                isPlaying = false
            }

        case .segment:
            if ayah < loopSettings.endAyah {
                scheduleAfterRepeatPause { [weak self] in self?.loadItem(ayah: ayah + 1) }
            } else {
                let max = loopSettings.repeatCount
                if max == 0 || repeatCounter < max - 1 {
                    repeatCounter += 1
                    let start = loopSettings.startAyah
                    scheduleAfterRepeatPause { [weak self] in self?.loadItem(ayah: start) }
                } else {
                    repeatCounter = 0
                    player.removeAllItems()
                    isPlaying = false
                }
            }
        }
    }

    /// Runs `work` after the Listen & Repeat gap — a fixed number of seconds, or the
    /// just-played ayah's own length ("Match ayah length") — so *every* loop mode
    /// (sequential, single, and segment) pauses for the reciter to repeat aloud.
    /// When Listen & Repeat is off, `work` runs immediately. A manual stop clears
    /// `pausedForRepeat`, cancelling a scheduled resume.
    private func scheduleAfterRepeatPause(_ work: @escaping () -> Void) {
        guard loopSettings.listenAndRepeat, duration > 0 else { work(); return }
        player.pause()
        isPlaying = false
        pausedForRepeat = true
        updateNowPlayingInfo()
        let rawDelay = loopSettings.listenRepeatDelay.rawValue
        let delay = rawDelay < 0 ? duration : rawDelay
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.loopSettings.listenAndRepeat, self.pausedForRepeat else { return }
            self.pausedForRepeat = false
            work()
        }
    }

    private func setupPlayerTimeObserver() {
        // 0.1 s gives smooth UI progress without hammering MPNowPlayingInfoCenter.
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isWordLooping else { return }
                if let dur = self.player.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
                    // A resumed session waits for the real duration before it can
                    // restore its playhead; do that first and let the next tick
                    // report the corrected progress.
                    if let fraction = self.pendingSeekFraction {
                        self.pendingSeekFraction = nil
                        self.duration = dur
                        self.seek(toFraction: fraction)
                        return
                    }
                    self.progress = time.seconds / dur
                    if self.duration != dur { self.duration = dur }
                }
                // Throttle NowPlaying writes to once per second — writing every 0.1 s
                // causes the system to stall audio delivery on the main thread.
                let now = Date()
                if now.timeIntervalSince(self.lastNowPlayingUpdate) >= 1.0 {
                    self.lastNowPlayingUpdate = now
                    self.updateNowPlayingInfo()
                    self.recordListeningSession()
                }
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
