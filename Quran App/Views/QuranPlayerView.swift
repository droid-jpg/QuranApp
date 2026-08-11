import SwiftUI
import UIKit

// MARK: - Shared vocabulary

enum PlayerScope { case off, ayah, range }
enum PlayerDrill { case listen, repeatAfter, chain }

/// Pure logic that maps the player's controls onto the shared `AudioService` +
/// `LoopSettings`. A cheap value type the mini bar and expanded sheet build on
/// demand, so both surfaces stay in lock-step without duplicating the audio wiring.
struct PlayerEngine {
    let surah: Surah
    let viewModel: SurahDetailViewModel
    let audioService: AudioService

    var total: Int { surah.numberOfAyahs }
    var currentAyah: Int { audioService.currentAyah ?? 1 }
    var loop: LoopSettings { audioService.loopSettings }
    var repsCount: Int { loop.repeatCount }
    var scope: PlayerScope {
        switch loop.mode {
        case .off:     return .off
        case .single:  return .ayah
        case .segment: return .range
        }
    }

    private func apply(_ s: LoopSettings) { viewModel.applyLoopSettings(s, audioService: audioService) }

    func setScope(_ sc: PlayerScope, a: Int, b: Int) {
        switch sc {
        case .off:
            apply(LoopSettings(mode: .off, startAyah: 1, endAyah: total, repeatCount: 0,
                               listenAndRepeat: loop.listenAndRepeat,
                               listenRepeatDelay: loop.listenRepeatDelay))
        case .ayah:
            apply(LoopSettings(mode: .single, startAyah: currentAyah, endAyah: currentAyah,
                               repeatCount: repsCount,
                               listenAndRepeat: loop.listenAndRepeat,
                               listenRepeatDelay: loop.listenRepeatDelay))
        case .range:
            let lo = min(a, b), hi = max(a, b)
            apply(LoopSettings(mode: .segment, startAyah: lo, endAyah: hi,
                               repeatCount: repsCount,
                               listenAndRepeat: loop.listenAndRepeat,
                               listenRepeatDelay: loop.listenRepeatDelay))
        }
    }

    func setReps(_ n: Int) { var s = loop; s.repeatCount = n; apply(s) }

    func runDrill(_ d: PlayerDrill) {
        let reps = repsCount
        let ayah = currentAyah
        let s: LoopSettings
        switch d {
        case .listen:      s = .listen(ayah: ayah, repeatCount: reps)
        case .repeatAfter: s = .repeatAfter(ayah: ayah, repeatCount: reps)
        case .chain:       s = .chain(from: 1, through: ayah, repeatCount: reps)
        }
        apply(s)
        audioService.playLoop(surah: surah.number, settings: s,
                              totalAyahs: total, surahName: surah.englishName)
    }

    func cycleSpeed(_ speeds: [Float]) {
        let idx = speeds.firstIndex(of: audioService.playbackRate) ?? 0
        audioService.setPlaybackRate(speeds[(idx + 1) % speeds.count])
    }

    func playPause() { audioService.togglePlayPause() }
    func stop()      { audioService.stop() }
    func prev()      { audioService.skipToPreviousAyah() }
    func next()      { audioService.skipToNextAyah() }
    func seek(_ f: Double) { audioService.seek(toFraction: f) }
}

let playerSpeeds: [Float] = [1.0, 1.5, 2.0, 0.75]

// MARK: - Player (mini + expanded, both in place above the reader)

/// The reader's audio player. It floats above the scripture in two stages: a mini
/// bar, and an expanded sheet you swipe up to. Both stay in place — the reader
/// keeps the screen, so the ayah being drilled is always the one you're reading.
struct QuranPlayerView: View {
    let surah: Surah
    @ObservedObject var viewModel: SurahDetailViewModel
    @EnvironmentObject private var audioService: AudioService

    @State private var stage: Stage = .mini
    @State private var rangeA = 1
    @State private var rangeB = 1
    @State private var selectedDrill: PlayerDrill? = nil

    private enum Stage { case mini, expanded }

    private var engine: PlayerEngine { PlayerEngine(surah: surah, viewModel: viewModel, audioService: audioService) }
    private var total: Int { surah.numberOfAyahs }
    private var currentAyah: Int { audioService.currentAyah ?? 1 }
    private var playing: Bool { audioService.isPlaying }
    private var scope: PlayerScope { engine.scope }
    private var repsCount: Int { engine.repsCount }

    var body: some View {
        ZStack(alignment: .bottom) {
            if stage != .mini {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { setStage(.mini) }
            }
            switch stage {
            case .mini:
                miniBar.transition(.move(edge: .bottom).combined(with: .opacity))
            case .expanded:
                expandedSheet.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear(perform: syncRange)
        .onChange(of: currentAyah) { _, _ in if scope != .range { syncRange() } }
    }

    // MARK: Stage transitions

    private func goUp()   { Haptics.tap(); setStage(.expanded) }
    private func goDown() { Haptics.tap(); setStage(.mini) }
    private func setStage(_ s: Stage) {
        withAnimation(AppAnim.spring) { stage = s }
    }
    private var stageDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { v in
                if v.translation.height <= -30 { goUp() }
                else if v.translation.height >= 30 { goDown() }
            }
    }

    // MARK: Mini

    private var miniBar: some View {
        HStack(spacing: 13) {
            Button { goUp() } label: {
                HStack(spacing: 13) {
                    if playing { PlayingIndicatorView(color: .brand) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(surah.englishName)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text("Ayah \(currentAyah)")
                            .font(.subheadline.weight(.medium))
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.selection()
                selectedDrill = nil
                engine.setScope(scope == .off ? .ayah : scope == .ayah ? .range : .off,
                                a: rangeA, b: rangeB)
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolVariant(scope == .ayah ? .fill : .none)
                    .foregroundStyle(scope == .off ? Color(.tertiaryLabel) : .brand)
            }
            .buttonStyle(.plain)

            PlayPauseButton(size: 44, playing: playing) { Haptics.tap(); engine.playPause() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        .padding(.horizontal, 10)
        .padding(.bottom, 10 + safeInsets.bottom)
        .simultaneousGesture(stageDrag)
        .animation(AppAnim.springFast, value: playing)
    }

    // MARK: Expanded

    private var expandedSheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(.tertiaryLabel).opacity(0.7)).frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10).padding(.bottom, 10)
                .contentShape(Rectangle())
                .onTapGesture { setStage(.mini) }
                .simultaneousGesture(stageDrag)

            VStack(spacing: 15) {
                HStack {
                    Text("Memorize ayah \(currentAyah)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text("1 tap · plays now")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.brand)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.brand.opacity(0.12), in: Capsule())
                }

                HStack(spacing: 8) {
                    DrillButton(icon: "repeat", label: "Listen", on: selectedDrill == .listen) { drill(.listen) }
                    DrillButton(icon: "pause.circle", label: "Repeat", on: selectedDrill == .repeatAfter) { drill(.repeatAfter) }
                    DrillButton(icon: "link", label: "Chain", on: selectedDrill == .chain) { drill(.chain) }
                }

                Scrubber(audioService: audioService)

                HStack(spacing: 8) {
                    ScopeSegmented(scope: scope) { setScope($0) }
                    RepsControl(options: [0, 3, 5], current: repsCount, fill: false) { setReps($0) }
                }

                // The A–B rail only earns its space once "Range" is the chosen
                // scope — otherwise the two handles have nothing to point at.
                if scope == .range {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Loop range")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.brand)
                            Spacer()
                            Text(rangeLabel)
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(.brand)
                        }
                        RangeRail(total: total, a: $rangeA, b: $rangeB) {
                            Haptics.selection(); selectedDrill = nil
                            engine.setScope(.range, a: rangeA, b: rangeB)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.brand.opacity(0.18), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 14) {
                    SpeedPill(rate: audioService.playbackRate, prominent: true) { cycleSpeed() }
                    Spacer()
                    TransportButton(system: "backward.end.fill", size: 26) { Haptics.tap(); engine.prev() }
                    PlayPauseButton(size: 58, playing: playing) { Haptics.tap(); engine.playPause() }
                    TransportButton(system: "forward.end.fill", size: 26) { Haptics.tap(); engine.next() }
                    Spacer()
                    TransportButton(system: "stop.fill", size: 20, tint: .secondary) {
                        Haptics.tap(); engine.stop(); setStage(.mini)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 20)
            .animation(AppAnim.spring, value: scope)
        }
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.brand.opacity(0.12), lineWidth: 0.5)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8 + safeInsets.bottom)
    }

    // MARK: Control actions

    private func drill(_ d: PlayerDrill) {
        Haptics.impact(.light)
        withAnimation(AppAnim.springFast) { selectedDrill = d }
        if d == .chain { rangeA = 1; rangeB = currentAyah } else { rangeA = currentAyah; rangeB = currentAyah }
        engine.runDrill(d)
    }
    private func setScope(_ sc: PlayerScope) {
        Haptics.selection()
        selectedDrill = nil
        engine.setScope(sc, a: rangeA, b: rangeB)
    }
    private func setReps(_ n: Int) { Haptics.selection(); engine.setReps(n) }
    private func cycleSpeed() { Haptics.selection(); engine.cycleSpeed(playerSpeeds) }

    private var rangeLabel: String {
        let a = min(rangeA, rangeB), b = max(rangeA, rangeB)
        return a == b ? "Ayah \(a)" : "Ayahs \(a)–\(b)"
    }

    private func syncRange() {
        if scope == .range { rangeA = engine.loop.startAyah; rangeB = engine.loop.endAyah }
        else { rangeA = currentAyah; rangeB = min(total, currentAyah + 1) }
    }

    private var safeInsets: UIEdgeInsets { keyWindowInsets() }
}


// MARK: - Reusable control views

/// Slim in-ayah scrubber. Its own view so only it re-renders on the 0.1 s
/// playback tick — the surrounding sheet stays put.
private struct Scrubber: View {
    @ObservedObject var audioService: AudioService

    var body: some View {
        let dur = audioService.duration
        let frac = dur > 0 ? min(1, max(0, audioService.progress)) : 0
        return HStack(spacing: 10) {
            Text(fmtTime(dur * frac))
                .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 6)
                    Capsule().fill(Color.brand).frame(width: max(0, w * frac), height: 6)
                    Circle().fill(.white).frame(width: 17, height: 17)
                        .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                        .offset(x: max(0, min(w - 17, w * frac - 8.5)))
                }
                .frame(height: 17)
                .animation(.linear(duration: 0.12), value: frac)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in audioService.seek(toFraction: v.location.x / max(w, 1)) }
                )
            }
            .frame(height: 17)
            Text(fmtTime(dur))
                .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// One of the three acquisition drills — Listen, Repeat, Chain. Shared by the
/// reader's expanded player and Home's memorizing card so the same drill always
/// looks and reads the same wherever it's started from.
struct DrillButton: View {
    let icon: String
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(on ? .white : .brand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(on ? AnyShapeStyle(LinearGradient.brandHero) : AnyShapeStyle(Color.brand.opacity(0.1)))
            }
            .shadow(color: on ? Color.brandDeep.opacity(0.3) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct ScopeSegmented: View {
    let scope: PlayerScope
    let onPick: (PlayerScope) -> Void

    var body: some View {
        HStack(spacing: 3) {
            item("Off", scope == .off) { onPick(.off) }
            item("This ayah", scope == .ayah) { onPick(.ayah) }
            item("Range", scope == .range) { onPick(.range) }
        }
        .padding(3)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    private func item(_ label: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: on ? .bold : .semibold))
                .foregroundStyle(on ? .white : .secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(on ? Color.brand : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct RepsControl: View {
    let options: [Int]
    let current: Int
    let fill: Bool
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { n in
                Button { onPick(n) } label: {
                    Text(n == 0 ? "∞" : "\(n)×")
                        .font(.system(size: fill ? 13 : 12, weight: current == n ? .bold : .semibold))
                        .foregroundStyle(current == n ? .white : .secondary)
                        .frame(maxWidth: fill ? .infinity : nil)
                        .padding(.horizontal, fill ? 0 : 8)
                        .padding(.vertical, fill ? 7 : 6)
                        .background(current == n ? Color.brand : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(fill ? 3 : 4)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .frame(maxWidth: fill ? .infinity : nil)
    }
}

private struct SpeedPill: View {
    let rate: Float
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(speedLabel(rate))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(prominent ? .brand : .secondary)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(prominent ? Color.brand.opacity(0.1) : Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TransportButton: View {
    let system: String
    let size: CGFloat
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size * 0.62))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

private struct PlayPauseButton: View {
    let size: CGFloat
    let playing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(LinearGradient.brandHero, in: Circle())
                .shadow(color: Color.brandDeep.opacity(0.4), radius: size * 0.14, y: size * 0.07)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - A–B loop-range rail

/// Two draggable handles ("A" start, "B" end) over the surah's ayahs. Dragging a
/// handle snaps it to the nearest ayah; releasing commits the segment loop.
private struct RangeRail: View {
    let total: Int
    @Binding var a: Int
    @Binding var b: Int
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let xLo = x(for: min(a, b), w: w)
            let xHi = x(for: max(a, b), w: w)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiaryLabel).opacity(0.28)).frame(height: 5)
                Capsule().fill(Color.brand)
                    .frame(width: max(0, xHi - xLo), height: 5).offset(x: xLo)

                if total <= 20 {
                    ForEach(1...max(total, 1), id: \.self) { n in
                        Circle().fill(Color(.tertiaryLabel).opacity(0.5))
                            .frame(width: 6, height: 6).offset(x: x(for: n, w: w) - 3)
                    }
                }

                handle("A", filled: false, cx: x(for: a, w: w)) { px in
                    let n = ayah(atX: px, w: w); if n != a { a = n; Haptics.selection() }
                }
                handle("B", filled: true, cx: x(for: b, w: w)) { px in
                    let n = ayah(atX: px, w: w); if n != b { b = n; Haptics.selection() }
                }
            }
            .frame(height: 26)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 26)
    }

    private func x(for ayah: Int, w: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return (CGFloat(ayah) - 0.5) / CGFloat(total) * w
    }
    private func ayah(atX px: CGFloat, w: CGFloat) -> Int {
        guard total > 0, w > 0 else { return 1 }
        return min(max(Int((px / w * CGFloat(total)) + 0.5), 1), total)
    }
    private func handle(_ label: String, filled: Bool, cx: CGFloat,
                        set: @escaping (CGFloat) -> Void) -> some View {
        Circle()
            .fill(filled ? Color.brand : Color(.systemBackground))
            .overlay(Text(label).font(.system(size: 11, weight: .heavy)).foregroundStyle(filled ? .white : .brand))
            .overlay(Circle().strokeBorder(Color.brand.opacity(filled ? 0 : 0.5), lineWidth: filled ? 0 : 1))
            .frame(width: 26, height: 26)
            .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
            .offset(x: cx - 13)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in set(v.location.x) }
                    .onEnded { _ in onCommit() }
            )
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
