import Foundation

struct WordTiming: Identifiable {
    let id: Int                  // 1-based word index within the visible ayah (Bismillah excluded)
    let arabicText: String
    let transliteration: String  // e.g. "bismi", "allāhi" — empty if unavailable
    let startMs: Int
    let endMs: Int

    var startSeconds: Double { Double(startMs) / 1000.0 }
    var endSeconds: Double   { Double(endMs)   / 1000.0 }
}
