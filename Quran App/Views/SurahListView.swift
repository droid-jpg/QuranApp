import SwiftUI
import Combine

/// The Quran tab's request to focus its search field. Today sets it, then asks the
/// root to switch tabs; the list consumes it when it appears (it may not exist
/// until the tab is first shown).
@MainActor
final class QuranSearchRequest: ObservableObject {
    static let shared = QuranSearchRequest()
    @Published var pending = false
    private init() {}

    /// Switch to the Quran tab with its search field focused and the keyboard up.
    func open() {
        pending = true
        NotificationCenter.default.post(name: .showQuranTab, object: nil)
    }
}

extension Notification.Name {
    static let showQuranTab = Notification.Name("showQuranTab")
}

struct SurahListView: View {
    @StateObject private var viewModel = SurahListViewModel()
    @EnvironmentObject private var store: MemorizationStore
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var searchRequest = QuranSearchRequest.shared
    @AppStorage("selectedReciterId") private var selectedReciterId = 7
    @State private var showJuzBrowser  = false
    @State private var filter: SurahFilter = .all
    @State private var path = NavigationPath()
    @FocusState private var searchFocused: Bool

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
            VStack(spacing: 0) {
                SurahListTopBar(
                    searchText: $viewModel.searchText,
                    filter: $filter,
                    searchFocused: $searchFocused,
                    onJuz: {
                        Haptics.tap()
                        showJuzBrowser = true
                    }
                )

                content
            }
            .background(Palette.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Int.self) { idx in
                SurahPageView(surahs: viewModel.surahs, startIndex: idx)
            }
            // Audio failure: a banner above the mini player (it observes, this view doesn't).
            .safeAreaInset(edge: .bottom, spacing: 0) { PlaybackErrorBanner() }
            .sensoryFeedback(.selection, trigger: filter)
            // Light tap on push only.
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
            // Today's search field lands here with the keyboard up.
            .onChange(of: searchRequest.pending, initial: true) { _, pending in
                guard pending else { return }
                searchRequest.pending = false
                path = NavigationPath()
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    searchFocused = true
                }
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
            ProgressView("Loading surahs…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = viewModel.error, viewModel.surahs.isEmpty {
            ErrorView(message: err) { Task { await viewModel.load() } }
        } else {
            List {
                if displayedSurahs.isEmpty {
                    FilterEmptyState(filter: filter, search: viewModel.searchText)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(displayedSurahs) { surah in
                        let idx = viewModel.surahs.firstIndex(where: { $0.number == surah.number }) ?? 0
                        SurahRowView(surah: surah, onOpen: { path.append(idx) })
                            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenMargin,
                                                      bottom: 0, trailing: Spacing.screenMargin))
                            .listRowBackground(Palette.background)
                            .listRowSeparatorTint(Palette.separator)
                            .contextMenu { SurahQuickActions(surah: surah) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // The search field is ours and sits above the list, so a scroll is the
            // way to put the keyboard away.
            .scrollDismissesKeyboard(.immediately)
        }
    }
}

// MARK: - Top bar

/// The Quran tab's own opaque header: the title with the Juz button and Filter
/// menu, then the search field.
private struct SurahListTopBar: View {
    @Binding var searchText: String
    @Binding var filter: SurahFilter
    var searchFocused: FocusState<Bool>.Binding
    let onJuz: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("Quran")
                    .font(TypeScale.display)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: Spacing.xs)

                Button(action: onJuz) {
                    Text("Juz")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, Spacing.xs)
                        .frame(minHeight: MinSize.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(SurahFilter.allCases) { option in
                            Label(option.label, systemImage: option.icon).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.accent)
                        .overlay(alignment: .topTrailing) {
                            if filter != .all {
                                Circle()
                                    .fill(Palette.accent)
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                                    .offset(x: 3, y: -3)
                            }
                        }
                        .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Filter")
                .accessibilityValue(filter == .all ? "" : filter.label)
            }

            SurahSearchField(text: $searchText, focused: searchFocused)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.sm)
        .opaqueBar()
    }
}

/// The search field: name, meaning or number.
private struct SurahSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(TypeScale.secondary)
                .foregroundStyle(focused.wrappedValue ? Palette.accent : Palette.textSecondary)

            TextField("", text: $text,
                      prompt: Text("Search surahs").foregroundColor(Palette.textSecondary))
                .font(TypeScale.body)
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.accent)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Search surahs")

            if !text.isEmpty {
                Button {
                    Haptics.tap()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, Spacing.sm)
        .padding(.trailing, text.isEmpty ? Spacing.sm : 0)
        .frame(minHeight: MinSize.hitTarget)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: Spacing.xs))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.xs)
                .strokeBorder(focused.wrappedValue ? Palette.accent : Palette.separator, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
    }
}

// MARK: - Filter

enum SurahFilter: String, CaseIterable, Identifiable {
    case all, downloaded, memorized, inProgress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:        "All"
        case .downloaded: "Downloaded"
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
    var search = ""

    private var message: String {
        if !search.isEmpty { return "No surahs match “\(search)”" }
        switch filter {
        case .downloaded: return "No downloaded surahs yet"
        case .memorized:  return "No memorized surahs yet"
        case .inProgress: return "No surahs in Learning yet"
        case .all:        return "No surahs yet"
        }
    }

    var body: some View {
        Text(message)
            .font(TypeScale.body)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
    }
}

// MARK: - Context menu (long-press)

/// Play, Download / Remove download, and the memorization status. Observes the
/// stores itself, so the list doesn't; commands go through `audioServiceRef`.
struct SurahQuickActions: View {
    let surah: Surah

    @Environment(\.audioServiceRef) private var audioService
    @EnvironmentObject private var store: MemorizationStore
    @ObservedObject private var downloadManager = DownloadManager.shared

    private var reciterSubfolder: String { Reciter.selected.subfolder }

    var body: some View {
        if let audioService {
            Button {
                SurahPlayer.toggle(surah, audio: audioService)
            } label: {
                Label("Play", systemImage: "play.circle")
            }
        }

        if downloadManager.isDownloaded(surah.number) {
            Button(role: .destructive) {
                Haptics.warning()
                downloadManager.deleteSurah(surah.number, reciterSubfolder: reciterSubfolder)
            } label: {
                Label("Remove download", systemImage: "trash")
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
                Label("Download", systemImage: "arrow.down.circle")
            }
        }

        Divider()

        let status = store.status(for: surah.number)
        if status != .memorized {
            Button { set(.memorized) } label: {
                Label("Mark as memorized", systemImage: "checkmark.circle")
            }
        }
        if status != .inProgress {
            Button { set(.inProgress) } label: {
                Label("Mark as learning", systemImage: "circle.dotted.and.circle")
            }
        }
        if status != .notStarted {
            Button { set(.notStarted) } label: {
                Label("Mark as not started", systemImage: "circle")
            }
        }
    }

    private func set(_ status: MemorizationStatus) {
        Haptics.selection()
        store.set(status, for: surah.number)
    }
}
