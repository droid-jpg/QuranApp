import Foundation

struct JuzBoundary {
    let juz: Int
    let startSurah: Int
    let startAyah: Int
    let endSurah: Int
    let endAyah: Int
}

enum JuzData {
    // Standard 30-juz boundary table (surah:ayah, 1-indexed)
    static let boundaries: [JuzBoundary] = [
        JuzBoundary(juz:  1, startSurah:  1, startAyah:   1, endSurah:  2, endAyah: 141),
        JuzBoundary(juz:  2, startSurah:  2, startAyah: 142, endSurah:  2, endAyah: 252),
        JuzBoundary(juz:  3, startSurah:  2, startAyah: 253, endSurah:  3, endAyah:  91),
        JuzBoundary(juz:  4, startSurah:  3, startAyah:  92, endSurah:  4, endAyah:  23),
        JuzBoundary(juz:  5, startSurah:  4, startAyah:  24, endSurah:  4, endAyah: 147),
        JuzBoundary(juz:  6, startSurah:  4, startAyah: 148, endSurah:  5, endAyah:  81),
        JuzBoundary(juz:  7, startSurah:  5, startAyah:  82, endSurah:  6, endAyah: 110),
        JuzBoundary(juz:  8, startSurah:  6, startAyah: 111, endSurah:  7, endAyah:  87),
        JuzBoundary(juz:  9, startSurah:  7, startAyah:  88, endSurah:  8, endAyah:  40),
        JuzBoundary(juz: 10, startSurah:  8, startAyah:  41, endSurah:  9, endAyah:  92),
        JuzBoundary(juz: 11, startSurah:  9, startAyah:  93, endSurah: 11, endAyah:   5),
        JuzBoundary(juz: 12, startSurah: 11, startAyah:   6, endSurah: 12, endAyah:  52),
        JuzBoundary(juz: 13, startSurah: 12, startAyah:  53, endSurah: 14, endAyah:  52),
        JuzBoundary(juz: 14, startSurah: 15, startAyah:   1, endSurah: 16, endAyah: 128),
        JuzBoundary(juz: 15, startSurah: 17, startAyah:   1, endSurah: 18, endAyah:  74),
        JuzBoundary(juz: 16, startSurah: 18, startAyah:  75, endSurah: 20, endAyah: 135),
        JuzBoundary(juz: 17, startSurah: 21, startAyah:   1, endSurah: 22, endAyah:  78),
        JuzBoundary(juz: 18, startSurah: 23, startAyah:   1, endSurah: 25, endAyah:  20),
        JuzBoundary(juz: 19, startSurah: 25, startAyah:  21, endSurah: 27, endAyah:  55),
        JuzBoundary(juz: 20, startSurah: 27, startAyah:  56, endSurah: 29, endAyah:  45),
        JuzBoundary(juz: 21, startSurah: 29, startAyah:  46, endSurah: 33, endAyah:  30),
        JuzBoundary(juz: 22, startSurah: 33, startAyah:  31, endSurah: 36, endAyah:  27),
        JuzBoundary(juz: 23, startSurah: 36, startAyah:  28, endSurah: 39, endAyah:  31),
        JuzBoundary(juz: 24, startSurah: 39, startAyah:  32, endSurah: 41, endAyah:  46),
        JuzBoundary(juz: 25, startSurah: 41, startAyah:  47, endSurah: 45, endAyah:  37),
        JuzBoundary(juz: 26, startSurah: 46, startAyah:   1, endSurah: 51, endAyah:  30),
        JuzBoundary(juz: 27, startSurah: 51, startAyah:  31, endSurah: 57, endAyah:  29),
        JuzBoundary(juz: 28, startSurah: 58, startAyah:   1, endSurah: 66, endAyah:  12),
        JuzBoundary(juz: 29, startSurah: 67, startAyah:   1, endSurah: 77, endAyah:  50),
        JuzBoundary(juz: 30, startSurah: 78, startAyah:   1, endSurah: 114, endAyah:  6),
    ]

    static func boundary(for juz: Int) -> JuzBoundary? {
        boundaries.first { $0.juz == juz }
    }

    // All surah numbers that have at least one ayah in this juz
    static func surahNumbers(inJuz juz: Int) -> [Int] {
        guard let b = boundary(for: juz) else { return [] }
        return Array(b.startSurah ... b.endSurah)
    }

    // How many ayahs of a given surah fall inside a juz.
    // surahTotalAyahs is needed because Surah isn't imported here.
    static func ayahsInJuz(surahNumber: Int, surahTotalAyahs: Int, juz: Int) -> Int {
        guard let b = boundary(for: juz),
              b.startSurah <= surahNumber, surahNumber <= b.endSurah else { return 0 }

        let first = (surahNumber == b.startSurah) ? b.startAyah : 1
        let last  = (surahNumber == b.endSurah)   ? min(b.endAyah, surahTotalAyahs) : surahTotalAyahs

        return max(0, last - first + 1)
    }
}
