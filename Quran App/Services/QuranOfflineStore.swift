import Foundation

/// Reads the bundled Quran text (`quran_offline.json`) so the surah list and the
/// core reading text (Arabic + transliteration + the default English translation)
/// are always available with no network — the app opens and reads instantly, and
/// survives a dead API or airplane mode. Network is then only needed for audio and
/// optional extras (word timings, tafsir, and non-default translations, the latter
/// backed by an on-disk cache in `QuranAPIService`).
///
/// The bundle stores raw Arabic; the leading Basmala is stripped on load via the
/// same `QuranAPIService.strippingLeadingBasmala` the network path uses, so bundled
/// and fetched text line up exactly (including with the word-by-word data).
final class QuranOfflineStore {
    static let shared = QuranOfflineStore()

    /// The translation edition the bundled `translation` column was built from.
    /// Bundled translation text is only surfaced when the user reads with this
    /// edition; other editions come from the network / disk cache.
    private(set) var bundledTranslationId = "en.asad"

    private struct Payload: Decodable {
        let translationId: String
        let surahs: [SurahMeta]
        let ayahs: [String: [[String]]]   // surah → [[arabic, translit, translation], …]
    }
    private struct SurahMeta: Decodable {
        let number: Int
        let name: String
        let englishName: String
        let englishNameTranslation: String
        let numberOfAyahs: Int
        let revelationType: String
    }

    private let payload: Payload?

    private init() {
        if let url = Bundle.main.url(forResource: "quran_offline", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            payload = decoded
            bundledTranslationId = decoded.translationId
        } else {
            payload = nil
        }
    }

    var isAvailable: Bool { payload != nil }

    /// The full surah list from the bundle.
    func surahs() -> [Surah] {
        guard let payload else { return [] }
        return payload.surahs.map {
            Surah(number: $0.number, name: $0.name, englishName: $0.englishName,
                  englishNameTranslation: $0.englishNameTranslation,
                  numberOfAyahs: $0.numberOfAyahs, revelationType: $0.revelationType)
        }
    }

    /// Ayahs for a surah from the bundle. The translation column is only filled when
    /// the requested edition matches the bundled one; otherwise translation is empty
    /// (the caller can prefer a disk-cached copy for other editions).
    func ayahs(surah: Int, translationId: String) -> [Ayah]? {
        guard let rows = payload?.ayahs[String(surah)] else { return nil }
        let includeTranslation = (translationId == bundledTranslationId)
        return rows.enumerated().map { idx, cols in
            let numberInSurah = idx + 1
            let rawArabic = cols.count > 0 ? cols[0] : ""
            let translit  = cols.count > 1 ? cols[1] : ""
            let translation = (includeTranslation && cols.count > 2) ? cols[2] : ""
            return Ayah(
                numberInSurah: numberInSurah,
                globalNumber: 0,
                arabic: QuranAPIService.strippingLeadingBasmala(rawArabic, surah: surah, numberInSurah: numberInSurah),
                translation: translation,
                transliteration: translit
            )
        }
    }
}
