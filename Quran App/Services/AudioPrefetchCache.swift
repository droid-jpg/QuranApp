import Foundation

/// Downloads the next N ayah audio files to NSTemporaryDirectory so AVPlayer
/// can load from a local file URL instead of opening a new network connection
/// for every ayah. Reduces buffering pauses between ayahs significantly.
final class AudioPrefetchCache {
    static let shared = AudioPrefetchCache()

    private let queue = DispatchQueue(label: "audio.prefetch", qos: .utility)
    private var inFlight: Set<URL> = []
    private let tempDir: URL

    init() {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quran_prefetch", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    // MARK: - Public

    /// Pre-download a remote audio URL to a temp file. No-op if already cached or in-flight.
    func prefetch(_ remoteURL: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            let local = self.localPath(for: remoteURL)
            guard !FileManager.default.fileExists(atPath: local.path),
                  !self.inFlight.contains(remoteURL) else { return }
            self.inFlight.insert(remoteURL)
            let task = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tmp, _, err in
                guard let self, let tmp, err == nil else {
                    self?.queue.async { self?.inFlight.remove(remoteURL) }
                    return
                }
                try? FileManager.default.moveItem(at: tmp, to: local)
                self.queue.async { self.inFlight.remove(remoteURL) }
            }
            task.resume()
        }
    }

    /// Return the cached local file URL if available, otherwise nil.
    func cachedLocalURL(for remoteURL: URL) -> URL? {
        let local = localPath(for: remoteURL)
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    /// Evict all temp files (called when reciter changes or on startup if needed).
    func clearAll() {
        queue.async {
            try? FileManager.default.removeItem(at: self.tempDir)
            try? FileManager.default.createDirectory(at: self.tempDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Private

    private func localPath(for remoteURL: URL) -> URL {
        // Use a safe filename: replace slashes in path with underscores
        let safe = remoteURL.path.replacingOccurrences(of: "/", with: "_")
        return tempDir.appendingPathComponent(safe)
    }
}
