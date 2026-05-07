import Foundation
import Combine

@MainActor
class SurahDetailViewModel: ObservableObject {
    @Published var ayahs: [Ayah] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var loopSettings: LoopSettings
    @Published var showLoopSheet = false

    let surah: Surah

    init(surah: Surah) {
        self.surah = surah
        var settings = LoopSettings()
        settings.endAyah = surah.numberOfAyahs
        self.loopSettings = settings
    }

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

    func applyLoopSettings(_ settings: LoopSettings, audioService: AudioService) {
        loopSettings = settings
        audioService.updateLoop(settings)
    }

    func playAyah(_ number: Int, audioService: AudioService) {
        if audioService.currentSurah == surah.number, audioService.currentAyah == number {
            audioService.togglePlayPause()
        } else {
            audioService.play(
                surah: surah.number,
                startAyah: number,
                loop: loopSettings,
                totalAyahs: surah.numberOfAyahs
            )
        }
    }
}
