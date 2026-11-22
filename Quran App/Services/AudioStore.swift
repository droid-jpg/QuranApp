import AVFoundation
import Observation
import os

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

/// How much near-silence to skip at either end of an ayah's file. Some reciters' files
/// carry most of a second of silence before or after the recitation (Al-Minshawi, Abdul
/// Basit, Al-Husary), which made a long gap between ayahs. A short breath is kept on
/// both sides; files that start and end on the recitation are left as they are.
nonisolated enum AudioTrim {
    struct Bounds: Sendable {
        /// Where to start playing, in seconds.
        var start: Double = 0
        /// Where to stop, or nil for the end of the file.
        var end: Double?
    }

    private static let cache = OSAllocatedUnfairLock<[String: Bounds]>(initialState: [:])

    /// Measured once per file, then remembered for the session. Reads at most 3.5 s of
    /// audio, so it is quick, but call it off the main actor where that is easy.
    static func bounds(of url: URL) -> Bounds {
        if let known = cache.withLock({ $0[url.path] }) { return known }
        let found = measure(url) ?? Bounds()
        cache.withLock { $0[url.path] = found }
        return found
    }

    private static let window = 0.02
    /// The recitation has started once a 20 ms window is louder than −40 dBFS.
    private static let onsetLevel: Float = 0.01
    /// The tail ends at the last window louder than −50 dBFS, so reverb is kept.
    private static let tailLevel: Float = 0.003_16
    private static let leadBreath = 0.15
    private static let tailBreath = 0.2

    private static func measure(_ url: URL) -> Bounds? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        guard rate > 0, file.length > 0 else { return nil }
        let duration = Double(file.length) / rate

        var bounds = Bounds()
        if let head = levels(file, from: 0, length: min(2, duration)),
           let first = head.firstIndex(where: { $0 > onsetLevel }) {
            let start = Double(first) * window - leadBreath
            if start >= 0.1 { bounds.start = start }
        }
        let tailFrom = max(0, duration - 1.5)
        if let tail = levels(file, from: tailFrom, length: duration - tailFrom),
           let last = tail.lastIndex(where: { $0 > tailLevel }) {
            let end = tailFrom + Double(last + 1) * window + tailBreath
            if duration - end >= 0.1 { bounds.end = end }
        }
        // Never leave less than half a second to play.
        if let end = bounds.end, end - bounds.start < 0.5 { return nil }
        return bounds
    }

    /// The RMS level of each 20 ms window of the first channel.
    private static func levels(_ file: AVAudioFile, from seconds: Double, length: Double) -> [Float]? {
        let rate = file.processingFormat.sampleRate
        let count = AVAudioFrameCount(length * rate)
        guard count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { return nil }
        file.framePosition = AVAudioFramePosition(seconds * rate)
        guard (try? file.read(into: buffer, frameCount: count)) != nil,
              let samples = buffer.floatChannelData?[0] else { return nil }
        let frames = Int(buffer.frameLength)
        let size = max(1, Int(window * rate))
        var result: [Float] = []
        result.reserveCapacity(frames / size)
        var i = 0
        while i + size <= frames {
            var sum: Float = 0
            for j in i..<(i + size) { sum += samples[j] * samples[j] }
            result.append((sum / Float(size)).squareRoot())
            i += size
        }
        return result
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
