import SwiftUI
import WidgetKit

/// Drives the "also enroll the ayahs before this one?" prompt after a single-ayah
/// enrollment that leaves an un-enrolled run before it.
private struct PrecedingEnrollPrompt: Identifiable {
    let id = UUID()
    let ayah: Int       // the ayah just enrolled
    let count: Int      // how many earlier ayahs are not yet enrolled
}

struct SurahDetailView: View {
    let surah: Surah
    /// Whether this page is the one currently shown in the paged surah browser.
    /// Only the active page contributes toolbar items + nav title, so swiping
    /// between surahs doesn't produce duplicate bar buttons.
    let isActivePage: Bool
    @StateObject private var viewModel: SurahDetailViewModel
    @EnvironmentObject private var audioService: AudioService
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @EnvironmentObject private var targetStore: MemorizationTargetStore
    @ObservedObject private var downloadManager = DownloadManager.shared

    @AppStorage("showTranslation")      private var showTranslation     = true
    @AppStorage("showTransliteration")  private var showTransliteration = true
    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId

    @State private var showMushaf = false
    @State private var showSurahComplete = false
    @State private var showMemorizeSheet = false
    @State private var reviewSession: ReviewSessionConfig?
    /// Set when the memorize sheet is opened from the banner's first-time flow, so
    /// a focused review starts as soon as the user finishes enrolling.
    @State private var reviewAfterEnroll = false
    @State private var precedingPrompt: PrecedingEnrollPrompt? = nil
    @State private var scrollTarget: Int? = nil
    @State private var showResumeBar = false
    @State private var resumeAyah = 0
    @State private var resumeProxy: ScrollViewProxy? = nil
    /// True once the header has scrolled up under the nav bar — drives the
    /// transliteration title appearing inline.
    @State private var headerPassed = false

    init(surah: Surah, initialAyah: Int? = nil, isActivePage: Bool = true) {
        self.surah = surah
        self.isActivePage = isActivePage
        _viewModel = StateObject(wrappedValue: SurahDetailViewModel(surah: surah))
        _scrollTarget = State(initialValue: initialAyah)
    }

    private var isThisSurahActive: Bool {
        audioService.currentSurah == surah.number
    }

    /// The ayah the Repeat sheet centers its presets on: the ayah currently playing
    /// in this surah, else the memorization working ayah when this is the target
    /// surah, else the first ayah.
    private var loopFocusAyah: Int {
        if isThisSurahActive, let a = audioService.currentAyah { return a }
        if let t = targetStore.target, t.surah == surah.number { return t.workingAyah }
        return 1
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

    // MARK: - Memorize banner

    /// A standing entry into this surah's spaced-repetition review. The first time
    /// (no goal set yet) it opens the goal sheet to enroll, then drops into review;
    /// once a goal exists it goes straight to review. The goal stays editable from
    /// the ⋯ menu's "Memorize Surah…".
    @ViewBuilder
    private var memorizeBanner: some View {
        let enrolled = srStore.goal(forSurah: surah.number) != nil
        let due = srStore.dueItems(inSurah: surah.number).count
        Button {
            Haptics.tap()
            if enrolled {
                startSurahReview()
            } else {
                reviewAfterEnroll = true
                showMemorizeSheet = true
            }
        } label: {
            if enrolled && due > 0 {
                bannerContent(title: "Review this surah",
                              subtitle: "\(due) ayah\(due == 1 ? "" : "s") due now",
                              filled: true)
            } else if enrolled {
                bannerContent(title: "Review this surah",
                              subtitle: "Drill its ayahs anytime",
                              filled: false)
            } else {
                bannerContent(title: "Memorize this surah",
                              subtitle: "Spaced-repetition review, tailored to your goal",
                              filled: false)
            }
        }
        .buttonStyle(.plain)
    }

    private func bannerContent(title: String, subtitle: String, filled: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption2).opacity(0.9)
            }
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 20))
        }
        .foregroundStyle(filled ? Color.white : Color.brand)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(filled ? Color.brand : Color.brand.opacity(0.12))
        )
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

    var body: some View {
        VStack(spacing: 0) {
            // Resume bar sits in the layout flow — cannot be covered by the nav bar.
            if showResumeBar {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark.fill").foregroundStyle(.brand)
                    Text("Continue from Ayah \(resumeAyah)")
                        .font(.subheadline.bold())
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            resumeProxy?.scrollTo(resumeAyah, anchor: .top)
                        }
                        withAnimation { showResumeBar = false }
                    } label: {
                        Text("Resume")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.brand).clipShape(Capsule())
                    }
                    Button { withAnimation { showResumeBar = false } } label: {
                        Image(systemName: "xmark").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Non-lazy so its scroll tracker keeps reporting even
                            // after it scrolls off, keeping the inline title stable.
                            SurahHeaderView(
                                surah: surah,
                                isPlaying: isThisSurahActive && audioService.isPlaying,
                                onPlay: {
                                    if isThisSurahActive {
                                        audioService.togglePlayPause()
                                    } else {
                                        audioService.stopWordLoop()
                                        viewModel.playAyah(1, audioService: audioService)
                                    }
                                }
                            )

                            if !viewModel.ayahs.isEmpty {
                                memorizeBanner
                                    .padding(.horizontal, 16)
                                    .padding(.top, 14)
                                    .padding(.bottom, 4)
                            }

                            LazyVStack(spacing: 0) {
                            if viewModel.isLoading {
                                ProgressView("Loading ayahs…")
                                    .frame(maxWidth: .infinity, minHeight: 200)
                            } else if let err = viewModel.error {
                                ErrorView(message: err) { Task { await viewModel.loadAyahs() } }
                            } else {
                                ForEach(viewModel.ayahs) { ayah in
                                    AyahRowView(
                                        ayah: ayah,
                                        surahName: surah.englishName,
                                        surahNumber: surah.number,
                                        isPlaying: audioService.isPlaying
                                            && isThisSurahActive
                                            && audioService.currentAyah == ayah.numberInSurah,
                                        isWordLooping: audioService.isWordLooping
                                            && isThisSurahActive
                                            && audioService.currentAyah == ayah.numberInSurah,
                                        wordTimings: viewModel.wordTimingsByAyah.isEmpty
                                            ? nil
                                            : (viewModel.wordTimingsByAyah[ayah.numberInSurah] ?? []),
                                        isLoadingTimings: viewModel.isLoadingWordTimings,
                                        wordTimingsError: viewModel.wordTimingsError,
                                        wordDetails: viewModel.wordDetailsByAyah[ayah.numberInSurah],
                                        tafsir: viewModel.tafsirByAyah[ayah.numberInSurah],
                                        isBookmarked: bookmarkStore.isBookmarked(surah: surah.number, ayah: ayah.numberInSurah),
                                        isMemorizing: srStore.isScheduled(surah: surah.number, ayah: ayah.numberInSurah),
                                        isWorkingAyah: targetStore.target?.surah == surah.number
                                            && targetStore.target?.workingAyah == ayah.numberInSurah,
                                        onBookmark: {
                                            bookmarkStore.toggle(
                                                surahNumber: surah.number,
                                                surahName: surah.englishName,
                                                surahArabicName: surah.name,
                                                ayahNumber: ayah.numberInSurah,
                                                arabic: ayah.arabic,
                                                translation: ayah.translation
                                            )
                                        },
                                        onToggleMemorize: { toggleMemorize(ayah) },
                                        onPlay: {
                                            audioService.stopWordLoop()
                                            viewModel.playAyah(ayah.numberInSurah, audioService: audioService)
                                        },
                                        onWordLoop: { start, end in
                                            guard let chapterUrl = viewModel.chapterAudioUrl() else { return }
                                            audioService.startWordLoop(
                                                surah: surah.number,
                                                ayah: ayah.numberInSurah,
                                                chapterUrl: chapterUrl,
                                                wordStartMs: start.startMs,
                                                wordEndMs: end.endMs
                                            )
                                        },
                                        onRequestTimings: {
                                            Task { await viewModel.loadWordTimingsIfNeeded() }
                                        },
                                        onSetWorking: { setWorkingAyah(ayah.numberInSurah) },
                                        onMarkLearned: { markWorkingLearned() }
                                    )
                                    .id(ayah.numberInSurah)
                                    Divider().padding(.horizontal, 16)
                                }
                            }
                            }
                        }
                        // Clear the floating tab bar (and the audio player bar
                        // when it's showing) so the last ayah isn't covered.
                        .padding(.bottom, isThisSurahActive ? 140 : 90)
                    }
                    .coordinateSpace(.named("surahScroll"))
                    .onPreferenceChange(HeaderVisibilityKey.self) { maxY in
                        // maxY is the transliteration's bottom edge relative to the
                        // scroll viewport's top. Once it slips under the floating
                        // toolbar, reveal the transliteration title inline.
                        let passed = maxY < 50
                        if passed != headerPassed {
                            withAnimation(.easeInOut(duration: 0.2)) { headerPassed = passed }
                        }
                    }
                    .onChange(of: audioService.currentAyah) { _, newAyah in
                        guard let ayah = newAyah, isThisSurahActive else { return }
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(ayah, anchor: .top)
                        }
                    }
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

                if isThisSurahActive {
                    QuranPlayerView(surah: surah, viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: isThisSurahActive)
        }
        .animation(.spring(duration: 0.35), value: showResumeBar)
        .navigationTitle((isActivePage && headerPassed) ? surah.englishName : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isActivePage {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    DownloadButton(surahNumber: surah.number, ayahCount: surah.numberOfAyahs)

                    Button { viewModel.showLoopSheet = true } label: {
                        Image(systemName: "repeat")
                            .symbolVariant(
                                (viewModel.loopSettings.mode != .off || viewModel.loopSettings.listenAndRepeat)
                                ? .fill : .none
                            )
                            .foregroundStyle(
                                (viewModel.loopSettings.mode != .off || viewModel.loopSettings.listenAndRepeat)
                                ? .brand : .primary
                            )
                    }

                    // Reading options + Mushaf in one menu
                    Menu {
                        // Mushaf view
                        Button { showMushaf = true } label: {
                            Label("Mushaf View", systemImage: "book.pages.fill")
                        }

                        Divider()

                        // Translation toggle
                        Button { showTranslation.toggle() } label: {
                            Label(
                                showTranslation ? "Hide Translation" : "Show Translation",
                                systemImage: showTranslation ? "eye.slash" : "eye"
                            )
                        }

                        // Transliteration toggle
                        Button { showTransliteration.toggle() } label: {
                            Label(
                                showTransliteration ? "Hide Transliteration" : "Show Transliteration",
                                systemImage: showTransliteration ? "character.cursor.ibeam" : "character"
                            )
                        }

                        Divider()

                        // Loop-based acquisition: make this the active target.
                        Button { Haptics.tap(); startMemorizingSurah() } label: {
                            Label("Memorize this Surah", systemImage: "target")
                        }

                        // Meaning-flashcard review (stage 5 / retention).
                        Button { Haptics.tap(); showMemorizeSheet = true } label: {
                            Label("Flashcard Review…", systemImage: "graduationcap")
                        }
                        .disabled(viewModel.ayahs.isEmpty)
                    } label: {
                        Image(systemName: "textformat")
                            .foregroundStyle(.primary)
                    }
                }
            }
            }
        }
        .sheet(isPresented: $showMushaf) {
            MushafView(surah: surah, ayahs: viewModel.ayahs)
        }
        .sheet(isPresented: $showMemorizeSheet, onDismiss: { reviewAfterEnroll = false }) {
            MemorizeSurahSheet(surah: surah, ayahs: viewModel.ayahs) {
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
        .sheet(isPresented: $viewModel.showLoopSheet) {
            LoopSettingsSheet(
                settings: viewModel.loopSettings,
                totalAyahs: surah.numberOfAyahs,
                ayahs: viewModel.ayahs,
                focusAyah: loopFocusAyah,
                onApply: { newSettings in
                    viewModel.applyLoopSettings(newSettings, audioService: audioService)
                },
                onStartPreset: { preset in
                    viewModel.applyLoopSettings(preset, audioService: audioService)
                    audioService.playLoop(surah: surah.number, settings: preset,
                                          totalAyahs: surah.numberOfAyahs,
                                          surahName: surah.englishName)
                }
            )
        }
        .onChange(of: translationId) {
            Task { await viewModel.loadAyahs() }
        }
        .task {
            StreakService.shared.recordRead()
            await viewModel.loadAyahs()
            await viewModel.loadWordTimingsIfNeeded()
            await viewModel.loadWordDetails()
            await viewModel.loadTafsir()
            // Resume tracking (Feature 6)
            if let last = viewModel.lastPlayedAyah() {
                resumeAyah = last
                showResumeBar = true
            }
            // Track last-opened surah for widget
            let ud = UserDefaults(suiteName: "group.sami.Quran-App")
            ud?.set(surah.englishName, forKey: "lastSurahName")
            ud?.set(surah.number, forKey: "lastSurahNumber")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

// MARK: - Download button

private struct DownloadButton: View {
    let surahNumber: Int
    let ayahCount: Int
    @ObservedObject private var dm = DownloadManager.shared

    private var reciterSubfolder: String { Reciter.selected.subfolder }

    var body: some View {
        let prog = dm.progress[surahNumber]
        let isDownloaded = prog == 1.0
        let isDownloading = prog != nil && prog! < 1.0

        Button {
            if isDownloaded {
                dm.deleteSurah(surahNumber, reciterSubfolder: reciterSubfolder)
            } else if !isDownloading {
                dm.downloadSurah(surahNumber, ayahCount: ayahCount, reciterSubfolder: reciterSubfolder)
            }
        } label: {
            if isDownloading {
                ZStack {
                    CircularProgressView(progress: prog ?? 0)
                        .frame(width: 20, height: 20)
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: isDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(isDownloaded ? Color.brand : Color.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(AppAnim.spring, value: isDownloaded)
            }
        }
        .buttonStyle(.plain)
        .animation(AppAnim.spring, value: isDownloading)
    }
}

private struct CircularProgressView: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Scroll tracking

/// Reports the surah header's bottom edge (in scroll-viewport space) so the
/// detail view can reveal the inline title once the header scrolls away.
private struct HeaderVisibilityKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

// MARK: - Surah page browser (swipe between surahs)

/// Wraps multiple SurahDetailViews in a horizontally-paged TabView so the user
/// can swipe left/right to move between surahs. Navigation title and toolbar
/// items come from the active SurahDetailView and propagate to the nav bar.
struct SurahPageView: View {
    let surahs: [Surah]
    let startIndex: Int
    var initialAyah: Int? = nil

    @State private var currentIndex: Int

    init(surahs: [Surah], startIndex: Int, initialAyah: Int? = nil) {
        self.surahs    = surahs
        self.startIndex = startIndex
        self.initialAyah = initialAyah
        _currentIndex = State(initialValue: max(0, min(startIndex, surahs.count - 1)))
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(surahs.indices, id: \.self) { idx in
                SurahDetailView(
                    surah: surahs[idx],
                    initialAyah: idx == startIndex ? initialAyah : nil,
                    isActivePage: idx == currentIndex
                )
                .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Allow the audio player bar and surah content to extend to the
        // bottom of the screen without the safe-area cutting things off.
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Surah header

struct SurahHeaderView: View {
    let surah: Surah
    var isPlaying: Bool = false
    var onPlay: () -> Void = {}
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 6) {
            // Primary: transliteration
            Text(surah.englishName)
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .scaleEffect(appeared ? 1.0 : 0.92)
                .opacity(appeared ? 1 : 0)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: HeaderVisibilityKey.self,
                            value: geo.frame(in: .named("surahScroll")).maxY
                        )
                    }
                )

            // Secondary: Arabic script
            Text(surah.name)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
                .environment(\.layoutDirection, .rightToLeft)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)

            // Secondary: English translation
            Text(surah.englishNameTranslation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)

            HStack(spacing: 16) {
                Label("\(surah.numberOfAyahs) ayahs", systemImage: "text.alignright")
                Label(surah.revelationType,
                      systemImage: surah.revelationType == "Meccan" ? "sun.horizon" : "building.2")
            }
            .font(.caption)
            .foregroundStyle(Color(.tertiaryLabel))
            .padding(.top, 2)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)

            // Play the whole surah from ayah 1 (toggles when already playing it)
            Button(action: onPlay) {
                ZStack {
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 60, height: 60)
                        .shadow(color: .brand.opacity(0.35), radius: 8, y: 4)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .offset(x: isPlaying ? 0 : 2)   // optically center the play glyph
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.8)

            if surah.number != 1 && surah.number != 9 {
                Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
                    .font(.system(size: 20))
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.top, 10)
                    .foregroundStyle(.secondary)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
            }
        }
        .padding(.horizontal, 20)
        // Extra top padding so the transliteration title clears the floating
        // navigation toolbar (which overlays scroll content on iOS 26).
        .padding(.top, 56)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Color.brand.opacity(0.05))
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
                            .font(.title2.bold())
                        Text("\(ayahs.count) ayahs"
                             + (enrolledCount > 0 ? " · \(enrolledCount) already in review" : ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    Text("Adds every ayah to spaced-repetition review, so a few resurface for you to recall each day until the whole surah sticks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("What are you memorizing for?")
                            .font(.subheadline.weight(.semibold))
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
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.brand)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
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
                                .font(.subheadline.weight(.medium))
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
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? .white : .brand)
                    .frame(width: 42, height: 42)
                    .background(selected ? Color.brand : Color.brand.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(goal.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? .brand : Color(.tertiaryLabel))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(selected ? Color.brand : .clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
