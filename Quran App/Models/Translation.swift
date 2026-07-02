import Foundation

/// A Quran translation edition (alquran.cloud identifier), grouped by language.
/// Mirrors the `Reciter` pattern: a curated static list + a `selected` accessor
/// backed by `@AppStorage("selectedTranslationId")`.
struct Translation: Identifiable, Equatable {
    let id: String        // alquran.cloud edition identifier, e.g. "en.asad"
    let name: String      // translator / edition name
    let language: String  // display language, e.g. "English"
}

extension Translation {
    /// Preserves the app's previous hardcoded translation as the default.
    static let fallbackId = "en.asad"

    /// Edition used by the memorization "Simple" toggle: a plain, easy-to-skim
    /// rendering for getting the gist of an ayah while drilling its meaning,
    /// independent of whatever (possibly verbose) translation the user reads with.
    static let simpleMeaningId = "en.sahih"

    /// Display name of the simple-meaning edition, shown as a source caption.
    static var simpleMeaningName: String {
        all.first { $0.id == simpleMeaningId }?.name ?? "Simple"
    }

    static let all: [Translation] = [
        // English
        Translation(id: "en.asad",       name: "Muhammad Asad",          language: "English"),
        Translation(id: "en.sahih",      name: "Saheeh International",    language: "English"),
        Translation(id: "en.itani",      name: "The Clear Quran (Itani)", language: "English"),
        Translation(id: "en.pickthall",  name: "Pickthall",              language: "English"),
        Translation(id: "en.yusufali",   name: "Yusuf Ali",              language: "English"),
        // Urdu
        Translation(id: "ur.jalandhry",  name: "Jalandhry",              language: "Urdu"),
        Translation(id: "ur.maududi",    name: "Abul A'la Maududi",      language: "Urdu"),
        // Indonesian
        Translation(id: "id.indonesian", name: "Kementerian Agama",      language: "Indonesian"),
        // Turkish
        Translation(id: "tr.diyanet",    name: "Diyanet İşleri",         language: "Turkish"),
        // French
        Translation(id: "fr.hamidullah", name: "Muhammad Hamidullah",    language: "French"),
        // Spanish
        Translation(id: "es.cortes",     name: "Julio Cortés",           language: "Spanish"),
        // German
        Translation(id: "de.bubenheim",  name: "Bubenheim & Elyas",      language: "German"),
        // Russian
        Translation(id: "ru.kuliev",     name: "Elmir Kuliev",           language: "Russian"),
        // Bengali
        Translation(id: "bn.bengali",    name: "Muhiuddin Khan",         language: "Bengali"),
        // Hindi
        Translation(id: "hi.hindi",      name: "Suhel Farooq Khan",      language: "Hindi"),
        // Persian
        Translation(id: "fa.makarem",    name: "Makarem Shirazi",        language: "Persian"),
        // Malay
        Translation(id: "ms.basmeih",    name: "Abdullah Basmeih",       language: "Malay"),
        // Italian
        Translation(id: "it.piccardo",   name: "Hamza R. Piccardo",      language: "Italian"),
        // Dutch
        Translation(id: "nl.siregar",    name: "Sofian Siregar",         language: "Dutch"),
        // Portuguese
        Translation(id: "pt.elhayek",    name: "Samir El-Hayek",         language: "Portuguese"),
        // Chinese
        Translation(id: "zh.jian",       name: "Ma Jian",                language: "Chinese"),
        // Tamil
        Translation(id: "ta.tamil",      name: "Jan Trust Foundation",   language: "Tamil"),
        // Swahili
        Translation(id: "sw.barwani",    name: "Al-Barwani",             language: "Swahili"),
        // Japanese
        Translation(id: "ja.japanese",   name: "Ryoichi Mita",           language: "Japanese"),
        // Azerbaijani
        Translation(id: "az.mammadaliyev", name: "Məmmədəliyev & Bünyadov", language: "Azerbaijani"),
    ]

    static var selected: Translation {
        let id = UserDefaults.standard.string(forKey: "selectedTranslationId") ?? fallbackId
        return all.first { $0.id == id }
            ?? all.first { $0.id == fallbackId }
            ?? all[0]
    }

    /// Languages in list order, de-duplicated.
    static var languages: [String] {
        var seen = Set<String>()
        return all.compactMap { seen.insert($0.language).inserted ? $0.language : nil }
    }

    static func translations(in language: String) -> [Translation] {
        all.filter { $0.language == language }
    }
}
