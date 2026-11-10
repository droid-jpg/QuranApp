import Foundation
import Combine

/// The last thing the user actually *listened* to — surah, ayah, reciter, repeat
/// and how far into that ayah playback got.
///
/// Memorization has `MemorizationTargetStore` for "what am I working on"; this is
/// the parallel pointer for "what was playing". Home's resume hero reads it so a
/// listening session costs one tap instead of a tab switch and a 114-row list.
struct ListeningSession: Codable, Equatable {
    var surah: Int
    var surahName: String
    var ayah: Int
    var totalAyahs: Int
    var reciterId: Int
    var repeatState: RepeatState
    /// 0…1 position inside `ayah` when this snapshot was written.
    var fraction: Double
    /// Length of `ayah` in seconds (0 when it was never known).
    var duration: Double
    var updated: Date

    var reciterName: String {
        Reciter.all.first { $0.id == reciterId }?.name ?? Reciter.all[0].name
    }

    /// True when the session was a repeat rather than plain listening.
    var isLoop: Bool { repeatState.isOn }

    /// The status line for this session, from the one status function.
    var loopLabel: String { repeatState.status(currentAyah: ayah, reciterName: reciterName) }

    var elapsed: Double { duration * min(1, max(0, fraction)) }
    var remaining: Double { max(0, duration - elapsed) }
}

// Sessions saved before `RepeatState` hold the old `LoopSettings` under "loop";
// they migrate on read. A repeat that can't be read at all becomes "off" rather
// than losing the whole session.
extension ListeningSession {
    private enum CodingKeys: String, CodingKey {
        case surah, surahName, ayah, totalAyahs, reciterId, fraction, duration, updated
        case repeatState = "repeat"
    }
    private enum LegacyKeys: String, CodingKey { case loop }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surah      = try c.decode(Int.self, forKey: .surah)
        surahName  = (try? c.decodeIfPresent(String.self, forKey: .surahName)) ?? ""
        ayah       = try c.decode(Int.self, forKey: .ayah)
        totalAyahs = try c.decode(Int.self, forKey: .totalAyahs)
        reciterId  = (try? c.decodeIfPresent(Int.self, forKey: .reciterId)) ?? Reciter.all[0].id
        fraction   = (try? c.decodeIfPresent(Double.self, forKey: .fraction)) ?? 0
        duration   = (try? c.decodeIfPresent(Double.self, forKey: .duration)) ?? 0
        updated    = (try? c.decodeIfPresent(Date.self, forKey: .updated)) ?? Date()

        if let state = try? c.decodeIfPresent(RepeatState.self, forKey: .repeatState) {
            repeatState = state
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
                    .decodeIfPresent(RepeatState.Legacy.self, forKey: .loop) {
            repeatState = RepeatState(legacy: legacy, surah: surah)
        } else {
            repeatState = RepeatState(surah: surah, from: ayah, to: ayah)
        }
        if repeatState.surah == 0 { repeatState.surah = surah }
    }
}

@MainActor
final class ListeningSessionStore: ObservableObject {
    static let shared = ListeningSessionStore()

    /// The last committed snapshot. Deliberately *not* republished on every
    /// playback tick — position-only changes are persisted quietly and the live
    /// player is the source of truth while audio is running, so Home doesn't
    /// re-render ten times a second behind the reader.
    @Published private(set) var session: ListeningSession?

    private let key = "quran_listening_session_v1"
    private var defaults: UserDefaults { UserDefaults(suiteName: sharedAppGroup) ?? .standard }

    /// Latest position reported by the player, published on `flush()`.
    private var pending: ListeningSession?
    private var lastWrite: Date = .distantPast
    private static let writeInterval: TimeInterval = 5

    private init() { load() }

    // MARK: - Recording

    func record(surah: Int, surahName: String, ayah: Int, totalAyahs: Int,
                repeatState: RepeatState, fraction: Double, duration: Double) {
        guard surah > 0, ayah > 0, totalAyahs > 0 else { return }
        let name = surahName.isEmpty ? (session?.surah == surah ? session?.surahName ?? "" : "") : surahName
        let snapshot = ListeningSession(
            surah: surah, surahName: name, ayah: ayah, totalAyahs: totalAyahs,
            reciterId: Reciter.selected.id, repeatState: repeatState,
            fraction: min(1, max(0, fraction)), duration: max(0, duration),
            updated: Date()
        )
        // An ayah is recorded the moment it loads, before its length is known.
        // Most ayahs are shorter than the write interval, so without this the
        // snapshot that survives to disk would never learn its own duration.
        let durationJustLearned = (pending?.duration ?? 0) == 0 && snapshot.duration > 0
        pending = snapshot

        // A new ayah (or surah) is a real change of what's playing — publish it.
        // Everything else is just the playhead moving, so only touch disk.
        if session?.surah != snapshot.surah || session?.ayah != snapshot.ayah {
            session = snapshot
            save(snapshot)
        } else if durationJustLearned || Date().timeIntervalSince(lastWrite) >= Self.writeInterval {
            save(snapshot)
        }
    }

    /// Commit the pending position — call when playback pauses or stops, so the
    /// resume card shows exactly where the user left off.
    func flush() {
        guard let p = pending else { return }
        session = p
        save(p)
    }

    func clear() {
        pending = nil
        session = nil
        defaults.removeObject(forKey: key)
    }

    // MARK: - Persistence

    private func save(_ s: ListeningSession) {
        lastWrite = Date()
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: key)
        }
    }

    private func load() {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(ListeningSession.self, from: data)
        else { return }
        session = decoded
        pending = decoded
    }
}
