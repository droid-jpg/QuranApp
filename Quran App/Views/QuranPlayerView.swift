import SwiftUI
import UIKit

// MARK: - Shared wiring

/// The transport actions the mini player and Now Playing share, so both surfaces
/// stay in lock-step without duplicating the audio wiring. Repeat is not here: both
/// open the one `RepeatSheet`.
struct PlayerEngine {
    let audioService: AudioService

    /// The saved session, when nothing is loaded in the player (restored paused
    /// at launch, or after a stop).
    private var restoredSession: ListeningSession? {
        audioService.currentAyah == nil ? ListeningSessionStore.shared.session : nil
    }

    func cycleSpeed(_ speeds: [Float]) {
        let idx = speeds.firstIndex(of: audioService.playbackRate) ?? 0
        audioService.setPlaybackRate(speeds[(idx + 1) % speeds.count])
    }

    /// Play/pause; with nothing loaded, resumes the saved session where it stopped,
    /// with the repeat as the Repeat sheet left it.
    func playPause() {
        if var session = restoredSession {
            if audioService.repeatState.surah == session.surah {
                session.repeatState = audioService.repeatState
            }
            audioService.resume(session)
        } else {
            audioService.togglePlayPause()
        }
    }

    func prev()      { audioService.skipToPreviousAyah() }
    func next()      { audioService.skipToNextAyah() }
    func seek(_ f: Double) { audioService.seek(toFraction: f) }

    /// The surah in the player, or the saved session's.
    var playerSurahNumber: Int? {
        if audioService.currentAyah != nil, audioService.currentSurah > 0 { return audioService.currentSurah }
        return ListeningSessionStore.shared.session?.surah
    }

    /// The repeat that applies to what the player shows: the live one, or for a
    /// restored session the service's state when it names that surah (the Repeat
    /// sheet edits it before Play), else the session's own.
    private func repeatState(session: ListeningSession?) -> RepeatState? {
        if audioService.currentAyah != nil { return audioService.activeRepeat }
        guard let session else { return nil }
        return audioService.repeatState.surah == session.surah ? audioService.repeatState : session.repeatState
    }

    func isRepeating(session: ListeningSession?) -> Bool {
        repeatState(session: session)?.isOn ?? false
    }

    /// What the player is doing, in one line, from the one status function.
    func statusText(session: ListeningSession?) -> String {
        if audioService.currentAyah != nil { return audioService.statusText }
        guard let session, let state = repeatState(session: session) else { return "" }
        return state.status(currentAyah: session.ayah, reciterName: session.reciterName)
    }
}

let playerSpeeds: [Float] = [1.0, 1.5, 2.0, 0.75]

// MARK: - Expanded player

/// Now Playing: scrubber, Repeat, speed and transport. Presented by the root as
/// an overlay over the whole app (`NowPlayingSlot`), so it opens from any tab.
/// It needs nothing from the reader: everything comes from the audio service.
struct QuranExpandedPlayer: View {
    let onCollapse: () -> Void
    let onRepeat: () -> Void
    /// Stops playback and forgets the saved session (replaces Stop).
    let onClosePlayer: () -> Void

    @EnvironmentObject private var audioService: AudioService
    @ObservedObject private var listening = ListeningSessionStore.shared

    private var engine: PlayerEngine { PlayerEngine(audioService: audioService) }
    private var playing: Bool { audioService.currentAyah != nil && audioService.isPlaying }

    init(onCollapse: @escaping () -> Void, onRepeat: @escaping () -> Void,
         onClosePlayer: @escaping () -> Void) {
        self.onCollapse = onCollapse
        self.onRepeat = onRepeat
        self.onClosePlayer = onClosePlayer
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.32))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCollapse() }
                .transition(.opacity)

            // A plain move: fading the whole sheet as a group cost an offscreen
            // pass on every frame of the open and close.
            sheet
                .transition(Motion.move(.move(edge: .bottom)))
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(.label).opacity(0.22)).frame(width: 38, height: 2)
                .frame(maxWidth: .infinity)
                .padding(.top, 12).padding(.bottom, 14)
                .contentShape(Rectangle())
                .onTapGesture { onCollapse() }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8).onEnded { v in
                        if v.translation.height >= 30 { onCollapse() }
                    }
                )

            VStack(spacing: 15) {
                Scrubber(clock: audioService.clock) { engine.seek($0) }

                RepeatButton(value: repeatValue,
                             on: engine.isRepeating(session: listening.session)) {
                    Haptics.tap()
                    onRepeat()
                }

                Hairline()

                HStack(spacing: 14) {
                    SpeedPill(rate: audioService.playbackRate) { cycleSpeed() }
                    Spacer()
                    TransportButton(system: "backward.end.fill", size: 24) { Haptics.tap(); engine.prev() }
                    Button { Haptics.tap(); engine.playPause() } label: {
                        PlayCircle(playing: playing, size: 54)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playing ? "Pause" : "Play")
                    TransportButton(system: "forward.end.fill", size: 24) { Haptics.tap(); engine.next() }
                    Spacer()
                    // Balances the speed pill, so the transport stays centred.
                    SpeedPill(rate: audioService.playbackRate) {}.hidden()
                }

                Button("Close player", action: onClosePlayer)
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(minHeight: MinSize.hitTarget)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 22)
        }
        // The controls stay inside the safe area; only the background runs on
        // under the home indicator, so no strip of dimmed page shows there.
        .background(Palette.surfaceRaised, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) { Hairline() }
    }

    /// "Off", or the repeat's short summary.
    private var repeatValue: String {
        if audioService.currentAyah != nil { return audioService.activeRepeat.shortSummary }
        guard let session = listening.session else { return "Off" }
        let state = audioService.repeatState.surah == session.surah ? audioService.repeatState : session.repeatState
        return state.shortSummary
    }

    private func cycleSpeed() { Haptics.selection(); engine.cycleSpeed(playerSpeeds) }
}

// MARK: - Reusable control views

/// "Repeat" with its current value under it; opens the Repeat sheet.
private struct RepeatButton: View {
    let value: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "repeat")
                    .font(.label(17, weight: .semibold))
                    .foregroundStyle(on ? Color.brand : Color.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeat")
                        .font(.label(17))
                        .foregroundStyle(Color.ink)
                    Text(value)
                        .font(.label(15).monospacedDigit())
                        .foregroundStyle(on ? Color.brand : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.label(13, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .overlay(Rectangle().strokeBorder(on ? Color.brand.opacity(0.5) : Color(.label).opacity(0.18),
                                              lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Repeat")
        .accessibilityValue(value)
        .accessibilityAddTraits(.isButton)
    }
}

/// Slim in-ayah scrubber. It observes the *clock* rather than the audio service:
/// the playhead ticks ten times a second, and nothing else should redraw with it.
private struct Scrubber: View {
    @ObservedObject var clock: PlaybackClock
    let onSeek: (Double) -> Void

    var body: some View {
        let dur = clock.duration
        let frac = dur > 0 ? min(1, max(0, clock.progress)) : 0
        return HStack(spacing: 10) {
            MetaText(fmtTime(dur * frac), size: 10.5)
            GeometryReader { geo in
                let w = geo.size.width
                // Ruled like the rest of the app: a 1.5pt track with a small
                // playhead, not a capsule with a white knob.
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(.label).opacity(0.16)).frame(height: 1.5)
                    Rectangle().fill(Color.brand).frame(width: max(0, w * frac), height: 1.5)
                    Circle().fill(Color.brand).frame(width: 11, height: 11)
                        .offset(x: max(0, min(w - 11, w * frac - 5.5)))
                }
                .frame(height: 18)
                // No implicit animation: the clock ticks every 0.1 s, and a
                // 0.12 s animation per tick kept the playhead permanently
                // mid-animation with overlapping animations stacked on it.
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in onSeek(v.location.x / max(w, 1)) }
                )
            }
            .frame(height: 18)
            MetaText(fmtTime(dur), size: 10.5)
        }
    }
}

private struct SpeedPill: View {
    let rate: Float
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(speedLabel(rate))
                .font(.label(10.5, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.brand)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .overlay(Rectangle().strokeBorder(Color.brand.opacity(0.5), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Playback speed \(speedLabel(rate))")
    }
}

private struct TransportButton: View {
    let system: String
    let size: CGFloat
    var tint: Color = Color(.label).opacity(0.75)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size * 0.62))
                .foregroundStyle(tint)
                .frame(width: size + 12, height: size + 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Free helpers

private func fmtTime(_ s: Double) -> String {
    let t = Int(max(0, s).rounded(.down))
    return "\(t / 60):" + String(format: "%02d", t % 60)
}

private func speedLabel(_ r: Float) -> String {
    switch r {
    case 1.0:  return "1×"
    case 1.5:  return "1.5×"
    case 2.0:  return "2×"
    case 0.75: return "0.75×"
    default:   return "\(r)×"
    }
}
