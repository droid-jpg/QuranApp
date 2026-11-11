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
    @Published var playbackRate: Float = 1.0

    /// The one repeat state. Set only through `setRepeat`, `startRepeat`,
    /// `setRepeatFromSystem` and playback itself. It may name a surah other than
    /// the one loaded (chosen in that surah's reader before playing); it is then
    /// inert until playback starts in that surah, and a start anywhere else turns
    /// it off.
    @Published private(set) var repeatState = RepeatState()

    /// Set while a word range loops. Suspends `repeatState` without changing it.
    @Published private(set) var wordRepeat: WordRepeat?
    var isWordLooping: Bool { wordRepeat != nil }

    /// True while the player is waiting for the current ayah's audio to arrive.
    /// Published only when it changes, which is at most a couple of times per ayah.
    @Published private(set) var isBuffering = false

    /// The ayah whose audio could not be played, until the next load. Playback is
    /// paused with that ayah still current, so Play retries it.
    @Published private(set) var failedAyah: Int?

    /// Repeat is on for the surah that is loaded.
    var isRepeating: Bool {
        repeatState.isOn && currentSurah > 0 && repeatState.surah == currentSurah
    }

    /// `repeatState` as it applies to the loaded surah (off when it names another).
    var activeRepeat: RepeatState {
        var s = repeatState
        if !isRepeating { s.isOn = false }
        return s
    }

    /// The playback status line, from the one status function.
    var statusText: String {
        activeRepeat.status(currentAyah: currentAyah ?? 1, reciterName: Reciter.selected.name,
                            wordRepeat: wordRepeat)
    }

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
    private var preloadedAyah: Int?             // which ayah `preloadedItem` holds
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    // Chapter-level player for word loops (quranicaudio.com full-chapter file).
    private var chapterPlayer: AVPlayer?
    private var chapterItem: AVPlayerItem?
    private var chapterTimeObserver: Any?
    private var loadedChapterUrl: URL?

    private var totalAyahs: Int = 0

    // Word-loop boundaries — global seconds into the chapter audio file.
    private var wordLoopStart: Double = 0
    private var wordLoopEnd: Double = 0
    private var isSeeking = false
    private var lastNowPlayingUpdate: Date = .distantPast

    /// True while waiting out a Listen & Repeat gap between ayahs. A manual stop or
    /// pause clears it so the scheduled resume is cancelled.
    private var pausedForRepeat = false

    /// What the Listen & Repeat gap will do when it ends, and the timer waiting to
    /// do it. Held separately so a pause during the gap can cancel the timer and
    /// keep the work for the next play, and so play can skip the gap.
    private var pendingRepeatWork: (() -> Void)?
    private var repeatGapTask: Task<Void, Never>?

    /// The ayah the main player was on before a word loop borrowed `currentSurah`
    /// and `currentAyah`, restored when the word loop ends.
    private var positionBeforeWordLoop: (surah: Int, ayah: Int?)?

    /// Position to restore once the ayah's real duration is known — set by
    /// `resume(_:)` so a saved listening session picks up mid-ayah.
    private var pendingSeekFraction: Double?

    /// Set when a call or another app interrupts playback, so it can pick up again afterwards.
    private var resumeAfterInterruption = false

    private var bufferingWatch: AnyCancellable?
    /// Watches the current item for a load failure; replaced whenever it changes.
    private var itemStatusWatch: AnyCancellable?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        setupPlayerTimeObserver()
        setupRemoteCommandCenter()
        observeAudioSession()
        observeBuffering()
    }

    // MARK: - Normal per-ayah playback

    /// Play from `startAyah`. Takes no repeat argument: the service's own
    /// `repeatState` is kept when it is for this surah and the ayah is inside its
    /// range, and turned off otherwise.
    func play(surah: Int, startAyah: Int, totalAyahs: Int, surahName: String = "") {
        cancelRepeatGap()
        pendingSeekFraction = nil
        stopWordLoopInternal()
        currentSurah = surah
        currentSurahName = surahName.isEmpty ? Self.surahName(surah) : surahName
        self.totalAyahs = totalAyahs
        repeatState = repeatState.keptWhenPlaying(surah: surah, ayah: startAyah)
        loadItem(ayah: startAyah)
    }

    /// Set `state` and play it from its first ayah (presets, the Repeat sheet).
    func startRepeat(_ state: RepeatState, totalAyahs: Int, surahName: String = "") {
        repeatState = state.clamped(ayahCount: totalAyahs)
        play(surah: state.surah, startAyah: repeatState.from, totalAyahs: totalAyahs, surahName: surahName)
    }

    /// Pick up a saved listening session exactly where it stopped — same ayah, same
    /// repeat, and (once the ayah has loaded and reported a duration) the same
    /// position inside it. Positions at the very edges are ignored: restoring to the
    /// last sliver of an ayah would just trip the end handler immediately.
    func resume(_ session: ListeningSession) {
        repeatState = session.repeatState
        play(surah: session.surah, startAyah: session.ayah,
             totalAyahs: session.totalAyahs, surahName: session.surahName)
        if session.fraction > 0.02 && session.fraction < 0.95 {
            pendingSeekFraction = session.fraction
        }
    }

    /// At launch, before anything plays: take the saved session's repeat as the
    /// service's own, so the Repeat sheet shows it while the player sits restored
    /// and paused. Loads nothing.
    func adoptRepeat(from session: ListeningSession) {
        guard currentAyah == nil, currentSurah == 0 else { return }
        repeatState = session.repeatState
    }

    // MARK: - Repeat changes

    /// Any change to the repeat. Applies at once: while playing, an ayah outside
    /// the new range jumps to its first ayah; while paused only the state changes
    /// and the jump happens on the next play.
    func setRepeat(_ new: RepeatState) {
        var s = new
        if s.surah == currentSurah, totalAyahs > 0 { s = s.clamped(ayahCount: totalAyahs) }
        let old = repeatState
        // A new range, count or on/off starts counting passes again; a pause
        // change alone does not.
        let shapeChanged = (s.isOn, s.surah, s.from, s.to, s.times)
            != (old.isOn, old.surah, old.from, old.to, old.times)
        if shapeChanged { s.completed = 0 }
        repeatState = s

        // In a pause the finished item has left the queue, so `currentItem` is nil.
        let inGap = pendingRepeatWork != nil
        guard currentSurah > 0, s.surah == currentSurah, !isWordLooping,
              let ayah = currentAyah, player.currentItem != nil || inGap else { return }
        if let target = activeRepeat.jumpTarget(current: ayah) {
            if isPlaying || pausedForRepeat { loadItem(ayah: target) }
            return
        }
        if inGap {
            // The gap's next step was decided by the old shape; redecide it.
            if shapeChanged {
                let adv = activeRepeat.advance(after: ayah, ayahCount: totalAyahs)
                repeatState = adv.state
                pendingRepeatWork = work(for: adv.step)
            }
        } else {
            refreshQueuedFollower()
        }
    }

    /// Lock screen and CarPlay: off ↔ the current ayah forever.
    func setRepeatFromSystem(_ on: Bool) {
        if on {
            setRepeat(.repeatThisAyah(surah: currentSurah, ayah: currentAyah ?? 1))
        } else {
            var s = repeatState
            s.isOn = false
            setRepeat(s)
        }
    }

    // MARK: - CarPlay / lock-screen navigation helpers

    func skipToNextAyah() {
        stopWordLoopInternal()
        guard let ayah = currentAyah,
              let next = activeRepeat.nextAyah(after: ayah, ayahCount: totalAyahs) else { return }
        loadItem(ayah: next)
    }

    func skipToPreviousAyah() {
        stopWordLoopInternal()
        guard let ayah = currentAyah,
              let prev = activeRepeat.previousAyah(before: ayah) else { return }
        loadItem(ayah: prev)
    }

    func togglePlayPause() {
        if isWordLooping {
            if isPlaying { chapterPlayer?.pause(); isPlaying = false }
            else         { chapterPlayer?.play();  isPlaying = true  }
        } else if !isPlaying, let ayah = currentAyah, player.currentItem != nil || pendingRepeatWork != nil,
                  let target = activeRepeat.jumpTarget(current: ayah) {
            // The range changed while paused and no longer holds this ayah.
            loadItem(ayah: target)
        } else if let work = pendingRepeatWork {
            // In (or held after) a Listen & Repeat gap: play means "go on now".
            cancelRepeatGap()
            work()
        } else if player.currentItem == nil {
            // The queue ran out (end of the Quran) but an ayah is still shown:
            // play starts that ayah again instead of doing nothing.
            guard !isPlaying, let ayah = currentAyah, currentSurah > 0 else { return }
            loadItem(ayah: ayah)
        } else {
            if isPlaying { player.pause(); isPlaying = false; ListeningSessionStore.shared.flush() }
            else         { player.play(); player.rate = playbackRate; isPlaying = true }
        }
    }

    /// Pause from outside the app's own button (lock screen, a call, headphones
    /// unplugged). During a Listen & Repeat gap nothing is audibly playing, so
    /// this stops the gap's timer; the next play carries on from there.
    private func pauseFromSystem() {
        if isPlaying {
            togglePlayPause()
        } else if pausedForRepeat {
            repeatGapTask?.cancel()
            repeatGapTask = nil
            pausedForRepeat = false
        }
    }

    private func cancelRepeatGap() {
        repeatGapTask?.cancel()
        repeatGapTask = nil
        pendingRepeatWork = nil
        pausedForRepeat = false
    }

    /// "Close player": stop, forget the saved session and clear the lock screen,
    /// so the mini player goes away and stays away after a relaunch.
    func closePlayer() {
        stop()
        ListeningSessionStore.shared.clear()
        updateNowPlayingInfo()
    }

    private func stop() {
        cancelRepeatGap()
        pendingSeekFraction = nil
        stopWordLoopInternal()
        clearPlayerItem()
        isPlaying = false
        currentAyah = nil
        failedAyah = nil
        progress = 0
        ListeningSessionStore.shared.flush()
    }

    /// Snapshot what's playing for Home's resume card. Cheap and throttled inside
    /// the store, so it's safe to call from the once-a-second playback tick.
    private func recordListeningSession() {
        guard let ayah = currentAyah, currentSurah > 0, totalAyahs > 0 else { return }
        ListeningSessionStore.shared.record(
            surah: currentSurah, surahName: currentSurahName, ayah: ayah,
            totalAyahs: totalAyahs, repeatState: activeRepeat,
            fraction: progress, duration: duration
        )
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
        wordEndMs: Int,
        fromWord: Int,
        toWord: Int
    ) {
        wordLoopStart = Double(wordStartMs) / 1000.0
        wordLoopEnd   = Double(wordEndMs)   / 1000.0
        if !isWordLooping {
            positionBeforeWordLoop = (currentSurah, player.currentItem != nil ? currentAyah : nil)
        }
        cancelRepeatGap()
        currentSurah  = surah
        currentAyah   = ayah
        isSeeking     = false
        wordRepeat    = WordRepeat(surah: surah, ayah: ayah,
                                   fromWord: min(fromWord, toWord), toWord: max(fromWord, toWord))

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

    /// End a word loop. With `resume`, the main player carries on from where it
    /// was; without, it stays paused there for the caller to decide.
    func stopWordLoop(resume: Bool = true) {
        guard isWordLooping else { return }
        stopWordLoopInternal()
        if resume, player.currentItem != nil {
            player.play()
            isPlaying = true
        } else {
            isPlaying = false
        }
    }

    // MARK: - Internal: per-ayah (AVQueuePlayer)

    /// Load an ayah by rebuilding the queue on the shared AVQueuePlayer.
    /// The ayah that will follow is pre-queued so iOS can auto-advance in the
    /// background without a new play() call.
    private func loadItem(ayah: Int) {
        removeEndObserver()
        cancelRepeatGap()

        currentAyah = ayah
        isSeeking   = false
        if failedAyah != nil { failedAyah = nil }

        // Tear down old queue and insert the new current item.
        player.removeAllItems()
        preloadedItem = nil
        preloadedAyah = nil

        let item = AVPlayerItem(url: audioURL(surah: currentSurah, ayah: ayah))
        item.preferredForwardBufferDuration = 6
        playerItem = item
        watchStatus(of: item)
        player.insert(item, after: nil)

        queueFollower(after: ayah)

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
                totalAyahs: totalAyahs, repeatState: activeRepeat, fraction: 0, duration: 0
            )
        }
    }

    /// Pre-queue the ayah that `repeatState` says follows `ayah`, when it follows
    /// seamlessly: same surah, no pause (a queued item would play through the
    /// pause). Covers repeats too, so a range keeps looping in the background.
    private func queueFollower(after ayah: Int) {
        let adv = activeRepeat.advance(after: ayah, ayahCount: totalAyahs)
        guard adv.pause == .none, case .ayah(let next) = adv.step else { return }
        let item = AVPlayerItem(url: audioURL(surah: currentSurah, ayah: next))
        item.preferredForwardBufferDuration = 6
        player.insert(item, after: player.items().last)
        preloadedItem = item   // strong ref — we'll observe it in handleAyahEnd
        preloadedAyah = next
    }

    /// Re-pick the pre-queued follower after the repeat changed mid-ayah.
    private func refreshQueuedFollower() {
        if let pre = preloadedItem, player.items().contains(pre), pre !== player.currentItem {
            player.remove(pre)
        }
        preloadedItem = nil
        preloadedAyah = nil
        guard let ayah = currentAyah, player.currentItem != nil else { return }
        queueFollower(after: ayah)
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
        itemStatusWatch = nil
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

        let adv = activeRepeat.advance(after: ayah, ayahCount: totalAyahs)
        // A state for another surah is left alone; only the live one moves on.
        if isRepeating { repeatState = adv.state }

        if adv.pause == .none, case .ayah(let next) = adv.step,
           let pre = preloadedItem, preloadedAyah == next {
            // Seamless, background-safe advance using the pre-queued item.
            currentAyah   = next
            playerItem    = pre
            preloadedItem = nil
            preloadedAyah = nil
            watchStatus(of: pre)
            observeAyahEnd()
            queueFollower(after: next)
            updateNowPlayingInfo()
        } else {
            // During a pause currentAyah stays put so the reader keeps
            // highlighting the ayah being recited.
            scheduleAfterRepeatPause(adv.pause, work(for: adv.step))
        }
    }

    private func work(for step: RepeatState.Step) -> () -> Void {
        switch step {
        case .ayah(let n): return { [weak self] in self?.loadItem(ayah: n) }
        case .nextSurah:   return { [weak self] in self?.continueToNextSurahOrStop() }
        }
    }

    /// Ayah 1 of the next surah, with repeat off (a surah change always turns it
    /// off); after An-Nas, stop.
    private func continueToNextSurahOrStop() {
        if currentSurah < 114, let nextCount = Self.surahAyahCounts[currentSurah + 1] {
            currentSurah    += 1
            currentSurahName = Self.surahName(currentSurah)
            totalAyahs       = nextCount
            repeatState      = repeatState.keptWhenPlaying(surah: currentSurah, ayah: 1)
            loadItem(ayah: 1)
        } else {
            // End of the Quran. The last ayah stays shown; play starts it again.
            player.removeAllItems()
            playerItem = nil
            preloadedItem = nil
            preloadedAyah = nil
            isPlaying = false
            progress = 0
            updateNowPlayingInfo()
        }
    }

    /// The English name for a surah from the bundled text (no network), falling
    /// back to the list cached for the widget, then to "Surah N".
    private static func surahName(_ number: Int) -> String {
        if let s = QuranOfflineStore.shared.surahs().first(where: { $0.number == number }) {
            return s.englishName
        }
        if let s = SharedSurahCache.load().first(where: { $0.number == number }) {
            return s.englishName
        }
        return "Surah \(number)"
    }

    /// Runs `work` after the repeat pause — a fixed number of seconds, or the
    /// just-played ayah's own length. With no pause, `work` runs immediately. A
    /// manual stop clears `pausedForRepeat`, cancelling a scheduled resume.
    private func scheduleAfterRepeatPause(_ pause: RepeatState.Pause, _ work: @escaping () -> Void) {
        let delay: Double
        switch pause {
        case .none:           work(); return
        case .ayahLength:     delay = duration
        case .seconds(let s): delay = Double(s)
        }
        guard delay > 0 else { work(); return }
        player.pause()
        isPlaying = false
        repeatGapTask?.cancel()
        pendingRepeatWork = work
        pausedForRepeat = true
        updateNowPlayingInfo()
        repeatGapTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.pausedForRepeat,
                  let work = self.pendingRepeatWork else { return }
            self.cancelRepeatGap()
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

    // MARK: - Loading and failure state

    private func observeBuffering() {
        bufferingWatch = player.publisher(for: \.timeControlStatus)
            .map { $0 == .waitingToPlayAtSpecifiedRate }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] waiting in
                MainActor.assumeIsolated {
                    guard let self, self.isBuffering != waiting else { return }
                    self.isBuffering = waiting
                }
            }
    }

    private func watchStatus(of item: AVPlayerItem) {
        itemStatusWatch = item.publisher(for: \.status, options: [.initial, .new])
            .filter { $0 == .failed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                MainActor.assumeIsolated {
                    guard let self, let item else { return }
                    self.handleItemFailure(item)
                }
            }
    }

    /// The current ayah's audio couldn't load (no network, missing file). Stop
    /// the queue there and keep the ayah current: Play then reloads it.
    private func handleItemFailure(_ item: AVPlayerItem) {
        guard item === playerItem, !isWordLooping else { return }
        cancelRepeatGap()
        clearPlayerItem()
        isPlaying = false
        failedAyah = currentAyah
        updateNowPlayingInfo()
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
        if isWordLooping, let before = positionBeforeWordLoop {
            currentSurah = before.surah
            currentAyah  = before.ayah
        }
        positionBeforeWordLoop = nil
        wordRepeat = nil
        teardownChapterPlayer()
    }

    // MARK: - Interruptions and route changes

    /// The HIG's "Playing audio" guidance: when a call or another app interrupts, stop showing
    /// playback as running and resume afterwards only if the system says it should; when
    /// headphones are unplugged, stay paused. AVPlayer pauses itself in both cases, but nothing
    /// told `isPlaying`, so the app kept showing a pause button over silence.
    private func observeAudioSession() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                           queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(
                rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated {
                guard let self, let type else { return }
                switch type {
                case .began:
                    guard self.isPlaying || self.pausedForRepeat else { return }
                    self.resumeAfterInterruption = true
                    self.pauseFromSystem()
                case .ended:
                    defer { self.resumeAfterInterruption = false }
                    guard self.resumeAfterInterruption, options.contains(.shouldResume), !self.isPlaying
                    else { return }
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self.togglePlayPause()
                @unknown default:
                    break
                }
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                           queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                // Headphones or a car disconnected: keep the recitation private by staying paused.
                guard let self, reason == .oldDeviceUnavailable else { return }
                self.pauseFromSystem()
            }
        }
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
                self?.pauseFromSystem()
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
                self?.setRepeatFromSystem(e.repeatType != .off)
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
        let repeating = activeRepeat
        MPRemoteCommandCenter.shared().changeRepeatModeCommand.currentRepeatType =
            !repeating.isOn ? .off : repeating.isSingleAyah ? .one : .all
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:             repeating.status(currentAyah: ayah,
                                                                   reciterName: Reciter.selected.name,
                                                                   wordRepeat: wordRepeat),
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
