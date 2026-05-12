import Foundation
import Combine
import WidgetKit

// Shared between the app and the widget extension via App Groups.
let sharedAppGroup = "group.sami.Quran-App"

private var sharedDefaults: UserDefaults {
    UserDefaults(suiteName: sharedAppGroup) ?? .standard
}

class MemorizationStore: ObservableObject {
    @Published private(set) var statuses: [Int: MemorizationStatus] = [:]
    @Published private(set) var reviewedNumbers: Set<Int> = []

    private let statusKey = "quran_memorization_v1"
    private let reviewKey = "quran_review_v1"

    init() {
        load()
        loadReview()
    }

    // MARK: - Status

    func status(for surahNumber: Int) -> MemorizationStatus {
        statuses[surahNumber] ?? .notStarted
    }

    var memorizedCount: Int  { statuses.values.filter { $0 == .memorized  }.count }
    var inProgressCount: Int { statuses.values.filter { $0 == .inProgress }.count }
    var reviewedCount: Int   { reviewedNumbers.count }

    var inProgressNumbers: [Int] {
        statuses.filter { $0.value == .inProgress }.keys.sorted()
    }

    func set(_ status: MemorizationStatus, for surahNumber: Int) {
        if status == .notStarted {
            statuses.removeValue(forKey: surahNumber)
        } else {
            statuses[surahNumber] = status
        }
        save()
    }

    func cycle(for surahNumber: Int) {
        set(status(for: surahNumber).next, for: surahNumber)
    }

    // MARK: - Review

    func isReviewed(_ surahNumber: Int) -> Bool {
        reviewedNumbers.contains(surahNumber)
    }

    func toggleReview(_ surahNumber: Int) {
        if reviewedNumbers.contains(surahNumber) {
            reviewedNumbers.remove(surahNumber)
        } else {
            reviewedNumbers.insert(surahNumber)
        }
        saveReview()
    }

    // MARK: - Persistence (App Group shared container — survives app updates,
    //         persists as long as the app is installed on the device)

    private func save() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: statuses.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            sharedDefaults.set(data, forKey: statusKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func load() {
        guard
            let data    = sharedDefaults.data(forKey: statusKey),
            let decoded = try? JSONDecoder().decode([String: MemorizationStatus].self, from: data)
        else { return }
        statuses = Dictionary(uniqueKeysWithValues: decoded.compactMap { k, v in
            guard let n = Int(k) else { return nil }
            return (n, v)
        })
    }

    private func saveReview() {
        let arr = Array(reviewedNumbers)
        if let data = try? JSONEncoder().encode(arr) {
            sharedDefaults.set(data, forKey: reviewKey)
        }
    }

    private func loadReview() {
        guard
            let data = sharedDefaults.data(forKey: reviewKey),
            let arr  = try? JSONDecoder().decode([Int].self, from: data)
        else { return }
        reviewedNumbers = Set(arr)
    }
}

// MARK: - Shared surah cache (written by app, read by widget)

struct SharedSurahInfo: Codable {
    let number: Int
    let englishName: String
    let arabicName: String
    let numberOfAyahs: Int
}

enum SharedSurahCache {
    private static let key = "quran_surah_list_v1"

    static func save(_ surahs: [Surah]) {
        let info = surahs.map {
            SharedSurahInfo(number: $0.number, englishName: $0.englishName,
                            arabicName: $0.name, numberOfAyahs: $0.numberOfAyahs)
        }
        if let data = try? JSONEncoder().encode(info) {
            sharedDefaults.set(data, forKey: key)
        }
    }

    static func load() -> [SharedSurahInfo] {
        guard
            let data = sharedDefaults.data(forKey: key),
            let info = try? JSONDecoder().decode([SharedSurahInfo].self, from: data)
        else { return [] }
        return info
    }
}
