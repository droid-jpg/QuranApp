import Foundation
import Combine

@MainActor
class SurahListViewModel: ObservableObject {
    @Published var surahs: [Surah] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var searchText = ""

    var filtered: [Surah] {
        guard !searchText.isEmpty else { return surahs }
        return surahs.filter {
            $0.englishName.localizedCaseInsensitiveContains(searchText) ||
            $0.englishNameTranslation.localizedCaseInsensitiveContains(searchText) ||
            String($0.number).contains(searchText)
        }
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            surahs = try await QuranAPIService.shared.fetchSurahList()
            SharedSurahCache.save(surahs)   // keep widget data fresh
            SurahRegistry.shared.surahs = surahs
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Shared surah list registry
// Populated when the main list loads so any view can access the full ordered
// surah list without needing the SurahListViewModel in scope.
final class SurahRegistry {
    static let shared = SurahRegistry()
    private init() {}
    var surahs: [Surah] = []
}
