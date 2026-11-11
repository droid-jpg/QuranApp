import SwiftUI
import WidgetKit
import Combine

/// Drives the "also enroll the ayahs before this one?" prompt after a single-ayah
/// enrollment that leaves an un-enrolled run before it.
private struct PrecedingEnrollPrompt: Identifiable {
    let id = UUID()
    let ayah: Int       // the ayah just enrolled
    let count: Int      // how many earlier ayahs are not yet enrolled
}

// MARK: - Page models

/// One `SurahDetailViewModel` per surah, owned by the pager rather than by the
/// page. The reader's chrome — top bar, player, sheets — is drawn once, outside
/// the pages, and needs the *active* page's model to do it; a `@StateObject`
/// inside each page would be out of reach. Swiping back to a surah also finds its
/// ayahs still loaded.
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
/// the action menu, and the reader's sheets. The mini player and Now Playing are
/// the app's, mounted at the root (`BottomChrome`, `NowPlayingSlot`); the root's
/// bottom inset reaches the pages, so no ayah ends up under the mini player.
struct SurahPageView: View {
    let surahs: [Surah]
    let startIndex: Int
    var initialAyah: Int? = nil

    @Environment(\.audioServiceRef) private var audioService
    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @EnvironmentObject private var targetStore: MemorizationTargetStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var models = SurahModelStore()
    @StateObject private var menu = EditorialMenuPresenter()

    @State private var currentIndex: Int
    /// True once the active page's chapter title has scrolled up behind the bar —
    /// the bar then shows the surah name in its place.
    @State private var headerPassed = false
    @State private var showReadingType = false
    @State private var showMushaf = false
    /// The surah the Repeat sheet is open for, or nil.
    @State private var repeatSheetSurah: Surah?
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
            ReaderTopBar(
                surah: surah,
                model: model,
                showsTitle: headerPassed,
                onBack: { Haptics.tap(); dismiss() },
                onLoop: { Haptics.tap(); repeatSheetSurah = surah },
                onType: { Haptics.tap(); showReadingType = true },
                onMore: { presentReaderMenu() }
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
                                isActivePage: idx == currentIndex,
                                headerPassed: $headerPassed,
                                menu: menu
                            )
                        } else {
                            Color(.systemBackground)
                        }
                    }
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        // Ours replaces it: see `ReaderTopBar`.
        .toolbar(.hidden, for: .navigationBar)
        .editorialMenu(menu)
        // Reading gets the whole page — the tab bar comes back on the way out.
        .onAppear { Chrome.shared.tabBarHidden = true }
        .onDisappear { Chrome.shared.tabBarHidden = false }
        .onChange(of: currentIndex) { _, _ in
            headerPassed = false
            menu.dismiss()
        }
        .sheet(isPresented: $showReadingType) {
            ReadingTypeSheet()
        }
        .sheet(isPresented: $showMushaf) {
            MushafView(surah: surah, ayahs: model.ayahs)
        }
        .sheet(item: $repeatSheetSurah) { target in
            RepeatSheet(surah: target, ayahs: models.model(for: target).ayahs,
                        focusAyah: repeatFocusAyah(in: target))
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

    // MARK: Bar actions

    /// Where a fresh repeat starts: the ayah playing in that surah, else the
    /// memorization working ayah when it is the target surah, else ayah 1.
    private func repeatFocusAyah(in target: Surah) -> Int {
        if let audioService, audioService.currentSurah == target.number,
           let a = audioService.currentAyah { return a }
        if let t = targetStore.target, t.surah == target.number { return t.workingAyah }
        return 1
    }

    /// The reader's overflow, as the app's own panel rather than a UIKit menu.
    private func presentReaderMenu() {
        let dm = DownloadManager.shared
        let prog = dm.progress[surah.number]
        let isDownloaded = prog == 1.0
        let isDownloading = prog != nil && prog! < 1.0

        let library: [EditorialAction] = [
            EditorialAction(
                isDownloaded ? "Remove download" : (isDownloading ? "Downloading" : "Download for offline"),
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
            EditorialAction("Mushaf view", icon: "book.pages.fill") { showMushaf = true },
        ]

        let due = srStore.dueItems(inSurah: surah.number).count
        let enrolled = srStore.goal(forSurah: surah.number) != nil
        let memorize: [EditorialAction] = [
            EditorialAction("Memorize this surah", icon: "target", kind: .accent) {
                startMemorizingSurah()
            },
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
            groups: [library, memorize]
        ))
    }

    /// Begin (or resume) memorizing this whole surah — sets it as the active target,
    /// resuming at the first un-learned ayah.
    private func startMemorizingSurah() {
        targetStore.start(surah: surah.number, surahName: surah.englishName,
                          totalAyahs: surah.numberOfAyahs)
        if memorizationStore.manualStatus(for: surah.number) == .notStarted {
            memorizationStore.set(.inProgress, for: surah.number)
        }
        StreakService.shared.recordRead()
        Haptics.success()
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

/// The reader's own bar: back, the chapter it's on, and the three controls that
/// belong to reading. It sits *in the layout*, above the pages, so nothing it
/// draws can ever land on scripture — which is what the system bar was doing.
private struct ReaderTopBar: View {
    let surah: Surah
    @ObservedObject var model: SurahDetailViewModel
    @EnvironmentObject private var audioService: AudioService
    let showsTitle: Bool
    let onBack: () -> Void
    let onLoop: () -> Void
    let onType: () -> Void
    let onMore: () -> Void

    private var type = ReadingType()

    init(surah: Surah, model: SurahDetailViewModel, showsTitle: Bool,
         onBack: @escaping () -> Void, onLoop: @escaping () -> Void,
         onType: @escaping () -> Void, onMore: @escaping () -> Void) {
        self.surah = surah
        _model = ObservedObject(wrappedValue: model)
        self.showsTitle = showsTitle
        self.onBack = onBack
        self.onLoop = onLoop
        self.onType = onType
        self.onMore = onMore
    }

    private var loopOn: Bool {
        audioService.repeatState.isOn && audioService.repeatState.surah == surah.number
    }

    var body: some View {
        HStack(spacing: 2) {
            BarButton(icon: "chevron.left", label: "Back", action: onBack)

            Spacer(minLength: 4)

            // The number is enough while the chapter title is still on screen;
            // once it scrolls away the bar takes over as the title.
            ZStack {
                Eyebrow("Surah \(surah.number)")
                    .opacity(showsTitle ? 0 : 1)
                Text(surah.englishName)
                    .font(type.serif(17, weight: .medium))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(showsTitle ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: showsTitle)

            Spacer(minLength: 4)

            BarButton(icon: "repeat", label: "Repeat", on: loopOn, action: onLoop)
            BarButton(icon: "textformat.size", label: "Reading type", action: onType)
            BarButton(icon: "ellipsis", label: "More", action: onMore)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 46)
        // Bar chrome stops growing at the largest non-accessibility size, as system bars do.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .opaqueBar()
    }
}

// `BarButton` — the glyph both this bar and the surah list's use — lives in
// DesignSystem.swift.

// MARK: - One surah

struct SurahDetailView: View {
    let surah: Surah
    @ObservedObject var viewModel: SurahDetailViewModel
    /// Whether this page is the one currently shown in the paged surah browser.
    /// Only the active page reports its scroll position up to the bar.
    let isActivePage: Bool
    @Binding var headerPassed: Bool
    /// The reader's menu, presented above the pager.
    let menu: EditorialMenuPresenter

    /// Commands only: playback state is drawn by the leaf views below
    /// (`AyahRowSlot`, `SurahHeaderSlot`, `PlaybackScrollFollower`), so an ayah
    /// advance or a play/pause doesn't re-render the page or every row.
    @Environment(\.audioServiceRef) private var audioService
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @EnvironmentObject private var targetStore: MemorizationTargetStore

    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId

    @State private var showSurahComplete = false
    @State private var precedingPrompt: PrecedingEnrollPrompt? = nil
    @State private var scrollTarget: Int? = nil
    @State private var showResumeBar = false
    @State private var resumeAyah = 0
    @State private var resumeProxy: ScrollViewProxy? = nil
    /// Sheets raised from an ayah — owned here rather than by the row, so the
    /// long-press menu and the tap-revealed strip open the same one.
    @State private var wordPickerAyah: Ayah? = nil
    @State private var tafsirAyah: Ayah? = nil

    private var type = ReadingType()

    init(surah: Surah, viewModel: SurahDetailViewModel, initialAyah: Int? = nil,
         isActivePage: Bool, headerPassed: Binding<Bool>, menu: EditorialMenuPresenter) {
        self.surah = surah
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.isActivePage = isActivePage
        _headerPassed = headerPassed
        self.menu = menu
        _scrollTarget = State(initialValue: initialAyah)
    }

    // MARK: - Memorization target (loop-based acquisition)

    /// Point the active memorization target at this surah/ayah (or start it here if
    /// a different surah was the target). Drives the Home card and the Siri intent.
    private func setWorkingAyah(_ ayah: Int) {
        if targetStore.target?.surah == surah.number {
            targetStore.setWorkingAyah(ayah)
        } else {
            targetStore.start(surah: surah.number, surahName: surah.englishName,
                              totalAyahs: surah.numberOfAyahs, at: ayah)
        }
        if memorizationStore.manualStatus(for: surah.number) == .notStarted {
            memorizationStore.set(.inProgress, for: surah.number)
        }
        StreakService.shared.recordRead()
        Haptics.success()
    }

    /// Mark the working ayah learned and advance. When the whole surah is done, the
    /// meaning-flashcard offer (stage 5 of the method) is surfaced.
    private func markWorkingLearned() {
        guard targetStore.target?.surah == surah.number else { return }
        targetStore.markWorkingAyahLearned()
        StreakService.shared.recordRead()
        Haptics.success()
        if targetStore.target?.isComplete == true {
            showSurahComplete = true
        }
    }

    /// Enroll every loaded ayah in meaning-only spaced repetition — the stage-5
    /// "go back and get the gist of each ayah" pass, run once the surah is memorized.
    private func enrollForMeaning() {
        let seeds = viewModel.ayahs.map {
            MemorizationSRStore.AyahSeed(
                ayah: $0.numberInSurah, arabic: $0.arabic,
                translation: $0.translation, transliteration: $0.transliteration
            )
        }
        srStore.enrollSurah(surah: surah.number, surahName: surah.englishName,
                            ayahs: seeds, goal: .meaning)
        memorizationStore.set(.memorized, for: surah.number)
        Haptics.success()
    }

    /// Enroll/unenroll a single ayah in spaced-repetition review. A new ayah
    /// inherits the surah's existing goal (or "Both" by default) and nudges the
    /// surah's heatmap status to "in progress".
    private func toggleMemorize(_ ayah: Ayah) {
        let wasScheduled = srStore.isScheduled(surah: surah.number, ayah: ayah.numberInSurah)
        let goal = srStore.goal(forSurah: surah.number) ?? .both
        srStore.toggle(
            surah: surah.number, ayah: ayah.numberInSurah,
            surahName: surah.englishName,
            arabic: ayah.arabic, translation: ayah.translation,
            transliteration: ayah.transliteration,
            goal: goal
        )
        if !wasScheduled, memorizationStore.status(for: surah.number) == .notStarted {
            memorizationStore.set(.inProgress, for: surah.number)
        }
        Haptics.tap()
        // Just enrolled an ayah that has earlier, un-enrolled ayahs? Offer to add
        // the run before it too, so the surah can be memorized in order.
        if !wasScheduled {
            let preceding = precedingUnenrolled(before: ayah.numberInSurah)
            if !preceding.isEmpty {
                precedingPrompt = PrecedingEnrollPrompt(ayah: ayah.numberInSurah, count: preceding.count)
            }
        }
    }

    /// Loaded ayahs of this surah that come before `ayahNumber` and aren't yet
    /// enrolled in review.
    private func precedingUnenrolled(before ayahNumber: Int) -> [Ayah] {
        guard ayahNumber > 1 else { return [] }
        return viewModel.ayahs.filter {
            $0.numberInSurah < ayahNumber
                && !srStore.isScheduled(surah: surah.number, ayah: $0.numberInSurah)
        }
    }

    /// Enrolls every loaded ayah from 1 through `ayahNumber` at the surah's goal.
    /// Already-enrolled ayahs keep their schedule (only their goal is aligned).
    private func enrollPreceding(through ayahNumber: Int) {
        let goal = srStore.goal(forSurah: surah.number) ?? .both
        let seeds = viewModel.ayahs
            .filter { $0.numberInSurah <= ayahNumber }
            .map {
                MemorizationSRStore.AyahSeed(
                    ayah: $0.numberInSurah, arabic: $0.arabic,
                    translation: $0.translation, transliteration: $0.transliteration
                )
            }
        srStore.enrollSurah(surah: surah.number, surahName: surah.englishName,
                            ayahs: seeds, goal: goal)
        Haptics.success()
    }

    // MARK: - Playback

    /// Loop the given ayah on its own — the reader's "Repeat this ayah".
    private func repeatAyah(_ ayah: Int) {
        Haptics.tap()
        audioService?.startRepeat(.repeatThisAyah(surah: surah.number, ayah: ayah),
                                 totalAyahs: surah.numberOfAyahs, surahName: surah.englishName)
    }

    private func playFrom(_ ayah: Int) {
        // Don't resume the main player here: `playAyah` decides what plays next,
        // and a resume followed by its toggle would pause the ayah just asked for.
        guard let audioService else { return }
        audioService.stopWordLoop(resume: false)
        viewModel.playAyah(ayah, audioService: audioService)
    }

    private func toggleBookmark(_ ayah: Ayah) {
        bookmarkStore.toggle(
            surahNumber: surah.number,
            surahName: surah.englishName,
            surahArabicName: surah.name,
            ayahNumber: ayah.numberInSurah,
            arabic: ayah.arabic,
            translation: ayah.translation
        )
    }

    private func openWordByWord(_ ayah: Ayah) {
        Task { await viewModel.loadWordTimingsIfNeeded() }
        wordPickerAyah = ayah
    }

    // MARK: - Ayah menu
    //
    // Everything an ayah can do, raised as the app's own panel. It's built here
    // (rather than in the row) so it can be drawn above the pager and the player,
    // and so the actions read against the reader's stores.

    private func presentAyahMenu(_ ayah: Ayah) {
        let n = ayah.numberInSurah
        let isMemorizing = srStore.isScheduled(surah: surah.number, ayah: n)
        let isBookmarked = bookmarkStore.isBookmarked(surah: surah.number, ayah: n)
        let isWorking = targetStore.target?.surah == surah.number
            && targetStore.target?.workingAyah == n

        var playback: [EditorialAction] = [
            EditorialAction("Play from here", icon: "play.fill", kind: .accent) { playFrom(n) },
            EditorialAction("Repeat this ayah", icon: "repeat") { repeatAyah(n) },
            EditorialAction("Word by word", icon: "text.word.spacing") { openWordByWord(ayah) },
        ]
        if viewModel.tafsirByAyah[n] != nil {
            playback.append(EditorialAction("Tafsir", icon: "text.book.closed") { tafsirAyah = ayah })
        }

        var memorize: [EditorialAction] = []
        if isWorking {
            memorize.append(EditorialAction("Mark learned → next ayah",
                                            icon: "checkmark.circle", kind: .accent) {
                markWorkingLearned()
            })
        } else {
            memorize.append(EditorialAction("Memorize from here", icon: "target") {
                setWorkingAyah(n)
            })
        }
        memorize.append(EditorialAction(
            isMemorizing ? "Remove from review" : "Add to review",
            icon: isMemorizing ? "graduationcap.fill" : "graduationcap"
        ) { toggleMemorize(ayah) })
        memorize.append(EditorialAction(
            isBookmarked ? "Remove bookmark" : "Bookmark",
            icon: isBookmarked ? "bookmark.slash" : "bookmark"
        ) { toggleBookmark(ayah) })

        let share: [EditorialAction] = [
            EditorialAction(share: "Share ayah", icon: "square.and.arrow.up",
                            text: ayahShareText(ayah, surahName: surah.englishName)),
            EditorialAction(share: "Share with translation", icon: "doc.text",
                            text: ayahShareTextWithTranslation(ayah, surahName: surah.englishName)),
        ]

        menu.present(EditorialMenuRequest(
            eyebrow: "\(surah.englishName) · Ayah \(n)",
            arabic: ayah.arabic,
            translation: ayah.translation,
            groups: [playback, memorize, share]
        ))
    }

    // MARK: - Rows

    /// Broken out of `body`: inline, the row's twenty arguments took the type
    /// checker past its budget. Everything but playback is filled in here; the
    /// slot adds the playback flags, so only it watches the audio service.
    private func row(for ayah: Ayah) -> some View {
        let n = ayah.numberInSurah
        let target = targetStore.target

        return AyahRowSlot(row: AyahRowView(
            ayah: ayah,
            surahNumber: surah.number,
            isPlaying: false,
            isWordLooping: false,
            isLoadingTimings: viewModel.isLoadingWordTimings,
            wordDetails: viewModel.wordDetailsByAyah[n],
            isBookmarked: bookmarkStore.isBookmarked(surah: surah.number, ayah: n),
            isMemorizing: srStore.isScheduled(surah: surah.number, ayah: n),
            isWorkingAyah: target?.surah == surah.number && target?.workingAyah == n,
            hasTafsir: viewModel.tafsirByAyah[n] != nil,
            onAction: { handle($0, for: ayah) }
        ))
    }

    private func handle(_ action: AyahRowAction, for ayah: Ayah) {
        switch action {
        case .bookmark:       toggleBookmark(ayah)
        case .toggleMemorize: toggleMemorize(ayah)
        case .play:           playFrom(ayah.numberInSurah)
        case .repeatAyah:     repeatAyah(ayah.numberInSurah)
        case .wordByWord:     openWordByWord(ayah)
        case .tafsir:         tafsirAyah = ayah
        case .longPress:      presentAyahMenu(ayah)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Resume bar sits in the layout flow — cannot be covered by the bar.
            if showResumeBar {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark.fill")
                        .font(.label(11))
                        .foregroundStyle(.brand)
                    Text("Continue from ayah \(resumeAyah)")
                        .font(type.serif(15))
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            resumeProxy?.scrollTo(resumeAyah, anchor: .top)
                        }
                        withAnimation { showResumeBar = false }
                    } label: {
                        Text("RESUME")
                            .font(.label(10, weight: .semibold))
                            .kerning(1.2)
                            .foregroundStyle(.brand)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .overlay(Rectangle().strokeBorder(Color.brand.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation { showResumeBar = false } } label: {
                        Image(systemName: "xmark")
                            .font(.label(12, weight: .bold))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .opaqueBar()
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Non-lazy so its scroll tracker keeps reporting even
                        // after it scrolls off, keeping the inline title stable.
                        SurahHeaderSlot(surah: surah, onPlayFromStart: { playFrom(1) })

                        LazyVStack(spacing: 0) {
                            if viewModel.isLoading && viewModel.ayahs.isEmpty {
                                ProgressView("Loading ayahs…")
                                    .frame(maxWidth: .infinity, minHeight: 200)
                            } else if let err = viewModel.error, viewModel.ayahs.isEmpty {
                                ErrorView(message: err) { Task { await viewModel.loadAyahs() } }
                            } else {
                                ForEach(viewModel.ayahs) { ayah in
                                    row(for: ayah)
                                        .id(ayah.numberInSurah)
                                    Hairline().padding(.horizontal, 28)
                                }
                            }
                        }
                    }
                    // Breathing room only: the player and the bar reserve their
                    // own space as insets now.
                    .padding(.bottom, 28)
                }
                .coordinateSpace(.named("surahScroll"))
                .onPreferenceChange(HeaderVisibilityKey.self) { maxY in
                    // maxY is the chapter title's bottom edge relative to the
                    // scroll viewport's top. Once it slips away, the reader bar
                    // takes over as the title.
                    guard isActivePage else { return }
                    let passed = maxY < 8
                    if passed != headerPassed { headerPassed = passed }
                }
                .background(PlaybackScrollFollower(surahNumber: surah.number, proxy: proxy))
                .onChange(of: viewModel.ayahs.isEmpty) { _, isEmpty in
                    guard !isEmpty else { return }
                    if let target = scrollTarget {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                proxy.scrollTo(target, anchor: .top)
                            }
                            scrollTarget = nil
                        }
                    }
                }
                .onAppear { resumeProxy = proxy }
            }
        }
        .animation(.spring(duration: 0.35), value: showResumeBar)
        .sheet(item: $wordPickerAyah) { ayah in
            WordLoopPickerView(
                ayah: ayah,
                timings: viewModel.wordTimingsByAyah[ayah.numberInSurah] ?? [],
                isLoading: viewModel.isLoadingWordTimings,
                errorMessage: viewModel.wordTimingsError
            ) { start, end in
                guard let chapterUrl = viewModel.chapterAudioUrl() else { return }
                audioService?.startWordLoop(
                    surah: surah.number,
                    ayah: ayah.numberInSurah,
                    chapterUrl: chapterUrl,
                    wordStartMs: start.startMs,
                    wordEndMs: end.endMs,
                    fromWord: start.id,
                    toWord: end.id
                )
            }
        }
        .sheet(item: $tafsirAyah) { ayah in
            if let text = viewModel.tafsirByAyah[ayah.numberInSurah] {
                TafsirSheet(ayah: ayah, surahName: surah.englishName, text: text)
            }
        }
        .confirmationDialog(
            "Add earlier ayahs?",
            isPresented: Binding(
                get: { precedingPrompt != nil },
                set: { if !$0 { precedingPrompt = nil } }
            ),
            titleVisibility: .visible,
            presenting: precedingPrompt
        ) { prompt in
            Button("Add ayahs 1–\(prompt.ayah)") { enrollPreceding(through: prompt.ayah) }
            Button("Just this ayah", role: .cancel) {}
        } message: { prompt in
            Text("Add the \(prompt.count) earlier ayah\(prompt.count == 1 ? "" : "s") in \(surah.englishName) too, so you memorize in order?")
        }
        .confirmationDialog(
            "\(surah.englishName) memorized 🎉",
            isPresented: $showSurahComplete,
            titleVisibility: .visible
        ) {
            Button("Start meaning review") { enrollForMeaning() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("You've memorized the whole surah. Go back through it with meaning flashcards to lock in the gist of each ayah?")
        }
        .onChange(of: translationId) {
            Task { await viewModel.loadAyahs() }
        }
        .task {
            StreakService.shared.recordRead()
            // The model outlives the page now, so a surah swiped back to is
            // already loaded and doesn't re-fetch.
            if viewModel.ayahs.isEmpty {
                await viewModel.loadAyahs()
            }
            await viewModel.loadWordTimingsIfNeeded()
            await viewModel.loadWordDetails()
            await viewModel.loadTafsir()
            // Resume tracking (Feature 6)
            if let last = viewModel.lastPlayedAyah(), scrollTarget == nil, !showResumeBar {
                resumeAyah = last
                showResumeBar = true
            }
            // Track last-opened surah for widget
            let ud = UserDefaults(suiteName: "group.com.saminukta.Quran-App")
            ud?.set(surah.englishName, forKey: "lastSurahName")
            ud?.set(surah.number, forKey: "lastSurahNumber")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

// MARK: - Playback leaves
//
// The only parts of a page that observe the audio service. Each is small, so an
// ayah advance or a play/pause re-runs these and the one or two rows whose
// playback flags actually changed, not the page and not every row.

/// Adds the playback flags to a row built by the page, then lets SwiftUI skip
/// the row unless something it draws changed (`AyahRowView` is `Equatable`).
private struct AyahRowSlot: View {
    let row: AyahRowView
    @EnvironmentObject private var audioService: AudioService

    var body: some View {
        let isCurrent = audioService.currentSurah == row.surahNumber
            && audioService.currentAyah == row.ayah.numberInSurah
        var row = row
        row.isPlaying = isCurrent && audioService.isPlaying
        row.isWordLooping = isCurrent && audioService.isWordLooping
        return row.equatable()
    }
}

/// The title page, with its play button tied to the player.
private struct SurahHeaderSlot: View {
    let surah: Surah
    let onPlayFromStart: () -> Void
    @EnvironmentObject private var audioService: AudioService

    var body: some View {
        let active = audioService.currentSurah == surah.number
        SurahHeaderView(
            surah: surah,
            isPlaying: active && audioService.isPlaying,
            onPlay: { [audioService, surah] in
                if audioService.currentSurah == surah.number {
                    audioService.togglePlayPause()
                } else {
                    onPlayFromStart()
                }
            }
        )
        .equatable()
    }
}

/// Keeps the ayah being recited in view as playback advances.
private struct PlaybackScrollFollower: View {
    let surahNumber: Int
    let proxy: ScrollViewProxy
    @EnvironmentObject private var audioService: AudioService

    var body: some View {
        Color.clear
            .onChange(of: audioService.currentAyah) { _, newAyah in
                guard let ayah = newAyah, audioService.currentSurah == surahNumber else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(ayah, anchor: .top)
                }
            }
    }
}

// MARK: - Scroll tracking

/// Reports the surah header's bottom edge (in scroll-viewport space) so the
/// reader bar can take over as the title once the chapter title scrolls away.
private struct HeaderVisibilityKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

// MARK: - Surah header

/// The title page of a surah: number, name, meaning, provenance, an ornamental
/// rule, then the Basmala. Centred and unfilled — the reader opens on something
/// that looks like the top of a chapter rather than the top of a screen.
struct SurahHeaderView: View, Equatable {
    let surah: Surah
    var isPlaying: Bool = false
    var onPlay: () -> Void = {}
    @State private var appeared = false
    /// Read during body, so a change of face or script repaints the title page.
    private var type = ReadingType()

    init(surah: Surah, isPlaying: Bool = false, onPlay: @escaping () -> Void = {}) {
        self.surah = surah
        self.isPlaying = isPlaying
        self.onPlay = onPlay
    }

    /// What the title page draws. `onPlay` is left out: it only ever sends the
    /// same command, and comparing it would keep the page from being skipped.
    nonisolated static func == (lhs: SurahHeaderView, rhs: SurahHeaderView) -> Bool {
        lhs.surah.number == rhs.surah.number && lhs.isPlaying == rhs.isPlaying
    }

    var body: some View {
        VStack(spacing: 0) {
            Eyebrow("Surah \(surah.number)")
                .opacity(appeared ? 1 : 0)

            // Primary: transliteration
            Text(surah.englishName)
                .font(type.serif(34, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .scaleEffect(appeared ? 1.0 : 0.94)
                .opacity(appeared ? 1 : 0)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: HeaderVisibilityKey.self,
                            value: geo.frame(in: .named("surahScroll")).maxY
                        )
                    }
                )

            // Secondary: what the name means
            Text(surah.englishNameTranslation)
                .font(type.serif(16, italic: true))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)

            Eyebrow("\(surah.revelationType) · \(surah.numberOfAyahs) ayahs")
                .padding(.top, 12)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

            DiamondRule()
                .padding(.vertical, 22)
                .opacity(appeared ? 1 : 0)

            if surah.number != 1 && surah.number != 9 {
                Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
                    .font(type.arabic(22))
                    .lineSpacing(10)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
                    .foregroundStyle(Color.secondary)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
            }

            // Play the whole surah from ayah 1 (toggles when already playing it)
            Button(action: onPlay) {
                PlayCircle(playing: isPlaying, size: 48)
            }
            .buttonStyle(CardButtonStyle(scale: 0.9))
            .padding(.top, 22)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.85)
            .accessibilityLabel(isPlaying ? "Pause surah" : "Play surah")
        }
        .padding(.horizontal, 28)
        // The reader's bar is in the layout now, not floating over the page, so
        // the chapter title needs an opening margin rather than a clearance.
        .padding(.top, 26)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !appeared else { return }
            withAnimation(AppAnim.spring.delay(0.05)) { appeared = true }
        }
    }
}

// MARK: - Memorize whole surah (goal chooser)

/// Enroll an entire surah in spaced repetition with a chosen memorization goal.
/// Existing cards keep their schedule; only their goal is updated.
private struct MemorizeSurahSheet: View {
    let surah: Surah
    let ayahs: [Ayah]
    /// Called after the user enrolls/updates the surah, before the sheet dismisses.
    var onEnrolled: () -> Void = {}

    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @Environment(\.dismiss) private var dismiss

    @State private var goal: MemorizationGoal = .both

    private var enrolledCount: Int { srStore.scheduledAyahs(inSurah: surah.number).count }
    private var allEnrolled: Bool { !ayahs.isEmpty && enrolledCount >= ayahs.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Text(surah.englishName)
                            .font(.appSerif(24, weight: .medium))
                        Text("\(ayahs.count) ayahs"
                             + (enrolledCount > 0 ? " · \(enrolledCount) already in review" : ""))
                            .font(.appSerif(14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    Text("Adds every ayah to spaced-repetition review, so a few resurface for you to recall each day until the whole surah sticks.")
                        .font(.appSerif(13, italic: true))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("What are you memorizing for?")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(MemorizationGoal.allCases) { g in
                            GoalOptionRow(goal: g, selected: g == goal) {
                                Haptics.selection()
                                withAnimation(.easeOut(duration: 0.15)) { goal = g }
                            }
                        }
                    }

                    Button {
                        let seeds = ayahs.map {
                            MemorizationSRStore.AyahSeed(
                                ayah: $0.numberInSurah, arabic: $0.arabic,
                                translation: $0.translation, transliteration: $0.transliteration
                            )
                        }
                        srStore.enrollSurah(surah: surah.number, surahName: surah.englishName,
                                            ayahs: seeds, goal: goal)
                        if memorizationStore.manualStatus(for: surah.number) == .notStarted {
                            memorizationStore.set(.inProgress, for: surah.number)
                        }
                        Haptics.success()
                        onEnrolled()
                        dismiss()
                    } label: {
                        Text(allEnrolled ? "Update goal for all ayahs" : "Memorize all \(ayahs.count) ayahs")
                            .font(.headline)
                            .foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.brand)
                            .clipShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(ayahs.isEmpty)

                    if enrolledCount > 0 {
                        Button(role: .destructive) {
                            Haptics.warning()
                            srStore.removeSurah(surah.number)
                            dismiss()
                        } label: {
                            Text("Remove surah from memorization")
                                .font(.appSerif(15))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Memorize Surah")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { goal = srStore.goal(forSurah: surah.number) ?? .both }
    }
}

private struct GoalOptionRow: View {
    let goal: MemorizationGoal
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: goal.icon)
                    .font(.label(16))
                    .foregroundStyle(selected ? Color.brand : Color.secondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.appSerif(17))
                        .foregroundStyle(.primary)
                    Text(goal.caption)
                        .font(.appSerif(13, italic: true))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark")
                        .font(.label(12, weight: .bold))
                        .foregroundStyle(.brand)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .overlay(
                Rectangle()
                    .strokeBorder(selected ? Color.brand : Color(.label).opacity(0.18),
                                  lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
