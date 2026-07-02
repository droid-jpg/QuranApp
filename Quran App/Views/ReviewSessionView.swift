import SwiftUI

/// A request to open a review session, carrying the exact cards and title. Used
/// with `.fullScreenCover(item:)` so the payload travels *with* the presentation
/// — presenting via a separately-set `@State` array (especially from inside a
/// `List` row) can capture a stale, empty value and falsely report "nothing due".
struct ReviewSessionConfig: Identifiable {
    let id = UUID()
    let cards: [AyahReview]
    var title: String = "Review"
}

/// Per-ayah recitation URL, preferring a downloaded copy for offline review.
private func ayahAudioURL(surah: Int, ayah: Int) -> URL {
    let subfolder = Reciter.selected.subfolder
    if let local = DownloadManager.shared.localURL(surah: surah, ayah: ayah, reciterSubfolder: subfolder) {
        return local
    }
    let s = String(format: "%03d", surah)
    let a = String(format: "%03d", ayah)
    return URL(string: "https://everyayah.com/data/\(subfolder)/\(s)\(a).mp3")!
}

/// A full spaced-repetition session: works through the due queue one card at a
/// time, grades each with SM-2, and requeues cards graded "Again" so they come
/// back before the session ends.
struct ReviewSessionView: View {
    @ObservedObject var store: MemorizationSRStore
    let initialCards: [AyahReview]
    var title: String = "Review"

    @Environment(\.dismiss) private var dismiss

    @State private var queue: [AyahReview] = []
    @State private var currentMode: ReviewMode = .flashcard
    @State private var reviewedCount = 0
    @State private var total = 0
    @State private var step = 0            // bumps each advance to reset the card view
    @State private var started = false

    var body: some View {
        NavigationStack {
            Group {
                if let card = queue.first {
                    VStack(spacing: 0) {
                        ProgressView(value: Double(reviewedCount), total: Double(max(total, 1)))
                            .tint(.brand)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        ReviewCardView(card: card, mode: currentMode) { grade in
                            handle(card, grade)
                        }
                        .id(step)
                    }
                } else {
                    completionView
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !queue.isEmpty {
                        Text("\(reviewedCount)/\(total)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { ClipPlayer.shared.stop(); GapClipPlayer.shared.stop(); dismiss() }
                }
            }
            .onAppear {
                guard !started else { return }
                started = true
                queue = initialCards
                total = initialCards.count
                pickMode(for: queue.first)
            }
            .onDisappear { ClipPlayer.shared.stop(); GapClipPlayer.shared.stop() }
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.brand)
            Text(total == 0 ? "Nothing due right now" : "Review complete")
                .font(.title2.bold())
            Text(total == 0
                 ? "Add ayahs from the reader to start memorizing."
                 : "You reviewed \(reviewedCount) ayah\(reviewedCount == 1 ? "" : "s").")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(40)
    }

    /// The drill style is chosen from the card's own goal, so a "Meaning" ayah is
    /// only ever shown as a meaning-recall flashcard while a "Recitation" ayah is
    /// drilled with audio / fill-in-the-blank.
    private func pickMode(for card: AyahReview?) {
        currentMode = (card?.goal.modes ?? ReviewMode.allCases).randomElement() ?? .flashcard
    }

    private func handle(_ card: AyahReview, _ grade: ReviewGrade) {
        let updated = store.recordReview(card, grade: grade)
        ClipPlayer.shared.stop()
        GapClipPlayer.shared.stop()
        if !queue.isEmpty { queue.removeFirst() }
        if grade == .again {
            queue.append(updated)   // see it again before the session ends
        } else {
            reviewedCount += 1
        }
        step += 1
        pickMode(for: queue.first)
    }
}

// MARK: - One card

private struct ReviewCardView: View {
    let card: AyahReview
    let mode: ReviewMode
    let onGrade: (ReviewGrade) -> Void

    @State private var revealed = false
    @State private var blankIndex = 0
    @ObservedObject private var clip = ClipPlayer.shared
    @ObservedObject private var gap = GapClipPlayer.shared
    @AppStorage("fillBlankUseTransliteration") private var fillBlankUseTransliteration = false
    @AppStorage("memorizationUseSimpleMeaning") private var useSimpleMeaning = false
    @AppStorage("memorizationCardScript")          private var cardScript: MemorizationCardScript = .arabic
    @AppStorage("memorizationArabicFontSize")       private var cardArabicFontSize: Double = 30
    @AppStorage("memorizationTransliterationFontSize") private var cardTransliterationFontSize: Double = 18
    @State private var simpleText: String? = nil
    @State private var loadingSimple = false
    /// Word/verse timings for this ayah (fetched lazily for the fill-blank drill).
    @State private var gapTimings: SurahTimingData? = nil

    private var arabicWords: [String] {
        card.arabic.split { $0 == " " || $0 == "\n" }.map(String.init)
    }

    /// The fill-in-the-blank exercise runs on the transliteration only when that's
    /// the chosen script and one is available; otherwise on the Arabic words.
    private var fillBlankUsesTranslit: Bool {
        cardScript == .transliteration && !card.transliteration.isEmpty
    }

    private var fillBlankWords: [String] {
        fillBlankUsesTranslit
            ? card.transliteration.split { $0 == " " || $0 == "\n" }.map(String.init)
            : arabicWords
    }

    private var audioURL: URL { ayahAudioURL(surah: card.surah, ayah: card.ayah) }
    private var isPlaying: Bool { clip.isPlaying(audioURL) }

    var body: some View {
        VStack(spacing: 16) {
            Label(mode.title, systemImage: mode.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.brand)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.brand.opacity(0.12)))
                .padding(.top, 12)

            Text("\(card.surahName) · Ayah \(card.ayah)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 18) {
                    switch mode {
                    case .flashcard: flashcardContent
                    case .fillBlank: fillBlankContent
                    case .audio:     audioContent
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Spacer(minLength: 0)

            if revealed {
                gradeButtons
            } else {
                revealButton
            }
        }
        .padding(.bottom, 16)
        .onAppear { if mode == .audio { clip.play(audioURL) } }
        .task(id: useSimpleMeaning) { await loadSimpleIfNeeded() }
    }

    // MARK: Mode content

    // Meaning recall: the ayah is shown (script per the user's preference), the
    // user recalls what it means. A tap-to-play button offers the recitation as a
    // recall aid (no autoplay).
    private var flashcardContent: some View {
        VStack(spacing: 18) {
            promptScript

            audioButton

            if revealed {
                Divider()
                meaningToggle
                meaningText
                // When the prompt itself isn't already showing the transliteration,
                // surface it on reveal as a pronunciation aid.
                if cardScript == .arabic && !card.transliteration.isEmpty {
                    Text(card.transliteration)
                        .font(.system(size: cardTransliterationFontSize)).italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                hint("Recall what this means, then reveal.")
            }
        }
    }

    /// The ayah as shown on a card — Arabic, transliteration, or both, at the
    /// configured sizes. Falls back to Arabic if a transliteration isn't available.
    @ViewBuilder
    private var promptScript: some View {
        let showArabic = cardScript.showsArabic || card.transliteration.isEmpty
        let showTranslit = cardScript.showsTransliteration && !card.transliteration.isEmpty
        VStack(spacing: 10) {
            if showArabic {
                Text(card.arabic)
                    .font(.system(size: cardArabicFontSize))
                    .environment(\.layoutDirection, .rightToLeft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(10)
            }
            if showTranslit {
                Text(card.transliteration)
                    .font(.system(size: cardTransliterationFontSize))
                    .italic()
                    .foregroundStyle(showArabic ? .secondary : .primary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// A compact recitation toggle, used on the meaning-recall card so the audio
    /// can be heard on demand.
    private var audioButton: some View {
        Button { isPlaying ? clip.stop() : clip.play(audioURL) } label: {
            Label(isPlaying ? "Stop" : "Play recitation",
                  systemImage: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.brand)
        }
        .buttonStyle(.plain)
    }

    private var fillBlankContent: some View {
        let wordFont = fillBlankUsesTranslit ? cardTransliterationFontSize : cardArabicFontSize
        return VStack(spacing: 18) {
            FlowLayout(spacing: 6, lineSpacing: 14, rightToLeft: !fillBlankUsesTranslit) {
                ForEach(Array(fillBlankWords.enumerated()), id: \.offset) { idx, word in
                    if idx == blankIndex && !revealed {
                        Text("ـــــ")
                            .font(.system(size: wordFont))
                            .foregroundStyle(.brand)
                    } else {
                        Text(word)
                            .font(.system(size: wordFont))
                            .italic(fillBlankUsesTranslit)
                            .foregroundStyle(idx == blankIndex ? .brand : .primary)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            gapAudioButton

            if revealed {
                Divider()
                // Reveal the alternate script so "Both" and "Transliteration" still
                // surface the Arabic (or vice-versa) once the answer is shown.
                if fillBlankUsesTranslit {
                    Text(card.arabic)
                        .font(.system(size: cardArabicFontSize))
                        .environment(\.layoutDirection, .rightToLeft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(10)
                } else if cardScript == .both && !card.transliteration.isEmpty {
                    Text(card.transliteration)
                        .font(.system(size: cardTransliterationFontSize)).italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                let useTranslitHint = fillBlankUseTransliteration && cardScript == .arabic
                    && !card.transliteration.isEmpty
                let hintText = useTranslitHint ? card.transliteration : displayedMeaning
                if !hintText.isEmpty {
                    Text(hintText)
                        .font(.callout)
                        .italic(useTranslitHint)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                hint("Listen for the gap, recall the missing word, then reveal.")
            }
        }
        .onAppear {
            blankIndex = fillBlankWords.indices.randomElement() ?? 0
            Task { await prepareGapAudio() }
        }
        .onChange(of: revealed) { _, nowRevealed in
            if nowRevealed { playFullAyah() }   // full recitation once the answer is shown
        }
        .onDisappear { GapClipPlayer.shared.stop() }
    }

    /// Plays the ayah with the hidden word silenced (before reveal) or in full
    /// (after reveal), using the word-by-word timings. Hidden if timings aren't
    /// available so the card still works offline.
    @ViewBuilder
    private var gapAudioButton: some View {
        if gapTimings?.verseTimestamps[card.ayah] != nil {
            Button {
                if gap.isActive { GapClipPlayer.shared.stop() }
                else if revealed { playFullAyah() }
                else { playGapAudio() }
            } label: {
                Label(gap.isActive ? "Stop"
                        : (revealed ? "Play full ayah" : "Play with gap"),
                      systemImage: gap.isActive ? "stop.circle.fill" : "play.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.brand)
            }
            .buttonStyle(.plain)
        }
    }

    private var audioContent: some View {
        VStack(spacing: 18) {
            Button { isPlaying ? clip.stop() : clip.play(audioURL) } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 66))
                    .foregroundStyle(.brand)
            }
            .buttonStyle(.plain)

            Text(isPlaying ? "Listening…" : "Tap to replay")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if revealed {
                Divider()
                promptScript
                if !displayedMeaning.isEmpty {
                    Text(displayedMeaning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                hint("Recite from memory, then reveal.")
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.tertiary)
    }

    // MARK: Meaning (translation ⟷ simple)

    /// The meaning to reveal: the simple edition when the user has the "Simple"
    /// toggle on and it has loaded, otherwise the card's stored translation.
    private var displayedMeaning: String {
        if useSimpleMeaning, let simpleText, !simpleText.isEmpty { return simpleText }
        return card.translation
    }

    /// Switches the revealed meaning between the user's reading translation and a
    /// deliberately simple edition. The choice is global (persisted), so it
    /// carries across cards and the other drill styles too.
    private var meaningToggle: some View {
        Picker("Meaning", selection: $useSimpleMeaning) {
            Text("Translation").tag(false)
            Text("Simple").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
    }

    @ViewBuilder private var meaningText: some View {
        if useSimpleMeaning && loadingSimple && simpleText == nil {
            ProgressView().padding(.vertical, 6)
        } else {
            VStack(spacing: 4) {
                Text(displayedMeaning.isEmpty ? "(no translation)" : displayedMeaning)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                if useSimpleMeaning {
                    Text(simpleText != nil
                         ? Translation.simpleMeaningName
                         : "Simple unavailable offline — showing your translation")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    /// Fetches the simple-meaning text once per card when the toggle is on. On
    /// failure `simpleText` stays nil, so `displayedMeaning` falls back to the
    /// card's stored translation and the caption says so (e.g. offline).
    private func loadSimpleIfNeeded() async {
        guard useSimpleMeaning, simpleText == nil, !loadingSimple else { return }
        loadingSimple = true
        simpleText = await QuranAPIService.shared.fetchSimpleMeaning(surah: card.surah, ayah: card.ayah)
        loadingSimple = false
    }

    // MARK: Fill-in-the-blank gap audio

    /// Loads this ayah's word/verse timings (cached per surah) and, if the answer
    /// isn't already showing, auto-plays the recitation with the hidden word
    /// silenced. Failures are swallowed so the card still works without audio.
    private func prepareGapAudio() async {
        if gapTimings == nil {
            let ayah = Ayah(numberInSurah: card.ayah, globalNumber: 0,
                            arabic: card.arabic, translation: card.translation,
                            transliteration: card.transliteration)
            gapTimings = try? await WordTimingService.shared.timings(surah: card.surah, ayahs: [ayah])
        }
        if !revealed { playGapAudio() }
    }

    /// The verse range and the blanked word's mute window, if timings are loaded.
    private func gapWindow() -> (from: Int, to: Int, muteFrom: Int?, muteTo: Int?)? {
        guard let data = gapTimings, let verse = data.verseTimestamps[card.ayah] else { return nil }
        // WordTiming.id is the 1-based word index within the ayah, matching blankIndex+1.
        let blanked = (data.wordTimings[card.ayah] ?? []).first { $0.id == blankIndex + 1 }
        return (verse.fromMs, verse.toMs, blanked?.startMs, blanked?.endMs)
    }

    private func playGapAudio() {
        guard let w = gapWindow(), let url = gapTimings?.chapterAudioUrl else { return }
        GapClipPlayer.shared.play(url: url, fromMs: w.from, toMs: w.to,
                                  muteFromMs: w.muteFrom, muteToMs: w.muteTo)
    }

    private func playFullAyah() {
        guard let w = gapWindow(), let url = gapTimings?.chapterAudioUrl else { return }
        GapClipPlayer.shared.play(url: url, fromMs: w.from, toMs: w.to)
    }

    // MARK: Controls

    private var revealButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { revealed = true }
        } label: {
            Text("Show Answer")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.brand)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private var gradeButtons: some View {
        HStack(spacing: 10) {
            ForEach(ReviewGrade.allCases, id: \.self) { grade in
                Button {
                    Haptics.tap()
                    onGrade(grade)
                } label: {
                    Text(grade.label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(grade.tint.opacity(0.18))
                        .foregroundStyle(grade.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}
