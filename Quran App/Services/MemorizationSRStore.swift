import Foundation
import Combine

/// One surah's spaced-repetition footprint, computed in a single pass over the
/// cards so views don't each re-scan the dictionary.
struct SurahSRProgress: Equatable {
    var enrolled: Int = 0   // ayahs of this surah enrolled in review
    var mature: Int = 0     // of those, how many have reached the mature interval
    var due: Int = 0        // of those, how many are due now
}

/// Per-ayah spaced-repetition store — the heart of the memorization engine. It
/// tracks individual ayahs the user is actively drilling, each tagged with a
/// `MemorizationGoal` and scheduled with SM-2. The per-surah heatmap in
/// `MemorizationStore` is *derived* from this (see `effectiveStatus`), so the
/// two systems stay in sync instead of drifting apart. Persisted in the shared
/// App Group container so it survives app updates.
final class MemorizationSRStore: ObservableObject {
    @Published private(set) var cards: [String: AyahReview] = [:]

    private let key = "quran_sr_cards_v1"
    private var defaults: UserDefaults { UserDefaults(suiteName: sharedAppGroup) ?? .standard }

    init() {
        load()
        NotificationCenter.default.addObserver(
            forName: CloudSync.didPull, object: nil, queue: .main
        ) { [weak self] _ in
            self?.load()
        }
    }

    private func cardID(_ surah: Int, _ ayah: Int) -> String { "\(surah):\(ayah)" }

    // MARK: - Queries

    func isScheduled(surah: Int, ayah: Int) -> Bool {
        cards[cardID(surah, ayah)] != nil
    }

    var totalCount: Int { cards.count }

    /// Total ayahs that have reached the mature interval across all surahs.
    var matureCount: Int { cards.values.filter(\.isMature).count }

    /// Cards due now, soonest first, ties broken by surah then ayah order.
    func dueItems(asOf date: Date = Date()) -> [AyahReview] {
        cards.values
            .filter { $0.isDue(asOf: date) }
            .sorted { ($0.dueDate, $0.surah, $0.ayah) < ($1.dueDate, $1.surah, $1.ayah) }
    }

    func dueCount(asOf date: Date = Date()) -> Int {
        cards.values.filter { $0.isDue(asOf: date) }.count
    }

    /// Ayah numbers from `surah` currently enrolled, for the reader's indicators.
    func scheduledAyahs(inSurah surah: Int) -> Set<Int> {
        Set(cards.values.filter { $0.surah == surah }.map(\.ayah))
    }

    /// All cards for a surah, in ayah order.
    func cards(inSurah surah: Int) -> [AyahReview] {
        cards.values.filter { $0.surah == surah }.sorted { $0.ayah < $1.ayah }
    }

    /// Due cards for a surah, soonest first.
    func dueItems(inSurah surah: Int, asOf date: Date = Date()) -> [AyahReview] {
        cards(inSurah: surah).filter { $0.isDue(asOf: date) }
    }

    /// Distinct surah numbers with at least one enrolled ayah, sorted.
    func enrolledSurahs() -> [Int] {
        Set(cards.values.map(\.surah)).sorted()
    }

    /// The representative goal for a surah (the goal of its first enrolled ayah),
    /// used to default single-ayah enrollments and seed the surah goal picker.
    func goal(forSurah surah: Int) -> MemorizationGoal? {
        cards(inSurah: surah).first?.goal
    }

    /// One-pass per-surah progress map, keyed by surah number.
    func surahProgress(asOf date: Date = Date()) -> [Int: SurahSRProgress] {
        var out: [Int: SurahSRProgress] = [:]
        for c in cards.values {
            var p = out[c.surah] ?? SurahSRProgress()
            p.enrolled += 1
            if c.isMature { p.mature += 1 }
            if c.isDue(asOf: date) { p.due += 1 }
            out[c.surah] = p
        }
        return out
    }

    // MARK: - Mutations

    func add(surah: Int, ayah: Int, surahName: String,
             arabic: String, translation: String, transliteration: String,
             goal: MemorizationGoal = .both) {
        let id = cardID(surah, ayah)
        guard cards[id] == nil else { return }   // never reset an existing card's schedule
        cards[id] = AyahReview(surah: surah, ayah: ayah, surahName: surahName,
                               arabic: arabic, translation: translation,
                               transliteration: transliteration, goal: goal)
        save()
    }

    func remove(surah: Int, ayah: Int) {
        if cards.removeValue(forKey: cardID(surah, ayah)) != nil { save() }
    }

    func toggle(surah: Int, ayah: Int, surahName: String,
                arabic: String, translation: String, transliteration: String,
                goal: MemorizationGoal = .both) {
        if isScheduled(surah: surah, ayah: ayah) {
            remove(surah: surah, ayah: ayah)
        } else {
            add(surah: surah, ayah: ayah, surahName: surahName,
                arabic: arabic, translation: translation,
                transliteration: transliteration, goal: goal)
        }
    }

    /// One enrolled ayah's worth of text, used for bulk surah enrollment.
    struct AyahSeed {
        let ayah: Int
        let arabic: String
        let translation: String
        let transliteration: String
    }

    /// Enroll every supplied ayah of a surah at once with a shared goal, and set
    /// that goal on any of them already enrolled. Existing cards keep their SM-2
    /// schedule; only their goal is updated.
    func enrollSurah(surah: Int, surahName: String, ayahs: [AyahSeed], goal: MemorizationGoal) {
        for seed in ayahs {
            let id = cardID(surah, seed.ayah)
            if var existing = cards[id] {
                if existing.goal != goal { existing.goal = goal; cards[id] = existing }
            } else {
                cards[id] = AyahReview(surah: surah, ayah: seed.ayah, surahName: surahName,
                                       arabic: seed.arabic, translation: seed.translation,
                                       transliteration: seed.transliteration, goal: goal)
            }
        }
        save()
    }

    /// Change the goal on a single enrolled ayah.
    func setGoal(_ goal: MemorizationGoal, surah: Int, ayah: Int) {
        let id = cardID(surah, ayah)
        guard var card = cards[id], card.goal != goal else { return }
        card.goal = goal
        cards[id] = card
        save()
    }

    /// Change the goal on every enrolled ayah of a surah.
    func setGoal(_ goal: MemorizationGoal, forSurah surah: Int) {
        var changed = false
        for (id, card) in cards where card.surah == surah && card.goal != goal {
            var c = card; c.goal = goal; cards[id] = c; changed = true
        }
        if changed { save() }
    }

    /// Remove every enrolled ayah of a surah.
    func removeSurah(_ surah: Int) {
        let before = cards.count
        cards = cards.filter { $0.value.surah != surah }
        if cards.count != before { save() }
    }

    /// Records a graded review and returns the rescheduled card.
    @discardableResult
    func recordReview(_ card: AyahReview, grade: ReviewGrade) -> AyahReview {
        var updated = card
        updated.apply(grade)
        cards[updated.id] = updated
        save()
        return updated
    }

    // MARK: - Translation refresh

    /// Brings every enrolled ayah's cached translation up to the user's current
    /// translation choice. Each card remembers the edition its text came from; any
    /// whose edition no longer matches the selected one is re-fetched (per surah,
    /// one request each) and its `translation` replaced — SM-2 scheduling, goal,
    /// and history are left untouched. Failures are skipped so offline review
    /// still works and stale cards refresh on the next pass; an unavailable
    /// edition (empty text) is likewise left alone rather than blanking the card.
    @MainActor
    func refreshTranslations() async {
        let target = Translation.selected.id
        let staleSurahs = Set(
            cards.values.filter { $0.translationEditionId != target }.map(\.surah)
        ).sorted()
        guard !staleSurahs.isEmpty else { return }

        var changed = false
        for surah in staleSurahs {
            // The user can switch translations again mid-refresh; bail so we never
            // tag a card with an edition we didn't actually fetch.
            guard Translation.selected.id == target else { break }
            guard let ayahs = try? await QuranAPIService.shared.fetchAyahs(surahNumber: surah)
            else { continue }
            let textByAyah = Dictionary(ayahs.map { ($0.numberInSurah, $0.translation) },
                                        uniquingKeysWith: { first, _ in first })

            // Snapshot the stale cards into a separate array before mutating `cards`
            // (iterating `cards.values` while writing back to `cards` is unsafe).
            let stale = cards.values.filter { $0.surah == surah && $0.translationEditionId != target }
            for card in stale {
                guard let text = textByAyah[card.ayah], !text.isEmpty else { continue }
                guard cards[card.id] != nil else { continue }   // not removed mid-refresh
                var updated = card
                updated.translation = text
                updated.translationEditionId = target
                cards[card.id] = updated
                changed = true
            }
        }
        if changed { save() }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(cards) {
            defaults.set(data, forKey: key)
        }
    }

    private func load() {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: AyahReview].self, from: data)
        else { return }
        cards = decoded
    }
}
