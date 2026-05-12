import Foundation

struct Reciter: Identifiable, Codable, Equatable {
    let id: Int
    let name: String
    let subfolder: String  // everyayah.com path segment
}

extension Reciter {
    static let all: [Reciter] = [
        Reciter(id: 7,  name: "Mishary Al-Afasy",        subfolder: "Alafasy_128kbps"),
        Reciter(id: 1,  name: "Abdul Basit (Murattal)",   subfolder: "Abdul_Basit_Murattal_192kbps"),
        Reciter(id: 2,  name: "Al-Sudais",                subfolder: "Abdurrahmaan_As-Sudais_192kbps"),
        Reciter(id: 3,  name: "Saad Al-Ghamdi",          subfolder: "Ghamadi_40kbps"),
        Reciter(id: 9,  name: "Mahmoud Al-Husary",       subfolder: "Husary_128kbps"),
    ]

    static var selected: Reciter {
        let savedId = UserDefaults.standard.integer(forKey: "selectedReciterId")
        return all.first { $0.id == savedId } ?? all[0]
    }
}
