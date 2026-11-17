import AVFoundation
import MediaPlayer
import Observation

/// The app's one audio engine.
///
/// It plays one local file per ayah (`AudioStore`), so there is no streaming and no
/// buffering state: an ayah is either on disk or being fetched. Everything else is a
/// decision made when an ayah ends (`step`): the next ayah, the start of the repeat
/// range, the next surah, or stop.
///
/// Views read the properties they draw. `@Observable` tracks each one separately, so
/// the 20 Hz `progress` and `wordPosition` only redraw the views that show them.
@MainActor @Observable
final class Player {

    // MARK: - State

    /// The surah loaded, playing or paused. Nil until something has been played.
    private(set) var surah: Surah?
    /// The ayah loaded. 0 while nothing is.
    private(set) var ayah = 0
    /// What the listener asked for. Stays true while an ayah is being fetched and
    /// during the pause after an ayah.
    private(set) var isPlaying = false
    /// The current ayah is being fetched.
    private(set) var isLoading = false
    /// The current ayah could not be fetched. Cleared by the next play.
    private(set) var failed = false
    private(set) var repeatRange: RepeatRange?
    /// Passes of the repeat range finished so far.
    private(set) var passesDone = 0
    /// The word being recited (quran.com position, 1-based), when timings are known.
    private(set) var wordPosition: Int?
    /// How many words quran.com counts in the current ayah. 0 when unknown.
    private(set) var timedWordCount = 0
    /// A stretch of words inside one ayah being repeated or played once.
    private(set) var wordLoop: WordLoop?
    /// 0...1 through the current ayah.
    private(set) var progress = 0.0
    /// The last few surahs listened to, newest first.
    private(set) var recents: [Recent] = []

    private(set) var rate: Float = 1
    private(set) var pauseAfterAyah: PauseAfterAyah = .off

    static let rateChoices: [Float] = [0.75, 1, 1.25, 1.5]

    func setRate(_ value: Float) {
        rate = value
        UserDefaults.standard.set(value, forKey: Keys.rate)
        if player.rate != 0 { player.rate = value }
        updateNowPlaying()
    }

    func setPauseAfterAyah(_ value: PauseAfterAyah) {
        pauseAfterAyah = value
        UserDefaults.standard.set(value.rawValue, forKey: Keys.pause)
    }

    struct WordLoop: Equatable {
        let ayah: Int
        let from: Int
        let to: Int
        var start: Double
        var end: Double
        /// Play the stretch once and stop, instead of repeating it.
        var once = false
    }

    struct Recent: Codable, Equatable, Identifiable {
        var surah: Int
        var ayah: Int
        var repeatRange: RepeatRange?
        var id: Int { surah }
    }

    /// True when there is something to resume.
    var hasSession: Bool { surah != nil && ayah > 0 }

    func isCurrent(_ surah: Int) -> Bool { self.surah?.number == surah }

    // MARK: - Private

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var spans: [Int: [WordSpan]] = [:]
    @ObservationIgnored private var spansKey = ""
    @ObservationIgnored private var gapTask: Task<Void, Never>?
    /// Plays silence through the pause after an ayah, and while an ayah is fetched.
    /// iOS suspends an app in the background a few seconds after its audio stops,
    /// and a suspended app would never start the next ayah on a locked phone.
    @ObservationIgnored private lazy var silence: AVAudioPlayer? = {
        let player = try? AVAudioPlayer(data: Self.silentWAV)
        player?.numberOfLoops = -1
        player?.volume = 0
        return player
    }()
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var itemLoaded = false
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var durationReported = false
    /// Called when a surah's last missing ayah has been fetched by playing it.
    @ObservationIgnored var onSurahFetched: ((Surah) -> Void)?

    private enum Keys {
        static let rate = "playbackRate"
        static let pause = "pauseAfterAyah"
        static let recents = "recentListening_v2"
    }

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.object(forKey: Keys.rate) as? Float, saved > 0 { rate = saved }
        pauseAfterAyah = PauseAfterAyah(rawValue: defaults.string(forKey: Keys.pause) ?? "") ?? .off
        if let data = defaults.data(forKey: Keys.recents),
           let saved = try? JSONDecoder().decode([Recent].self, from: data) {
            recents = saved
        }
        // Come back paused where listening stopped.
        if let last = recents.first, let surah = QuranText.shared.surah(last.surah) {
            self.surah = surah
            ayah = min(max(1, last.ayah), surah.numberOfAyahs)
            repeatRange = last.repeatRange
        }
        player.automaticallyWaitsToMinimizeStalling = false
        observe()
        setUpRemoteCommands()
    }

    // MARK: - Commands

    /// Plays a surah from an ayah. A repeat stays on only if it covers that ayah.
    func play(_ surah: Surah, from ayah: Int = 1) {
        if self.surah != surah || repeatRange?.contains(ayah) != true { clearRepeatState() }
        self.surah = surah
        wordLoop = nil
        isPlaying = true
        load(ayah)
    }

    /// Resumes a recent surah where it was left, with the repeat it had.
    func play(_ recent: Recent) {
        guard let surah = QuranText.shared.surah(recent.surah) else { return }
        self.surah = surah
        repeatRange = recent.repeatRange
        passesDone = 0
        wordLoop = nil
        isPlaying = true
        load(recent.ayah)
    }

    func toggle() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        cancelGap()
        isPlaying = false
        player.pause()
        updateNowPlaying()
    }

    func resume() {
        guard surah != nil, ayah > 0 else { return }
        isPlaying = true
        if failed || !itemLoaded {
            load(ayah)
        } else if pendingStep != nil {
            // Paused during the pause after an ayah: carry on with what was due.
            runPendingStep()
        } else {
            activateSession()
            player.playImmediately(atRate: rate)
            updateNowPlaying()
        }
    }

    func next() {
        guard let surah, ayah > 0 else { return }
        wordLoop = nil
        if ayah < surah.numberOfAyahs {
            jump(to: ayah + 1)
        } else if let following = QuranText.shared.surah(surah.number + 1) {
            let wasPlaying = isPlaying
            clearRepeatState()
            self.surah = following
            isPlaying = wasPlaying
            load(1)
        }
    }

    func previous() {
        guard surah != nil, ayah > 0 else { return }
        wordLoop = nil
        // Like a music player: back to the start of this ayah first, then the one before.
        if player.currentTime().seconds > 2 || ayah == 1 {
            cancelGap()
            pendingStep = nil
            progress = 0
            player.seek(to: .zero)
            if isPlaying, itemLoaded { player.playImmediately(atRate: rate) }
            updateNowPlaying()
        } else {
            jump(to: ayah - 1)
        }
    }

    /// Moves to an ayah of the loaded surah, keeping play or pause as it was.
    func jump(to ayah: Int) {
        guard let surah, (1...surah.numberOfAyahs).contains(ayah) else { return }
        if repeatRange?.contains(ayah) == false { clearRepeatState() }
        wordLoop = nil
        load(ayah)
    }

    // MARK: - Repeat

    /// Repeats a range of a surah and starts playing it. If the ayah loaded is already
    /// inside the range, playback carries on from there.
    func setRepeat(in surah: Surah, from: Int, to: Int, times: Int = 0) {
        let range = RepeatRange(from: min(from, to), to: max(from, to), times: times)
        let stayPut = self.surah == surah && range.contains(ayah) && itemLoaded && !failed
        self.surah = surah
        repeatRange = range
        passesDone = 0
        wordLoop = nil
        isPlaying = true
        if stayPut {
            saveSession()
            resume()
        } else {
            load(range.from)
        }
    }

    /// Repeats just the ayah that is loaded.
    func repeatCurrentAyah() {
        guard let surah, ayah > 0 else { return }
        setRepeat(in: surah, from: ayah, to: ayah, times: repeatRange?.times ?? 0)
    }

    func setRepeatTimes(_ times: Int) {
        guard repeatRange != nil else { return }
        repeatRange?.times = times
        passesDone = 0
        saveSession()
    }

    func clearRepeat() {
        clearRepeatState()
        saveSession()
    }

    private func clearRepeatState() {
        repeatRange = nil
        passesDone = 0
    }

    // MARK: - Words

    /// Repeats (or, with `once`, plays one time) the words `from...to` of an ayah.
    /// Does nothing until that surah's timings have been fetched.
    func playWords(in surah: Surah, ayah: Int, from: Int, to: Int, once: Bool) async {
        let timings = await WordTimings.shared.spans(reciter: .selected, surah: surah.number)
        guard let ayahSpans = timings[ayah],
              let start = ayahSpans.first(where: { $0.word >= from })?.start,
              let end = ayahSpans.last(where: { $0.word <= to })?.end, end > start else { return }
        if self.surah != surah { clearRepeatState() }
        self.surah = surah
        wordLoop = WordLoop(ayah: ayah, from: from, to: to, start: start, end: end, once: once)
        isPlaying = true
        load(ayah, startAt: start)
    }

    func stopWords() {
        guard wordLoop != nil else { return }
        wordLoop = nil
        pause()
    }

    /// Whether word timings exist for this surah with the selected reciter.
    func hasTimings(for surah: Int) async -> Bool {
        !(await WordTimings.shared.spans(reciter: .selected, surah: surah)).isEmpty
    }

    // MARK: - Loading an ayah

    private func load(_ number: Int, startAt: Double = 0) {
        guard let surah else { return }
        cancelGap()
        pendingStep = nil
        generation += 1
        let token = generation
        let reciter = Reciter.selected

        ayah = number
        failed = false
        progress = 0
        wordPosition = nil
        timedWordCount = 0
        itemLoaded = false
        durationReported = false
        player.pause()
        saveSession()

        if AudioStore.isLocal(reciter: reciter, surah: surah.number, ayah: number) {
            isLoading = false
            start(AudioStore.fileURL(reciter: reciter, surah: surah.number, ayah: number), at: startAt)
        } else {
            isLoading = true
            // Likewise while the next ayah is fetched: the app must stay awake to play it.
            if isPlaying {
                activateSession()
                silence?.play()
            }
            updateNowPlaying()
            Task {
                do {
                    let url = try await AudioStore.shared.file(reciter: reciter, surah: surah.number, ayah: number)
                    guard token == generation else { return }
                    isLoading = false
                    start(url, at: startAt)
                    onSurahFetched?(surah)
                } catch {
                    guard token == generation else { return }
                    isLoading = false
                    failed = true
                    isPlaying = false
                    silence?.pause()
                    updateNowPlaying()
                }
            }
        }

        AudioStore.shared.prefetch(reciter: reciter, surah: surah.number, ayahs: upcoming(after: number, in: surah))
        loadSpans(reciter: reciter, surah: surah.number, token: token)
    }

    private func start(_ url: URL, at seconds: Double) {
        silence?.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        itemLoaded = true
        if seconds > 0 {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if isPlaying {
            activateSession()
            player.playImmediately(atRate: rate)
        }
        updateNowPlaying()
    }

    /// The next three ayahs that will be needed, following the repeat range around.
    private func upcoming(after number: Int, in surah: Surah) -> [Int] {
        var result: [Int] = []
        var n = number
        for _ in 0..<3 {
            if let range = repeatRange, n >= range.to { n = range.from } else { n += 1 }
            guard n <= surah.numberOfAyahs, n != number, !result.contains(n) else { break }
            result.append(n)
        }
        return result
    }

    private func loadSpans(reciter: Reciter, surah: Int, token: Int) {
        let key = "\(reciter.id)_\(surah)"
        if key == spansKey {
            timedWordCount = spans[ayah]?.map(\.word).max() ?? 0
            return
        }
        Task {
            let fetched = await WordTimings.shared.spans(reciter: reciter, surah: surah)
            guard token == generation || (self.surah?.number == surah && Reciter.selected == reciter) else { return }
            spans = fetched
            spansKey = key
            timedWordCount = fetched[ayah]?.map(\.word).max() ?? 0
        }
    }

    // MARK: - When an ayah ends

    private enum Step { case ayah(Int), surah(Surah), finishRepeat(Int), stop }

    @ObservationIgnored private var pendingStep: Step?

    private func ayahEnded() {
        guard let surah, isPlaying else { return }
        if let loop = wordLoop {
            loop.once ? stopWords() : seekAndPlay(loop.start)
            return
        }
        let step = step(after: ayah, in: surah)
        let duration = player.currentItem?.duration.seconds ?? 0
        let gap = pauseAfterAyah.seconds(ayahDuration: duration.isFinite ? duration / Double(rate) : 0)
        guard gap > 0, case .ayah = step else {
            perform(step)
            return
        }
        pendingStep = step
        silence?.play()
        gapTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(gap))
            guard !Task.isCancelled else { return }
            self?.runPendingStep()
        }
    }

    private func step(after number: Int, in surah: Surah) -> Step {
        if let range = repeatRange {
            if number < range.to { return .ayah(number + 1) }
            let done = passesDone + 1
            if range.times == 0 || done < range.times {
                passesDone = done
                return .ayah(range.from)
            }
            return .finishRepeat(range.from)
        }
        if number < surah.numberOfAyahs { return .ayah(number + 1) }
        if let following = QuranText.shared.surah(surah.number + 1) { return .surah(following) }
        return .stop
    }

    private func runPendingStep() {
        guard let step = pendingStep else { return }
        pendingStep = nil
        gapTask = nil
        silence?.pause()
        perform(step)
    }

    private func perform(_ step: Step) {
        switch step {
        case .ayah(let number):
            load(number)
        case .surah(let following):
            surah = following
            load(1)
        case .finishRepeat(let first):
            // Every pass has played: stop at the start of the range, ready to go again.
            passesDone = 0
            isPlaying = false
            load(first)
        case .stop:
            isPlaying = false
            player.pause()
            updateNowPlaying()
        }
    }

    /// Stops waiting out the pause after an ayah. The step that was due is kept, so
    /// Play carries on with it; loading any ayah discards it.
    private func cancelGap() {
        gapTask?.cancel()
        gapTask = nil
        silence?.pause()
    }

    /// One second of silence as a WAV file: 8 kHz, mono, 16-bit.
    private static let silentWAV: Data = {
        let sampleRate: UInt32 = 8000
        let byteCount = sampleRate * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + byteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(sampleRate); append(sampleRate * 2)
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        data.append(Data(count: Int(byteCount)))
        return data
    }()

    private func seekAndPlay(_ seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        if isPlaying { player.playImmediately(atRate: rate) }
    }

    // MARK: - Observing the player

    private func observe() {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            let item = note.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, item === self.player.currentItem else { return }
                self.ayahEnded()
            }
        }

        // 20 Hz: the word being recited, the word loop's end, and the progress line.
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }

        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == .began {
                    self.resumeAfterInterruption = self.isPlaying
                    if self.isPlaying { self.pause() }
                } else if type == .ended {
                    if self.resumeAfterInterruption, options.contains(.shouldResume) { self.resume() }
                    self.resumeAfterInterruption = false
                }
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                // Headphones unplugged: stop rather than carry on through the speaker.
                if reason == .oldDeviceUnavailable, self?.isPlaying == true { self?.pause() }
            }
        }
    }

    private func tick(_ seconds: Double) {
        guard itemLoaded, seconds.isFinite else { return }
        if let loop = wordLoop, seconds >= loop.end - 0.02 {
            loop.once ? stopWords() : seekAndPlay(loop.start)
            return
        }
        if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 {
            let value = min(1, max(0, seconds / duration))
            if abs(value - progress) > 0.004 { progress = value }
            if !durationReported {
                durationReported = true
                updateNowPlaying()
            }
        }
        let word = spans[ayah]?.last(where: { $0.start <= seconds })?.word
        if word != wordPosition { wordPosition = word }
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    // MARK: - Remembering where listening stopped

    private func saveSession() {
        guard let surah, ayah > 0 else { return }
        let entry = Recent(surah: surah.number, ayah: ayah, repeatRange: repeatRange)
        if recents.first != entry {
            recents.removeAll { $0.surah == surah.number }
            recents.insert(entry, at: 0)
            if recents.count > 6 { recents.removeLast(recents.count - 6) }
        }
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: Keys.recents)
        }
    }

    /// Forgets the session and stops, for "Close player".
    func close() {
        cancelGap()
        pendingStep = nil
        generation += 1
        isPlaying = false
        isLoading = false
        failed = false
        wordLoop = nil
        clearRepeatState()
        player.replaceCurrentItem(with: nil)
        itemLoaded = false
        surah = nil
        ayah = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// The reciter changed: drop the loaded file and timings so the next play uses the new one.
    func reciterChanged() {
        spans = [:]
        spansKey = ""
        wordLoop = nil
        if hasSession { load(ayah) }
    }

    // MARK: - Lock screen and Control Center

    private func setUpRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let surah, ayah > 0 else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "\(surah.englishName) · Ayah \(ayah)",
            MPMediaItemPropertyArtist: Reciter.selected.name,
            MPMediaItemPropertyAlbumTitle: "Quran",
            MPNowPlayingInfoPropertyPlaybackRate: player.rate,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0),
        ]
        if let duration = player.currentItem?.duration.seconds, duration.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
