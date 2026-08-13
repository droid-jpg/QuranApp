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

    /// "Ayah 14 · looping ×5" — what the player is doing, in one line, the same
    /// phrasing Home's docked bar uses.
    var summary: String {
        let reps = loop.repeatCount
        let tail = reps > 0 ? " ×\(reps)" : ""
        switch loop.mode {
        case .off:
            return loop.listenAndRepeat ? "Ayah \(currentAyah) · listen & repeat" : "Ayah \(currentAyah)"
        case .single:
            return loop.listenAndRepeat
                ? "Ayah \(currentAyah) · repeat after\(tail)"
                : "Ayah \(currentAyah) · looping\(tail)"
        case .segment:
            return "Ayah \(currentAyah) · chaining \(loop.startAyah)–\(loop.endAyah)"
        }
    }
}

let playerSpeeds: [Float] = [1.0, 1.5, 2.0, 0.75]

// MARK: - Mini bar

/// The docked bar. The reader hands it to its pager as a bottom safe-area inset,
/// so every page reserves exactly its height and no ayah is ever drawn under it.
struct QuranPlayerBar: View {
    let surah: Surah
    @ObservedObject var viewModel: SurahDetailViewModel
    let onExpand: () -> Void

    @EnvironmentObject private var audioService: AudioService

    private var type = ReadingType()

    init(surah: Surah, viewModel: SurahDetailViewModel, onExpand: @escaping () -> Void) {
        self.surah = surah
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.onExpand = onExpand
    }

    private var engine: PlayerEngine {
        PlayerEngine(surah: surah, viewModel: viewModel, audioService: audioService)
    }
    private var playing: Bool { audioService.isPlaying }
    private var scope: PlayerScope { engine.scope }

    var body: some View {
        HStack(spacing: 14) {
            Button { onExpand() } label: {
                HStack(spacing: 12) {
                    if playing {
                        PlayingIndicatorView(color: .brand)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .semibold))
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
                Haptics.selection()
                engine.setScope(scope == .off ? .ayah : scope == .ayah ? .range : .off,
                                a: engine.loop.startAyah, b: engine.loop.endAyah)
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(scope == .off ? Color(.label).opacity(0.4) : .brand)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Loop scope")

            Button { Haptics.tap(); engine.playPause() } label: {
                PlayCircle(playing: playing, size: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause" : "Play")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
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

/// The drill surface: presets, scrubber, scope, range, transport. Presented as an
/// overlay over the whole reader (never a system sheet) so the ayah being drilled
/// stays on screen behind it.
struct QuranExpandedPlayer: View {
    let surah: Surah
    @ObservedObject var viewModel: SurahDetailViewModel
    let onCollapse: () -> Void

    @EnvironmentObject private var audioService: AudioService

    @State private var rangeA = 1
    @State private var rangeB = 1
    @State private var selectedDrill: PlayerDrill? = nil
    @State private var showRangePicker = false

    private var type = ReadingType()

    init(surah: Surah, viewModel: SurahDetailViewModel, onCollapse: @escaping () -> Void) {
        self.surah = surah
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.onCollapse = onCollapse
    }

    private var engine: PlayerEngine {
        PlayerEngine(surah: surah, viewModel: viewModel, audioService: audioService)
    }
    private var total: Int { surah.numberOfAyahs }
    private var currentAyah: Int { audioService.currentAyah ?? 1 }
    private var playing: Bool { audioService.isPlaying }
    private var scope: PlayerScope { engine.scope }
    private var repsCount: Int { engine.repsCount }

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
        .onAppear(perform: syncRange)
        .onChange(of: currentAyah) { _, _ in if scope != .range { syncRange() } }
        .sheet(isPresented: $showRangePicker) {
            AyahRangePickerSheet(
                ayahs: viewModel.ayahs,
                totalAyahs: total,
                initialStart: min(rangeA, rangeB),
                initialEnd: max(rangeA, rangeB)
            ) { start, end in
                rangeA = start
                rangeB = end
                Haptics.selection()
                selectedDrill = nil
                engine.setScope(.range, a: start, b: end)
            }
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
                HStack(spacing: 7) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.brand)
                    Eyebrow("Memorize ayah \(currentAyah)")
                    Spacer(minLength: 8)
                    MetaText("1 TAP · PLAYS NOW", tint: .brand, size: 9)
                }

                HStack(spacing: 8) {
                    DrillButton(icon: "repeat", label: "Listen", on: selectedDrill == .listen) { drill(.listen) }
                    DrillButton(icon: "pause.circle", label: "Repeat", on: selectedDrill == .repeatAfter) { drill(.repeatAfter) }
                    DrillButton(icon: "link", label: "Chain", on: selectedDrill == .chain) { drill(.chain) }
                }

                Scrubber(clock: audioService.clock) { engine.seek($0) }

                HStack(spacing: 8) {
                    ScopeSegmented(scope: scope) { setScope($0) }
                    RepsControl(options: [0, 3, 5], current: repsCount) { setReps($0) }
                }

                // The range block only earns its space once "Range" is the chosen
                // scope. It shows the two ayahs the loop actually runs between —
                // dragging two unlabelled handles never told anyone what they'd
                // picked.
                if scope == .range {
                    rangeBlock
                        .transition(.opacity.combined(with: .move(edge: .top)))
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
                                    tint: Color(.label).opacity(0.45)) {
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
            .animation(AppAnim.spring, value: scope)
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: Range

    /// From / to, each with the opening of the ayah itself. Tapping either opens
    /// the full picker, where every ayah is shown with its text.
    private var rangeBlock: some View {
        VStack(spacing: 0) {
            HStack {
                Eyebrow("Loop range", tint: .brand)
                Spacer()
                MetaText(rangeLabel.uppercased(), tint: .brand, size: 9.5)
            }
            .padding(.bottom, 10)

            Button {
                Haptics.tap()
                showRangePicker = true
            } label: {
                VStack(spacing: 0) {
                    RangeEndRow(tag: "From", number: min(rangeA, rangeB),
                                preview: preview(min(rangeA, rangeB)), script: type.script)
                    Hairline()
                    RangeEndRow(tag: "To", number: max(rangeA, rangeB),
                                preview: preview(max(rangeA, rangeB)), script: type.script)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 9, weight: .bold))
                MetaText("TAP TO CHOOSE AYAHS", size: 9)
            }
            .foregroundStyle(Color(.label).opacity(0.4))
            .padding(.top, 9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .overlay(Rectangle().strokeBorder(Color.brand.opacity(0.4), lineWidth: 1))
    }

    /// The opening of an ayah — enough to recognise which one it is.
    private func preview(_ n: Int) -> String? {
        viewModel.ayahs.first { $0.numberInSurah == n }?.arabic
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
        return a == b ? "Ayah \(a)" : "Ayahs \(a)–\(b) · \(b - a + 1) ayahs"
    }

    private func syncRange() {
        if scope == .range { rangeA = engine.loop.startAyah; rangeB = engine.loop.endAyah }
        else { rangeA = currentAyah; rangeB = min(total, currentAyah + 1) }
    }

    private var safeInsets: UIEdgeInsets { keyWindowInsets() }
}

// MARK: - Reusable control views

/// One end of the loop range: its tag, its number, and the opening words of the
/// ayah so the choice can be made by reading rather than by counting.
private struct RangeEndRow: View {
    let tag: String
    let number: Int
    let preview: String?
    let script: ArabicScript

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(tag, tint: Color(.label).opacity(0.4), size: 8.5)
                MetaText("\(number)", tint: .brand, size: 13)
            }
            .frame(width: 34, alignment: .leading)

            if let preview {
                Text(preview)
                    .font(script.font(size: 16))
                    .foregroundStyle(Color(.label).opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
            } else {
                Text("Ayah \(number)")
                    .font(.appSerif(15))
                    .foregroundStyle(Color(.label).opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(.label).opacity(0.3))
        }
        .padding(.vertical, 9)
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

/// One of the three acquisition drills — Listen, Repeat, Chain. Outlined rather
/// than filled: `OutlineButton` with the drill's glyph, so a drill looks the same
/// here as it does on the dashboard.
struct DrillButton: View {
    let icon: String
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        OutlineButton(label: label, icon: icon, on: on, action: action)
    }
}

private struct ScopeSegmented: View {
    let scope: PlayerScope
    let onPick: (PlayerScope) -> Void

    var body: some View {
        HStack(spacing: -1) {   // shared borders, one hairline between segments
            item("Off", scope == .off) { onPick(.off) }
            item("This ayah", scope == .ayah) { onPick(.ayah) }
            item("Range", scope == .range) { onPick(.range) }
        }
        .frame(maxWidth: .infinity)
    }

    private func item(_ label: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(1)
                .foregroundStyle(on ? Color.brand : Color(.label).opacity(0.55))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .overlay(
                    Rectangle().strokeBorder(on ? Color.brand : Color(.label).opacity(0.18),
                                             lineWidth: 1)
                )
                // The selected segment's border has to win where they overlap.
                .zIndex(on ? 1 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RepsControl: View {
    let options: [Int]
    let current: Int
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: -1) {
            ForEach(options, id: \.self) { n in
                Button { onPick(n) } label: {
                    Text(n == 0 ? "∞" : "\(n)×")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(current == n ? Color.brand : Color(.label).opacity(0.55))
                        .frame(minWidth: 34)
                        .padding(.vertical, 9)
                        .overlay(
                            Rectangle().strokeBorder(current == n ? Color.brand : Color(.label).opacity(0.18),
                                                     lineWidth: 1)
                        )
                        .zIndex(current == n ? 1 : 0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SpeedPill: View {
    let rate: Float
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(speedLabel(rate))
                .font(.system(size: 10.5, weight: .semibold))
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
