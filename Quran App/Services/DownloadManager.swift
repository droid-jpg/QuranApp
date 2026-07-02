import Foundation
import Combine

@MainActor
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    /// surahNumber → 0.0–1.0 download progress (1.0 = complete) for the
    /// currently-selected reciter.
    @Published var progress: [Int: Double] = [:]

    private var ayahCounters: [Int: (done: Int, total: Int)] = [:]

    /// Persisted record of completed downloads, keyed by reciter subfolder.
    /// Survives app restarts so the UI can reflect on-disk audio.
    private let completedKey = "downloaded_surahs_v1"
    private var completedByReciter: [String: Set<Int>] = [:]

    override init() {
        super.init()
        loadCompleted()
        rebuildProgressForCurrentReciter()
    }

    // MARK: - Public API

    /// True when the surah's audio is fully downloaded for the current reciter.
    func isDownloaded(_ surahNumber: Int) -> Bool {
        (progress[surahNumber] ?? 0) >= 1.0
    }

    func isSurahDownloaded(_ surahNumber: Int, reciterSubfolder: String) -> Bool {
        guard surahHasFiles(surahNumber, reciterSubfolder: reciterSubfolder) else { return false }
        return completedByReciter[reciterSubfolder]?.contains(surahNumber) ?? false
    }

    /// Number of fully-downloaded surahs for the current reciter.
    var downloadedCount: Int {
        progress.values.filter { $0 >= 1.0 }.count
    }

    /// Rebuilds the `progress` map for whichever reciter is currently selected.
    /// Call when the selected reciter changes so the UI shows the right state.
    func syncCurrentReciter() {
        rebuildProgressForCurrentReciter()
    }

    func downloadSurah(_ surahNumber: Int, ayahCount: Int, reciterSubfolder: String) {
        guard progress[surahNumber] == nil || (progress[surahNumber] ?? 0) < 1.0 else { return }
        progress[surahNumber] = 0.001  // show spinner immediately

        let dir = surahDirectory(surahNumber, reciterSubfolder: reciterSubfolder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        ayahCounters[surahNumber] = (done: 0, total: ayahCount)

        Task {
            // Download up to 8 ayahs concurrently for fast progress
            // while keeping network usage reasonable.
            await withTaskGroup(of: Void.self) { group in
                var inflight = 0
                for ayah in 1...ayahCount {
                    let localURL = self.localFileURL(surah: surahNumber, ayah: ayah, reciterSubfolder: reciterSubfolder)
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        self.markAyahDone(surahNumber: surahNumber, ayahCount: ayahCount, reciterSubfolder: reciterSubfolder)
                        continue
                    }
                    // Throttle: wait for a slot before adding more work
                    if inflight >= 8 {
                        await group.next()
                        inflight -= 1
                    }
                    let remoteURL = self.remoteAyahURL(surah: surahNumber, ayah: ayah, reciterSubfolder: reciterSubfolder)
                    group.addTask { [localURL, remoteURL] in
                        do {
                            let (tmpURL, _) = try await URLSession.shared.download(from: remoteURL)
                            try? FileManager.default.moveItem(at: tmpURL, to: localURL)
                        } catch { /* network error — still count toward progress */ }
                        await self.markAyahDone(surahNumber: surahNumber, ayahCount: ayahCount, reciterSubfolder: reciterSubfolder)
                    }
                    inflight += 1
                }
            }
        }
    }

    func deleteSurah(_ surahNumber: Int, reciterSubfolder: String) {
        let dir = surahDirectory(surahNumber, reciterSubfolder: reciterSubfolder)
        try? FileManager.default.removeItem(at: dir)
        progress.removeValue(forKey: surahNumber)
        ayahCounters.removeValue(forKey: surahNumber)
        if var set = completedByReciter[reciterSubfolder] {
            set.remove(surahNumber)
            completedByReciter[reciterSubfolder] = set
            persistCompleted()
        }
    }

    /// Returns local file URL if a downloaded copy exists, otherwise nil.
    func localURL(surah: Int, ayah: Int, reciterSubfolder: String) -> URL? {
        let url = localFileURL(surah: surah, ayah: ayah, reciterSubfolder: reciterSubfolder)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Private helpers

    @MainActor private func markAyahDone(surahNumber: Int, ayahCount: Int, reciterSubfolder: String) {
        var counter = ayahCounters[surahNumber] ?? (done: 0, total: ayahCount)
        counter.done += 1
        ayahCounters[surahNumber] = counter
        progress[surahNumber] = Double(counter.done) / Double(counter.total)

        if counter.done >= counter.total {
            ayahCounters.removeValue(forKey: surahNumber)
            var set = completedByReciter[reciterSubfolder] ?? []
            set.insert(surahNumber)
            completedByReciter[reciterSubfolder] = set
            persistCompleted()
        }
    }

    private func rebuildProgressForCurrentReciter() {
        let sub = Reciter.selected.subfolder
        // Drop any completed entries whose files are no longer on disk.
        var done = completedByReciter[sub] ?? []
        let onDisk = done.filter { surahHasFiles($0, reciterSubfolder: sub) }
        if onDisk != done {
            done = onDisk
            completedByReciter[sub] = done
            persistCompleted()
        }

        var newProgress: [Int: Double] = [:]
        for n in done { newProgress[n] = 1.0 }
        // Preserve any in-flight downloads for the current reciter.
        for (n, p) in progress where p < 1.0 { newProgress[n] = p }
        progress = newProgress
    }

    private func surahHasFiles(_ surahNumber: Int, reciterSubfolder: String) -> Bool {
        let dir = surahDirectory(surahNumber, reciterSubfolder: reciterSubfolder)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return !files.isEmpty
    }

    private func loadCompleted() {
        guard
            let data = UserDefaults.standard.data(forKey: completedKey),
            let decoded = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else { return }
        completedByReciter = decoded.mapValues { Set($0) }
    }

    private func persistCompleted() {
        let encodable = completedByReciter.mapValues { Array($0).sorted() }
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: completedKey)
        }
    }

    private func surahDirectory(_ surahNumber: Int, reciterSubfolder: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let s = String(format: "%03d", surahNumber)
        return docs.appendingPathComponent("quran_audio/\(reciterSubfolder)/\(s)")
    }

    private func localFileURL(surah: Int, ayah: Int, reciterSubfolder: String) -> URL {
        let a = String(format: "%03d", ayah)
        return surahDirectory(surah, reciterSubfolder: reciterSubfolder).appendingPathComponent("\(a).mp3")
    }

    private func remoteAyahURL(surah: Int, ayah: Int, reciterSubfolder: String) -> URL {
        let s = String(format: "%03d", surah)
        let a = String(format: "%03d", ayah)
        return URL(string: "https://everyayah.com/data/\(reciterSubfolder)/\(s)\(a).mp3")!
    }
}
