import Foundation

// Returned by WordTimingService — everything needed to drive word-level playback.
struct SurahTimingData {
    let chapterAudioUrl: URL
    // Word timings keyed by ayah number. Timestamps are GLOBAL into chapterAudioUrl (not per-ayah).
    let wordTimings: [Int: [WordTiming]]
    // Verse-level timestamps (also global into chapterAudioUrl).
    let verseTimestamps: [Int: VerseTimestamp]
}

struct VerseTimestamp {
    let fromMs: Int
    let toMs: Int
}

class WordTimingService {
    static let shared = WordTimingService()
    private init() {}

    private var cache: [Int: SurahTimingData] = [:]
    private let reciterId = 7   // Mishary Al-Afasy

    func timings(surah: Int, ayahs: [Ayah]) async throws -> SurahTimingData {
        if let cached = cache[surah] { return cached }

        // Fetch audio segments and word transliterations in parallel.
        async let audioFetch   = fetchAudioFile(surah: surah)
        async let translitFetch = fetchTransliterations(surah: surah)

        let (audioResult, translit) = try await (audioFetch, translitFetch)

        let (chapterUrl, verseTimings) = audioResult

        // Arabic words for each ayah (from preloaded Ayah objects — no Bismillah included).
        let wordsByAyah = Dictionary(uniqueKeysWithValues:
            ayahs.map { ($0.numberInSurah,
                         $0.arabic.components(separatedBy: " ").filter { !$0.isEmpty }) }
        )

        var wordTimings: [Int: [WordTiming]] = [:]
        var verseTimestamps: [Int: VerseTimestamp] = [:]

        for vt in verseTimings {
            guard
                let verseKey = vt["verse_key"]      as? String,
                let ayahNum  = parseAyahNumber(from: verseKey),
                let fromMs   = vt["timestamp_from"] as? Int,
                let toMs     = vt["timestamp_to"]   as? Int
            else { continue }

            verseTimestamps[ayahNum] = VerseTimestamp(fromMs: fromMs, toMs: toMs)

            guard let rawSegs = vt["segments"] as? [[Any]] else { continue }

            let arabicWords   = wordsByAyah[ayahNum] ?? []
            let translitWords = translit[ayahNum] ?? [:]   // [wordPosition: transliteration]

            // The alquran.cloud `quran-simple` edition prepends the Bismillah (4 words) to
            // the Arabic text of Ayah 1 for every surah except Al-Fatiha (1, where Bismillah
            // IS Ayah 1) and At-Tawbah (9, which has no Bismillah).
            //
            // The QDC audio API does NOT include Bismillah in the word-timing segments —
            // its wordIdx 1 is already the first real word of the ayah.
            //
            // Fix: for affected surahs, drop the first 4 words from arabicWords so that
            // wordIdx 1 correctly maps to the first non-Bismillah word.
            let needsBismillahStrip = (ayahNum == 1 && surah != 1 && surah != 9)
            let effectiveWords: [String] = needsBismillahStrip
                ? Array(arabicWords.dropFirst(4))
                : arabicWords

            var timings: [WordTiming] = []

            for seg in rawSegs {
                guard
                    seg.count >= 3,
                    let wordIdx = seg[0] as? Int,
                    let startMs = seg[1] as? Int,
                    let endMs   = seg[2] as? Int,
                    startMs >= 0, endMs > startMs
                else { continue }

                timings.append(WordTiming(
                    id: wordIdx,
                    arabicText: effectiveWords[safe: wordIdx - 1] ?? "",
                    transliteration: translitWords[wordIdx] ?? "",
                    startMs: startMs,
                    endMs: endMs
                ))
            }

            timings.sort { $0.id < $1.id }
            if !timings.isEmpty { wordTimings[ayahNum] = timings }
        }

        let result = SurahTimingData(
            chapterAudioUrl: chapterUrl,
            wordTimings: wordTimings,
            verseTimestamps: verseTimestamps
        )
        cache[surah] = result
        return result
    }

    func invalidate(surah: Int) { cache.removeValue(forKey: surah) }

    // MARK: - Private fetch helpers

    private func fetchAudioFile(surah: Int) async throws -> (URL, [[String: Any]]) {
        let urlStr = "https://api.qurancdn.com/api/qdc/audio/reciters/\(reciterId)/audio_files?chapter_number=\(surah)&segments=true"
        guard let url = URL(string: urlStr) else { throw WordTimingError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WordTimingError.badResponse
        }
        guard
            let root         = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let audioFiles   = root["audio_files"]   as? [[String: Any]],
            let firstFile    = audioFiles.first,
            let audioUrlStr  = firstFile["audio_url"] as? String,
            let chapterUrl   = URL(string: audioUrlStr),
            let verseTimings = firstFile["verse_timings"] as? [[String: Any]]
        else {
            throw WordTimingError.badFormat
        }
        return (chapterUrl, verseTimings)
    }

    /// Fetch word-level transliterations from QDC.
    /// Returns [ayahNum: [wordPosition: transliterationText]].
    /// Failures are silently swallowed — the caller falls back to empty strings.
    private func fetchTransliterations(surah: Int) async -> [Int: [Int: String]] {
        let urlStr = "https://api.qurancdn.com/api/qdc/verses/by_chapter/\(surah)?words=true&word_fields=transliteration&per_page=300&page=1"
        guard
            let url = URL(string: urlStr),
            let (data, _) = try? await URLSession.shared.data(from: url),
            let root    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let verses  = root["verses"] as? [[String: Any]]
        else { return [:] }

        var result: [Int: [Int: String]] = [:]
        for verse in verses {
            guard
                let ayahNum = verse["verse_number"] as? Int,
                let words   = verse["words"] as? [[String: Any]]
            else { continue }

            var positionMap: [Int: String] = [:]
            for word in words {
                guard
                    let position = word["position"] as? Int,
                    let tlObj    = word["transliteration"] as? [String: Any],
                    let text     = tlObj["text"] as? String
                else { continue }
                positionMap[position] = text
            }
            if !positionMap.isEmpty { result[ayahNum] = positionMap }
        }
        return result
    }

    private func parseAyahNumber(from verseKey: String) -> Int? {
        let parts = verseKey.split(separator: ":")
        guard parts.count == 2 else { return nil }
        return Int(parts[1])
    }
}

enum WordTimingError: LocalizedError {
    case badURL, badResponse, badFormat
    var errorDescription: String? {
        switch self {
        case .badURL:      return "Invalid timing API URL."
        case .badResponse: return "Timing server returned an error."
        case .badFormat:   return "Timing data was in an unexpected format."
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
