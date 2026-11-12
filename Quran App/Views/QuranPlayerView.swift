import SwiftUI
import UIKit
import Combine

// MARK: - Shared wiring

/// The transport actions the mini player and Now Playing share, so both surfaces
/// stay in lock-step without duplicating the audio wiring. Repeat is not here: both
/// open the one `RepeatSheet`.
struct PlayerEngine {
    let audioService: AudioService

    /// Something is loaded in the player.
    private var loaded: Bool { audioService.currentAyah != nil }

    /// The saved session, when nothing is loaded in the player (restored paused
    /// at launch, or after a stop).
    private var restoredSession: ListeningSession? {
        loaded ? nil : ListeningSessionStore.shared.session
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

    /// Previous ayah. With only a saved session, starts playback at the ayah
    /// before the saved one rather than doing nothing.
    func prev() {
        if loaded { audioService.skipToPreviousAyah(); return }
        guard let session = restoredSession,
              let target = navigationRepeat(session: session).previousAyah(before: session.ayah)
        else { return }
        startRestored(at: target)
    }

    /// Next ayah; like `prev()` for a saved session.
    func next() {
        if loaded { audioService.skipToNextAyah(); return }
        guard let session = restoredSession,
              let target = navigationRepeat(session: session)
                .nextAyah(after: session.ayah, ayahCount: session.totalAyahs)
        else { return }
        startRestored(at: target)
    }

    /// Plays `ayah` of the surah in the player (the ayah bar). Outside a repeat's
    /// range, `play` turns the repeat off.
    func jump(to ayah: Int) {
        if loaded {
            audioService.play(surah: audioService.currentSurah, startAyah: ayah,
                              totalAyahs: audioService.loadedAyahCount,
                              surahName: audioService.currentSurahName)
        } else {
            startRestored(at: ayah)
        }
    }

    /// Whether Previous / Next would go anywhere from `ayah`.
    func canGoBack(from ayah: Int, session: ListeningSession?) -> Bool {
        navigationRepeat(session: session).previousAyah(before: ayah) != nil
    }

    func canGoForward(from ayah: Int, count: Int, session: ListeningSession?) -> Bool {
        navigationRepeat(session: session).nextAyah(after: ayah, ayahCount: count) != nil
    }

    /// Starts the saved session at `ayah`, from the top of it.
    private func startRestored(at ayah: Int) {
        guard var session = restoredSession else { return }
        if audioService.repeatState.surah == session.surah {
            session.repeatState = audioService.repeatState
        }
        session.ayah = max(1, min(ayah, session.totalAyahs))
        session.fraction = 0
        audioService.resume(session)
    }

    /// The repeat Previous / Next obey: on only when it is for the surah shown.
    private func navigationRepeat(session: ListeningSession?) -> RepeatState {
        if loaded { return audioService.activeRepeat }
        var s = repeatState(session: session) ?? RepeatState()
        if s.surah != session?.surah { s.isOn = false }
        return s
    }

    /// The surah in the player, or the saved session's.
    var playerSurahNumber: Int? {
        if audioService.currentAyah != nil, audioService.currentSurah > 0 { return audioService.currentSurah }
        return ListeningSessionStore.shared.session?.surah
    }

    /// The repeat that applies to what the player shows: the live one, or for a
    /// restored session the service's state when it names that surah (the Repeat
    /// sheet edits it before Play), else the session's own.
    func repeatState(session: ListeningSession?) -> RepeatState? {
        if audioService.currentAyah != nil { return audioService.activeRepeat }
        guard let session else { return nil }
        return audioService.repeatState.surah == session.surah ? audioService.repeatState : session.repeatState
    }

    func isRepeating(session: ListeningSession?) -> Bool {
        repeatState(session: session)?.isOn ?? false
    }

    /// "Off", or the repeat's short summary ("Ayahs 3–4 · 5 times").
    func repeatSummary(session: ListeningSession?) -> String {
        repeatState(session: session)?.shortSummary ?? "Off"
    }

    /// What the player is doing, in one line, from the one status function.
    func statusText(session: ListeningSession?) -> String {
        if audioService.currentAyah != nil { return audioService.statusText }
        guard let session, let state = repeatState(session: session) else { return "" }
        return state.status(currentAyah: session.ayah, reciterName: session.reciterName)
    }
}

/// The playback rates offered by Speed, slowest first.
let playerSpeeds: [Float] = [0.75, 1.0, 1.5, 2.0]

func speedLabel(_ r: Float) -> String {
    switch r {
    case 1.0:  return "1×"
    case 1.5:  return "1.5×"
    case 2.0:  return "2×"
    case 0.75: return "0.75×"
    default:   return "\(r)×"
    }
}

// MARK: - Now Playing

/// How far Now Playing has been pulled down. Kept apart from the content so the
/// drag re-renders only the container's offset, never the controls.
@MainActor
final class NowPlayingDrag: ObservableObject {
    @Published var offset: CGFloat = 0
}

/// Now Playing (REDESIGN §3.5): a full-height, opaque cover presented by the
/// root (`NowPlayingSlot`) so it opens from any tab. Swipe down or tap the
/// grabber to close it.
struct NowPlayingView: View {
    let ui: PlayerUI
    @StateObject private var drag = NowPlayingDrag()

    var body: some View {
        NowPlayingContent(ui: ui, drag: drag)
            .offset(y: drag.offset)
            // A plain move: no fade, no material, so nothing renders offscreen.
            .transition(Motion.move(.move(edge: .bottom)))
    }
}

/// Everything inside Now Playing. Observes the audio service (not its clock: no
/// part of this screen moves ten times a second).
private struct NowPlayingContent: View {
    let ui: PlayerUI
    let drag: NowPlayingDrag

    @EnvironmentObject private var audioService: AudioService
    @ObservedObject private var listening = ListeningSessionStore.shared
    @AppStorage("selectedReciterId") private var reciterId = 7
    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId
    @AppStorage("arabicFontSize") private var arabicFontSize: Double = 26
    private var type = ReadingType()

    /// The surah's text, read without the network, keyed by what was loaded.
    @State private var text: (key: String, ayahs: [Ayah])?
    /// Whether the ayah text is scrolled to its top, so a pull down there closes.
    @State private var textAtTop = true
    /// The cover's height, for the pull-down threshold.
    @State private var sheetHeight: CGFloat = 0

    init(ui: PlayerUI, drag: NowPlayingDrag) {
        self.ui = ui
        self.drag = drag
    }

    private var engine: PlayerEngine { PlayerEngine(audioService: audioService) }
    private var session: ListeningSession? { listening.session }
    private var loaded: Bool { audioService.currentAyah != nil }
    private var playing: Bool { loaded && audioService.isPlaying }
    private var loading: Bool { playing && audioService.isBuffering }
    private var failedAyah: Int? { loaded ? audioService.failedAyah : nil }
    private var wordRepeating: Bool { loaded && audioService.isWordLooping }

    private var surahNumber: Int {
        loaded ? audioService.currentSurah : (session?.surah ?? 0)
    }

    private var surahName: String {
        let name = loaded ? audioService.currentSurahName : (session?.surahName ?? "")
        return name.isEmpty ? "Surah \(surahNumber)" : name
    }

    private var ayah: Int {
        loaded ? (audioService.currentAyah ?? 1) : (session?.ayah ?? 1)
    }

    private var ayahCount: Int {
        let n = loaded ? audioService.loadedAyahCount : (session?.totalAyahs ?? 0)
        if n > 0 { return n }
        return QuranOfflineStore.shared.surahs().first { $0.number == surahNumber }?.numberOfAyahs ?? 1
    }

    private var reciterName: String {
        Reciter.all.first { $0.id == reciterId }?.name ?? Reciter.selected.name
    }

    /// Line 2: where playback is; while a repeat or word repeat runs, the same
    /// status line the mini player and Today show.
    private var detailLine: String {
        if wordRepeating || (repeatState?.isOn ?? false) { return engine.statusText(session: session) }
        return "Ayah \(ayah) of \(ayahCount) · \(reciterName)"
    }

    private var repeatState: RepeatState? { engine.repeatState(session: session) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                titleBlock
            }
            .contentShape(Rectangle())
            .gesture(dismissDrag)

            ayahText
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controls
                .contentShape(Rectangle())
                .gesture(dismissDrag)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surfaceRaised.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { ui.closeNowPlaying() }
        .task(id: "\(surahNumber)|\(translationId)") { loadText() }
    }

    // MARK: Top

    private var topRow: some View {
        ZStack {
            Button {
                ui.closeNowPlaying()
            } label: {
                Capsule()
                    .fill(Palette.textTertiary)
                    .frame(width: Spacing.xxl, height: Spacing.xxs + 1)
                    .frame(width: MinSize.primaryPlay, height: MinSize.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide Now Playing")

            HStack {
                Spacer()
                optionsMenu
            }
        }
        .padding(.horizontal, Spacing.xs)
    }

    private var optionsMenu: some View {
        Menu {
            Button {
                goToReader()
            } label: {
                Label("Go to ayah in reader", systemImage: "book")
            }
            Menu {
                Picker("Reciter", selection: reciterBinding) {
                    ForEach(Reciter.all) { r in
                        Text(r.name).tag(r.id)
                    }
                }
            } label: {
                Label {
                    Text("Reciter")
                    Text(reciterName)
                } icon: {
                    Image(systemName: "person.wave.2")
                }
            }
            Divider()
            Button(role: .destructive) {
                Haptics.tap()
                ui.closeNowPlaying()
                audioService.closePlayer()
            } label: {
                Label("Close player", systemImage: "xmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Player options")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(surahName)
                .font(TypeScale.title)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detailLine)
                .font(TypeScale.secondary)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.md)
    }

    // MARK: Ayah text

    @ViewBuilder
    private var ayahText: some View {
        if let failed = failedAyah {
            VStack(spacing: Spacing.sm) {
                Text("Couldn't play ayah \(failed)")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textPrimary)
                Button("Try again") {
                    Haptics.tap()
                    engine.playPause()
                }
                .font(TypeScale.body.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .frame(minHeight: MinSize.hitTarget)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .contentShape(Rectangle())
            .gesture(dismissDrag)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if let current = currentAyahText {
                        Text(current.arabic)
                            .font(type.arabic(arabicFontSize, scales: false))
                            .foregroundStyle(Palette.textPrimary)
                            .lineSpacing(arabicFontSize * 0.45)
                            .multilineTextAlignment(.leading)
                            .environment(\.layoutDirection, .rightToLeft)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        if !current.translation.isEmpty {
                            Text(current.translation)
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.xs)
                .id(ayah)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y <= geo.contentInsets.top * -1 + 1
            } action: { _, atTop in
                textAtTop = atTop
            }
            .simultaneousGesture(dismissDrag, including: textAtTop ? .all : .subviews)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
        }
    }

    private var currentAyahText: Ayah? {
        guard let text, text.key == textKey else { return nil }
        let i = ayah - 1
        return text.ayahs.indices.contains(i) ? text.ayahs[i] : nil
    }

    private var textKey: String { "\(surahNumber)|\(translationId)" }

    /// The surah's text without the network: the reader's on-disk copy for the
    /// chosen translation, else the bundled text (its translation exists only for
    /// the bundled edition; otherwise the ayah shows in Arabic alone).
    private func loadText() {
        guard surahNumber > 0, text?.key != textKey else { return }
        let ayahs = QuranAPIService.offlineAyahs(surah: surahNumber, translationId: translationId) ?? []
        text = (textKey, ayahs)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: Spacing.lg) {
            AyahBar(ayah: ayah, count: ayahCount,
                    range: (repeatState?.isOn ?? false) ? repeatState.map { $0.from...$0.to } : nil,
                    enabled: !wordRepeating) { target in
                Haptics.selection()
                engine.jump(to: target)
            }

            transport

            optionsRow
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.md)
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            TransportButton(system: "backward.end.fill", label: "Previous ayah") {
                engine.prev()
            }
            .disabled(wordRepeating || !engine.canGoBack(from: ayah, session: session))
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                engine.playPause()
            } label: {
                ZStack {
                    if loading {
                        Circle().strokeBorder(Palette.accent.opacity(0.55), lineWidth: 1)
                        ProgressView().tint(Palette.accent).controlSize(.large)
                    } else {
                        PlayCircle(playing: playing, size: MinSize.nowPlayingPlay, filled: true)
                    }
                }
                .frame(width: MinSize.nowPlayingPlay, height: MinSize.nowPlayingPlay)
                .animation(Motion.quick, value: playing)
                .animation(Motion.quick, value: loading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause" : "Play")
            Spacer(minLength: 0)
            TransportButton(system: "forward.end.fill", label: "Next ayah") {
                engine.next()
            }
            .disabled(wordRepeating || !engine.canGoForward(from: ayah, count: ayahCount, session: session))
            Spacer(minLength: 0)
        }
    }

    private var optionsRow: some View {
        let repeating = repeatState?.isOn ?? false
        let repeatValue = engine.repeatSummary(session: session)
        let rate = audioService.playbackRate
        return HStack(spacing: Spacing.sm) {
            Button {
                Haptics.tap()
                ui.openRepeat(for: audioService)
            } label: {
                OptionLabel(icon: "repeat", title: "Repeat", value: repeatValue, on: repeating)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Repeat")
            .accessibilityValue(repeating ? repeatValue : "Off")
            .accessibilityAddTraits(.isButton)

            Menu {
                Picker("Speed", selection: speedBinding) {
                    ForEach(playerSpeeds, id: \.self) { r in
                        Text(speedLabel(r)).tag(r)
                    }
                }
            } label: {
                OptionLabel(icon: "gauge.with.dots.needle.67percent", title: "Speed",
                            value: speedLabel(rate), on: false)
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speed")
            .accessibilityValue(speedLabel(rate))
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: Actions

    private var reciterBinding: Binding<Int> {
        Binding(
            get: { reciterId },
            set: { id in
                guard id != reciterId else { return }
                Haptics.selection()
                reciterId = id
                // Heard at once: replay the current ayah in the new voice.
                if playing, !wordRepeating, let a = audioService.currentAyah {
                    audioService.play(surah: audioService.currentSurah, startAyah: a,
                                      totalAyahs: audioService.loadedAyahCount,
                                      surahName: audioService.currentSurahName)
                }
            }
        )
    }

    private var speedBinding: Binding<Float> {
        Binding(
            get: { audioService.playbackRate },
            set: { r in
                Haptics.selection()
                audioService.setPlaybackRate(r)
            }
        )
    }

    private func goToReader() {
        let surah = surahNumber, target = ayah
        guard surah > 0 else { return }
        Haptics.tap()
        ui.closeNowPlaying()
        NotificationCenter.default.post(name: .openReaderAtAyah, object: nil,
                                        userInfo: ["surah": surah, "ayah": target])
    }

    /// Pull down to close: follows the finger, closes past a quarter of the
    /// screen or on a flick, else springs back.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: Spacing.sm, coordinateSpace: .global)
            .onChanged { v in
                let dy = v.translation.height
                guard drag.offset > 0 || (dy > 0 && dy >= abs(v.translation.width) * 2) else { return }
                drag.offset = max(0, dy)
            }
            .onEnded { v in
                guard drag.offset > 0 else { return }
                let height = max(sheetHeight, 1)
                if drag.offset > height * 0.25 || v.predictedEndTranslation.height > height * 0.5 {
                    ui.closeNowPlaying()
                } else {
                    withAnimation(Motion.sheet) { drag.offset = 0 }
                }
            }
    }
}

// MARK: - Ayah bar

/// One track for the whole surah, its thumb at the current ayah. Drag (or tap)
/// to jump; the jump is made on release. A repeat's range is an accent span.
private struct AyahBar: View {
    let ayah: Int
    let count: Int
    let range: ClosedRange<Int>?
    let enabled: Bool
    let onJump: (Int) -> Void

    @State private var dragAyah: Int?

    private static let thumb: CGFloat = Spacing.md
    private static let track: CGFloat = Spacing.xxs

    private var shown: Int { dragAyah ?? ayah }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.separator)
                        .frame(width: max(0, w - Self.thumb), height: Self.track)
                        .offset(x: Self.thumb / 2)
                    if let range {
                        let x0 = x(range.lowerBound, w), x1 = x(range.upperBound, w)
                        // At least two thumbs wide, so a short range in a long
                        // surah still shows beside the thumb.
                        let width = max(x1 - x0, Self.thumb * 2)
                        Capsule()
                            .fill(Palette.accent.opacity(0.5))
                            .frame(width: width, height: Self.track + 2)
                            .offset(x: min(max(Self.thumb / 2, (x0 + x1) / 2 - width / 2),
                                           w - Self.thumb / 2 - width))
                    }
                    Circle()
                        .fill(enabled ? Palette.accent : Palette.textTertiary)
                        .frame(width: Self.thumb, height: Self.thumb)
                        .offset(x: x(shown, w) - Self.thumb / 2)
                        .animation(dragAyah == nil ? Motion.standard : nil, value: shown)
                }
                .frame(width: w, height: MinSize.hitTarget, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let a = ayah(at: v.location.x, w)
                            if a != dragAyah { dragAyah = a }
                        }
                        .onEnded { v in
                            let a = ayah(at: v.location.x, w)
                            dragAyah = nil
                            if a != ayah { onJump(a) }
                        }
                )
            }
            .frame(height: MinSize.hitTarget)

            HStack {
                Text("1")
                Spacer(minLength: Spacing.xs)
                if let dragAyah {
                    Text("Ayah \(dragAyah)")
                        .foregroundStyle(Palette.accent)
                }
                Spacer(minLength: Spacing.xs)
                Text("\(count)")
            }
            .font(TypeScale.secondary.monospacedDigit())
            .foregroundStyle(Palette.textSecondary)
        }
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ayah")
        .accessibilityValue("\(ayah) of \(count)")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: if ayah < count { onJump(ayah + 1) }
            case .decrement: if ayah > 1 { onJump(ayah - 1) }
            @unknown default: break
            }
        }
        .disabled(!enabled)
    }

    /// Centre of `a`'s position on a bar `w` wide.
    private func x(_ a: Int, _ w: CGFloat) -> CGFloat {
        let usable = max(1, w - Self.thumb)
        let f = count > 1 ? CGFloat(a - 1) / CGFloat(count - 1) : 0.5
        return Self.thumb / 2 + min(1, max(0, f)) * usable
    }

    private func ayah(at px: CGFloat, _ w: CGFloat) -> Int {
        guard count > 1 else { return 1 }
        let usable = max(1, w - Self.thumb)
        let f = min(1, max(0, (px - Self.thumb / 2) / usable))
        return Int((f * CGFloat(count - 1)).rounded()) + 1
    }
}

// MARK: - Control pieces

/// A labelled option with its value on a second line (Repeat, Speed).
private struct OptionLabel: View {
    let icon: String
    let title: String
    let value: String
    let on: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on ? Palette.accent : Palette.textSecondary)
                .frame(width: Spacing.lg)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textPrimary)
                Text(value)
                    .font(TypeScale.secondary.monospacedDigit())
                    .foregroundStyle(on ? Palette.accent : Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: MinSize.primaryPlay, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.sm)
                .strokeBorder(on ? Palette.accent.opacity(0.6) : Palette.separator, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

private struct TransportButton: View {
    let system: String
    let label: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 24))
                .foregroundStyle(isEnabled ? Palette.textPrimary : Palette.textTertiary)
                .frame(width: MinSize.primaryPlay, height: MinSize.primaryPlay)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
