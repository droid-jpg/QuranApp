import Foundation
import Combine
import SwiftUI

struct BookmarkedAyah: Codable, Identifiable, Equatable {
    let surahNumber: Int
    let surahName: String        // english name
    let surahArabicName: String  // arabic name
    let ayahNumber: Int
    let arabic: String
    let translation: String
    var id: String { "\(surahNumber):\(ayahNumber)" }
}

class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [BookmarkedAyah] = []
    private let key = "quran_bookmarks_v1"

    init() {
        load()
        NotificationCenter.default.addObserver(
            forName: CloudSync.didPull, object: nil, queue: .main
        ) { [weak self] _ in
            self?.load()
        }
    }

    func isBookmarked(surah: Int, ayah: Int) -> Bool {
        bookmarks.contains { $0.surahNumber == surah && $0.ayahNumber == ayah }
    }

    /// Toggle bookmark for an ayah. Provide surah metadata for display.
    func toggle(surahNumber: Int, surahName: String, surahArabicName: String, ayahNumber: Int, arabic: String, translation: String) {
        if let idx = bookmarks.firstIndex(where: { $0.surahNumber == surahNumber && $0.ayahNumber == ayahNumber }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.insert(BookmarkedAyah(
                surahNumber: surahNumber,
                surahName: surahName,
                surahArabicName: surahArabicName,
                ayahNumber: ayahNumber,
                arabic: arabic,
                translation: translation
            ), at: 0)
        }
        save()
    }

    func clearAll() { bookmarks = []; save() }

    func savePublic() { save() }

    func remove(atOffsets offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([BookmarkedAyah].self, from: data)
        else { return }
        bookmarks = decoded
    }
}
