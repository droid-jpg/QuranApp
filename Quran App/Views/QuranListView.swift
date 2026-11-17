import SwiftUI

// MARK: - Surah row

/// A surah in any list: tap the row to read it, tap the button to hear it, without
/// leaving the list.
struct SurahRow: View {
    @Environment(Player.self) private var player
    @Environment(Downloads.self) private var downloads
    @Environment(AppRouter.self) private var router
    let surah: Surah
    /// Replaces "The Cow · 286 ayahs", for rows that say where listening stopped.
    var subtitle: String? = nil
    /// When set, the play button resumes this position and its repeat.
    var recent: Player.Recent? = nil

    private var isCurrent: Bool { player.isCurrent(surah.number) }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                router.openReader(surah: surah.number, ayah: recent?.ayah)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text("\(surah.number)")
                        .font(TypeScale.secondary.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 30, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Spacing.xs) {
                            Text(surah.englishName)
                                .font(TypeScale.rowTitle)
                                .foregroundStyle(isCurrent ? Color.brand : Palette.textPrimary)
                            if isCurrent && player.isPlaying {
                                // The surah being recited shows a small moving waveform.
                                Image(systemName: "waveform")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.brand)
                                    .symbolEffect(.variableColor.iterative, options: .repeat(.continuous),
                                                  isActive: !Motion.reduceMotion)
                                    .transition(Motion.pop)
                                    .accessibilityHidden(true)
                            }
                        }
                        HStack(spacing: Spacing.xxs) {
                            Text(subtitle ?? "\(surah.englishNameTranslation) · \(surah.numberOfAyahs) ayahs")
                                .lineLimit(1)
                            if downloads.complete.contains(surah.number) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.caption)
                                    .accessibilityLabel("Downloaded")
                                    .transition(Motion.pop)
                            } else if downloads.failed.contains(surah.number) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(Palette.danger)
                                    .accessibilityLabel("Download didn't finish")
                            }
                        }
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.textSecondary)
                    }
                    .animation(Motion.standard, value: isCurrent)
                    .animation(Motion.bouncy, value: isCurrent && player.isPlaying)
                    .animation(Motion.bouncy, value: downloads.complete.contains(surah.number))
                    Spacer(minLength: Spacing.xs)
                    Text(surah.name.replacingOccurrences(of: "سُورَةُ ", with: ""))
                        .font(TypeScale.arabicList)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                .frame(minHeight: MinSize.surahRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())

            playButton
        }
        .contextMenu {
            if downloads.complete.contains(surah.number) {
                Button("Remove download", systemImage: "trash", role: .destructive) { downloads.remove(surah.number) }
            } else if downloads.progress[surah.number] != nil {
                Button("Cancel download", systemImage: "xmark") { downloads.cancel(surah.number) }
            } else {
                Button("Download", systemImage: "arrow.down.circle") {
                    Haptics.tap()
                    downloads.download(surah)
                }
            }
        }
    }

    private var playButton: some View {
        Button {
            Haptics.impact(.light)
            if isCurrent {
                player.toggle()
            } else if let recent {
                player.play(recent)
            } else {
                player.play(surah)
            }
        } label: {
            ZStack {
                Circle().strokeBorder(Color.brand.opacity(0.5), lineWidth: 1)
                if let fraction = downloads.progress[surah.number] {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(Motion.spring, value: fraction)
                        .transition(.opacity)
                }
                if isCurrent && player.isLoading && player.isPlaying {
                    ProgressView().controlSize(.small)
                        .transition(Motion.pop)
                } else {
                    Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.brand)
                        .contentTransition(.symbolEffect(.replace))
                        .transition(Motion.pop)
                }
            }
            .frame(width: 36, height: 36)
            .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)
            .contentShape(Rectangle())
            .animation(Motion.quick, value: isCurrent && player.isLoading && player.isPlaying)
            .animation(Motion.standard, value: downloads.progress[surah.number] != nil)
        }
        .buttonStyle(CardButtonStyle(scale: 0.88))
        .accessibilityLabel(isCurrent && player.isPlaying ? "Pause \(surah.englishName)" : "Play \(surah.englishName)")
    }
}

// MARK: - Quran tab

struct QuranListView: View {
    @Environment(Downloads.self) private var downloads
    @State private var search = ""
    @State private var downloadedOnly = false

    private var surahs: [Surah] {
        var all = QuranText.shared.surahs
        if downloadedOnly { all = all.filter { downloads.complete.contains($0.number) } }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        if let number = Int(query) { return all.filter { $0.number == number } }
        let folded = Self.fold(query)
        return all.filter {
            Self.fold($0.englishName).contains(folded) || Self.fold($0.englishNameTranslation).contains(folded) || $0.name.contains(query)
        }
    }

    /// Lower-cased with hyphens, apostrophes and spaces removed, so "al baqara",
    /// "albaqara" and "Al-Baqara" all match.
    private static func fold(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    var body: some View {
        List {
            ForEach(surahs) { surah in
                SurahRow(surah: surah)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenMargin, bottom: 0, trailing: Spacing.sm))
                    .listRowBackground(Palette.background)
                    .listRowSeparatorTint(Palette.separator)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .overlay {
            if surahs.isEmpty {
                ContentUnavailableView(
                    downloadedOnly && search.isEmpty ? "No downloaded surahs yet" : "No surahs match “\(search)”",
                    systemImage: downloadedOnly && search.isEmpty ? "arrow.down.circle" : "magnifyingglass",
                    description: downloadedOnly && search.isEmpty ? Text("Touch and hold a surah to download it.") : nil
                )
            }
        }
        .navigationTitle("Quran")
        .searchable(text: $search, prompt: "Search surahs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.juz) { Text("Juz") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Show", selection: $downloadedOnly) {
                        Text("All surahs").tag(false)
                        Text("Downloaded").tag(true)
                    }
                } label: {
                    Image(systemName: downloadedOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter")
            }
        }
    }
}

// MARK: - Juz

struct JuzListView: View {
    @Environment(Player.self) private var player
    @Environment(AppRouter.self) private var router

    var body: some View {
        List(JuzData.boundaries, id: \.juz) { juz in
            let start = QuranText.shared.surah(juz.startSurah)
            let end = QuranText.shared.surah(juz.endSurah)
            HStack(spacing: Spacing.sm) {
                Button {
                    router.openReader(surah: juz.startSurah, ayah: juz.startAyah)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Juz \(juz.juz)")
                            .font(TypeScale.rowTitle)
                            .foregroundStyle(Palette.textPrimary)
                        Text("\(start?.englishName ?? "") \(juz.startAyah) to \(end?.englishName ?? "") \(juz.endAyah)")
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: MinSize.surahRow, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())

                Button {
                    Haptics.impact(.light)
                    if let start { player.play(start, from: juz.startAyah) }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.brand)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Color.brand.opacity(0.5), lineWidth: 1))
                        .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CardButtonStyle(scale: 0.88))
                .accessibilityLabel("Play Juz \(juz.juz)")
            }
            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenMargin, bottom: 0, trailing: Spacing.sm))
            .listRowBackground(Palette.background)
            .listRowSeparatorTint(Palette.separator)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Juz")
        .navigationBarTitleDisplayMode(.inline)
    }
}
