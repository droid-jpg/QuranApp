import SwiftUI

struct SurahListView: View {
    @StateObject private var viewModel = SurahListViewModel()
    @EnvironmentObject private var store: MemorizationStore
    @EnvironmentObject private var audioService: AudioService
    @ObservedObject private var downloadManager = DownloadManager.shared
    @AppStorage("selectedReciterId") private var selectedReciterId = 7
    @State private var showJuzBrowser  = false
    @State private var filter: SurahFilter = .all
    @State private var path = NavigationPath()

    /// Search + status/download filter applied together.
    private var displayedSurahs: [Surah] {
        viewModel.filtered.filter { surah in
            switch filter {
            case .all:        return true
            case .downloaded: return downloadManager.isDownloaded(surah.number)
            case .memorized:  return store.status(for: surah.number) == .memorized
            case .inProgress: return store.status(for: surah.number) == .inProgress
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.isLoading && viewModel.surahs.isEmpty {
                    ProgressView("Loading Surahs…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = viewModel.error, viewModel.surahs.isEmpty {
                    ErrorView(message: err) { Task { await viewModel.load() } }
                } else {
                    List {
                        // Full surah list
                        Section {
                            if displayedSurahs.isEmpty {
                                FilterEmptyState(filter: filter)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            } else {
                                ForEach(displayedSurahs) { surah in
                                    let idx = viewModel.surahs.firstIndex(where: { $0.number == surah.number }) ?? 0
                                    NavigationLink(value: idx) {
                                        SurahRowView(
                                            surah: surah,
                                            status: store.status(for: surah.number)
                                        )
                                    }
                                    .contextMenu {
                                        SurahQuickActions(
                                            surah: surah,
                                            store: store,
                                            downloadManager: downloadManager,
                                            audioService: audioService
                                        )
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        let next = store.status(for: surah.number).next
                                        Button {
                                            Haptics.impact()
                                            withAnimation { store.cycle(for: surah.number) }
                                        } label: {
                                            Label(next.label, systemImage: next.icon)
                                        }
                                        .tint(next.color)
                                    }
                                }
                            }
                        } header: {
                            if filter != .all {
                                SectionHeader(title: filter.label, systemImage: filter.icon)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $viewModel.searchText, prompt: "Search surah…")
                }
            }
            .navigationTitle("The Holy Quran")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Int.self) { idx in
                SurahPageView(surahs: viewModel.surahs, startIndex: idx)
            }
            .sensoryFeedback(.selection, trigger: filter)
            // Light tap on push only. Replaces a per-row gesture that, on List
            // rows, fired the haptic on the content but didn't navigate.
            .sensoryFeedback(trigger: path) { old, new in
                new.count > old.count ? .impact(weight: .light) : nil
            }
            .task {
                await viewModel.load()
                downloadManager.syncCurrentReciter()
            }
            .onChange(of: selectedReciterId) { _, _ in
                downloadManager.syncCurrentReciter()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.tap()
                        showJuzBrowser = true
                    } label: {
                        Image(systemName: "list.number")
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(SurahFilter.allCases) { f in
                                Label(f.label, systemImage: f.icon).tag(f)
                            }
                        }
                    } label: {
                        Image(systemName: filter == .all
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(filter == .all ? Color.primary : Color.brand)
                    }
                }            }
            .sheet(isPresented: $showJuzBrowser) {
                JuzBrowserView(surahs: viewModel.surahs)
            }        }
    }
}

// MARK: - Row

struct SurahRowView: View {
    let surah: Surah
    let status: MemorizationStatus
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        HStack(spacing: 16) {
            NumberBadge(number: surah.number)

            VStack(alignment: .leading, spacing: 2) {
                Text(surah.englishName)
                    .font(.system(.body, weight: .semibold))
                Text(surah.englishNameTranslation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(surah.name)
                    .font(.system(size: 20))
                    .environment(\.layoutDirection, .rightToLeft)

                HStack(spacing: 6) {
                    if downloadManager.isDownloaded(surah.number) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.brand)
                    }
                    if status != .notStarted {
                        Image(systemName: status.icon)
                            .font(.caption)
                            .foregroundStyle(status.color)
                    } else {
                        Text("\(surah.numberOfAyahs) ayahs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Filter

enum SurahFilter: String, CaseIterable, Identifiable {
    case all, downloaded, memorized, inProgress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:        "All Surahs"
        case .downloaded: "Downloaded"
        case .memorized:  "Memorized"
        case .inProgress: "In Progress"
        }
    }

    var icon: String {
        switch self {
        case .all:        "square.stack.3d.up"
        case .downloaded: "arrow.down.circle"
        case .memorized:  "checkmark.circle.fill"
        case .inProgress: "circle.dotted.and.circle"
        }
    }
}

struct FilterEmptyState: View {
    let filter: SurahFilter

    private var message: String {
        switch filter {
        case .downloaded: "No downloaded surahs yet. Tap and hold a surah to download it."
        case .memorized:  "No memorized surahs yet."
        case .inProgress: "Nothing in progress yet."
        case .all:        "No surahs found."
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: filter.icon)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Quick actions (long-press context menu)

struct SurahQuickActions: View {
    let surah: Surah
    @ObservedObject var store: MemorizationStore
    @ObservedObject var downloadManager: DownloadManager
    let audioService: AudioService

    private var reciterSubfolder: String { Reciter.selected.subfolder }

    var body: some View {
        // Memorization status (checkmark shows current selection)
        Picker("Status", selection: Binding(
            get: { store.status(for: surah.number) },
            set: { Haptics.selection(); store.set($0, for: surah.number) }
        )) {
            Label("Not Started", systemImage: "circle").tag(MemorizationStatus.notStarted)
            Label("In Progress", systemImage: "circle.dotted.and.circle").tag(MemorizationStatus.inProgress)
            Label("Memorized", systemImage: "checkmark.circle.fill").tag(MemorizationStatus.memorized)
        }

        Divider()

        Button {
            Haptics.tap()
            audioService.play(
                surah: surah.number,
                startAyah: 1,
                loop: LoopSettings(),
                totalAyahs: surah.numberOfAyahs,
                surahName: surah.englishName
            )
        } label: {
            Label("Play Audio", systemImage: "play.circle")
        }

        if downloadManager.isDownloaded(surah.number) {
            Button(role: .destructive) {
                Haptics.warning()
                downloadManager.deleteSurah(surah.number, reciterSubfolder: reciterSubfolder)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        } else if (downloadManager.progress[surah.number] ?? 0) > 0 {
            Label("Downloading…", systemImage: "arrow.down.circle")
        } else {
            Button {
                Haptics.tap()
                downloadManager.downloadSurah(
                    surah.number,
                    ayahCount: surah.numberOfAyahs,
                    reciterSubfolder: reciterSubfolder
                )
            } label: {
                Label("Download Audio", systemImage: "arrow.down.circle")
            }
        }
    }
}

struct NumberBadge: View {
    let number: Int

    var body: some View {
        ZStack {
            Image(systemName: "seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.brand.opacity(0.16), Color.brand.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "seal")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.brand.opacity(0.35))
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.brand)
        }
        .frame(width: 44, height: 44)
    }
}

// MARK: - Verse of the Day

struct VerseOfDayCard: View {
    /// Home overlays its own Play button on the card's top-right corner. It can't
    /// live *inside* the card, because the whole card is a NavigationLink there and
    /// nested buttons swallow each other's taps — so the card just leaves room.
    var reservesPlaySlot: Bool = false

    @ObservedObject private var service = DailyVerseService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Verse of the Day", systemImage: "sun.horizon.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Spacer()
                if let v = service.verse {
                    Text("\(v.surahName) \(v.ayahNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, reservesPlaySlot ? 72 : 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if service.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if let v = service.verse {
                VStack(alignment: .trailing, spacing: 12) {
                    Text(v.arabic)
                        .font(.system(size: 24, weight: .regular))
                        .multilineTextAlignment(.trailing)
                        .lineSpacing(10)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)

                    Text(v.translation)
                        .font(.subheadline)
                        .fontDesign(.serif)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .tintedCard(.orange)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.orange.opacity(0.5))
                .frame(width: 3)
                .padding(.vertical, 12)
        }
    }
}

