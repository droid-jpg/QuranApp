import SwiftUI
import Combine
import UIKit

// The surah row with a play button (REDESIGN §3.2), shared by the Quran tab, the
// Juz sheet and Today. Screens hold only the plain `audioServiceRef`; the row and
// its button read playback through `SurahPlaybackState`, a deduplicated summary
// of the service, so an ayah advance re-renders no row and a play/pause or a
// change of surah re-renders only the few rows on screen.

// MARK: - Playback state for rows

/// What a row needs to know about the player, and nothing that changes per ayah:
/// which surah is loaded, whether it is playing or waiting for audio, and whether
/// its audio failed. Bound once at launch (`bind(to:)`), then published only when
/// one of these four values changes.
@MainActor
final class SurahPlaybackState: ObservableObject {
    static let shared = SurahPlaybackState()

    struct Snapshot: Equatable {
        /// The surah loaded in the player; 0 when nothing is loaded.
        var loadedSurah = 0
        var isPlaying = false
        var isBuffering = false
        var failed = false
    }

    @Published private(set) var snapshot = Snapshot()
    private var binding: AnyCancellable?

    private init() {}

    func bind(to audio: AudioService) {
        guard binding == nil else { return }
        binding = Publishers.CombineLatest(
            Publishers.CombineLatest3(audio.$currentAyah, audio.$currentSurah, audio.$failedAyah),
            Publishers.CombineLatest(audio.$isPlaying, audio.$isBuffering)
        )
        .map { loaded, flags in
            Snapshot(loadedSurah: loaded.0 == nil ? 0 : loaded.1,
                     isPlaying: flags.0, isBuffering: flags.1, failed: loaded.2 != nil)
        }
        .removeDuplicates()
        .sink { [weak self] in self?.snapshot = $0 }
    }

    func isPlaying(surah: Int) -> Bool { snapshot.loadedSurah == surah && snapshot.isPlaying }
    func isLoading(surah: Int) -> Bool { isPlaying(surah: surah) && snapshot.isBuffering }
}

// MARK: - Commands

/// What a row's play button does. Pure commands on the service; no observation.
@MainActor
enum SurahPlayer {
    /// Tap on a surah's play button:
    /// - this surah is loaded: play/pause;
    /// - it is the restored session (paused, nothing loaded): resume it;
    /// - `resume` is given (a Recent row): resume that position and repeat;
    /// - otherwise: start at `startAyah`, or ayah 1.
    /// An explicit `startAyah` (a juz) never resumes a saved position.
    static func toggle(_ surah: Surah, startAyah: Int? = nil, resume: ListeningSession? = nil,
                       audio: AudioService) {
        Haptics.tap()
        let engine = PlayerEngine(audioService: audio)
        if audio.currentAyah != nil, audio.currentSurah == surah.number {
            engine.playPause()
        } else if audio.currentAyah == nil, startAyah == nil,
                  ListeningSessionStore.shared.session?.surah == surah.number {
            engine.playPause()
        } else if let resume, startAyah == nil {
            audio.resume(resume)
        } else {
            audio.play(surah: surah.number, startAyah: startAyah ?? 1,
                       totalAyahs: surah.numberOfAyahs, surahName: surah.englishName)
        }
    }
}

// MARK: - Row

/// 64 pt minimum. Leading number, title and subtitle (with a "downloaded" glyph),
/// then the Arabic name and a 44 pt play button. Tapping the text opens; the play
/// button is a sibling, so neither swallows the other's tap.
struct SurahRow: View {
    let leading: String
    let title: String
    let subtitle: String
    let arabic: String
    var downloaded = false
    /// The surah whose playback state the play button shows.
    let playSurah: Int
    /// Names the button: "Play Al-Baqara", "Play Juz 30".
    let playName: String
    let onOpen: () -> Void
    let onPlay: () -> Void

    @ObservedObject private var playback = SurahPlaybackState.shared
    // Declared so rows follow a change of reading face or script.
    @AppStorage("readingFace")  private var readingFace = ReadingFace.newYork.rawValue
    @AppStorage("arabicScript") private var arabicScript = ArabicScript.system.rawValue

    /// The name without its leading "سورة" ("surah of"), which every row would
    /// otherwise repeat and which squeezes the subtitle onto extra lines.
    static func shortArabic(_ name: String) -> String {
        let parts = name.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return name }
        let bare = parts[0].unicodeScalars.filter { !(0x064B...0x0670).contains($0.value) && $0.value != 0x0671 }
        let first = String(String.UnicodeScalarView(bare))
        return (first == "سورة" || first == "سور") ? String(parts[1]) : name
    }

    private var playing: Bool { playback.isPlaying(surah: playSurah) }
    private var loading: Bool { playback.isLoading(surah: playSurah) }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: Spacing.sm) {
                    Text(leading)
                        .font(TypeScale.secondary.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 28, alignment: .leading)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(TypeScale.rowTitle)
                            .foregroundStyle(playing ? Palette.accent : Palette.textPrimary)
                            .multilineTextAlignment(.leading)
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                            Text(subtitle)
                                .font(TypeScale.secondary)
                                .foregroundStyle(Palette.textSecondary)
                                .multilineTextAlignment(.leading)
                            if downloaded {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(TypeScale.secondary)
                                    .foregroundStyle(Palette.accent)
                                    .accessibilityLabel("Downloaded")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(Self.shortArabic(arabic))
                        .font(TypeScale.arabicList)
                        .foregroundStyle(Palette.textPrimary)
                        .environment(\.layoutDirection, .rightToLeft)
                        .fixedSize()
                }
                .padding(.vertical, Spacing.xs)
                .frame(minHeight: MinSize.surahRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onPlay) {
                ZStack {
                    if loading {
                        Circle().strokeBorder(Palette.accent.opacity(0.55), lineWidth: 1)
                        ProgressView().tint(Palette.accent)
                    } else {
                        PlayCircle(playing: playing, size: MinSize.listPlayButton)
                    }
                }
                .frame(width: MinSize.listPlayButton, height: MinSize.listPlayButton)
                .animation(Motion.quick, value: playing)
                .animation(Motion.quick, value: loading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, Spacing.sm)
            .accessibilityLabel("\(playing ? "Pause" : "Play") \(playName)")
        }
    }
}

/// The row for a surah, with the usual subtitle ("The Cow · 286 ayahs") unless a
/// screen gives its own (Today's "Ayah 142"). Observes the download list for the
/// glyph, so a finished download shows without the screen re-rendering.
struct SurahRowView: View {
    let surah: Surah
    var subtitle: String?
    /// Position to resume from when this surah isn't the one in the player (Today's Recent).
    var resume: ListeningSession?
    let onOpen: () -> Void

    @Environment(\.audioServiceRef) private var audioService
    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        SurahRow(
            leading: "\(surah.number)",
            title: surah.englishName,
            subtitle: subtitle ?? "\(surah.englishNameTranslation) · \(surah.numberOfAyahs) ayahs",
            arabic: surah.name,
            downloaded: downloads.isDownloaded(surah.number),
            playSurah: surah.number,
            playName: surah.englishName,
            onOpen: onOpen,
            onPlay: {
                guard let audioService else { return }
                SurahPlayer.toggle(surah, resume: resume, audio: audioService)
            }
        )
    }
}

// MARK: - Error banner

/// "Couldn't play Al-Baqara. Try again", above the mini player, while the loaded
/// ayah's audio has failed. Tapping it retries. A leaf: it alone observes the
/// player's state.
struct PlaybackErrorBanner: View {
    @Environment(\.audioServiceRef) private var audioService
    @ObservedObject private var playback = SurahPlaybackState.shared

    var body: some View {
        if playback.snapshot.failed, let audioService {
            let name = audioService.currentSurahName.isEmpty
                ? "Surah \(audioService.currentSurah)" : audioService.currentSurahName
            Button {
                Haptics.tap()
                PlayerEngine(audioService: audioService).playPause()
            } label: {
                Text("Couldn’t play \(name). Try again")
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.vertical, Spacing.sm)
                    .frame(minHeight: MinSize.hitTarget)
                    .opaqueBar(Palette.surfaceRaised, hairline: .top)
            }
            .buttonStyle(.plain)
        }
    }
}
