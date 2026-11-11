import SwiftUI

/// What a row asks the reader to do. One closure carries it, so the row's
/// inputs are values the reader can compare (see `AyahRowView.==`).
enum AyahRowAction {
    /// The number button or a long press: open Ayah actions for this ayah.
    case openActions
}

/// One ayah: a 44 pt number button in the leading gutter, then the Arabic, the
/// transliteration and the translation (REDESIGN §3.3).
///
/// The number button and a long press anywhere on the ayah (the Arabic words
/// included) open Ayah actions; a tap on a word keeps its own meaning. The ayah
/// in the player gets the `highlight` background and a 3 pt accent bar; ayahs
/// inside an active repeat get a thin accent rule in the gutter.
///
/// `Equatable` so the reader can skip every row whose drawn inputs didn't change
/// (apply `.equatable()`): an ayah advance then re-renders the two rows whose
/// playback flags flipped, not every row loaded.
struct AyahRowView: View, Equatable {
    let ayah: Ayah
    let surahNumber: Int
    /// The ayah loaded in the player (playing or paused). Set by `AyahRowSlot`.
    var isCurrent: Bool
    /// Inside the repeat range that is on for this surah. Set by `AyahRowSlot`.
    var isInRepeat: Bool
    let wordDetails: [WordDetail]?   // per-word meaning/audio; nil until loaded
    var isWorkingAyah: Bool = false  // the current memorization target ayah
    /// Left out of `==`: it only forwards to the reader.
    let onAction: (AyahRowAction) -> Void

    @AppStorage("showTranslation")          private var showTranslation     = true
    @AppStorage("showTransliteration")      private var showTransliteration = true
    @AppStorage("arabicFontSize")           private var arabicFontSize: Double = 26
    @AppStorage("translationFontSize")      private var translationFontSize: Double = 17
    @AppStorage("transliterationFontSize")  private var transliterationFontSize: Double = 13
    // Read during body — that is what makes a change of face or script repaint
    // the page immediately rather than on the next visit. Not `private`: a plain
    // stored property (unlike the wrappers above) would take the memberwise
    // initializer private with it.
    var type = ReadingType()

    /// The row's drawn inputs. Settings it reads (`@AppStorage`, `ReadingType`)
    /// re-render it on their own, so they aren't compared. Word details load once
    /// per surah, so presence and count stand in for comparing every word.
    nonisolated static func == (lhs: AyahRowView, rhs: AyahRowView) -> Bool {
        lhs.ayah.numberInSurah == rhs.ayah.numberInSurah
            && lhs.surahNumber == rhs.surahNumber
            && lhs.isCurrent == rhs.isCurrent
            && lhs.isInRepeat == rhs.isInRepeat
            && lhs.isWorkingAyah == rhs.isWorkingAyah
            && lhs.wordDetails?.count == rhs.wordDetails?.count
            && lhs.ayah.arabic == rhs.ayah.arabic
            && lhs.ayah.translation == rhs.ayah.translation
            && lhs.ayah.transliteration == rhs.ayah.transliteration
    }

    /// Accent while in the player, orange while it's the memorization target.
    private var numeralTint: Color {
        if isCurrent { return Palette.accent }
        if isWorkingAyah { return .orange }
        return Palette.textSecondary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            numberButton

            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Arabic — each word is tappable for its meaning/audio; a long
                // press on a word opens Ayah actions like anywhere else.
                TappableArabicText(
                    ayah: ayah,
                    surahNumber: surahNumber,
                    wordDetails: wordDetails,
                    fontSize: arabicFontSize,
                    script: type.script,
                    onLongPress: { onAction(.openActions) }
                )

                if showTransliteration {
                    Text(ayah.transliteration)
                        .font(type.serif(max(transliterationFontSize, 13), italic: true, scales: false))
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if showTranslation {
                    Text(ayah.translation)
                        .font(type.serif(translationFontSize, scales: false))
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, Spacing.xxs)
            .padding(.trailing, Spacing.screenMargin)
        }
        .padding(.leading, Spacing.xxs)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Palette.highlight : Color.clear)
        .overlay(alignment: .leading) { gutterMarks }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: Self.longPress) { onAction(.openActions) }
        .animation(Motion.standard, value: isCurrent)
    }

    static let longPress: Double = 0.35

    /// "4" in a hairline circle, 44 pt to hit. Opens Ayah actions.
    private var numberButton: some View {
        Button {
            Haptics.tap()
            onAction(.openActions)
        } label: {
            Text("\(ayah.numberInSurah)")
                .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                .foregroundStyle(numeralTint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(Spacing.xxs)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(isCurrent ? Palette.accent : Palette.separator, lineWidth: 1))
                .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ayah \(ayah.numberInSurah) actions")
    }

    /// The thin repeat rule and, over it, the current ayah's 3 pt bar.
    private var gutterMarks: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Palette.accent)
                .frame(width: 1.5)
                .padding(.leading, Spacing.xxs)
                .opacity(isInRepeat ? 1 : 0)
            Rectangle()
                .fill(Palette.accent)
                .frame(width: 3)
                .opacity(isCurrent ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Share helpers
//
// What Ayah actions → Share hands to the share sheet.

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
    /// A long press on a word: the row's long press, which the word's own tap
    /// would otherwise swallow.
    let onLongPress: () -> Void

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
                               detail: detail(forDisplayIndex: idx),
                               onLongPress: onLongPress) { d in
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
    let onLongPress: () -> Void
    let onTap: (WordDetail) -> Void

    @State private var flash = false

    var body: some View {
        Text(word)
            .font(script.font(size: fontSize, scales: false))
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(Rectangle().fill(Color.brand.opacity(flash ? 0.18 : 0)))
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: AyahRowView.longPress) { onLongPress() }
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
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(.subheadline, weight: .bold))
                            .accessibilityHidden(true)
                        Text(isPlaying ? "Stop" : "Play")
                            .font(.system(.body, weight: .semibold))
                    }
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.xxs)
                    .frame(minHeight: 44)
                    .overlay(Rectangle().strokeBorder(Color.brand.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        // The system grabber; .large is there for when Dynamic Type outgrows 280 pt.
        .presentationDetents([.height(280), .large])
        .presentationDragIndicator(.visible)
        // Opaque like the other sheets (AUDIT #21).
        .presentationBackground(Palette.surfaceRaised)
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
            // Opaque like the other sheets (AUDIT #21), bar included.
            .presentationBackground(Palette.surfaceRaised)
            .toolbarBackground(Palette.surfaceRaised, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
