import Foundation

class StreakService {
    static let shared = StreakService()
    private init() {}

    private let streakKey    = "readingStreak"
    private let lastDateKey  = "lastReadDate"

    var currentStreak: Int {
        UserDefaults.standard.integer(forKey: streakKey)
    }

    /// Call whenever the user opens a surah or plays an ayah.
    func recordRead() {
        let ud       = UserDefaults.standard
        let cal      = Calendar.current
        let today    = cal.startOfDay(for: Date())
        let fmt      = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let todayStr = fmt.string(from: today)

        let lastStr  = ud.string(forKey: lastDateKey) ?? ""
        if lastStr == todayStr { return }   // already counted today

        let streak   = ud.integer(forKey: streakKey)
        if let last  = fmt.date(from: lastStr),
           cal.isDate(last, inSameDayAs: cal.date(byAdding: .day, value: -1, to: today)!) {
            // Yesterday — extend streak
            ud.set(streak + 1, forKey: streakKey)
        } else {
            // Gap — reset
            ud.set(1, forKey: streakKey)
        }
        ud.set(todayStr, forKey: lastDateKey)
    }
}
