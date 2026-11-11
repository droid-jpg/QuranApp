import SwiftUI
import Combine

// MARK: - Page models

/// One `SurahDetailViewModel` per surah, owned by the pager rather than by the
/// page. The reader's chrome — top bar, sheets — is drawn once, outside the
/// pages, and needs the *active* page's model to do it; a `@StateObject` inside
/// each page would be out of reach. Swiping back to a surah also finds its ayahs
/// still loaded.
@MainActor
final class SurahModelStore: ObservableObject {
    // Nothing here is `@Published`: models are vended during body evaluation, and
    // publishing from there would be a mutation mid-update.
    private var models: [Int: SurahDetailViewModel] = [:]

    func model(for surah: Surah) -> SurahDetailViewModel {
        if let existing = models[surah.number] { return existing }
        let made = SurahDetailViewModel(surah: surah)
        models[surah.number] = made
        return made
    }
}

// MARK: - Non-observing audio reference

extension EnvironmentValues {
    /// `AudioService` as a plain reference. Reading it does not subscribe the
    /// view to the service's changes, so the pager and the pages can send it
    /// commands without re-rendering on every ayah advance or play/pause. Views
    /// that draw playback state observe it themselves (`@EnvironmentObject`).
    @Entry var audioServiceRef: AudioService? = nil
}

// MARK: - Surah page browser (swipe between surahs)

/// Wraps multiple `SurahDetailView`s in a horizontally-paged TabView so the user
/// can swipe left/right between surahs, and owns everything that must sit *above*
/// the pages: the reader's own top bar (the system navigation bar is hidden — on
/// iOS 26 it floats over scroll content, which put chrome on top of scripture),
/// the reader options menu, and the reader's sheets. The mini player, Now Playing
/// and the one Repeat sheet are the app's, mounted at the root.
///
/// It observes neither the audio service nor `Chrome`: playback and "Hide
/// controls while reading" are drawn by leaf slots.
struct SurahPageView: View {
    let surahs: [Surah]
    let startIndex: Int
    var initialAyah: Int? = nil

    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @EnvironmentObject private var targetStore: MemorizationTargetStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var models = SurahModelStore()
    @StateObject private var menu = EditorialMenuPresenter()
    /// Held, not observed: only `ReaderSheetsHost` re-renders when it changes.
    @State private var router = ReaderSheetRouter()

    @State private var currentIndex: Int
    @State private var showReadingType = false
    @State private var showMushaf = false
    @State private var showMemorizeSheet = false
    @State private var reviewAfterEnroll = false
    @State private var reviewSession: ReviewSessionConfig?

    init(surahs: [Surah], startIndex: Int, initialAyah: Int? = nil) {
        self.surahs    = surahs
        self.startIndex = startIndex
        self.initialAyah = initialAyah
        _currentIndex = State(initialValue: max(0, min(startIndex, surahs.count - 1)))
    }

    private var surah: Surah { surahs[max(0, min(currentIndex, surahs.count - 1))] }
    private var model: SurahDetailViewModel { models.model(for: surah) }

    var body: some View {
        VStack(spacing: 0) {
            ReaderTopBarSlot(
                title: surah.englishName,
                onBack: { Haptics.tap(); dismiss() },
                onType: { Haptics.tap(); showReadingType = true },
                onOptions: { presentReaderMenu() }
            )

            TabView(selection: $currentIndex) {
                ForEach(surahs.indices, id: \.self) { idx in
                    // Only the page on screen and its neighbours are built; the
                    // rest stay blank until a swipe brings them next door, so
                    // opening the reader doesn't make a model and a page for all
                    // 114 surahs, and re-rendering the pager stays cheap.
                    Group {
                        if abs(idx - currentIndex) <= 1 {
                            SurahDetailView(
                                surah: surahs[idx],
                                viewModel: models.model(for: surahs[idx]),
                                initialAyah: idx == startIndex ? initialAyah : nil,
                                router: router
                            )
                        } else {
                            Palette.background
                        }
                    }
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Palette.background)
        // Ours replaces it: see `ReaderTopBar`.
        .toolbar(.hidden, for: .navigationBar)
        .editorialMenu(menu)
        .background(ReaderSheetsHost(router: router))
        // Reading gets the whole page — the tab bar comes back on the way out,
        // and so does anything "Hide controls while reading" put away.
        .onAppear { Chrome.shared.tabBarHidden = true }
        .onDisappear {
            Chrome.shared.tabBarHidden = false
            Chrome.shared.leaveReader()
        }
        .onChange(of: currentIndex) { _, _ in
            menu.dismiss()
        }
        .sheet(isPresented: $showReadingType) {
            ReadingTypeSheet()
        }
        .sheet(isPresented: $showMushaf) {
            MushafView(surah: surah, ayahs: model.ayahs)
        }
        .sheet(isPresented: $showMemorizeSheet, onDismiss: { reviewAfterEnroll = false }) {
            MemorizeSurahSheet(surah: surah, ayahs: model.ayahs) {
                // First-time flow: once enrolled, start a focused review. The delay
                // lets the sheet finish dismissing before the cover presents.
                guard reviewAfterEnroll else { return }
                reviewAfterEnroll = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { startSurahReview() }
            }
        }
        .fullScreenCover(item: $reviewSession) { cfg in
            ReviewSessionView(store: srStore, initialCards: cfg.cards, title: cfg.title)
        }
    }

    // MARK: Reader options

    /// The reader's `…`: Mushaf view, Download, Hide controls while reading, then
    /// the surah's flashcard actions. The app's own panel, not a UIKit menu.
    private func presentReaderMenu() {
        let dm = DownloadManager.shared
        let prog = dm.progress[surah.number]
        let isDownloaded = prog == 1.0
        let isDownloading = prog != nil && prog! < 1.0
        let hidesControls = UserDefaults.standard.bool(forKey: "immersiveReading")

        let reading: [EditorialAction] = [
            EditorialAction("Mushaf view", icon: "book.pages.fill") { showMushaf = true },
            EditorialAction(
                isDownloaded ? "Remove download" : (isDownloading ? "Downloading" : "Download"),
                icon: isDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle",
                kind: isDownloaded ? .accent : .normal,
                detail: isDownloading ? "\(Int((prog ?? 0) * 100))%" : nil,
                isEnabled: !isDownloading
            ) {
                let subfolder = Reciter.selected.subfolder
                if isDownloaded {
                    dm.deleteSurah(surah.number, reciterSubfolder: subfolder)
                } else {
                    dm.downloadSurah(surah.number, ayahCount: surah.numberOfAyahs,
                                     reciterSubfolder: subfolder)
                }
            },
            EditorialAction("Hide controls while reading",
                            icon: hidesControls ? "eye.slash.fill" : "eye.slash",
                            kind: hidesControls ? .accent : .normal,
                            detail: hidesControls ? "On" : nil) {
                UserDefaults.standard.set(!hidesControls, forKey: "immersiveReading")
            },
        ]

        let due = srStore.dueItems(inSurah: surah.number).count
        let enrolled = srStore.goal(forSurah: surah.number) != nil
        let memorize: [EditorialAction] = [
            EditorialAction(
                enrolled ? "Review this surah" : "Set up flashcards",
                icon: "graduationcap",
                detail: due > 0 ? "\(due) due" : nil,
                isEnabled: !model.ayahs.isEmpty
            ) { reviewOrEnroll() },
            EditorialAction("Flashcard goal", icon: "slider.horizontal.3",
                            isEnabled: !model.ayahs.isEmpty) {
                showMemorizeSheet = true
            },
        ]

        menu.present(EditorialMenuRequest(
            eyebrow: "\(surah.englishName) · \(surah.numberOfAyahs) ayahs",
            groups: [reading, memorize]
        ))
    }

    /// The first time (no goal set yet) this opens the goal sheet to enroll, then
    /// drops into review; once a goal exists it goes straight to review.
    private func reviewOrEnroll() {
        if srStore.goal(forSurah: surah.number) != nil {
            startSurahReview()
        } else {
            reviewAfterEnroll = true
            showMemorizeSheet = true
        }
    }

    /// Opens a review scoped to this surah — due cards first, falling back to all
    /// of them so it can be drilled even when nothing is due.
    private func startSurahReview() {
        let due = srStore.dueItems(inSurah: surah.number)
        let all = srStore.cards(inSurah: surah.number)
        let cards = due.isEmpty ? all : due
        guard !cards.isEmpty else { return }
        reviewSession = ReviewSessionConfig(cards: cards, title: surah.englishName)
    }
}

// MARK: - Reader top bar

/// The top bar, or nothing while "Hide controls while reading" has put it away.
/// Observes `Chrome` and the setting itself, so the pager doesn't.
private struct ReaderTopBarSlot: View {
    let title: String
    let onBack: () -> Void
    let onType: () -> Void
    let onOptions: () -> Void

    @ObservedObject private var chrome = Chrome.shared
    @AppStorage("immersiveReading") private var hidesControls = false

    var body: some View {
        VStack(spacing: 0) {
            if !chrome.readerControlsHidden {
                ReaderTopBar(title: title, onBack: onBack, onType: onType, onOptions: onOptions)
                    .transition(Motion.move(.move(edge: .top).combined(with: .opacity)))
            }
        }
        .onAppear { chrome.setReaderHidesControls(hidesControls) }
        .onChange(of: hidesControls) { _, on in chrome.setReaderHidesControls(on) }
    }
}

/// Back · the surah name (always) · Reading type · Reader options. Opaque, and in
/// the layout above the pages, so nothing it draws can land on scripture.
private struct ReaderTopBar: View {
    let title: String
    let onBack: () -> Void
    let onType: () -> Void
    let onOptions: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(TypeScale.rowTitleCompact)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, BarButton.side * 2 + Spacing.xs)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                BarButton(icon: "chevron.left", label: "Back", action: onBack)
                Spacer(minLength: 0)
                BarButton(icon: "textformat.size", label: "Reading type", action: onType)
                BarButton(icon: "ellipsis", label: "Reader options", action: onOptions)
            }
        }
        .padding(.horizontal, Spacing.xxs)
        .frame(minHeight: MinSize.hitTarget + Spacing.xxs)
        // Bar chrome stops growing at the largest non-accessibility size, as system bars do.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .opaqueBar()
    }
}
