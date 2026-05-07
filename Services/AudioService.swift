import AVFoundation
import Combine

@MainActor
class AudioService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentAyah: Int? = nil
    @Published var currentSurah: Int = 0
    @Published var progress: Double = 0

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    private var loopSettings = LoopSettings()
    private var totalAyahs: Int = 0
    private var repeatCounter = 0

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Public API

    func play(surah: Int, startAyah: Int, loop: LoopSettings, totalAyahs: Int) {
        currentSurah = surah
        loopSettings = loop
        self.totalAyahs = totalAyahs
        repeatCounter = 0
        load(ayah: startAyah)
    }

    func togglePlayPause() {
        guard player != nil else { return }
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true
        }
    }

    func stop() {
        teardown()
        isPlaying = false
        currentAyah = nil
        progress = 0
    }

    func updateLoop(_ settings: LoopSettings) {
        loopSettings = settings
    }

    // MARK: - Internal

    private func load(ayah: Int) {
        teardown()
        currentAyah = ayah

        let url = audioURL(surah: currentSurah, ayah: ayah)
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        observeEnd()
        observeTime()
        player?.play()
        isPlaying = true
    }

    private func audioURL(surah: Int, ayah: Int) -> URL {
        let s = String(format: "%03d", surah)
        let a = String(format: "%03d", ayah)
        // Mishary Rashid Al-Afasy 128kbps
        return URL(string: "https://everyayah.com/data/Alafasy_128kbps/\(s)\(a).mp3")!
    }

    private func observeEnd() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleEnd() }
        }
    }

    private func handleEnd() {
        guard let ayah = currentAyah else { return }

        switch loopSettings.mode {

        case .off:
            if ayah < totalAyahs {
                load(ayah: ayah + 1)
            } else {
                isPlaying = false
            }

        case .single:
            let max = loopSettings.repeatCount
            if max == 0 || repeatCounter < max - 1 {
                repeatCounter += 1
                player?.seek(to: .zero)
                player?.play()
            } else {
                repeatCounter = 0
                isPlaying = false
            }

        case .segment:
            if ayah < loopSettings.endAyah {
                load(ayah: ayah + 1)
            } else {
                let max = loopSettings.repeatCount
                if max == 0 || repeatCounter < max - 1 {
                    repeatCounter += 1
                    load(ayah: loopSettings.startAyah)
                } else {
                    repeatCounter = 0
                    isPlaying = false
                }
            }
        }
    }

    private func observeTime() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self,
                  let duration = self.playerItem?.duration.seconds,
                  duration.isFinite, duration > 0 else { return }
            self.progress = time.seconds / duration
        }
    }

    private func teardown() {
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs); endObserver = nil }
        player?.pause()
        player = nil
        playerItem = nil
    }
}
