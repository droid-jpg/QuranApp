import SwiftUI
import UIKit

// MARK: - Shared wiring

/// The transport actions the mini bar and expanded player share, so both surfaces
/// stay in lock-step without duplicating the audio wiring. Repeat is not here: both
/// open the one `RepeatSheet`.
struct PlayerEngine {
    let audioService: AudioService

    func cycleSpeed(_ speeds: [Float]) {
        let idx = speeds.firstIndex(of: audioService.playbackRate) ?? 0
        audioService.setPlaybackRate(speeds[(idx + 1) % speeds.count])
    }

    func playPause() { audioService.togglePlayPause() }
    func stop()      { audioService.stop() }
    func prev()      { audioService.skipToPreviousAyah() }
    func next()      { audioService.skipToNextAyah() }
    func seek(_ f: Double) { audioService.seek(toFraction: f) }

    /// What the player is doing, in one line, from the one status function.
    var summary: String { audioService.statusText }
}

let playerSpeeds: [Float] = [1.0, 1.5, 2.0, 0.75]

// MARK: - Mini bar

/// The docked bar. The reader hands it to its pager as a bottom safe-area inset,
/// so every page reserves exactly its height and no ayah is ever drawn under it.
struct QuranPlayerBar: View {
    let onExpand: () -> Void
    let onRepeat: () -> Void

    @EnvironmentObject private var audioService: AudioService

    private var type = ReadingType()

    init(onExpand: @escaping () -> Void, onRepeat: @escaping () -> Void) {
        self.onExpand = onExpand
        self.onRepeat = onRepeat
    }

    private var engine: PlayerEngine { PlayerEngine(audioService: audioService) }
    private var playing: Bool { audioService.isPlaying }
    private var repeating: Bool { audioService.isRepeating }

    var body: some View {
        HStack(spacing: 2) {
            Button { onExpand() } label: {
                HStack(spacing: 12) {
                    if playing {
                        PlayingIndicatorView(color: .brand)
                    } else {
                        Image(systemName: "waveform")
                            .font(.label(14, weight: .semibold))
                            .foregroundStyle(.brand)
                            .frame(width: 20, height: 14)
                    }
                    Text(engine.summary)
                        .font(type.serif(15))
                        .foregroundStyle(Color(.label).opacity(0.8))
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                onRepeat()
            } label: {
                Image(systemName: "repeat")
                    .font(.label(15, weight: .semibold))
                    .foregroundStyle(repeating ? Color.brand : Color.secondary)
                    // The HIG's minimum hit target, without making the bar taller.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .padding(.vertical, -11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat")
            .accessibilityValue(repeating ? audioService.statusText : "Off")

            Button { Haptics.tap(); engine.playPause() } label: {
                PlayCircle(playing: playing, size: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause" : "Play")
        }
        .padding(.leading, 16)
        .padding(.trailing, 13)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(Rectangle().strokeBorder(Color(.label).opacity(0.16), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8).onEnded { v in
                if v.translation.height <= -30 { onExpand() }
            }
        )
        .animation(AppAnim.springFast, value: playing)
    }
}

// MARK: - Expanded player

/// Scrubber, Repeat, speed and transport. Presented as an overlay over the whole
/// reader (never a system sheet) so the ayah being heard stays on screen behind it.
struct QuranExpandedPlayer: View {
    let onCollapse: () -> Void
    let onRepeat: () -> Void

    @EnvironmentObject private var audioService: AudioService

    private var engine: PlayerEngine { PlayerEngine(audioService: audioService) }
    private var playing: Bool { audioService.isPlaying }

    init(onCollapse: @escaping () -> Void, onRepeat: @escaping () -> Void) {
        self.onCollapse = onCollapse
        self.onRepeat = onRepeat
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.32))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCollapse() }
                .transition(.opacity)

            sheet
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .ignoresSafeArea(edges: .bottom)
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

                RepeatButton(value: audioService.activeRepeat.shortSummary,
                             on: audioService.isRepeating) {
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
                    TransportButton(system: "stop.fill", size: 18,
                                    tint: Color.secondary) {
                        Haptics.tap(); engine.stop(); onCollapse()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            // The safe-area allowance lives inside the sheet so its background
            // runs all the way to the screen edge — padding the sheet itself
            // leaves a strip of dimmed page under the home indicator.
            .padding(.bottom, 22 + safeInsets.bottom)
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Hairline() }
    }

    private func cycleSpeed() { Haptics.selection(); engine.cycleSpeed(playerSpeeds) }

    private var safeInsets: UIEdgeInsets { keyWindowInsets() }
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
                .animation(.linear(duration: 0.12), value: frac)
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

private func keyWindowInsets() -> UIEdgeInsets {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?.windows.first { $0.isKeyWindow }?.safeAreaInsets ?? .zero
}
