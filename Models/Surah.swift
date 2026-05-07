import Foundation

struct Surah: Identifiable, Codable, Hashable {
    let number: Int
    let name: String                    // Arabic script
    let englishName: String
    let englishNameTranslation: String
    let numberOfAyahs: Int
    let revelationType: String

    var id: Int { number }
}
