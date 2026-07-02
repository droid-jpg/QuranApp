import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject private var store: BookmarkStore
    @State private var showClearAlert = false

    var body: some View {
        Group {
            if store.bookmarks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 52))
                        .foregroundStyle(.tertiary)
                    Text("No Bookmarks Yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Long-press any ayah and tap Bookmark to save it here.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.bookmarks) { bm in
                        let allSurahs = SurahRegistry.shared.surahs
                        let idx = allSurahs.firstIndex(where: { $0.number == bm.surahNumber }) ?? 0
                        // Use the full registry so swiping between surahs works.
                        // Fall back to a stub surah if registry isn't loaded yet.
                        let dest: AnyView = allSurahs.isEmpty
                            ? AnyView(SurahDetailView(
                                surah: Surah(
                                    number: bm.surahNumber,
                                    name: bm.surahArabicName,
                                    englishName: bm.surahName,
                                    englishNameTranslation: "",
                                    numberOfAyahs: 0,
                                    revelationType: ""
                                ),
                                initialAyah: bm.ayahNumber))
                            : AnyView(SurahPageView(surahs: allSurahs, startIndex: idx, initialAyah: bm.ayahNumber))
                        NavigationLink(destination: dest) {
                            BookmarkRow(bm: bm)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete { store.remove(atOffsets: $0) }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.bookmarks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear All", role: .destructive) { showClearAlert = true }
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .alert("Clear All Bookmarks?", isPresented: $showClearAlert) {
            Button("Clear", role: .destructive) { store.clearAll() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct BookmarkRow: View {
    let bm: BookmarkedAyah

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(bm.surahName) · Ayah \(bm.ayahNumber)", systemImage: "bookmark.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.brand)
                Spacer()
                Text(bm.surahArabicName)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            Text(bm.arabic)
                .font(.system(size: 20, weight: .regular))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
                .lineSpacing(6)
            Text(bm.translation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
