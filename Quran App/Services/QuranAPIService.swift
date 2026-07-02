import Foundation

class QuranAPIService {
    static let shared = QuranAPIService()
    private let base = "https://api.alquran.cloud/v1"

    /// In-memory cache of simple-meaning text, keyed "surah:ayah", so the
    /// memorization "Simple" toggle doesn't refetch an ayah it has already shown.
    private let simpleMeaningCache = NSCache<NSString, NSString>()

    func fetchSurahList() async throws -> [Surah] {
        do {
            let url = URL(string: "\(base)/surah")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return try JSONDecoder().decode(SurahListResponse.self, from: data).data.map(\.toSurah)
        } catch {
            // Offline / API down: serve the bundled surah list so the app still opens.
            let bundled = QuranOfflineStore.shared.surahs()
            if !bundled.isEmpty { return bundled }
            throw error
        }
    }

    /// The reading text for a surah, resilient to a missing network. Tries the live
    /// API first (and caches the result to disk), then a previously-cached copy for
    /// this translation, then the bundled text (Arabic + transliteration, plus the
    /// default translation) so the reader is never blank offline.
    func fetchAyahs(surahNumber: Int) async throws -> [Ayah] {
        let translationId = Translation.selected.id
        do {
            let ayahs = try await fetch(surah: surahNumber, translationId: translationId)
            Self.cacheToDisk(ayahs, surah: surahNumber, translationId: translationId)
            return ayahs
        } catch {
            if let cached = Self.cachedFromDisk(surah: surahNumber, translationId: translationId) {
                return cached
            }
            if let bundled = QuranOfflineStore.shared.ayahs(surah: surahNumber, translationId: translationId),
               !bundled.isEmpty {
                return bundled
            }
            // Last resort: Arabic + transliteration only (also cache-less offline
            // this throws, which the reader surfaces as a retryable error).
            return try await fetch(surah: surahNumber, translationId: nil)
        }
    }

    // MARK: - On-disk ayah cache
    //
    // Any surah viewed online is written to the caches directory keyed by
    // surah + translation, so re-opening it (or opening it offline) is instant and
    // network-free — including the translation, which the bundle only carries for
    // the default edition.

    private static func cacheURL(surah: Int, translationId: String) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("quran_text", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeId = translationId.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent("\(surah)_\(safeId).json")
    }

    private static func cacheToDisk(_ ayahs: [Ayah], surah: Int, translationId: String) {
        guard !ayahs.isEmpty, let data = try? JSONEncoder().encode(ayahs) else { return }
        try? data.write(to: cacheURL(surah: surah, translationId: translationId), options: .atomic)
    }

    private static func cachedFromDisk(surah: Int, translationId: String) -> [Ayah]? {
        let url = cacheURL(surah: surah, translationId: translationId)
        guard let data = try? Data(contentsOf: url),
              let ayahs = try? JSONDecoder().decode([Ayah].self, from: data),
              !ayahs.isEmpty
        else { return nil }
        return ayahs
    }

    private func fetch(surah: Int, translationId: String?) async throws -> [Ayah] {
        var ids = ["quran-simple", "en.transliteration"]
        if let t = translationId { ids.insert(t, at: 1) }
        let editions = ids.joined(separator: ",")
        let url = URL(string: "\(base)/surah/\(surah)/editions/\(editions)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(EditionsResponse.self, from: data)
        return merge(decoded.data, surah: surah, translationId: translationId)
    }

    /// Single ayah across the Arabic + selected translation + transliteration editions.
    /// Used by the spaced-repetition review session, which pulls ayahs from many surahs.
    /// The single-ayah multi-edition endpoint returns inline ayah fields per edition
    /// (not an `ayahs` array), so it is parsed directly rather than via `merge`.
    func fetchAyah(surah: Int, ayah: Int) async throws -> Ayah {
        let translationId = Translation.selected.id
        let ids = ["quran-simple", translationId, "en.transliteration"].joined(separator: ",")
        let url = URL(string: "\(base)/ayah/\(surah):\(ayah)/editions/\(ids)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let arr  = root["data"] as? [[String: Any]]
        else { throw URLError(.cannotParseResponse) }

        func text(for identifier: String) -> String {
            for item in arr where (item["edition"] as? [String: Any])?["identifier"] as? String == identifier {
                return item["text"] as? String ?? ""
            }
            return ""
        }
        let numberInSurah = (arr.first?["numberInSurah"] as? Int) ?? ayah
        let global        = (arr.first?["number"] as? Int) ?? 0
        return Ayah(
            numberInSurah:   numberInSurah,
            globalNumber:    global,
            arabic:          Self.strippingLeadingBasmala(text(for: "quran-simple"), surah: surah, numberInSurah: numberInSurah),
            translation:     text(for: translationId),
            transliteration: text(for: "en.transliteration")
        )
    }

    /// Plain-English "gist" of one ayah from the deliberately simple
    /// `Translation.simpleMeaningId` edition, for the memorization "Simple"
    /// toggle. Cached in memory for the session; returns nil on any failure so
    /// callers can fall back to the card's own stored translation (e.g. offline).
    func fetchSimpleMeaning(surah: Int, ayah: Int) async -> String? {
        let key = "\(surah):\(ayah)" as NSString
        if let cached = simpleMeaningCache.object(forKey: key) { return cached as String }

        let edition = Translation.simpleMeaningId
        guard let url = URL(string: "\(base)/ayah/\(surah):\(ayah)/\(edition)") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard
                let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = root["data"] as? [String: Any],
                let text = payload["text"] as? String, !text.isEmpty
            else { return nil }
            simpleMeaningCache.setObject(text as NSString, forKey: key)
            return text
        } catch {
            return nil
        }
    }

    /// Arabic is required; translation (the selected edition) and transliteration are
    /// optional so a missing/unavailable edition degrades gracefully to empty text.
    private func merge(_ editions: [EditionData], surah: Int, translationId: String?) -> [Ayah] {
        guard let arabic = editions.first(where: { $0.edition.identifier == "quran-simple" })
        else { return [] }

        let translit = editions.first { $0.edition.identifier == "en.transliteration" }
        let trans    = translationId.flatMap { id in editions.first { $0.edition.identifier == id } }

        return arabic.ayahs.indices.map { i in
            Ayah(
                numberInSurah:  arabic.ayahs[i].numberInSurah,
                globalNumber:   arabic.ayahs[i].number,
                arabic:         Self.strippingLeadingBasmala(arabic.ayahs[i].text, surah: surah, numberInSurah: arabic.ayahs[i].numberInSurah),
                translation:    trans?.ayahs[safe: i]?.text ?? "",
                transliteration: translit?.ayahs[safe: i]?.text ?? ""
            )
        }
    }
}

// MARK: - Basmala stripping

extension QuranAPIService {
    /// alquran.cloud's Arabic text editions prepend the Basmala to ayah 1 of every
    /// surah except Al-Faatiha (1, where the Basmala *is* ayah 1) and At-Tawbah (9,
    /// which has none). The translation, transliteration, and audio editions don't,
    /// so ayah 1 used to show an extra inline line that nothing else reflected.
    /// Removing it keeps every edition — and the standalone header Basmala — aligned.
    nonisolated static func strippingLeadingBasmala(_ text: String, surah: Int, numberInSurah: Int) -> String {
        guard numberInSurah == 1, surah != 1, surah != 9 else { return text }
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 4 else { return text }
        guard words.prefix(4).map(normalizeArabic) == basmalaWords else { return text }
        return words.dropFirst(4).joined(separator: " ")
    }

    /// The Basmala's four words, diacritic-free, for a tolerant prefix comparison.
    nonisolated private static let basmalaWords = ["بسم", "الله", "الرحمن", "الرحيم"]

    /// Strips Arabic harakat / tashkeel / tatweel and folds the alef variants, so the
    /// comparison survives the different vowel marks the editions use.
    nonisolated private static func normalizeArabic(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            let v = u.value
            // Drop combining marks (harakat/tashkeel), the superscript alef, tatweel,
            // and the Quranic annotation marks.
            if (0x064B...0x0652).contains(v) || v == 0x0670 || v == 0x0640 || (0x06D6...0x06ED).contains(v) {
                continue
            }
            // Fold alef variants (madda, hamza above/below, wasla) to a bare alef.
            if v == 0x0622 || v == 0x0623 || v == 0x0625 || v == 0x0671 {
                scalars.append(Unicode.Scalar(0x0627)!)
            } else {
                scalars.append(u)
            }
        }
        return String(scalars)
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
