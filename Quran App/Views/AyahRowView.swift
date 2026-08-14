import SwiftUI

/// One ayah, set as a page of a book rather than a row of a list.
///
/// The control row that used to sit above every ayah is gone: a tap reveals a
/// compact strip, a long press opens the full menu, and immersive reading turns
/// even the strip off. What's left on the page is scripture, a numeral, and — on
/// the ayah being recited — a single accent rule down the left margin.
struct AyahRowView: View {
    let ayah: Ayah
    let surahNumber: Int
    let isPlaying: Bool
    let isWordLooping: Bool
    let isLoadingTimings: Bool
    let wordDetails: [WordDetail]?   // per-word meaning/audio; nil until loaded
    let isBookmarked: Bool
    let isMemorizing: Bool           // enrolled in spaced-repetition review
    var isWorkingAyah: Bool = false  // the current memorization target ayah
    let hasTafsir: Bool
    let onBookmark: () -> Void
    let onToggleMemorize: () -> Void
    let onPlay: () -> Void
    var onRepeat: () -> Void = {}       // "Repeat this ayah"
    /// Opens the word-by-word picker (the reader owns the sheet).
    var onWordByWord: () -> Void = {}
    var onTafsir: () -> Void = {}
    /// Long press — the reader raises its own menu panel for this ayah.
    var onLongPress: () -> Void = {}

    @AppStorage("showTranslation")          private var showTranslation     = true
    @AppStorage("showTransliteration")      private var showTransliteration = true
    @AppStorage("arabicFontSize")           private var arabicFontSize: Double = 26
    @AppStorage("translationFontSize")      private var translationFontSize: Double = 17
    @AppStorage("transliterationFontSize")  private var transliterationFontSize: Double = 13
    @AppStorage("immersiveReading")         private var immersiveReading = false
    // Read during body — that is what makes a change of face or script repaint
    // the page immediately rather than on the next visit. Not `private`: a plain
    // stored property (unlike the wrappers above) would take the memberwise
    // initializer private with it.
    var type = ReadingType()

    @State private var revealed = false

    /// Brand while reciting, orange while it's the memorization target, otherwise
    /// dim — the numeral is the only status indicator left on the page.
    private var numeralTint: Color {
        if isPlaying { return .brand }
        if isWorkingAyah { return .orange }
        return Color(.label).opacity(0.35)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Arabic — each word is tappable for its meaning/audio.
            TappableArabicText(
                ayah: ayah,
                surahNumber: surahNumber,
                wordDetails: wordDetails,
                fontSize: arabicFontSize,
                script: type.script
            )
            .padding(.horizontal, 28)
            .padding(.top, 22)

            if showTransliteration || showTranslation {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(ayah.numberInSurah)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .kerning(0.6)
                        .foregroundStyle(numeralTint)
                        .frame(minWidth: 20, alignment: .leading)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        if showTransliteration {
                            Text(ayah.transliteration)
                                .font(type.serif(transliterationFontSize, weight: .light, italic: true))
                                .foregroundStyle(Color(.label).opacity(0.44))
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if showTranslation {
                            Text(ayah.translation)
                                .font(type.serif(translationFontSize))
                                .foregroundStyle(Color(.label).opacity(0.86))
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
            } else {
                // Nothing beneath the Arabic, so the numeral carries the line.
                Text("\(ayah.numberInSurah)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .kerning(0.6)
                    .foregroundStyle(numeralTint)
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
            }

            if revealed && !immersiveReading {
                controlStrip
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !immersiveReading else { return }
            Haptics.tap()
            withAnimation(AppAnim.springFast) { revealed.toggle() }
        }
        // The app's own panel, raised by the reader, instead of `.contextMenu` —
        // the last piece of UIKit chrome the restyle hadn't reached.
        .onLongPressGesture(minimumDuration: 0.32) { onLongPress() }
        // The one accent on the page: a rule down the margin of the ayah being
        // recited. Replaces the old tinted background wash.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.brand)
                .frame(width: 2)
                .opacity(isPlaying ? 1 : 0)
                .animation(AppAnim.spring, value: isPlaying)
        }
        .onChange(of: immersiveReading) { _, on in
            if on { revealed = false }
        }
    }

    // MARK: - Revealed controls

    /// The compact strip a tap reveals. Everything here is also in the long-press
    /// menu — this exists so the common actions cost one tap instead of a press.
    private var controlStrip: some View {
        HStack(spacing: 18) {
            GlyphButton(icon: isPlaying ? "pause.fill" : "play.fill",
                        on: isPlaying, label: isPlaying ? "Pause" : "Play from here",
                        action: onPlay)

            GlyphButton(icon: "repeat", on: false, label: "Repeat this ayah", action: onRepeat)

            GlyphButton(icon: "text.word.spacing", on: isWordLooping,
                        loading: isLoadingTimings, label: "Word by word",
                        action: onWordByWord)

            if hasTafsir {
                GlyphButton(icon: "text.book.closed", on: false, label: "Tafsir", action: onTafsir)
            }

            GlyphButton(icon: isMemorizing ? "checkmark.circle.fill" : "plus.circle",
                        on: isMemorizing, label: "Add to review", action: onToggleMemorize)

            GlyphButton(icon: isBookmarked ? "bookmark.fill" : "bookmark",
                        on: isBookmarked, label: "Bookmark", action: onBookmark)

            Spacer(minLength: 0)
        }
    }

}

// MARK: - Share helpers
//
// The long-press menu itself now lives in the reader (so its panel can be drawn
// above the pager and the player); these build what it shares.

func ayahShareText(_ ayah: Ayah, surahName: String) -> String {
    """
    \(ayah.arabic)

    [\(surahName) \(ayah.numberInSurah)]
    """
}

func ayahShareTextWithTranslation(_ ayah: Ayah, surahName: String) -> String {
    """
    \(ayah.arabic)

    \(ayah.translation)

    [\(surahName) \(ayah.numberInSurah)]
    """
}

// MARK: - Glyph button

/// A bare glyph in the revealed strip — no border, no fill, accent only when the
/// thing it toggles is on.
private struct GlyphButton: View {
    let icon: String
    let on: Bool
    var loading: Bool = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if loading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(on ? Color.brand : Color(.label).opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
    /// Passed in rather than looked up, so a change of script repaints the page.
    let script: ArabicScript

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
        FlowLayout(spacing: 5, lineSpacing: fontSize * 0.62, rightToLeft: true) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                ArabicWordChip(word: word, fontSize: fontSize, script: script,
                               detail: detail(forDisplayIndex: idx)) { d in
                    selected = d
                }
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $selected) { WordDefinitionSheet(detail: $0) }
    }
}

/// A single Arabic word. Taps flash an accent highlight and open the definition
/// sheet; words without loaded `WordDetail` data are inert.
private struct ArabicWordChip: View {
    let word: String
    let fontSize: CGFloat
    let script: ArabicScript
    let detail: WordDetail?
    let onTap: (WordDetail) -> Void

    @State private var flash = false

    var body: some View {
        Text(word)
            .font(script.font(size: fontSize))
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(Rectangle().fill(Color.brand.opacity(flash ? 0.18 : 0)))
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
                .font(.appArabic(40))
                .environment(\.layoutDirection, .rightToLeft)
                .multilineTextAlignment(.center)

            if !detail.transliteration.isEmpty {
                Text(detail.transliteration)
                    .font(.appSerif(19, italic: true))
                    .foregroundStyle(.secondary)
            }

            if !detail.translation.isEmpty {
                Text(detail.translation)
                    .font(.appSerif(21, weight: .medium))
                    .multilineTextAlignment(.center)
            }

            if let url = detail.audioURL {
                Button {
                    if isPlaying { clip.stop() } else { clip.play(url) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(isPlaying ? "STOP" : "PLAY")
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(1.2)
                    }
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .overlay(Rectangle().strokeBorder(Color.brand.opacity(0.55), lineWidth: 1))
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

/// Scrollable commentary sheet for a single ayah. Presented by the reader.
struct TafsirSheet: View {
    let ayah: Ayah
    let surahName: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(ayah.arabic)
                        .font(.appArabic(24))
                        .lineSpacing(12)
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Eyebrow(TafsirService.shared.sourceName)

                    Hairline()

                    Text(text)
                        .font(.appSerif(17))
                        .lineSpacing(4)
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
