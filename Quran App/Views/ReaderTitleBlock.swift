import SwiftUI

// The reader's title block (REDESIGN §3.3.2): the surah name, one line of
// metadata, one Play/Pause button, then the Basmala where the surah has one.

/// The title block with its button tied to the player. The only part of the
/// block that observes the audio service, so a play/pause re-runs this and the
/// block's comparison, not the page.
struct ReaderTitleSlot: View {
    let surah: Surah
    let onPlayFromStart: () -> Void
    @EnvironmentObject private var audioService: AudioService

    var body: some View {
        ReaderTitleBlock(
            surah: surah,
            isPlaying: audioService.currentSurah == surah.number && audioService.isPlaying,
            onPlay: { [audioService, surah] in
                if audioService.currentSurah == surah.number, audioService.currentAyah != nil {
                    audioService.togglePlayPause()
                } else {
                    onPlayFromStart()
                }
            }
        )
        .equatable()
    }
}

/// "Al-Faatiha" · "The Opening · Meccan · 7 ayahs" · Play. Compact, so the
/// first ayah starts high on the page.
struct ReaderTitleBlock: View, Equatable {
    let surah: Surah
    var isPlaying: Bool = false
    var onPlay: () -> Void = {}
    /// Read during body, so a change of face or script repaints the block.
    private var type = ReadingType()

    init(surah: Surah, isPlaying: Bool = false, onPlay: @escaping () -> Void = {}) {
        self.surah = surah
        self.isPlaying = isPlaying
        self.onPlay = onPlay
    }

    /// `onPlay` is left out: it only ever sends the same command.
    nonisolated static func == (lhs: ReaderTitleBlock, rhs: ReaderTitleBlock) -> Bool {
        lhs.surah.number == rhs.surah.number && lhs.isPlaying == rhs.isPlaying
    }

    static let basmala = "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ"

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(surah.englishName)
                .font(TypeScale.title)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("\(surah.englishNameTranslation) · \(surah.revelationType) · \(surah.numberOfAyahs) ayahs")
                .font(TypeScale.secondary)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)

            playButton
                .padding(.top, Spacing.xs)

            if surah.number != 1 && surah.number != 9 {
                Text(Self.basmala)
                    .font(type.arabic(22))
                    .lineSpacing(Spacing.xs)
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, Spacing.md)
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity)
    }

    /// One filled button: Play, or Pause while this surah is playing.
    private var playButton: some View {
        Button {
            Haptics.tap()
            onPlay()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(isPlaying ? "Pause" : "Play")
            }
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, Spacing.lg)
            .frame(minWidth: 120, minHeight: MinSize.hitTarget)
            .background(Capsule().fill(Palette.accent))
            .contentShape(Capsule())
            .animation(Motion.quick, value: isPlaying)
        }
        .buttonStyle(CardButtonStyle(scale: 0.95))
    }
}

/// The loading state: the title block is real (the surah is known), the ayahs
/// are three grey placeholders.
struct AyahSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Circle()
                .strokeBorder(Palette.separator, lineWidth: 1)
                .frame(width: 34, height: 34)
                .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)
            VStack(alignment: .trailing, spacing: Spacing.sm) {
                bar.frame(height: 22)
                bar.frame(height: 22).padding(.leading, Spacing.xxl)
                bar.frame(height: 14).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, Spacing.xl)
                bar.frame(height: 14)
            }
            .padding(.top, Spacing.xxs)
            .padding(.trailing, Spacing.screenMargin)
        }
        .padding(.leading, Spacing.xxs)
        .padding(.vertical, Spacing.md)
        .accessibilityHidden(true)
    }

    private var bar: some View {
        Rectangle().fill(Palette.separator)
    }
}
