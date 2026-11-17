import Foundation

/// When one word is recited inside its ayah's audio file.
struct WordSpan: Codable, Equatable {
    /// 1-based position in the ayah.
    let word: Int
    let start: Double
    let end: Double
}

/// Word timings for the per-ayah audio files, from quran.com. Fetched once per surah
/// and reciter, then read from disk. Playback never waits for them: they only drive
/// the word highlight and word repeat.
actor WordTimings {
    static let shared = WordTimings()

    private var memory: [String: [Int: [WordSpan]]] = [:]

    /// ayah number -> spans in the order they are recited. Empty when unavailable.
    func spans(reciter: Reciter, surah: Int) async -> [Int: [WordSpan]] {
        let key = "\(reciter.id)_\(surah)"
        if let hit = memory[key] { return hit }
        let file = AppFiles.directory("Timings").appendingPathComponent("\(key).json")
        if let cached = AppFiles.read([Int: [WordSpan]].self, from: file) {
            memory[key] = cached
            return cached
        }
        guard let fetched = try? await fetch(reciter: reciter, surah: surah), !fetched.isEmpty else { return [:] }
        memory[key] = fetched
        AppFiles.write(fetched, to: file)
        return fetched
    }

    private func fetch(reciter: Reciter, surah: Int) async throws -> [Int: [WordSpan]] {
        let url = URL(string: "https://api.quran.com/api/v4/recitations/\(reciter.id)/by_chapter/\(surah)?fields=segments&per_page=300")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = root["audio_files"] as? [[String: Any]] else { throw URLError(.badServerResponse) }

        var result: [Int: [WordSpan]] = [:]
        for file in files {
            guard let key = file["verse_key"] as? String,
                  let ayah = key.split(separator: ":").last.flatMap({ Int($0) }),
                  let segments = file["segments"] as? [[Any]] else { continue }
            // A segment is [index, word, startMs, endMs] (or [word, startMs, endMs]),
            // as numbers or as strings depending on the reciter.
            let spans: [WordSpan] = segments.compactMap { raw in
                let n = raw.compactMap { ($0 as? NSNumber)?.doubleValue ?? Double("\($0)") }
                guard n.count >= 3 else { return nil }
                let (word, start, end) = (n[n.count - 3], n[n.count - 2], n[n.count - 1])
                guard word >= 1, end > start else { return nil }
                return WordSpan(word: Int(word), start: start / 1000, end: end / 1000)
            }
            if !spans.isEmpty { result[ayah] = spans.sorted { $0.start < $1.start } }
        }
        return result
    }
}

/// One word of an ayah with its meaning, for the Word by word sheet.
struct WordMeaning: Codable, Identifiable, Equatable {
    let position: Int
    let arabic: String
    let transliteration: String
    let meaning: String

    var id: Int { position }
}

/// Word meanings from quran.com, fetched once per surah and then read from disk.
actor WordMeanings {
    static let shared = WordMeanings()

    private var memory: [Int: [Int: [WordMeaning]]] = [:]

    func words(surah: Int) async throws -> [Int: [WordMeaning]] {
        if let hit = memory[surah] { return hit }
        let file = AppFiles.directory("Words").appendingPathComponent("\(surah).json")
        if let cached = AppFiles.read([Int: [WordMeaning]].self, from: file) {
            memory[surah] = cached
            return cached
        }
        let url = URL(string: "https://api.qurancdn.com/api/qdc/verses/by_chapter/\(surah)?words=true&word_fields=text_uthmani&word_translation_language=en&per_page=300&page=1")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let verses = root["verses"] as? [[String: Any]] else { throw URLError(.badServerResponse) }

        var result: [Int: [WordMeaning]] = [:]
        for verse in verses {
            guard let ayah = verse["verse_number"] as? Int, let words = verse["words"] as? [[String: Any]] else { continue }
            result[ayah] = words.compactMap { w in
                guard (w["char_type_name"] as? String) == "word", let position = w["position"] as? Int else { return nil }
                return WordMeaning(
                    position: position,
                    arabic: (w["text_uthmani"] as? String) ?? (w["text"] as? String) ?? "",
                    transliteration: ((w["transliteration"] as? [String: Any])?["text"] as? String) ?? "",
                    meaning: ((w["translation"] as? [String: Any])?["text"] as? String) ?? ""
                )
            }.sorted { $0.position < $1.position }
        }
        guard !result.isEmpty else { throw URLError(.cannotParseResponse) }
        memory[surah] = result
        AppFiles.write(result, to: file)
        return result
    }
}

/// Matches the words of the bundled Arabic to quran.com's word positions.
///
/// The two texts split a few phrases differently: the bundled text writes the vocative
/// "يا" (and "ها") as its own word where quran.com joins it to the next. Given how many
/// words quran.com counts, this returns, for each bundled word, the position it belongs
/// to, or nil when the two cannot be reconciled (then only the ayah is highlighted).
enum WordAlignment {
    static func positions(for words: [String], timedCount: Int) -> [Int]? {
        guard timedCount > 0, words.count >= timedCount else { return nil }
        var joinsNext = [Bool](repeating: false, count: words.count)
        var extra = words.count - timedCount
        if extra > 0 {
            for index in words.indices.dropLast() where extra > 0 {
                let bare = QuranText.normalized(words[index])
                if bare == "يا" || bare == "ها" || bare == "ويا" {
                    joinsNext[index] = true
                    extra -= 1
                }
            }
        }
        guard extra == 0 else { return nil }
        var result: [Int] = []
        var position = 1
        for index in words.indices {
            result.append(position)
            if !joinsNext[index] { position += 1 }
        }
        return result
    }
}
