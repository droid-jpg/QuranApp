import SwiftUI

struct QuranSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query      = ""
    @State private var inArabic   = false
    @State private var results: [QuranSearchResult] = []
    @State private var isSearching = false
    @State private var errorMsg: String?
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar + language toggle
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(inArabic ? "Search in Arabic…" : "Search in English…", text: $query)
                            .textFieldStyle(.plain)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Picker("Language", selection: $inArabic) {
                        Text("English").tag(false)
                        Text("Arabic").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))

                Divider()

                if isSearching {
                    Spacer()
                    ProgressView("Searching…").padding()
                    Spacer()
                } else if let err = errorMsg {
                    Spacer()
                    Text(err).foregroundStyle(.secondary).padding()
                    Spacer()
                } else if results.isEmpty && hasSearched {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.tertiary)
                        Text("No results found").foregroundStyle(.secondary)
                    }
                    Spacer()
                } else if !hasSearched {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "text.magnifyingglass").font(.system(size: 48)).foregroundStyle(.tertiary)
                        Text("Search across all 6,236 ayahs")
                            .font(.headline).foregroundStyle(.secondary)
                        Text("Type a word or phrase above and press Search")
                            .font(.subheadline).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    List(results) { result in
                        NavigationLink(destination: SurahDetailView(surah: result.surah, initialAyah: result.ayahNumber)) {
                            SearchResultRow(result: result, isArabic: inArabic)
                        }
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search Quran")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        errorMsg = nil
        hasSearched = true
        do {
            results = try await QuranAPIService.shared.searchAyahs(keyword: q, inArabic: inArabic)
        } catch {
            errorMsg = "Search failed: \(error.localizedDescription)"
            results = []
        }
        isSearching = false
    }
}

private struct SearchResultRow: View {
    let result: QuranSearchResult
    let isArabic: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(result.surah.englishName) · Ayah \(result.ayahNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(.teal)
                Spacer()
                Text(result.surah.name)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            Text(result.text)
                .font(isArabic ? .system(size: 18) : .subheadline)
                .lineLimit(3)
                .multilineTextAlignment(isArabic ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)
                .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    QuranSearchView()
}
