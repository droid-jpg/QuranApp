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

    /// The count that sits at the end of the masthead rule: the whole book when
    /// nothing is narrowing the list, otherwise how much of it is left showing.
    private var countLabel: String {
        let narrowed = filter != .all || !viewModel.searchText.isEmpty
        guard !viewModel.surahs.isEmpty else { return "" }
        return narrowed
            ? "\(displayedSurahs.count) SHOWN"
            : "\(viewModel.surahs.count) SURAHS"
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                SurahListTopBar(
                    count: countLabel,
                    searchText: $viewModel.searchText,
                    filter: $filter,
                    onJuz: {
                        Haptics.tap()
                        showJuzBrowser = true
                    }
                )

                content
            }
            // The system bar drew a large SF title, a grey capsule search field
            // and a popover menu — the last stretch of stock iOS in the tab.
            // `SurahListTopBar` replaces it from inside the layout.
            .toolbar(.hidden, for: .navigationBar)
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
            .sheet(isPresented: $showJuzBrowser) {
                JuzBrowserView(surahs: viewModel.surahs)
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.surahs.isEmpty {
            ProgressView("Loading Surahs…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = viewModel.error, viewModel.surahs.isEmpty {
            ErrorView(message: err) { Task { await viewModel.load() } }
        } else {
            List {
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
            }
            .listStyle(.plain)
            // The search field is ours now and sits above the list, so a scroll
            // is the only way left to put the keyboard away.
            .scrollDismissesKeyboard(.immediately)
        }
    }
}

// MARK: - Top bar

/// The Qur'an tab's own bar, in place of the system's large title, search field
/// and toolbar menu: a wordmark ruled across to the count, the search field set
/// in the reading serif, and the filter as segments rather than a popover.
private struct SurahListTopBar: View {
    let count: String
    @Binding var searchText: String
    @Binding var filter: SurahFilter
    let onJuz: () -> Void

    /// Read during body so a change of reading face repaints the wordmark here
    /// and now, rather than on the next visit to the tab.
    var type = ReadingType()

    private var filterOptions: [EditorialOption<SurahFilter>] {
        SurahFilter.allCases.map { EditorialOption($0, $0.shortLabel) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Qur’an")
                    .font(type.serif(32, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityAddTraits(.isHeader)

                Rectangle()
                    .fill(Color.rule)
                    .frame(height: 1)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 5 }

                if !count.isEmpty {
                    MetaText(count, size: 10)
                        .contentTransition(.numericText())
                        .animation(AppAnim.smooth, value: count)
                }

                BarButton(icon: "list.number", label: "Browse by juz", action: onJuz)
                    // The glyph's own 38pt box would otherwise push the bar's
                    // baseline around; pin it to the wordmark's instead.
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 9 }
            }
            .padding(.leading, 24)
            .padding(.trailing, 12)
            .padding(.top, 8)

            SurahSearchField(text: $searchText)
                .padding(.horizontal, 24)
                .padding(.top, 14)

            EditorialSegmented(selection: $filter, options: filterOptions)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// The ruled search field. `.searchable` draws UIKit's grey capsule inside the
/// navigation bar — this is the same job done in the app's own hand.
private struct SurahSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(focused || !text.isEmpty
                                 ? Color.brand
                                 : Color(.label).opacity(0.35))

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Search surah…")
                        .font(.appSerif(15.5, italic: true))
                        .foregroundStyle(Color(.label).opacity(0.35))
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .font(.appSerif(15.5))
                    .textFieldStyle(.plain)
                    .tint(.brand)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Search surah")
            }

            if !text.isEmpty {
                Button {
                    Haptics.tap()
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(.label).opacity(0.4))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, text.isEmpty ? 12 : 4)
        .padding(.vertical, 9)
        .overlay(
            Rectangle().strokeBorder(
                focused ? Color.brand.opacity(0.65) : Color(.label).opacity(0.18),
                lineWidth: 1
            )
        )
        .animation(AppAnim.smooth, value: focused)
        .animation(AppAnim.smooth, value: text.isEmpty)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

// MARK: - Row

struct SurahRowView: View {
    let surah: Surah
    let status: MemorizationStatus
    @ObservedObject private var downloadManager = DownloadManager.shared

    // Declared so the list follows a change of reading face or script.
    @AppStorage("readingFace")  private var readingFace = ReadingFace.newYork.rawValue
    @AppStorage("arabicScript") private var arabicScript = ArabicScript.system.rawValue

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // The numeral carries the index — a seal badge was a lot of
            // furniture for a number the eye only scans.
            Text("\(surah.number)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .kerning(0.6)
                .foregroundStyle(.brand)
                .frame(width: 22, alignment: .leading)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(surah.englishName)
                    .font(.appSerif(19, weight: .medium))
                Text(surah.englishNameTranslation)
                    .font(.appSerif(14, italic: true))
                    .foregroundStyle(Color(.label).opacity(0.5))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(surah.name)
                    .font(.appArabic(19))
                    .environment(\.layoutDirection, .rightToLeft)

                HStack(spacing: 6) {
                    if downloadManager.isDownloaded(surah.number) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.brand)
                    }
                    if status != .notStarted {
                        Image(systemName: status.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(status.color)
                    } else {
                        MetaText("\(surah.numberOfAyahs) AYAHS", size: 9)
                    }
                }
            }
        }
        .padding(.vertical, 8)
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

    /// What the segmented filter says. "All Surahs" and "In Progress" don't fit
    /// four across at small caps, and the segment is already labelled by context.
    var shortLabel: String {
        switch self {
        case .all:        "All"
        case .downloaded: "Saved"
        case .memorized:  "Memorized"
        case .inProgress: "Learning"
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

/// Retired with the seal-badge era — surah numbers are set as plain marginal
/// numerals now. Kept only until the last caller is gone.
private struct NumberBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .foregroundStyle(.brand)
            .frame(minWidth: 22, alignment: .leading)
    }
}

