import Foundation

class QuranAPIService {
    static let shared = QuranAPIService()
    private let base = "https://api.alquran.cloud/v1"

    func fetchSurahList() async throws -> [Surah] {
        let url = URL(string: "\(base)/surah")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SurahListResponse.self, from: data)
        return response.data.map(\.toSurah)
    }

    func fetchAyahs(surahNumber: Int) async throws -> [Ayah] {
        let editions = "quran-simple,en.asad,en.transliteration"
        let url = URL(string: "\(base)/surah/\(surahNumber)/editions/\(editions)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(EditionsResponse.self, from: data)
        return merge(response.data)
    }

    private func merge(_ editions: [EditionData]) -> [Ayah] {
        guard
            let arabic = editions.first(where: { $0.edition.identifier == "quran-simple" }),
            let trans  = editions.first(where: { $0.edition.identifier == "en.asad" }),
            let translit = editions.first(where: { $0.edition.identifier == "en.transliteration" })
        else { return [] }

        return arabic.ayahs.indices.map { i in
            Ayah(
                numberInSurah:  arabic.ayahs[i].numberInSurah,
                globalNumber:   arabic.ayahs[i].number,
                arabic:         arabic.ayahs[i].text,
                translation:    trans.ayahs[safe: i]?.text ?? "",
                transliteration: translit.ayahs[safe: i]?.text ?? ""
            )
        }
    }
}

// MARK: - API response types (private)

private struct SurahListResponse: Codable {
    let data: [SurahAPIData]
}

private struct SurahAPIData: Codable {
    let number: Int
    let name: String
    let englishName: String
    let englishNameTranslation: String
    let numberOfAyahs: Int
    let revelationType: String

    var toSurah: Surah {
        Surah(
            number: number,
            name: name,
            englishName: englishName,
            englishNameTranslation: englishNameTranslation,
            numberOfAyahs: numberOfAyahs,
            revelationType: revelationType
        )
    }
}

private struct EditionsResponse: Codable {
    let data: [EditionData]
}

private struct EditionData: Codable {
    let edition: EditionInfo
    let ayahs: [AyahAPIData]
}

private struct EditionInfo: Codable {
    let identifier: String
    let language: String
    let name: String
    let type: String
}

private struct AyahAPIData: Codable {
    let number: Int
    let text: String
    let numberInSurah: Int
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
