import Foundation
import Combine

struct DailyVerse: Codable {
    let surahNumber: Int
    let ayahNumber: Int
    let surahName: String
    let arabic: String
    let translation: String
    let fetchedDate: String   // "yyyy-MM-dd"
}

@MainActor
class DailyVerseService: ObservableObject {
    static let shared = DailyVerseService()
    @Published var verse: DailyVerse?
    @Published var isLoading = false

    // 30 curated (surah, ayah) references cycling through the year
    private static let schedule: [(Int, Int)] = [
        (1,1),(2,255),(2,286),(3,173),(4,36),(6,162),(7,23),(9,51),(13,28),(14,7),
        (15,9),(17,80),(18,10),(20,25),(23,97),(24,35),(27,62),(28,24),(29,69),(33,41),
        (39,53),(40,60),(50,16),(51,56),(55,13),(57,4),(59,23),(67,1),(93,5),(94,5)
    ]

    private init() {}

    func loadIfNeeded() async {
        let today = todayString()
        // Return cached verse if it's from today
        if let data = UserDefaults.standard.data(forKey: "dailyVerse"),
           let cached = try? JSONDecoder().decode(DailyVerse.self, from: data),
           cached.fetchedDate == today {
            verse = cached
            return
        }
        await fetch(date: today)
    }

    private func fetch(date: String) async {
        isLoading = true
        let idx = dayOfYear() % Self.schedule.count
        let (surah, ayah) = Self.schedule[idx]
        let urlStr = "https://api.alquran.cloud/v1/ayah/\(surah):\(ayah)/editions/quran-simple,en.asad"
        guard let url = URL(string: urlStr) else { isLoading = false; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let parsed = parseVerse(data: data, surah: surah, ayah: ayah, date: date) {
                verse = parsed
                if let encoded = try? JSONEncoder().encode(parsed) {
                    UserDefaults.standard.set(encoded, forKey: "dailyVerse")
                }
            }
        } catch { }
        isLoading = false
    }

    private func parseVerse(data: Data, surah: Int, ayah: Int, date: String) -> DailyVerse? {
        guard
            let root      = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArr   = root["data"] as? [[String: Any]],
            let arabic    = dataArr.first(where: { ($0["edition"] as? [String: Any])?["identifier"] as? String == "quran-simple" }),
            let english   = dataArr.first(where: { ($0["edition"] as? [String: Any])?["identifier"] as? String == "en.asad" }),
            let arabicText = arabic["text"] as? String,
            let engText    = english["text"] as? String,
            let surahInfo  = arabic["surah"] as? [String: Any],
            let surahName  = surahInfo["englishName"] as? String
        else { return nil }
        return DailyVerse(surahNumber: surah, ayahNumber: ayah, surahName: surahName,
                          arabic: arabicText, translation: engText, fetchedDate: date)
    }

    private func todayString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func dayOfYear() -> Int {
        Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    }
}
