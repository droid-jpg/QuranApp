import SwiftUI

struct SurahListView: View {
    @StateObject private var viewModel = SurahListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.surahs.isEmpty {
                    ProgressView("Loading Surahs…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = viewModel.error, viewModel.surahs.isEmpty {
                    ErrorView(message: err) { Task { await viewModel.load() } }
                } else {
                    List(viewModel.filtered) { surah in
                        NavigationLink(destination: SurahDetailView(surah: surah)) {
                            SurahRowView(surah: surah)
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $viewModel.searchText, prompt: "Search surah…")
                }
            }
            .navigationTitle("القرآن الكريم")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.load() }
        }
    }
}

// MARK: - Row

struct SurahRowView: View {
    let surah: Surah

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

            VStack(alignment: .trailing, spacing: 2) {
                Text(surah.name)
                    .font(.system(size: 20))
                    .environment(\.layoutDirection, .rightToLeft)
                Text("\(surah.numberOfAyahs) ayahs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct NumberBadge: View {
    let number: Int

    var body: some View {
        ZStack {
            Image(systemName: "seal")
                .font(.system(size: 38))
                .foregroundStyle(.teal.opacity(0.18))
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.teal)
        }
        .frame(width: 44, height: 44)
    }
}
