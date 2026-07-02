import Foundation
import Combine

@MainActor
class SurahDetailViewModel: ObservableObject {
    @Published var ayahs: [Ayah] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var loopSettings: LoopSettings
    @Published var showLoopSheet = false

    @Published var wordTimingsByAyah: [Int: [WordTiming]] = [:]
    @Published var isLoadingWordTimings = false
    @Published var wordTimingsError: String? = nil

    // Word-by-word details (meaning/transliteration/audio) and ayah commentary.
    @Published var wordDetailsByAyah: [Int: [WordDetail]] = [:]
    @Published var tafsirByAyah: [Int: String] = [:]

    let surah: Surah
    private var surahTimingData: SurahTimingData?
    private var didLoadWordDetails = false
    private var didLoadTafsir = false

    init(surah: Surah) {
        self.surah = surah
        var settings = LoopSettings()
        settings.endAyah = surah.numberOfAyahs
        self.loopSettings = settings
    }

    // MARK: - Ayah loading

    func loadAyahs() async {
        isLoading = true
        error = nil
        do {
            ayahs = try await QuranAPIService.shared.fetchAyahs(surahNumber: surah.number)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Word timings

    func loadWordTimingsIfNeeded() async {
        guard surahTimingData == nil, !isLoadingWordTimings, !ayahs.isEmpty else { return }
        isLoadingWordTimings = true
        wordTimingsError = nil
        do {
            let data = try await WordTimingService.shared.timings(surah: surah.number, ayahs: ayahs)
            surahTimingData = data
            wordTimingsByAyah = data.wordTimings
        } catch {
            wordTimingsError = error.localizedDescription
        }
        isLoadingWordTimings = false
    }

    // Exposed for SurahDetailView when wiring the word-loop callback
    func chapterAudioUrl() -> URL? { surahTimingData?.chapterAudioUrl }

    // MARK: - Word-by-word details & tafsir

    /// Per-word meaning/transliteration/audio for tappable words. Best-effort:
    /// a failure leaves the map empty so the reader still renders Arabic, and the
    /// guard allows a retry on the next call only if the previous attempt failed.
    func loadWordDetails() async {
        guard !didLoadWordDetails else { return }
        do {
            let details = try await WordDetailService.shared.wordDetails(surah: surah.number)
            wordDetailsByAyah = details
            didLoadWordDetails = true
        } catch {
            // Leave didLoadWordDetails false so a later view appearance can retry.
        }
    }

    /// Ayah-level commentary, keyed by ayah number. Only ayahs with non-empty
    /// commentary appear, so the reader shows the affordance solely on those.
    func loadTafsir() async {
        guard !didLoadTafsir else { return }
        do {
            let map = try await TafsirService.shared.tafsir(surah: surah.number)
            tafsirByAyah = map
            didLoadTafsir = true
        } catch {
            // Best-effort; retry allowed on a later appearance.
        }
    }

    // MARK: - Resume tracking

    /// Returns the last ayah the user played in this surah, if > 1.
    func lastPlayedAyah() -> Int? {
        let val = UserDefaults.standard.integer(forKey: "lastPlayedAyah_\(surah.number)")
        return val > 1 ? val : nil
    }

    /// Called when playback starts for a specific ayah.
    func recordPlay(ayah: Int) {
        UserDefaults.standard.set(ayah, forKey: "lastPlayedAyah_\(surah.number)")
    }

    // MARK: - Playback

    func applyLoopSettings(_ settings: LoopSettings, audioService: AudioService) {
        loopSettings = settings
        audioService.updateLoop(settings)
    }

    func playAyah(_ number: Int, audioService: AudioService) {
        if audioService.currentSurah == surah.number, audioService.currentAyah == number {
            audioService.togglePlayPause()
        } else {
            recordPlay(ayah: number)
            audioService.play(
                surah: surah.number,
                startAyah: number,
                loop: loopSettings,
                totalAyahs: surah.numberOfAyahs
            )
        }
    }
}
