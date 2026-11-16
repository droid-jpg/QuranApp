import SwiftUI

/// Everything one ayah can do (REDESIGN §3.7): a header, four buttons (Play,
/// Repeat, Bookmark, Share), three rows (Tafsir, Word by word, Add to
/// memorization) and "More repeat options". Opaque, sized to its content.
///
/// A leaf: it observes the audio service (for the Repeat label), the bookmark
/// and memorization stores and the surah's model itself, so opening it or
/// acting in it never re-renders the reader's rows.
struct AyahActionsSheet: View {
    let surah: Surah
    let ayah: Ayah
    @ObservedObject var model: SurahDetailViewModel
    /// Closes this sheet, then runs the step (another sheet, a dialog).
    let closeThen: (@escaping () -> Void) -> Void
    let onTafsir: () -> Void
    let onWordByWord: () -> Void
    let onAddToMemorization: () -> Void
    let onMoreRepeatOptions: () -> Void

    @EnvironmentObject private var audioService: AudioService
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var targetStore: MemorizationTargetStore
    @Environment(\.dismiss) private var dismiss

    @State private var contentHeight: CGFloat = 0
    @State private var detent: PresentationDetent = .medium
    private var type = ReadingType()

    init(surah: Surah, ayah: Ayah, model: SurahDetailViewModel,
         closeThen: @escaping (@escaping () -> Void) -> Void,
         onTafsir: @escaping () -> Void, onWordByWord: @escaping () -> Void,
         onAddToMemorization: @escaping () -> Void, onMoreRepeatOptions: @escaping () -> Void) {
        self.surah = surah
        self.ayah = ayah
        _model = ObservedObject(wrappedValue: model)
        self.closeThen = closeThen
        self.onTafsir = onTafsir
        self.onWordByWord = onWordByWord
        self.onAddToMemorization = onAddToMemorization
        self.onMoreRepeatOptions = onMoreRepeatOptions
    }

    private var n: Int { ayah.numberInSurah }
    private var repeatAction: RepeatState.AyahAction {
        audioService.repeatState.ayahAction(surah: surah.number, ayah: n)
    }
    private var isBookmarked: Bool { bookmarkStore.isBookmarked(surah: surah.number, ayah: n) }
    private var hasTafsir: Bool { model.tafsirByAyah[n] != nil }
    private var isInMemorization: Bool {
        AyahMemorization.isTracked(surah: surah.number, srStore: srStore, targetStore: targetStore)
            && srStore.isScheduled(surah: surah.number, ayah: n)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                buttons
                rows
                moreRepeat
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.surfaceRaised)
        .tint(Palette.accent)
        .presentationDetents(fitDetents, selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: fitDetents) { _, new in
            if !new.contains(detent) { detent = new.first { $0 != .large } ?? .large }
        }
        // Opaque: the reader must not show through (AUDIT #21).
        .presentationBackground(Palette.surfaceRaised)
    }

    private var fitDetents: Set<PresentationDetent> {
        guard contentHeight > 0 else { return [.medium, .large] }
        return [.height(contentHeight), .large]
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(surah.englishName) · Ayah \(n)")
                .font(TypeScale.rowTitle)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(ayah.arabic)
                .font(type.arabic(22))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .environment(\.layoutDirection, .rightToLeft)
                // The frame sits outside the right-to-left text, so trailing is
                // the right edge: the Arabic line starts at the right.
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(ayah.translation)
                .font(TypeScale.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
    }

    private var buttons: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            actionButton("Play", icon: "play.fill") {
                closeThen { [audioService, model] in
                    audioService.stopWordLoop(resume: false)
                    if audioService.currentSurah == model.surah.number, audioService.currentAyah == n {
                        if !audioService.isPlaying { audioService.togglePlayPause() }
                    } else {
                        model.playAyah(n, audioService: audioService)
                    }
                }
            }

            if repeatAction == .repeatAyah {
                // Tap loops this ayah forever; press and hold for ×3 / ×5.
                Menu {
                    ForEach(RepeatState.quickTimes) { t in
                        Button(t.loopLabel) { Haptics.tap(); applyRepeat(.repeatAyah, times: t) }
                    }
                } label: {
                    actionLabel(repeatAction.label, icon: "repeat", on: false)
                } primaryAction: {
                    Haptics.tap()
                    applyRepeat(.repeatAyah)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Loops this ayah. Hold for 3 or 5 times.")
            } else {
                actionButton(repeatAction.label,
                             icon: repeatAction == .stop ? "xmark.circle" : "repeat") {
                    applyRepeat(repeatAction)
                }
            }

            actionButton(isBookmarked ? "Bookmarked" : "Bookmark",
                         icon: isBookmarked ? "bookmark.fill" : "bookmark",
                         on: isBookmarked) {
                bookmarkStore.toggle(
                    surahNumber: surah.number, surahName: surah.englishName,
                    surahArabicName: surah.name, ayahNumber: n,
                    arabic: ayah.arabic, translation: ayah.translation
                )
            }

            Menu {
                ShareLink("Arabic only",
                          item: ayahShareText(ayah, surahName: surah.englishName))
                ShareLink("With translation",
                          item: ayahShareTextWithTranslation(ayah, surahName: surah.englishName))
            } label: {
                actionLabel("Share", icon: "square.and.arrow.up", on: false)
            }
            .buttonStyle(.plain)
        }
        // All four as tall as the tallest (a label may wrap to two lines).
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row("Tafsir", icon: "text.book.closed", enabled: hasTafsir) {
                closeThen(onTafsir)
            }
            Hairline()
            row("Word by word", icon: "text.word.spacing", enabled: true) {
                closeThen(onWordByWord)
            }
            Hairline()
            row(isInMemorization ? "Added to memorization" : "Add to memorization",
                icon: isInMemorization ? "checkmark.circle.fill" : "plus.circle",
                enabled: !isInMemorization) {
                closeThen(onAddToMemorization)
            }
        }
        .overlay(Rectangle().strokeBorder(Palette.separator, lineWidth: 1))
    }

    private var moreRepeat: some View {
        Button {
            Haptics.tap()
            closeThen(onMoreRepeatOptions)
        } label: {
            Text("More repeat options")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(maxWidth: .infinity, minHeight: MinSize.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Repeat

    /// Repeat starts this ayah (or collapses a range to it) and plays; extending
    /// keeps playing where it is when this surah is playing, else starts the
    /// range; Stop repeating turns repeat off and lets playback carry on.
    private func applyRepeat(_ action: RepeatState.AyahAction, times: RepeatState.Times? = nil) {
        var new = audioService.repeatState.applying(action, surah: surah.number, ayah: n)
        if let times { new.times = times }
        let playingHere = audioService.isPlaying && audioService.currentSurah == surah.number
        closeThen { [audioService, surah] in
            let extending = action == .repeatToHere || action == .repeatFromHere
            if action == .stop || (extending && playingHere) {
                audioService.setRepeat(new)
            } else {
                audioService.stopWordLoop(resume: false)
                audioService.startRepeat(new, totalAyahs: surah.numberOfAyahs, surahName: surah.englishName)
            }
        }
    }

    // MARK: Building blocks

    private func actionButton(_ title: String, icon: String, on: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            actionLabel(title, icon: icon, on: on)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ title: String, icon: String, on: Bool) -> some View {
        VStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Palette.accent)
                .frame(height: 28)
                .accessibilityHidden(true)
            Text(title)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                // Phrases wrap at a space; a single word shrinks a little instead
                // of being hyphenated ("Bookmarked").
                .lineLimit(title.contains(" ") ? 2 : 1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.xxs)
        .frame(maxWidth: .infinity, minHeight: MinSize.ayahActionButton, maxHeight: .infinity,
               alignment: .top)
        .frame(minWidth: MinSize.ayahActionButton)
        .background(Rectangle().fill(on ? Palette.highlight : Palette.surface))
        .overlay(Rectangle().strokeBorder(on ? Palette.accent : Palette.separator, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func row(_ title: String, icon: String, enabled: Bool,
                     action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(.body))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(title)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: MinSize.moreRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - Add to memorization

/// The one rule behind "Add to memorization": an ayah of a surah that is not yet
/// tracked starts memorizing there (the old "Memorize from here"); once the
/// surah is tracked the ayah goes into review (the old "Add to review").
enum AyahMemorization {
    /// Tracked = the active memorization target, or it already has review cards.
    static func isTracked(surah: Int, srStore: MemorizationSRStore,
                          targetStore: MemorizationTargetStore) -> Bool {
        targetStore.target?.surah == surah || srStore.goal(forSurah: surah) != nil
    }
}
