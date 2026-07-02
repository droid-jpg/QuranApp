import SwiftUI

struct AyahRowView: View {
    let ayah: Ayah
    let surahName: String
    let surahNumber: Int
    let isPlaying: Bool
    let isWordLooping: Bool
    let wordTimings: [WordTiming]?   // nil = not yet loaded; [] = loaded but empty/error
    let isLoadingTimings: Bool
    let wordTimingsError: String?
    let wordDetails: [WordDetail]?   // per-word meaning/audio; nil until loaded
    let tafsir: String?              // ayah commentary; nil when this ayah has none
    let isBookmarked: Bool
    let isMemorizing: Bool           // enrolled in spaced-repetition review
    var isWorkingAyah: Bool = false  // the current memorization target ayah
    let onBookmark: () -> Void
    let onToggleMemorize: () -> Void
    let onPlay: () -> Void
    let onWordLoop: (WordTiming, WordTiming) -> Void
    let onRequestTimings: () -> Void
    var onSetWorking: () -> Void = {}   // "Memorize from here"
    var onMarkLearned: () -> Void = {}  // "Mark learned → next ayah"

    @AppStorage("showTranslation")          private var showTranslation     = true
    @AppStorage("showTransliteration")      private var showTransliteration = true
    @AppStorage("arabicFontSize")           private var arabicFontSize: Double = 26
    @AppStorage("translationFontSize")      private var translationFontSize: Double = 14
    @AppStorage("transliterationFontSize")  private var transliterationFontSize: Double = 13

    @State private var showWordPicker = false
    @State private var showTafsir = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Control row
            HStack(spacing: 10) {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(isPlaying ? .brand : Color(.secondaryLabel))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                Button {
                    onRequestTimings()
                    showWordPicker = true
                } label: {
                    Group {
                        if isLoadingTimings {
                            ProgressView().scaleEffect(0.65)
                        } else {
                            Image(systemName: "text.word.spacing")
                                .font(.system(size: 16))
                                .foregroundStyle(isWordLooping ? Color.brand : Color(.tertiaryLabel))
                                .symbolVariant(isWordLooping ? .fill : .none)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showWordPicker) {
                    WordLoopPickerView(
                        ayah: ayah,
                        timings: wordTimings ?? [],
                        isLoading: isLoadingTimings,
                        errorMessage: wordTimingsError
                    ) { start, end in
                        onWordLoop(start, end)
                    }
                }

                // Commentary — shown only on ayahs that have tafsir.
                if let tafsir {
                    Button { showTafsir = true } label: {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.brand.opacity(0.7))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showTafsir) {
                        TafsirSheet(ayah: ayah, surahName: surahName, text: tafsir)
                    }
                }

                Button(action: onToggleMemorize) {
                    Image(systemName: isMemorizing ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isMemorizing ? Color.brand : Color(.tertiaryLabel))
                        .symbolEffect(.bounce, value: isMemorizing)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(ayah.numberInSurah)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(isPlaying ? Color.brand : (isWorkingAyah ? Color.orange : Color(.tertiaryLabel)))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.orange, lineWidth: isWorkingAyah && !isPlaying ? 2 : 0)
                            .padding(-3)
                    )
                    .scaleEffect(isPlaying ? 1.08 : 1.0)
                    .animation(AppAnim.spring, value: isPlaying)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Arabic text — each word is tappable for its meaning/audio.
            TappableArabicText(
                ayah: ayah,
                surahNumber: surahNumber,
                wordDetails: wordDetails,
                fontSize: arabicFontSize
            )
            .padding(.horizontal, 16)
            .padding(.bottom, (showTransliteration || showTranslation) ? 12 : 14)

            if showTransliteration || showTranslation {
                Divider().padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 6) {
                    if showTransliteration {
                        Text(ayah.transliteration)
                            .font(.system(size: transliterationFontSize, weight: .light))
                            .italic()
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if showTranslation {
                        Text(ayah.translation)
                            .font(.system(size: translationFontSize))
                            .foregroundStyle(Color(.label).opacity(0.78))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
        .background(isPlaying ? Color.brand.opacity(0.07) : Color.clear)
        .animation(AppAnim.smooth, value: isPlaying)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.brand)
                .frame(width: 3)
                .opacity(isPlaying ? 1 : 0)
                .pulseGlow(color: .brand, active: isPlaying)
                .animation(AppAnim.spring, value: isPlaying)
        }
        .contextMenu {
            ShareLink(item: shareText()) {
                Label("Share Ayah", systemImage: "square.and.arrow.up")
            }
            ShareLink(item: shareTextWithTranslation()) {
                Label("Share with Translation", systemImage: "doc.text")
            }
            Divider()
            Button {
                onBookmark()
            } label: {
                Label(isBookmarked ? "Remove Bookmark" : "Bookmark Ayah",
                      systemImage: isBookmarked ? "bookmark.slash" : "bookmark")
            }
            Button {
                onToggleMemorize()
            } label: {
                Label(isMemorizing ? "Remove from Memorization" : "Add to Memorization",
                      systemImage: isMemorizing ? "graduationcap.fill" : "graduationcap")
            }
            Divider()
            if isWorkingAyah {
                Button {
                    onMarkLearned()
                } label: {
                    Label("Mark Learned → Next Ayah", systemImage: "checkmark.circle")
                }
            } else {
                Button {
                    onSetWorking()
                } label: {
                    Label("Memorize From Here", systemImage: "target")
                }
            }
        }
    }

    // MARK: - Share helpers

    private func shareText() -> String {
        """
        \(ayah.arabic)

        [\(surahName) \(ayah.numberInSurah)]
        """
    }

    private func shareTextWithTranslation() -> String {
        """
        \(ayah.arabic)

        \(ayah.translation)

        [\(surahName) \(ayah.numberInSurah)]
        """
    }
}

// MARK: - Tappable Arabic (word-by-word)

/// Renders the ayah's Arabic as individually tappable words. The words always
/// come from `ayah.arabic` (so the script is identical to before and needs no
/// network), and a word only becomes tappable once matching `WordDetail` data
/// has loaded. RTL flow is handled by FlowLayout, not the environment.
private struct TappableArabicText: View {
    let ayah: Ayah
    let surahNumber: Int
    let wordDetails: [WordDetail]?
    let fontSize: CGFloat

    @State private var selected: WordDetail?

    private var words: [String] {
        ayah.arabic.split { $0 == " " || $0 == "\n" }.map(String.init)
    }

    /// The Basmala the text editions prepend to ayah 1 is stripped upstream in
    /// QuranAPIService, so display positions line up 1:1 with quran.com's
    /// per-word data: word i (0-based) is position i+1.
    private func detail(forDisplayIndex i: Int) -> WordDetail? {
        wordDetails?.first { $0.position == i + 1 }
    }

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 12, rightToLeft: true) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                ArabicWordChip(word: word, fontSize: fontSize, detail: detail(forDisplayIndex: idx)) { d in
                    selected = d
                }
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $selected) { WordDefinitionSheet(detail: $0) }
    }
}

/// A single Arabic word. Taps flash a teal highlight and open the definition
/// sheet; words without loaded `WordDetail` data are inert.
private struct ArabicWordChip: View {
    let word: String
    let fontSize: CGFloat
    let detail: WordDetail?
    let onTap: (WordDetail) -> Void

    @State private var flash = false

    var body: some View {
        Text(word)
            .font(.system(size: fontSize))
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.brand.opacity(flash ? 0.22 : 0))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard let detail else { return }
                Haptics.tap()
                withAnimation(.easeOut(duration: 0.15)) { flash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.easeOut(duration: 0.3)) { flash = false }
                }
                onTap(detail)
            }
    }
}

/// Bottom sheet showing one word's meaning, transliteration, and a play button
/// for its recitation clip (via ClipPlayer, kept off the main audio queue).
private struct WordDefinitionSheet: View {
    let detail: WordDetail
    @ObservedObject private var clip = ClipPlayer.shared

    private var isPlaying: Bool {
        guard let url = detail.audioURL else { return false }
        return clip.isPlaying(url)
    }

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Text(detail.arabic)
                .font(.system(size: 40))
                .environment(\.layoutDirection, .rightToLeft)
                .multilineTextAlignment(.center)

            if !detail.transliteration.isEmpty {
                Text(detail.transliteration)
                    .font(.title3).italic()
                    .foregroundStyle(.secondary)
            }

            if !detail.translation.isEmpty {
                Text(detail.translation)
                    .font(.title2.weight(.medium))
                    .multilineTextAlignment(.center)
            }

            if let url = detail.audioURL {
                Button {
                    if isPlaying { clip.stop() } else { clip.play(url) }
                } label: {
                    Label(isPlaying ? "Stop" : "Play",
                          systemImage: isPlaying ? "stop.fill" : "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(Color.brand)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(280)])
        .onDisappear { clip.stop() }
    }
}

/// Scrollable commentary sheet for a single ayah.
private struct TafsirSheet: View {
    let ayah: Ayah
    let surahName: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(ayah.arabic)
                        .font(.system(size: 24))
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Text(TafsirService.shared.sourceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    Text(text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(20)
            }
            .navigationTitle("\(surahName) \(ayah.numberInSurah)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
