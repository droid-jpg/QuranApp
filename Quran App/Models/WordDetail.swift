import Foundation

/// Word-by-word data for a single Arabic word: its meaning, transliteration, and
/// an optional per-word recitation clip. Sourced from the QDC (quran.com) API.
struct WordDetail: Identifiable {
    let position: Int          // 1-based word position within the ayah (Bismillah excluded on ayah 1)
    let arabic: String         // Uthmani script
    let transliteration: String
    let translation: String    // English gloss, e.g. "In (the) name"
    let audioURL: URL?         // word-by-word recitation clip

    var id: Int { position }
}
