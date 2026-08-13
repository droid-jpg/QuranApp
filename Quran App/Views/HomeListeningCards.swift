import SwiftUI

// The listening layer, restyled as editorial blocks: a "now playing" section
// ruled off from the rest of the page, a row of outlined one-tap starts, and a
// docked bar so audio never has to leave the tab. No cards, no fills — the
// accent survives as a mark on the scrub line and the play circle.

// MARK: - Now playing / resume

/// "Pick up where you stopped" — the exact surah, ayah, reciter and position the
/// last listening session ended on, one tap from sound. Reads live values off
/// `AudioService` whenever that session is still the thing playing, so the block
/// doubles as the now-playing surface instead of contradicting it.
struct ResumeListeningSection: View {
    let session: ListeningSession
    let surahs: [Surah]
    @ObservedObject var audioService: AudioService
    let onToggle: () -> Void

    /// True when the saved session *is* what the player currently holds.
    private var isLive: Bool {
        audioService.currentAyah != nil && audioService.currentSurah == session.surah
    }
    private var ayah: Int { isLive ? (audioService.currentAyah ?? session.ayah) : session.ayah }
    private var playing: Bool { isLive && audioService.isPlaying }

    private var surahName: String {
        if !session.surahName.isEmpty { return session.surahName }
        return surahs.first { $0.number == session.surah }?.englishName ?? "Surah \(session.surah)"
    }
    private var startIndex: Int? {
        surahs.firstIndex { $0.number == session.surah }
    }

    /// The block doubles as the now-playing surface, so the eyebrow has to stop
    /// promising a resume once the thing is already running. Kept to one or two
    /// words — the surah name underneath is the thing worth reading.
    private var eyebrow: String {
        guard isLive else { return "Resume" }
        return playing ? "Now playing" : "Paused"
    }

    private var eyebrowIcon: String {
        guard isLive else { return "arrow.counterclockwise" }
        return playing ? "waveform" : "pause.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline().padding(.bottom, 16)

            HStack(alignment: .top, spacing: 18) {
                Group {
                    if let idx = startIndex {
                        NavigationLink {
                            SurahPageView(surahs: surahs, startIndex: idx, initialAyah: ayah)
                        } label: { details }
                            .buttonStyle(.plain)
                            .hapticTap()
                    } else {
                        details
                    }
                }

                Button(action: onToggle) {
                    PlayCircle(playing: playing, size: 54)
                        .padding(.top, 6)
                }
                .buttonStyle(CardButtonStyle(scale: 0.92))
                .accessibilityLabel(playing ? "Pause" : "Resume listening")
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: eyebrowIcon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.brand)
                    .frame(width: 14, alignment: .leading)
                Eyebrow(eyebrow, tint: .brand)
            }

            Text(surahName)
                .font(.appSerif(24, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.top, 7)

            Text("Ayah \(ayah) · \(session.reciterName)")
                .font(.appSerif(14))
                .foregroundStyle(Color(.label).opacity(0.52))
                .lineLimit(1)
                .padding(.top, 3)

            // Its own view, observing the clock rather than the service: the
            // playhead ticks ten times a second, and only this line should
            // redraw when it does.
            LivePosition(clock: audioService.clock,
                         fallbackFraction: session.fraction,
                         fallbackDuration: session.duration,
                         isLive: isLive)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Live playhead

/// The resume block's scrub line and elapsed/total. Split out so the ten-times-a-
/// second playhead only invalidates this line, never the whole dashboard.
private struct LivePosition: View {
    @ObservedObject var clock: PlaybackClock
    let fallbackFraction: Double
    let fallbackDuration: Double
    let isLive: Bool

    private var fraction: Double { isLive ? clock.progress : fallbackFraction }
    private var duration: Double { isLive ? clock.duration : fallbackDuration }

    var body: some View {
        HStack(spacing: 10) {
            ScrubLine(fraction: fraction)
            if duration > 0 {
                MetaText("\(clockString(duration * fraction)) / \(clockString(duration))")
            }
        }
    }
}

// MARK: - Scrub line

/// The 1.5pt playhead: a ruled track, an accent fill and a dot at the position.
/// Replaces the decorative waveform — a ruled page wants a rule, not bars.
struct ScrubLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            let f = min(1, max(0, fraction))
            // `.leading` centres vertically, so the two 1.5pt rules sit on the
            // same axis as the playhead dot without any manual offset.
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.label).opacity(0.16))
                    .frame(height: 1.5)
                Rectangle()
                    .fill(Color.brand)
                    .frame(width: geo.size.width * f, height: 1.5)
                Circle()
                    .fill(Color.brand)
                    .frame(width: 6.5, height: 6.5)
                    .offset(x: max(0, geo.size.width * f - 3.25))
            }
            .frame(maxHeight: .infinity)
            .animation(.linear(duration: 0.25), value: fraction)
        }
        .frame(height: 7)
    }
}

// MARK: - Quick-start row

/// One-tap starts for when there's no thread to resume: today's verse, the loop
/// that was last running, and the juz most people actually listen through.
struct QuickStartRail: View {
    let items: [QuickStart]

    struct QuickStart: Identifiable {
        let id: String
        let label: String
        /// SF Symbol; `nil` renders a text-only chip (e.g. "Juz 30").
        var icon: String? = nil
        var tint: Color? = nil
        let action: () -> Void
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    OutlineChip(label: item.label, icon: item.icon, tint: item.tint, action: item.action)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Home mini player

/// The docked now-playing bar. Home gets audio controls of its own so starting,
/// pausing and resuming never require a trip to the Quran tab.
struct HomeMiniPlayer: View {
    @ObservedObject var audioService: AudioService
    let surahs: [Surah]

    private var ayah: Int { audioService.currentAyah ?? 1 }
    private var surahName: String {
        if !audioService.currentSurahName.isEmpty { return audioService.currentSurahName }
        return surahs.first { $0.number == audioService.currentSurah }?.englishName
            ?? "Surah \(audioService.currentSurah)"
    }
    private var subtitle: String {
        let loop = audioService.loopSettings
        switch loop.mode {
        case .off:     return loop.listenAndRepeat ? "Ayah \(ayah) · listen & repeat" : "Ayah \(ayah)"
        case .single:  return loop.listenAndRepeat ? "Ayah \(ayah) · repeat after" : "Ayah \(ayah) · looping"
        case .segment: return "Ayah \(ayah) · chaining \(loop.startAyah)–\(loop.endAyah)"
        }
    }
    private var startIndex: Int? {
        surahs.firstIndex { $0.number == audioService.currentSurah }
    }

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let idx = startIndex {
                    NavigationLink {
                        SurahPageView(surahs: surahs, startIndex: idx, initialAyah: ayah)
                    } label: { label }
                        .buttonStyle(.plain)
                } else {
                    label
                }
            }

            Button {
                Haptics.tap()
                audioService.togglePlayPause()
            } label: {
                PlayCircle(playing: audioService.isPlaying, size: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(audioService.isPlaying ? "Pause" : "Play")

            Button {
                Haptics.tap()
                audioService.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(.label).opacity(0.45))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop playback")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(Rectangle().strokeBorder(Color(.label).opacity(0.16), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var label: some View {
        HStack(spacing: 12) {
            if audioService.isPlaying {
                PlayingIndicatorView(color: .brand)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.brand)
                    .frame(width: 20, height: 14)
            }
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(surahName, tint: .brand, size: 9)
                Text(subtitle)
                    .font(.appSerif(14))
                    .foregroundStyle(Color(.label).opacity(0.75))
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Helpers

func clockString(_ seconds: Double) -> String {
    let t = Int(max(0, seconds).rounded(.down))
    return "\(t / 60):" + String(format: "%02d", t % 60)
}
