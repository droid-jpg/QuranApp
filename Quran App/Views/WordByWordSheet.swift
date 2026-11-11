import SwiftUI

/// Word by word (REDESIGN §3.7): the ayah's words as tappable chips, laid out
/// right to left. A tap hears the word. With "Repeat selected words" on, the
/// first tap picks a word (alone, it repeats by itself), a second tap makes the
/// range first-to-second, and a third starts over. The selection repeats until the
/// switch goes off or the sheet closes; both hand the main player back paused on
/// the ayah it was on.
///
/// A leaf: it follows the surah's model (timings, word details) and the audio
/// service itself, so the reader behind it is never re-rendered.
struct WordByWordSheet: View {
    let ref: ReaderAyahRef
    @ObservedObject var model: SurahDetailViewModel

    @EnvironmentObject private var audioService: AudioService
    @Environment(\.dismiss) private var dismiss

    @State private var repeating = false
    /// The selected word ids (1-based positions), and whether the next tap
    /// completes the range (true right after a first word).
    @State private var selection: ClosedRange<Int>?
    @State private var awaitingLast = false
    /// Set once the first timings load has finished, so an empty result reads as
    /// an error and not as "still loading".
    @State private var attempted = false

    private var type = ReadingType()

    init(ref: ReaderAyahRef, model: SurahDetailViewModel) {
        self.ref = ref
        _model = ObservedObject(wrappedValue: model)
    }

    private var n: Int { ref.ayah.numberInSurah }
    private var timings: [WordTiming] { model.wordTimingsByAyah[n] ?? [] }
    private var details: [WordDetail] { model.wordDetailsByAyah[n] ?? [] }
    private var isLoading: Bool { model.isLoadingWordTimings || (!attempted && timings.isEmpty) }
    private var failed: Bool { !isLoading && timings.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.sm)
            Hairline()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.surfaceRaised)
        .tint(Palette.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.surfaceRaised)
        .task {
            await model.loadWordTimingsIfNeeded()
            attempted = true
        }
        .onChange(of: audioService.wordRepeat) { _, new in
            // Something else took over playback (lock screen, CarPlay): the
            // repeat is over, so the switch must say so.
            if new == nil, repeating, selection != nil { endSelection() }
        }
        // Done, a swipe down, or anything else that closes the sheet.
        .onDisappear {
            ClipPlayer.shared.stop()
            audioService.stopWordLoop(resume: false)
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Word by word")
                    .font(type.serif(22, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("\(ref.surah.englishName) · Ayah \(n)")
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.xs)
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .fixedSize()
                    .frame(minWidth: MinSize.hitTarget, minHeight: MinSize.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: Spacing.sm) {
                ProgressView().tint(Palette.accent)
                Text("Loading words")
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if failed {
            VStack(spacing: Spacing.sm) {
                Text("Couldn't load word timings")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textPrimary)
                Button {
                    Haptics.tap()
                    attempted = false
                    Task {
                        await model.loadWordTimingsIfNeeded()
                        attempted = true
                    }
                } label: {
                    Text("Try again")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, Spacing.md)
                        .frame(minHeight: MinSize.hitTarget)
                        .overlay(Rectangle().strokeBorder(Palette.accent, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Toggle("Repeat selected words", isOn: repeatBinding)
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.textPrimary)
                        .tint(Palette.accent)
                        .frame(minHeight: MinSize.hitTarget)

                    FlowLayout(spacing: Spacing.xs, lineSpacing: Spacing.xs, rightToLeft: true) {
                        ForEach(timings) { word in
                            chip(word)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func chip(_ word: WordTiming) -> some View {
        let selected = selection?.contains(word.id) ?? false
        let meaning = meaning(of: word)
        return Button {
            Haptics.tap()
            tap(word)
        } label: {
            VStack(spacing: Spacing.xxs) {
                Text(word.arabicText.isEmpty ? "—" : word.arabicText)
                    .font(type.arabic(24))
                    .foregroundStyle(selected ? Palette.onAccent : Palette.textPrimary)
                    .environment(\.layoutDirection, .rightToLeft)
                if !meaning.isEmpty {
                    Text(meaning)
                        .font(TypeScale.caption)
                        .foregroundStyle(selected ? Palette.onAccent : Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(minWidth: MinSize.hitTarget, maxWidth: 190, minHeight: MinSize.hitTarget)
            .background(Rectangle().fill(selected ? Palette.accent : Palette.surface))
            .overlay(Rectangle().strokeBorder(selected ? Palette.accent : Palette.separator, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(meaning.isEmpty ? word.arabicText : "\(word.arabicText), \(meaning)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The word's meaning once word details are loaded; its transliteration
    /// (from the timings) until then.
    private func meaning(of word: WordTiming) -> String {
        if let d = details.first(where: { $0.position == word.id }), !d.translation.isEmpty {
            return d.translation
        }
        return word.transliteration
    }

    // MARK: Behaviour

    private var repeatBinding: Binding<Bool> {
        Binding(
            get: { repeating },
            set: { on in
                Haptics.selection()
                repeating = on
                if on {
                    ClipPlayer.shared.stop()
                } else {
                    endSelection()
                }
            }
        )
    }

    /// Switch off or the repeat ended elsewhere: clear the selection and hand
    /// the main player back, paused on the ayah it was on.
    private func endSelection() {
        repeating = false
        selection = nil
        awaitingLast = false
        audioService.stopWordLoop(resume: false)
    }

    private func tap(_ word: WordTiming) {
        guard repeating else { hear(word); return }
        if awaitingLast, let first = selection?.lowerBound {
            selection = min(first, word.id)...max(first, word.id)
            awaitingLast = false
        } else {
            selection = word.id...word.id
            awaitingLast = true
        }
        startRepeat()
    }

    /// Plays just this word. Main playback pauses first, so the two never overlap.
    private func hear(_ word: WordTiming) {
        guard let url = model.chapterAudioUrl() else { return }
        if audioService.isPlaying, !audioService.isWordLooping { audioService.togglePlayPause() }
        ClipPlayer.shared.play(url: url, fromMs: word.startMs, toMs: word.endMs)
    }

    private func startRepeat() {
        guard let range = selection, let url = model.chapterAudioUrl(),
              let first = timings.first(where: { $0.id == range.lowerBound }),
              let last = timings.first(where: { $0.id == range.upperBound }) else { return }
        ClipPlayer.shared.stop()
        audioService.startWordLoop(
            surah: ref.surah.number, ayah: n, chapterUrl: url,
            wordStartMs: first.startMs, wordEndMs: last.endMs,
            fromWord: first.id, toWord: last.id,
            totalAyahs: ref.surah.numberOfAyahs, surahName: ref.surah.englishName
        )
    }
}
