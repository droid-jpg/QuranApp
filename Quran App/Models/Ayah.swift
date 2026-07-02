import Foundation

struct Ayah: Identifiable, Codable {
    let numberInSurah: Int
    let globalNumber: Int
    let arabic: String
    let translation: String
    let transliteration: String

    var id: Int { numberInSurah }
}
