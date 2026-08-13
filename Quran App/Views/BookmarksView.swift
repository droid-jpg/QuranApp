import SwiftUI

/// Saved ayahs, set as scripture rather than as cards — the same block the
/// reader uses, ruled off from its neighbours.
struct BookmarksView: View {
    @EnvironmentObject private var store: BookmarkStore
    @State private var showClearAlert = false

    var body: some View {
        Group {
            if store.bookmarks.isEmpty {
                EditorialEmptyState(
                    icon: "bookmark",
                    title: "No bookmarks yet.",
                    message: "Long-press any ayah and choose Bookmark to save it here."
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.bookmarks.enumerated()), id: \.element.id) { index, bm in
                            if index > 0 {
                                Hairline().padding(.vertical, 22)
                            }
                            NavigationLink(destination: destination(for: bm)) {
                                BookmarkRow(bm: bm)
                            }
                            .buttonStyle(CardButtonStyle(scale: 0.985))
                            .contextMenu {
                                Button(role: .destructive) {
                                    Haptics.warning()
                                    store.remove(atOffsets: IndexSet(integer: index))
                                } label: {
                                    Label("Remove bookmark", systemImage: "bookmark.slash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !store.bookmarks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { showClearAlert = true }
                        .foregroundStyle(.red)
                }
            }
        }
        .alert("Clear all bookmarks?", isPresented: $showClearAlert) {
            Button("Clear", role: .destructive) { store.clearAll() }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Prefer the full registry so swiping between surahs works; fall back to a
    /// stub surah when it hasn't loaded yet.
    private func destination(for bm: BookmarkedAyah) -> AnyView {
        let allSurahs = SurahRegistry.shared.surahs
        guard !allSurahs.isEmpty else {
            // The reader is always the pager now (it owns the bar, the player and
            // the menu) — a single-surah pager stands in until the registry loads.
            let stub = Surah(
                number: bm.surahNumber,
                name: bm.surahArabicName,
                englishName: bm.surahName,
                englishNameTranslation: "",
                numberOfAyahs: 0,
                revelationType: ""
            )
            return AnyView(SurahPageView(surahs: [stub], startIndex: 0,
                                         initialAyah: bm.ayahNumber))
        }
        let idx = allSurahs.firstIndex { $0.number == bm.surahNumber } ?? 0
        return AnyView(SurahPageView(surahs: allSurahs, startIndex: idx, initialAyah: bm.ayahNumber))
    }
}

private struct BookmarkRow: View {
    let bm: BookmarkedAyah

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.brand)
                Eyebrow("\(bm.surahName) \(bm.ayahNumber)", tint: .brand)
                Spacer(minLength: 8)
                Text(bm.surahArabicName)
                    .font(.appArabic(15))
                    .foregroundStyle(Color(.label).opacity(0.4))
            }
            .padding(.bottom, 13)

            Text(bm.arabic)
                .font(.appArabic(21))
                .lineSpacing(12)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)

            Text(bm.translation)
                .font(.appSerif(16))
                .foregroundStyle(Color(.label).opacity(0.72))
                .lineSpacing(3)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Shared empty state

/// The ruled empty state used by the tool screens: a glyph, a serif line, and a
/// quiet instruction. No illustration, no card.
struct EditorialEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: (label: String, run: () -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.brand)
                .padding(.bottom, 18)

            Text(title)
                .font(.appSerif(23, weight: .medium))
                .padding(.bottom, 7)

            Text(message)
                .font(.appSerif(16))
                .foregroundStyle(Color(.label).opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            if let action {
                OutlineButton(label: action.label, on: true, action: action.run)
                    .padding(.top, 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
