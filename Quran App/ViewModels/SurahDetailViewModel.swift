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

    let surah: Surah
    private var surahTimingData: SurahTimingData?

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
