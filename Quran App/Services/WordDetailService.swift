import Foundation

/// Fetches per-word translation / transliteration / audio for a whole surah from
/// the QDC (quran.com) API and caches it. Mirrors WordTimingService's design:
/// a plain singleton with a per-surah cache, called from the @MainActor view model.
final class WordDetailService {
    static let shared = WordDetailService()
    private init() {}

    // surah -> ayahNumber -> ordered word details
    private var cache: [Int: [Int: [WordDetail]]] = [:]
    private let audioBase = "https://audio.qurancdn.com/"

    func wordDetails(surah: Int) async throws -> [Int: [WordDetail]] {
        if let cached = cache[surah] { return cached }

        let urlStr = "https://api.qurancdn.com/api/qdc/verses/by_chapter/\(surah)?words=true&word_fields=text_uthmani,audio_url&word_translation_language=en&per_page=300&page=1"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard
            let root   = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let verses = root["verses"] as? [[String: Any]]
        else { throw URLError(.cannotParseResponse) }

        var result: [Int: [WordDetail]] = [:]
        for verse in verses {
            guard
                let ayahNum = verse["verse_number"] as? Int,
                let words   = verse["words"] as? [[String: Any]]
            else { continue }

            var details: [WordDetail] = []
            for w in words {
                // Skip the ayah-end glyph (char_type_name == "end"); keep real words only.
                guard (w["char_type_name"] as? String) == "word",
                      let position = w["position"] as? Int else { continue }

                let arabic      = (w["text_uthmani"] as? String) ?? (w["text"] as? String) ?? ""
                let translit    = (w["transliteration"] as? [String: Any])?["text"] as? String ?? ""
                let translation = (w["translation"] as? [String: Any])?["text"] as? String ?? ""

                var audioURL: URL? = nil
                if let rel = w["audio_url"] as? String, !rel.isEmpty {
                    audioURL = rel.hasPrefix("http") ? URL(string: rel) : URL(string: audioBase + rel)
                }

                details.append(WordDetail(
                    position: position,
                    arabic: arabic,
                    transliteration: translit,
                    translation: translation,
                    audioURL: audioURL
                ))
            }
            details.sort { $0.position < $1.position }
            if !details.isEmpty { result[ayahNum] = details }
        }

        cache[surah] = result
        return result
    }
}
