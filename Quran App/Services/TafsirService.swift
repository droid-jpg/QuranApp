import Foundation

/// Fetches ayah-level commentary (tafsir) for a surah from the quran.com v4 API
/// and caches it. Only ayahs with non-empty commentary are returned, so callers
/// can show the affordance solely on "ayahs that have it".
final class TafsirService {
    static let shared = TafsirService()
    private init() {}

    private var cache: [Int: [Int: String]] = [:]   // surah -> ayahNumber -> plain text
    private let resourceId = 169                     // Ibn Kathir (Abridged), English

    /// The display name of the commentary source, for sheet headers.
    let sourceName = "Tafsir Ibn Kathir (Abridged)"

    func tafsir(surah: Int) async throws -> [Int: String] {
        if let cached = cache[surah] { return cached }

        var result: [Int: String] = [:]
        var page = 1
        // Safety cap: largest surah (286 ayahs) needs ~6 pages at 50/page.
        while page <= 12 {
            let urlStr = "https://api.quran.com/api/v4/tafsirs/\(resourceId)/by_chapter/\(surah)?per_page=50&page=\(page)"
            guard let url = URL(string: urlStr) else { break }

            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let root    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tafsirs = root["tafsirs"] as? [[String: Any]]
            else { break }

            for t in tafsirs {
                guard
                    let verseKey = t["verse_key"] as? String,
                    let ayahPart = verseKey.split(separator: ":").last,
                    let ayah     = Int(ayahPart),
                    let html     = t["text"] as? String
                else { continue }
                let plain = Self.plainText(fromHTML: html)
                if !plain.isEmpty { result[ayah] = plain }
            }

            // Stop when there is no next page.
            let pagination = root["pagination"] as? [String: Any]
            let next = pagination?["next_page"]
            if next == nil || next is NSNull { break }
            page += 1
        }

        cache[surah] = result
        return result
    }

    /// Best-effort HTML → plain text: block tags become line breaks, all other
    /// tags are stripped, and a handful of common entities are decoded.
    static func plainText(fromHTML html: String) -> String {
        var s = html
        for tag in ["</p>", "</h1>", "</h2>", "</h3>", "</h4>", "<br>", "<br/>", "<br />", "</div>", "</li>"] {
            s = s.replacingOccurrences(of: tag, with: "\n")
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}",
            "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}", "&hellip;": "\u{2026}",
        ]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
