import Foundation
import Observation

/// Per-ayah audio files on disk. The player only ever plays local files: an ayah that
/// isn't here yet is fetched first and then kept, so everything played once plays
/// offline afterwards and nothing is ever streamed.
actor AudioStore {
    static let shared = AudioStore()

    private var inFlight: [URL: Task<URL, Error>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    // MARK: - Paths

    static let root = AppFiles.directory("Audio")

    static func surahDirectory(reciter: Reciter, surah: Int) -> URL {
        root.appendingPathComponent("\(reciter.id)/\(surah)", isDirectory: true)
    }

    static func fileURL(reciter: Reciter, surah: Int, ayah: Int) -> URL {
        surahDirectory(reciter: reciter, surah: surah).appendingPathComponent("\(ayah).mp3")
    }

    static func isLocal(reciter: Reciter, surah: Int, ayah: Int) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(reciter: reciter, surah: surah, ayah: ayah).path)
    }

    /// How many of a surah's ayahs are on disk.
    static func localCount(reciter: Reciter, surah: Int) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: surahDirectory(reciter: reciter, surah: surah).path)) ?? []
        return names.filter { $0.hasSuffix(".mp3") }.count
    }

    // MARK: - Fetching

    /// The ayah's local file, downloading it first if needed. Concurrent requests for
    /// the same ayah share one download.
    func file(reciter: Reciter, surah: Int, ayah: Int) async throws -> URL {
        let destination = Self.fileURL(reciter: reciter, surah: surah, ayah: ayah)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        if let running = inFlight[destination] { return try await running.value }

        let sources = reciter.remoteURLs(surah: surah, ayah: ayah)
        let session = session
        let task = Task<URL, Error> {
            var lastError: Error = URLError(.badURL)
            for source in sources {
                do {
                    let (temp, response) = try await session.download(from: source)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    let fm = FileManager.default
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if !fm.fileExists(atPath: destination.path) {
                        try fm.moveItem(at: temp, to: destination)
                    }
                    return destination
                } catch {
                    lastError = error
                    if Task.isCancelled { break }
                }
            }
            throw lastError
        }
        inFlight[destination] = task
        defer { inFlight[destination] = nil }
        return try await task.value
    }

    /// Fetches ayahs ahead of the one playing, quietly.
    nonisolated func prefetch(reciter: Reciter, surah: Int, ayahs: [Int]) {
        for ayah in ayahs where !Self.isLocal(reciter: reciter, surah: surah, ayah: ayah) {
            Task(priority: .utility) { _ = try? await self.file(reciter: reciter, surah: surah, ayah: ayah) }
        }
    }
}

/// Whole-surah downloads and what is stored, for the surah list and Settings.
@MainActor @Observable
final class Downloads {
    /// Surahs fully on disk for the selected reciter.
    private(set) var complete: Set<Int> = []
    /// Fraction done, for surahs downloading now.
    private(set) var progress: [Int: Double] = [:]
    /// Surahs whose last download attempt did not finish.
    private(set) var failed: Set<Int> = []

    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]

    init() { refresh() }

    /// Re-reads the disk. Call after the reciter changes or audio is removed.
    func refresh() {
        let reciter = Reciter.selected
        var found: Set<Int> = []
        for surah in QuranText.shared.surahs
        where AudioStore.localCount(reciter: reciter, surah: surah.number) >= surah.numberOfAyahs {
            found.insert(surah.number)
        }
        complete = found
    }

    /// Notes a surah the player has just finished fetching, without a disk scan.
    func noteIfComplete(_ surah: Surah) {
        guard !complete.contains(surah.number),
              AudioStore.localCount(reciter: .selected, surah: surah.number) >= surah.numberOfAyahs else { return }
        complete.insert(surah.number)
    }

    func download(_ surah: Surah) {
        guard tasks[surah.number] == nil, !complete.contains(surah.number) else { return }
        let reciter = Reciter.selected
        failed.remove(surah.number)
        progress[surah.number] = 0
        tasks[surah.number] = Task {
            var done = 0
            var missed = 0
            await withTaskGroup(of: Bool.self) { group in
                var next = 1
                func add() {
                    guard next <= surah.numberOfAyahs else { return }
                    let ayah = next
                    next += 1
                    group.addTask {
                        (try? await AudioStore.shared.file(reciter: reciter, surah: surah.number, ayah: ayah)) != nil
                    }
                }
                for _ in 0..<4 { add() }
                for await ok in group {
                    if ok { done += 1 } else { missed += 1 }
                    progress[surah.number] = Double(done + missed) / Double(surah.numberOfAyahs)
                    if Task.isCancelled { group.cancelAll() } else { add() }
                }
            }
            progress[surah.number] = nil
            tasks[surah.number] = nil
            if missed == 0, !Task.isCancelled {
                complete.insert(surah.number)
                Haptics.success()
            } else if !Task.isCancelled {
                failed.insert(surah.number)
                Haptics.error()
            }
        }
    }

    func cancel(_ surah: Int) {
        tasks[surah]?.cancel()
        tasks[surah] = nil
        progress[surah] = nil
    }

    func remove(_ surah: Int) {
        cancel(surah)
        try? FileManager.default.removeItem(at: AudioStore.surahDirectory(reciter: .selected, surah: surah))
        complete.remove(surah)
    }

    func removeAll() {
        for surah in Array(tasks.keys) { cancel(surah) }
        try? FileManager.default.removeItem(at: AudioStore.root)
        _ = AppFiles.directory("Audio")
        complete = []
    }

    /// Bytes of audio kept on this device, all reciters.
    nonisolated static func storedBytes() async -> Int64 {
        await Task.detached(priority: .utility) { AppFiles.size(of: AudioStore.root) }.value
    }
}
