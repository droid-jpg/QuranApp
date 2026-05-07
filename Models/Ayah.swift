import Foundation

struct Ayah: Identifiable {
    let numberInSurah: Int
    let globalNumber: Int
    let arabic: String
    let translation: String
    let transliteration: String

    var id: Int { numberInSurah }
}
