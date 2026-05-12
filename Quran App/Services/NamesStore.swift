import Foundation
import Combine

/// Tracks which of the 99 Names the user has memorized or flagged for review.
class NamesStore: ObservableObject {
    enum NameStatus: String, Codable { case notStarted, learning, memorized }

    @Published private(set) var statuses: [Int: NameStatus] = [:]  // keyed by name id (1–99)

    private let key = "allah_names_status_v1"
    private var defaults: UserDefaults { UserDefaults(suiteName: "group.sami.Quran-App") ?? .standard }

    init() { load() }

    func status(for id: Int) -> NameStatus { statuses[id] ?? .notStarted }

    func cycle(for id: Int) {
        let next: NameStatus
        switch status(for: id) {
        case .notStarted: next = .learning
        case .learning:   next = .memorized
        case .memorized:  next = .notStarted
        }
        set(next, for: id)
    }

    func set(_ status: NameStatus, for id: Int) {
        if status == .notStarted { statuses.removeValue(forKey: id) }
        else                     { statuses[id] = status }
        save()
    }

    var memorizedCount: Int { statuses.values.filter { $0 == .memorized }.count }
    var learningCount:  Int { statuses.values.filter { $0 == .learning  }.count }

    private func save() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: statuses.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            defaults.set(data, forKey: key)
        }
    }

    private func load() {
        guard
            let data    = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: NameStatus].self, from: data)
        else { return }
        statuses = Dictionary(uniqueKeysWithValues: decoded.compactMap { k, v in
            guard let n = Int(k) else { return nil }
            return (n, v)
        })
    }
}
