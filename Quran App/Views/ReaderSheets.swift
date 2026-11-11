import SwiftUI
import Combine

// Sheet routing for the reader. The pager holds the router as a plain reference
// (`@State`, not `@StateObject`) and the pages only call it, so opening Ayah
// actions, Tafsir or Word by word re-renders this zero-size host, never the
// pager, the page or its rows.

/// One ayah of one surah, with the surah's model (tafsir, word timings).
struct ReaderAyahRef: Identifiable {
    let surah: Surah
    let ayah: Ayah
    let model: SurahDetailViewModel
    var id: String { "\(surah.number):\(ayah.numberInSurah)" }
}

/// Drives the "also enroll the ayahs before this one?" prompt after a single-ayah
/// enrollment that leaves an un-enrolled run before it.
struct PrecedingEnrollPrompt: Identifiable {
    let id = UUID()
    let ref: ReaderAyahRef
    let count: Int      // how many earlier ayahs are not yet enrolled
}

/// The one per-ayah sheet the reader has up. One `.sheet(item:)` for all of
/// them, so going from Ayah actions to Tafsir is close, then open, on the same
/// presenter.
enum ReaderSheet: Identifiable {
    case actions(ReaderAyahRef)
    case tafsir(ReaderAyahRef)
    case wordByWord(ReaderAyahRef)

    var id: String {
        switch self {
        case .actions(let r):    return "actions-\(r.id)"
        case .tafsir(let r):     return "tafsir-\(r.id)"
        case .wordByWord(let r): return "words-\(r.id)"
        }
    }
}

@MainActor
final class ReaderSheetRouter: ObservableObject {
    @Published var sheet: ReaderSheet?
    @Published var precedingPrompt: PrecedingEnrollPrompt?
    /// What runs once the current sheet has finished closing.
    private var afterDismiss: (() -> Void)?

    func openActions(surah: Surah, ayah: Ayah, model: SurahDetailViewModel) {
        Haptics.impact(.medium)
        sheet = .actions(ReaderAyahRef(surah: surah, ayah: ayah, model: model))
    }

    /// Closes the sheet and runs `next` after it is gone, so a following sheet
    /// (here or at the root) can present.
    func close(then next: @escaping () -> Void) {
        afterDismiss = next
        sheet = nil
    }

    func sheetDidDismiss() {
        let next = afterDismiss
        afterDismiss = nil
        next?()
    }
}

/// Presents the reader's per-ayah sheets. Each sheet sits on its own layer, since
/// only one `.sheet` per view is reliable.
struct ReaderSheetsHost: View {
    @ObservedObject var router: ReaderSheetRouter

    @Environment(\.playerUIRef) private var playerUI
    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @EnvironmentObject private var targetStore: MemorizationTargetStore

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .sheet(item: $router.sheet, onDismiss: { router.sheetDidDismiss() }) { sheet in
                switch sheet {
                case .actions(let ref):
                    AyahActionsSheet(
                        surah: ref.surah, ayah: ref.ayah, model: ref.model,
                        closeThen: { next in router.close(then: next) },
                        onTafsir: { router.sheet = .tafsir(ref) },
                        onWordByWord: { router.sheet = .wordByWord(ref) },
                        onAddToMemorization: { addToMemorization(ref) },
                        onMoreRepeatOptions: {
                            playerUI?.openRepeat(surah: ref.surah, pendingAyah: ref.ayah.numberInSurah)
                        }
                    )
                case .tafsir(let ref):
                    ReaderTafsirSheet(ref: ref, model: ref.model)
                case .wordByWord(let ref):
                    WordByWordSheet(ref: ref, model: ref.model)
                }
            }
            .confirmationDialog(
                "Add earlier ayahs?",
                isPresented: Binding(
                    get: { router.precedingPrompt != nil },
                    set: { if !$0 { router.precedingPrompt = nil } }
                ),
                titleVisibility: .visible,
                presenting: router.precedingPrompt
            ) { prompt in
                Button("Add ayahs 1–\(prompt.ref.ayah.numberInSurah)") { enrollPreceding(prompt.ref) }
                Button("Just this ayah", role: .cancel) {}
            } message: { prompt in
                Text("Add the \(prompt.count) earlier ayah\(prompt.count == 1 ? "" : "s") in \(prompt.ref.surah.englishName) too, so you memorize in order?")
            }
    }

    // MARK: Add to memorization

    /// Not tracked yet: start memorizing this surah at this ayah. Tracked: add the
    /// ayah to review (and offer the un-enrolled ayahs before it).
    private func addToMemorization(_ ref: ReaderAyahRef) {
        let surah = ref.surah
        if AyahMemorization.isTracked(surah: surah.number, srStore: srStore, targetStore: targetStore) {
            addToReview(ref)
        } else {
            targetStore.start(surah: surah.number, surahName: surah.englishName,
                              totalAyahs: surah.numberOfAyahs, at: ref.ayah.numberInSurah)
            if memorizationStore.manualStatus(for: surah.number) == .notStarted {
                memorizationStore.set(.inProgress, for: surah.number)
            }
            StreakService.shared.recordRead()
            Haptics.success()
        }
    }

    /// Enroll a single ayah in spaced-repetition review at the surah's goal.
    private func addToReview(_ ref: ReaderAyahRef) {
        let surah = ref.surah, ayah = ref.ayah, n = ayah.numberInSurah
        guard !srStore.isScheduled(surah: surah.number, ayah: n) else { return }
        let goal = srStore.goal(forSurah: surah.number) ?? .both
        srStore.toggle(
            surah: surah.number, ayah: n, surahName: surah.englishName,
            arabic: ayah.arabic, translation: ayah.translation,
            transliteration: ayah.transliteration, goal: goal
        )
        if memorizationStore.status(for: surah.number) == .notStarted {
            memorizationStore.set(.inProgress, for: surah.number)
        }
        Haptics.success()
        let preceding = ref.model.ayahs.filter {
            $0.numberInSurah < n && !srStore.isScheduled(surah: surah.number, ayah: $0.numberInSurah)
        }
        if !preceding.isEmpty {
            router.precedingPrompt = PrecedingEnrollPrompt(ref: ref, count: preceding.count)
        }
    }

    /// Enrolls every loaded ayah from 1 through this one at the surah's goal.
    private func enrollPreceding(_ ref: ReaderAyahRef) {
        let surah = ref.surah
        let goal = srStore.goal(forSurah: surah.number) ?? .both
        let seeds = ref.model.ayahs
            .filter { $0.numberInSurah <= ref.ayah.numberInSurah }
            .map {
                MemorizationSRStore.AyahSeed(
                    ayah: $0.numberInSurah, arabic: $0.arabic,
                    translation: $0.translation, transliteration: $0.transliteration
                )
            }
        srStore.enrollSurah(surah: surah.number, surahName: surah.englishName, ayahs: seeds, goal: goal)
        Haptics.success()
    }
}

/// Tafsir for one ayah, following the model so commentary that arrives late shows.
private struct ReaderTafsirSheet: View {
    let ref: ReaderAyahRef
    @ObservedObject var model: SurahDetailViewModel

    var body: some View {
        if let text = model.tafsirByAyah[ref.ayah.numberInSurah] {
            TafsirSheet(ayah: ref.ayah, surahName: ref.surah.englishName, text: text)
        }
    }
}
