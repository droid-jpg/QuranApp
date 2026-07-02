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

    private let statusKey = "quran_memorization_v1"

    init() {
        load()
        NotificationCenter.default.addObserver(
            forName: CloudSync.didPull, object: nil, queue: .main
        ) { [weak self] _ in
            self?.load()
        }
    }

    // MARK: - Status

    /// The status the user explicitly set, ignoring review progress.
    func manualStatus(for surahNumber: Int) -> MemorizationStatus {
        statuses[surahNumber] ?? .notStarted
    }

    func status(for surahNumber: Int) -> MemorizationStatus {
        statuses[surahNumber] ?? .notStarted
    }

    var memorizedCount: Int  { statuses.values.filter { $0 == .memorized  }.count }
    var inProgressCount: Int { statuses.values.filter { $0 == .inProgress }.count }

    var inProgressNumbers: [Int] {
        statuses.filter { $0.value == .inProgress }.keys.sorted()
    }

    /// Surahs the user explicitly marked Memorized, sorted.
    var memorizedNumbers: [Int] {
        statuses.filter { $0.value == .memorized }.keys.sorted()
    }

    /// Every surah carrying a manual mark (memorized or in progress), sorted.
    /// Used by the memorization hub to surface hand-marked surahs alongside the
    /// ayahs enrolled in spaced repetition.
    var markedNumbers: [Int] {
        statuses.filter { $0.value != .notStarted }.keys.sorted()
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

    // MARK: - Hybrid status (manual override + review-derived)

    /// Combines the user's manual mark with spaced-repetition progress. A manual
    /// "Memorized" always wins; otherwise the surah counts as memorized once every
    /// ayah is enrolled and mature, and in-progress once any ayah is enrolled (or
    /// the user manually flagged it). Counts come from `MemorizationSRStore`.
    func effectiveStatus(for surahNumber: Int, enrolled: Int, mature: Int, totalAyahs: Int) -> MemorizationStatus {
        if statuses[surahNumber] == .memorized { return .memorized }
        if totalAyahs > 0, enrolled >= totalAyahs, mature >= totalAyahs { return .memorized }
        if enrolled > 0 || statuses[surahNumber] == .inProgress { return .inProgress }
        return .notStarted
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
