import Foundation

struct Ayah: Identifiable, Equatable {
    let surah: Int
    let numberInSurah: Int
    let arabic: String
    let translation: String
    let transliteration: String

    var id: Int { numberInSurah }
}

/// The ayahs a repeat covers, and how many passes it makes. A single ayah is `from == to`.
struct RepeatRange: Codable, Equatable {
    var from: Int
    var to: Int
    /// 0 repeats until stopped.
    var times: Int = 0

    func contains(_ ayah: Int) -> Bool { (from...to).contains(ayah) }

    /// "Ayah 255" or "Ayahs 255–257".
    var label: String { from == to ? "Ayah \(from)" : "Ayahs \(from)–\(to)" }
    /// "∞" or "3×".
    var timesLabel: String { times == 0 ? "∞" : "\(times)×" }

    static let timeChoices = [0, 3, 5, 10]
}

/// The silence left after each ayah, for reciting it back.
enum PauseAfterAyah: String, CaseIterable, Identifiable {
    case off, ayahLength, three, five, ten

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:        "Off"
        case .ayahLength: "As long as the ayah"
        case .three:      "3 seconds"
        case .five:       "5 seconds"
        case .ten:        "10 seconds"
        }
    }

    func seconds(ayahDuration: Double) -> Double {
        switch self {
        case .off:        0
        case .ayahLength: max(1, ayahDuration)
        case .three:      3
        case .five:       5
        case .ten:        10
        }
    }
}
