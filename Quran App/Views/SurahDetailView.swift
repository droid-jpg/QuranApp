import SwiftUI
import WidgetKit

struct SurahDetailView: View {
    let surah: Surah
    @StateObject private var viewModel: SurahDetailViewModel
    @EnvironmentObject private var audioService: AudioService

    @AppStorage("showTranslation")      private var showTranslation     = true
    @AppStorage("showTransliteration")  private var showTransliteration = true
    @AppStorage("arabicFontSize")       private var arabicFontSize: Double = 26

    @State private var showMushaf = false
    @State private var scrollTarget: Int? = nil
    @State private var showResumeBar = false
    @State private var resumeAyah = 0

    init(surah: Surah, initialAyah: Int? = nil) {
        self.surah = surah
        _viewModel = StateObject(wrappedValue: SurahDetailViewModel(surah: surah))
        _scrollTarget = State(initialValue: initialAyah)
    }

    private var isThisSurahActive: Bool {
        audioService.currentSurah == surah.number
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        SurahHeaderView(surah: surah)

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
                                    }
                                )
                                .id(ayah.numberInSurah)
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.bottom, isThisSurahActive ? 100 : 0)
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
                .overlay(alignment: .top) {
                    if showResumeBar {
                        HStack(spacing: 12) {
                            Image(systemName: "bookmark.fill").foregroundStyle(.teal)
                            Text("Continue from Ayah \(resumeAyah)")
                                .font(.subheadline.bold())
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    proxy.scrollTo(resumeAyah, anchor: .top)
                                }
                                showResumeBar = false
                            } label: {
                                Text("Resume")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.teal).clipShape(Capsule())
                            }
                            Button { showResumeBar = false } label: {
                                Image(systemName: "xmark").foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        .padding(.horizontal, 10).padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.35), value: showResumeBar)
            }

            if isThisSurahActive {
                AudioPlayerBarView(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: isThisSurahActive)
        .navigationTitle(surah.englishName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Reading options menu (Feature 3)
                    Menu {
                        // Translation toggle
                        Button {
                            showTranslation.toggle()
                        } label: {
                            Label(
                                showTranslation ? "Hide Translation" : "Show Translation",
                                systemImage: showTranslation ? "eye.slash" : "eye"
                            )
                        }

                        // Transliteration toggle
                        Button {
                            showTransliteration.toggle()
                        } label: {
                            Label(
                                showTransliteration ? "Hide Transliteration" : "Show Transliteration",
                                systemImage: showTransliteration ? "character.cursor.ibeam" : "character"
                            )
                        }

                        Divider()

                        // Font size
                        Button {
                            arabicFontSize = min(arabicFontSize + 2, 44)
                        } label: {
                            Label("Larger Text", systemImage: "textformat.size.larger")
                        }

                        Button {
                            arabicFontSize = max(arabicFontSize - 2, 18)
                        } label: {
                            Label("Smaller Text", systemImage: "textformat.size.smaller")
                        }

                        Button {
                            arabicFontSize = 26
                        } label: {
                            Label("Reset Size", systemImage: "arrow.uturn.backward")
                        }
                    } label: {
                        Image(systemName: "textformat")
                            .foregroundStyle(.primary)
                    }

                    Button { showMushaf = true } label: {
                        Image(systemName: "book.pages.fill")
                            .foregroundStyle(.primary)
                    }
                    Button { viewModel.showLoopSheet = true } label: {
                        Image(systemName: "repeat")
                            .symbolVariant(
                                (viewModel.loopSettings.mode != .off || viewModel.loopSettings.listenAndRepeat)
                                ? .fill : .none
                            )
                            .foregroundStyle(
                                (viewModel.loopSettings.mode != .off || viewModel.loopSettings.listenAndRepeat)
                                ? .teal : .primary
                            )
                    }
                }
            }
        }
        .sheet(isPresented: $showMushaf) {
            MushafView(surah: surah, ayahs: viewModel.ayahs)
        }
        .sheet(isPresented: $viewModel.showLoopSheet) {
            LoopSettingsSheet(
                settings: viewModel.loopSettings,
                totalAyahs: surah.numberOfAyahs
            ) { newSettings in
                viewModel.applyLoopSettings(newSettings, audioService: audioService)
            }
        }
        .task {
            StreakService.shared.recordRead()
            await viewModel.loadAyahs()
            await viewModel.loadWordTimingsIfNeeded()
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

// MARK: - Surah header

struct SurahHeaderView: View {
    let surah: Surah

    var body: some View {
        VStack(spacing: 10) {
            Text(surah.name)
                .font(.system(size: 38, weight: .regular))
                .environment(\.layoutDirection, .rightToLeft)

            Text(surah.englishNameTranslation)
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                Label("\(surah.numberOfAyahs) Ayahs", systemImage: "text.alignright")
                Label(surah.revelationType,
                      systemImage: surah.revelationType == "Meccan" ? "sun.horizon" : "building.2")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if surah.number != 1 && surah.number != 9 {
                Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
                    .font(.system(size: 22))
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.top, 6)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.teal.opacity(0.06))
    }
}
