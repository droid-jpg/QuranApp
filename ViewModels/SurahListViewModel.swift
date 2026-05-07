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
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
