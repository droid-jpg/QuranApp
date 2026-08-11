import SwiftUI

// The listening layer Home gained in the 1b direction: a resume hero at the top,
// a rail of one-tap starts for when there's no thread to pick up, and a mini
// player that docks on the dashboard so audio never has to leave the tab.

// MARK: - Resume hero

/// "Pick up where you stopped" — the exact surah, ayah, reciter and position the
/// last listening session ended on, one tap from sound. Reads live values off
/// `AudioService` whenever that session is still the thing playing, so the card
/// doubles as the now-playing surface instead of contradicting it.
struct ResumeListeningCard: View {
    let session: ListeningSession
    let surahs: [Surah]
    @ObservedObject var audioService: AudioService
    let onToggle: () -> Void

    /// True when the saved session *is* what the player currently holds.
    private var isLive: Bool {
        audioService.currentAyah != nil && audioService.currentSurah == session.surah
    }
    private var ayah: Int { isLive ? (audioService.currentAyah ?? session.ayah) : session.ayah }
    private var fraction: Double { isLive ? audioService.progress : session.fraction }
    private var duration: Double { isLive ? audioService.duration : session.duration }
    private var playing: Bool { isLive && audioService.isPlaying }

    private var surahName: String {
        if !session.surahName.isEmpty { return session.surahName }
        return surahs.first { $0.number == session.surah }?.englishName ?? "Surah \(session.surah)"
    }
    private var startIndex: Int? {
        surahs.firstIndex { $0.number == session.surah }
    }

    /// The card doubles as the now-playing surface, so the eyebrow has to stop
    /// promising a resume once the thing is already running.
    private var eyebrow: String {
        guard isLive else { return "Pick up where you stopped" }
        return playing ? "Now playing" : "Paused"
    }

    var body: some View {
        HStack(spacing: 14) {
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
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.brandDeep)
                    .frame(width: 62, height: 62)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause" : "Resume listening")
        }
        .padding(18)
        .heroCard()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(eyebrow)
                    .font(.system(size: 10.5, weight: .bold))
                    .textCase(.uppercase)
                    .kerning(0.7)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if duration > 0 {
                    Text("\(clockString(max(0, duration - duration * fraction))) left")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }
            .padding(.bottom, 11)

            Text(surahName)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("Ayah \(ayah) · \(session.reciterName)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .padding(.top, 4)

            HStack(alignment: .bottom, spacing: 8) {
                MiniWaveform(fraction: fraction,
                             played: .white,
                             remaining: .white.opacity(0.35))
                    .frame(width: 92, height: 22)
                if duration > 0 {
                    Text("\(clockString(duration * fraction)) / \(clockString(duration))")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(.top, 11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Quick-start rail

/// One-tap starts for when there's no thread to resume: today's verse, the loop
/// that was last running, and the juz most people actually listen through.
struct QuickStartRail: View {
    let items: [QuickStart]

    struct QuickStart: Identifiable {
        let id: String
        let label: String
        /// SF Symbol; `nil` renders a text-only chip (e.g. "Juz 30").
        var icon: String? = nil
        var tint: Color = .brand
        let action: () -> Void
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button(action: item.action) {
                        HStack(spacing: 7) {
                            if let icon = item.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(item.tint)
                            }
                            Text(item.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        .overlay(Capsule().strokeBorder(item.tint.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(CardButtonStyle(scale: 0.94))
                }
            }
            .padding(.horizontal, 20)
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
        HStack(spacing: 12) {
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
                Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient.brandHero, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(audioService.isPlaying ? "Pause" : "Play")

            Button {
                Haptics.tap()
                audioService.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop playback")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.brand.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        .padding(.horizontal, 12)
    }

    private var label: some View {
        HStack(spacing: 11) {
            if audioService.isPlaying {
                PlayingIndicatorView(color: .brand)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.brand)
                    .frame(width: 20, height: 14)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(surahName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Waveform

/// A fixed decorative waveform filled left-to-right by playback position. Bars
/// are static by design — a real FFT would cost a tap's worth of latency to show
/// something the ear already knows.
struct MiniWaveform: View {
    let fraction: Double
    let played: Color
    let remaining: Color

    private static let bars: [CGFloat] = [
        0.32, 0.55, 0.82, 0.42, 0.70, 1.00, 0.48, 0.74,
        0.36, 0.88, 0.60, 0.45, 0.72, 0.28,
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                bars(remaining)
                bars(played)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: geo.size.width * min(1, max(0, fraction)))
                    }
            }
            .animation(.linear(duration: 0.2), value: fraction)
        }
    }

    private func bars(_ color: Color) -> some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Self.bars.indices, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(y: Self.bars[i], anchor: .center)
            }
        }
    }
}

// MARK: - Helpers

func clockString(_ seconds: Double) -> String {
    let t = Int(max(0, seconds).rounded(.down))
    return "\(t / 60):" + String(format: "%02d", t % 60)
}
