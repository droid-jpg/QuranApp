import SwiftUI
import WidgetKit

// MARK: - One surah

/// One page of the reader: the title block, then the ayahs. The pager
/// (`SurahPageView`, ReaderPager.swift) draws the bar and owns the sheets; the
/// Ayah actions and the sheets behind it go through `ReaderSheetRouter`
/// (ReaderSheets.swift), which this page only calls.
struct SurahDetailView: View {
    let surah: Surah
    @ObservedObject var viewModel: SurahDetailViewModel
    /// Opens Ayah actions. Held, not observed.
    let router: ReaderSheetRouter

    /// Commands only: playback state is drawn by the leaf views below
    /// (`AyahRowSlot`, `ReaderTitleSlot`, `PlaybackScrollFollower`), so an ayah
    /// advance or a play/pause doesn't re-render the page or every row.
    @Environment(\.audioServiceRef) private var audioService
    @EnvironmentObject private var targetStore: MemorizationTargetStore

    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId

    @State private var scrollTarget: Int? = nil
    @State private var showResumeBar = false
    @State private var resumeAyah = 0
    @State private var resumeProxy: ScrollViewProxy? = nil
    /// When the user last moved the page; auto-scroll waits 5 s after it. A
    /// plain reference, so scrolling never re-renders the page.
    @State private var scrollActivity = ReaderScrollActivity()

    init(surah: Surah, viewModel: SurahDetailViewModel, initialAyah: Int? = nil,
         router: ReaderSheetRouter) {
        self.surah = surah
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.router = router
        _scrollTarget = State(initialValue: initialAyah)
    }

    // MARK: - Playback

    private func playFrom(_ ayah: Int) {
        // Don't resume the main player here: `playAyah` decides what plays next,
        // and a resume followed by its toggle would pause the ayah just asked for.
        guard let audioService else { return }
        audioService.stopWordLoop(resume: false)
        viewModel.playAyah(ayah, audioService: audioService)
    }

    // MARK: - Rows

    /// Everything but playback is filled in here; the slot adds the playback and
    /// repeat flags, so only it watches the audio service.
    private func row(for ayah: Ayah) -> some View {
        let n = ayah.numberInSurah
        let target = targetStore.target

        return AyahRowSlot(row: AyahRowView(
            ayah: ayah,
            surahNumber: surah.number,
            isCurrent: false,
            isInRepeat: false,
            wordDetails: viewModel.wordDetailsByAyah[n],
            isWorkingAyah: target?.surah == surah.number && target?.workingAyah == n,
            onAction: { [router, surah, viewModel] _ in
                router.openActions(surah: surah, ayah: ayah, model: viewModel)
            }
        ))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Resume bar sits in the layout flow — cannot be covered by the bar.
            if showResumeBar {
                resumeBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ReaderTitleSlot(surah: surah, onPlayFromStart: { playFrom(1) })

                        // Separate containers, so the placeholders can't be
                        // mistaken for (and left among) the real rows.
                        if viewModel.ayahs.isEmpty && viewModel.error != nil && !viewModel.isLoading {
                            loadError
                        } else if viewModel.ayahs.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(0..<3, id: \.self) { _ in
                                    AyahSkeletonRow()
                                    Hairline().padding(.leading, MinSize.hitTarget + Spacing.xxs)
                                }
                            }
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.ayahs) { ayah in
                                    row(for: ayah)
                                        .id(ayah.numberInSurah)
                                    Hairline().padding(.leading, MinSize.hitTarget + Spacing.xxs)
                                }
                            }
                        }
                    }
                    // Breathing room only: the player and the bar reserve their
                    // own space as insets.
                    .padding(.bottom, Spacing.lg)
                    // A tap anywhere a word, a button or the number didn't take:
                    // brings back controls "Hide controls while reading" put away.
                    .contentShape(Rectangle())
                    .onTapGesture { Chrome.shared.readerTapped() }
                }
                .onScrollPhaseChange { old, new in
                    let user: Set<ScrollPhase> = [.interacting, .decelerating]
                    if user.contains(new) || user.contains(old) { scrollActivity.lastUserScroll = .now }
                    if new == .interacting { Chrome.shared.readerScrolled() }
                }
                .background(PlaybackScrollFollower(surahNumber: surah.number, proxy: proxy,
                                                   activity: scrollActivity))
                .onChange(of: viewModel.ayahs.isEmpty) { _, isEmpty in
                    guard !isEmpty else { return }
                    if let target = scrollTarget {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(Motion.standard) {
                                proxy.scrollTo(target, anchor: .top)
                            }
                            scrollTarget = nil
                        }
                    }
                }
                .onAppear { resumeProxy = proxy }
            }
        }
        .background(Palette.background)
        .animation(Motion.sheet, value: showResumeBar)
        .onChange(of: translationId) {
            Task { await viewModel.loadAyahs() }
        }
        .task {
            StreakService.shared.recordRead()
            // The model outlives the page, so a surah swiped back to is already
            // loaded and doesn't re-fetch.
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

    private var resumeBar: some View {
        HStack(spacing: Spacing.sm) {
            Text("Continue from ayah \(resumeAyah)")
                .font(TypeScale.secondary)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: Spacing.xs)
            Button {
                withAnimation(Motion.standard) {
                    resumeProxy?.scrollTo(resumeAyah, anchor: .top)
                }
                showResumeBar = false
            } label: {
                Text("Resume")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: MinSize.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { showResumeBar = false } label: {
                Image(systemName: "xmark")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, Spacing.screenMargin)
        .padding(.trailing, Spacing.xxs)
        .opaqueBar()
    }

    private var loadError: some View {
        VStack(spacing: Spacing.sm) {
            Text("Couldn't load this surah")
                .font(TypeScale.body)
                .foregroundStyle(Palette.textPrimary)
            Button {
                Task { await viewModel.loadAyahs() }
            } label: {
                Text("Try again")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: MinSize.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}

// MARK: - Playback leaves
//
// The only parts of a page that observe the audio service. Each is small, so an
// ayah advance or a play/pause re-runs these and the one or two rows whose
// playback flags actually changed, not the page and not every row.

/// Adds the playback and repeat flags to a row built by the page, then lets
/// SwiftUI skip the row unless something it draws changed (`AyahRowView` is
/// `Equatable`).
private struct AyahRowSlot: View {
    let row: AyahRowView
    @EnvironmentObject private var audioService: AudioService

    var body: some View {
        let n = row.ayah.numberInSurah
        let repeatState = audioService.repeatState
        var row = row
        row.isCurrent = audioService.currentSurah == row.surahNumber && audioService.currentAyah == n
        row.isInRepeat = repeatState.isOn && repeatState.surah == row.surahNumber && repeatState.contains(n)
        return row.equatable()
    }
}

/// When the user last scrolled a page by hand.
@MainActor
final class ReaderScrollActivity {
    var lastUserScroll = Date.distantPast
    /// Auto-scroll leaves the page alone this long after the user moved it.
    static let quietPeriod: TimeInterval = 5
    var userScrolledRecently: Bool { Date.now.timeIntervalSince(lastUserScroll) < Self.quietPeriod }
}

/// Keeps the ayah being recited in view as playback advances, unless the user
/// scrolled in the last 5 s.
private struct PlaybackScrollFollower: View {
    let surahNumber: Int
    let proxy: ScrollViewProxy
    let activity: ReaderScrollActivity
    @EnvironmentObject private var audioService: AudioService

    var body: some View {
        Color.clear
            .onChange(of: audioService.currentAyah) { _, newAyah in
                guard let ayah = newAyah, audioService.currentSurah == surahNumber,
                      !activity.userScrolledRecently else { return }
                withAnimation(Motion.standard) {
                    proxy.scrollTo(ayah, anchor: .top)
                }
            }
    }
}
