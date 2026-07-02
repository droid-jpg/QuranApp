import Foundation
import Combine

/// The single ayah (and surah) the user is *actively* memorizing right now, plus
/// how far they've already learned in that surah. This is the spine of the hifz
/// experience: the Home "Continue memorizing" card, the reader's loop presets, and
/// the "Continue memorizing" Siri intent all orient around it.
///
/// Deliberately lean — one working position per user. Memorizing is sequential in
/// practice (you drill one ayah, chain it onto the ones before, then move on), so a
/// single pointer matches how the method actually works. Persisted in the shared
/// App Group container so an App Intent / widget can read it without launching the
/// full app, and so it survives updates.
struct MemorizationTarget: Codable, Equatable {
    var surah: Int
    var surahName: String          // English transliteration, e.g. "Al-Mulk"
    var totalAyahs: Int
    /// The ayah currently being drilled.
    var workingAyah: Int
    /// Highest ayah confidently committed to memory (0 = none yet). The working
    /// ayah is normally `learnedThrough + 1`.
    var learnedThrough: Int
    var updated: Date

    /// Whole surah committed to memory — the point where meaning flashcards unlock.
    var isComplete: Bool { learnedThrough >= totalAyahs && totalAyahs > 0 }

    /// Fraction of the surah learned so far, for progress UI.
    var fraction: Double {
        totalAyahs > 0 ? min(1, Double(learnedThrough) / Double(totalAyahs)) : 0
    }
}

@MainActor
final class MemorizationTargetStore: ObservableObject {
    @Published private(set) var target: MemorizationTarget?

    private let key = "quran_hifz_target_v1"
    private var defaults: UserDefaults { UserDefaults(suiteName: sharedAppGroup) ?? .standard }

    init() {
        load()
        NotificationCenter.default.addObserver(
            forName: CloudSync.didPull, object: nil, queue: .main
        ) { [weak self] _ in
            // Re-capture weakly: the outer `self` is a mutable weak box, which
            // Swift 6 forbids referencing from concurrently-executing code.
            Task { @MainActor [weak self] in self?.load() }
        }
    }

    // MARK: - Mutations

    /// Begin (or switch to) memorizing a surah. Resumes at the first un-learned
    /// ayah if the surah was already in progress; otherwise starts at `ayah`.
    func start(surah: Int, surahName: String, totalAyahs: Int, at ayah: Int? = nil) {
        // Preserve prior progress when re-starting the same surah.
        let learned = (target?.surah == surah) ? (target?.learnedThrough ?? 0) : 0
        let working = ayah ?? max(1, min(learned + 1, totalAyahs))
        target = MemorizationTarget(
            surah: surah, surahName: surahName, totalAyahs: totalAyahs,
            workingAyah: max(1, min(working, totalAyahs)),
            learnedThrough: max(0, min(learned, totalAyahs)),
            updated: Date()
        )
        save()
    }

    /// Point the working position at a specific ayah of the current surah (e.g. the
    /// user tapped "Work on this ayah" in the reader).
    func setWorkingAyah(_ ayah: Int) {
        guard var t = target else { return }
        t.workingAyah = max(1, min(ayah, t.totalAyahs))
        t.updated = Date()
        target = t
        save()
    }

    /// Mark the working ayah as learned and advance to the next one. Clamps at the
    /// end of the surah (the caller can then offer meaning flashcards).
    func markWorkingAyahLearned() {
        guard var t = target else { return }
        t.learnedThrough = max(t.learnedThrough, t.workingAyah)
        t.workingAyah = min(t.workingAyah + 1, t.totalAyahs)
        t.updated = Date()
        target = t
        save()
    }

    /// Step back one ayah (undo an over-eager advance).
    func stepBack() {
        guard var t = target, t.workingAyah > 1 else { return }
        t.workingAyah -= 1
        t.learnedThrough = min(t.learnedThrough, t.workingAyah - 1)
        t.updated = Date()
        target = t
        save()
    }

    func clear() {
        target = nil
        defaults.removeObject(forKey: key)
    }

    // MARK: - Persistence

    private func save() {
        guard let t = target else { return }
        if let data = try? JSONEncoder().encode(t) {
            defaults.set(data, forKey: key)
        }
    }

    private func load() {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(MemorizationTarget.self, from: data)
        else { return }
        target = decoded
    }
}
