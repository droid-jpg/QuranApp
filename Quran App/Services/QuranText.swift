import Foundation

extension Notification.Name {
    /// Posted on the main actor when a translation has been downloaded, so text on
    /// screen can be read again in it.
    static let translationDidDownload = Notification.Name("translationDidDownload")
}

/// The Quran's text, read with no network. Arabic, transliteration and Pickthall's
/// translation come from the bundle (`quran_offline.json`). Any other translation is
/// downloaded once, whole, and read from disk after that.
final class QuranText: @unchecked Sendable {
    static let shared = QuranText()

    let surahs: [Surah]
    /// The edition in the bundle's translation column.
    let bundledTranslationId: String

    /// surah number -> [[arabic, transliteration, translation]]
    private let rows: [String: [[String]]]
    private let lock = NSLock()
    /// The downloaded edition last read from disk: one array of ayah texts per surah.
    private var loaded: (id: String, surahs: [[String]])?
    private var ayahCache: [String: [Ayah]] = [:]

    private struct Payload: Decodable {
        let translationId: String
        let surahs: [Surah]
        let ayahs: [String: [[String]]]
    }

    private init() {
        if let url = Bundle.main.url(forResource: "quran_offline", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            surahs = payload.surahs
            rows = payload.ayahs
            bundledTranslationId = payload.translationId
        } else {
            surahs = []
            rows = [:]
            bundledTranslationId = Translation.fallbackId
        }
    }

    func surah(_ number: Int) -> Surah? {
        surahs.indices.contains(number - 1) ? surahs[number - 1] : nil
    }

    /// A surah's ayahs in the selected translation, or in the bundled one while the
    /// selected edition has not been downloaded.
    func ayahs(_ surah: Int) -> [Ayah] {
        let wanted = Translation.selected.id
        let key = "\(surah)|\(wanted)"
        lock.lock(); defer { lock.unlock() }
        if let cached = ayahCache[key] { return cached }
        guard let surahRows = rows[String(surah)] else { return [] }

        let downloaded = wanted == bundledTranslationId ? nil : translation(wanted, surah: surah)
        let result = surahRows.enumerated().map { index, cols in
            let number = index + 1
            let bundled = cols.count > 2 ? cols[2] : ""
            return Ayah(
                surah: surah,
                numberInSurah: number,
                arabic: Self.strippingLeadingBasmala(cols.first ?? "", surah: surah, numberInSurah: number),
                translation: downloaded.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? bundled,
                transliteration: cols.count > 1 ? cols[1] : ""
            )
        }
        if ayahCache.count > 8 { ayahCache.removeAll() }
        ayahCache[key] = result
        return result
    }

    func ayah(_ surah: Int, _ number: Int) -> Ayah? {
        let all = ayahs(surah)
        return all.indices.contains(number - 1) ? all[number - 1] : nil
    }

    // MARK: - Downloaded translations

    func isAvailable(_ translationId: String) -> Bool {
        translationId == bundledTranslationId
            || FileManager.default.fileExists(atPath: Self.fileURL(translationId).path)
    }

    /// Fetches a whole edition (about 1–2 MB) and keeps it.
    func download(_ translationId: String) async throws {
        guard !isAvailable(translationId),
              let url = URL(string: "https://api.alquran.cloud/v1/quran/\(translationId)") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        struct Edition: Decodable {
            struct Body: Decodable { let surahs: [SurahBody] }
            struct SurahBody: Decodable { let ayahs: [AyahBody] }
            struct AyahBody: Decodable { let text: String }
            let data: Body
        }
        let texts = try JSONDecoder().decode(Edition.self, from: data).data.surahs.map { $0.ayahs.map(\.text) }
        guard texts.count == 114 else { throw URLError(.cannotParseResponse) }

        let file = Self.fileURL(translationId)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(texts).write(to: file, options: .atomic)
        lock.lock(); ayahCache.removeAll(); lock.unlock()
        await MainActor.run { NotificationCenter.default.post(name: .translationDidDownload, object: nil) }
    }

    /// Call with `lock` held.
    private func translation(_ id: String, surah: Int) -> [String]? {
        if loaded?.id != id {
            guard let data = try? Data(contentsOf: Self.fileURL(id)),
                  let texts = try? JSONDecoder().decode([[String]].self, from: data) else { return nil }
            loaded = (id, texts)
        }
        guard let texts = loaded?.surahs, texts.indices.contains(surah - 1) else { return nil }
        return texts[surah - 1]
    }

    private static func fileURL(_ translationId: String) -> URL {
        AppFiles.directory("Translations").appendingPathComponent("\(translationId).json")
    }

    // MARK: - Basmala

    /// The bundled Arabic prepends the Basmala to ayah 1 of every surah except
    /// Al-Faatiha (where it is ayah 1) and At-Tawba (which has none). The translation,
    /// the audio and the word timings don't, so it is removed here and drawn once as
    /// the surah's header instead.
    static func strippingLeadingBasmala(_ text: String, surah: Int, numberInSurah: Int) -> String {
        guard numberInSurah == 1, surah != 1, surah != 9 else { return text }
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 4, words.prefix(4).map(normalized) == ["بسم", "الله", "الرحمن", "الرحيم"] else { return text }
        return words.dropFirst(4).joined(separator: " ")
    }

    /// Arabic with the vowel marks removed and the alef forms folded together.
    static func normalized(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x064B...0x0652).contains(v) || v == 0x0670 || v == 0x0640 || (0x06D6...0x06ED).contains(v) { continue }
            if v == 0x0622 || v == 0x0623 || v == 0x0625 || v == 0x0671 {
                scalars.append("\u{0627}")
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}

/// Where the app keeps what it downloads. Application Support, so the system never
/// purges it, and excluded from backup because all of it can be fetched again.
nonisolated enum AppFiles {
    static func directory(_ name: String) -> URL {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        return url
    }

    /// Reads a cached JSON value, or nil.
    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func size(of directory: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
