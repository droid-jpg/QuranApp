import Foundation

/// A reciter whose per-ayah files and word timings are both published by quran.com.
/// `id` is quran.com's recitation id (used for the timings); `base` is the folder the
/// `SSSAAA.mp3` files sit in.
struct Reciter: Identifiable, Equatable {
    let id: Int
    let name: String
    let base: String
    /// The same folder on a second host, tried when the first one fails.
    let mirror: String

    func remoteURLs(surah: Int, ayah: Int) -> [URL] {
        let file = String(format: "%03d%03d.mp3", surah, ayah)
        return [base, mirror].compactMap { URL(string: "\($0)/\(file)") }
    }
}

extension Reciter {
    private static func quranCom(_ id: Int, _ name: String, _ folder: String) -> Reciter {
        Reciter(id: id, name: name,
                base: "https://verses.quran.com/\(folder)",
                mirror: "https://audio.qurancdn.com/\(folder)")
    }

    static let all: [Reciter] = [
        quranCom(7,  "Mishary Al-Afasy",        "Alafasy/mp3"),
        quranCom(2,  "Abdul Basit (Murattal)",  "AbdulBaset/Murattal/mp3"),
        quranCom(3,  "Abdur-Rahman As-Sudais",  "Sudais/mp3"),
        Reciter(id: 6, name: "Mahmoud Al-Husary",
                base: "https://mirrors.quranicaudio.com/everyayah/Husary_64kbps",
                mirror: "https://everyayah.com/data/Husary_64kbps"),
        quranCom(9,  "Al-Minshawi (Murattal)",  "Minshawi/Murattal/mp3"),
        quranCom(10, "Saud Ash-Shuraym",        "Shuraym/mp3"),
        quranCom(4,  "Abu Bakr Ash-Shatri",     "Shatri/mp3"),
    ]

    static var selected: Reciter {
        let savedId = UserDefaults.standard.integer(forKey: "selectedReciterId")
        return all.first { $0.id == savedId } ?? all[0]
    }
}
