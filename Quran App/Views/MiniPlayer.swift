import SwiftUI
import Combine
import UIKit

// The app-wide player chrome (REDESIGN §3.4): one mini player mounted once at
// the root, above the tab bar (or at the bottom of the reader), plus Now Playing
// and the Repeat sheet presented from the root so they open from any tab.
//
// Observation stays in the leaves: the root, the TabView and the tab screens
// hold neither `AudioService` nor `PlayerUI` as observed objects, so an ayah
// advance or opening Now Playing re-renders only the views in this file.

// MARK: - Player UI state

/// Whether Now Playing is up and which surah the root Repeat sheet is open for.
/// Held by the root as a plain reference (`@State`, not `@StateObject`), so only
/// the slots below, which observe it, re-render when it changes.
@MainActor
final class PlayerUI: ObservableObject {
    @Published var nowPlayingShown = false
    @Published var repeatSheetSurah: Surah?

    func openNowPlaying() {
        guard !nowPlayingShown else { return }
        withAnimation(Motion.sheet) { nowPlayingShown = true }
    }

    func closeNowPlaying() {
        guard nowPlayingShown else { return }
        withAnimation(Motion.sheet) { nowPlayingShown = false }
    }

    /// Opens the Repeat sheet for the surah in the player (or the saved session).
    func openRepeat(for audio: AudioService) {
        guard let number = PlayerEngine(audioService: audio).playerSurahNumber,
              let surah = QuranOfflineStore.shared.surahs().first(where: { $0.number == number })
        else { return }
        repeatSheetSurah = surah
    }
}

// MARK: - Bottom chrome

/// What sits under the tab content: the mini player, then the tab bar, laid over
/// the bottom of the TabView. It reports its height for `BottomChromeSpacer`,
/// which each tab reserves as its own bottom inset.
struct BottomChrome: View {
    @Binding var selection: AppTab
    let ui: PlayerUI

    @ObservedObject private var chrome = Chrome.shared
    /// Follows `chrome.tabBarHidden` inside an animated transaction, so the tab
    /// content's inset animates with the bar. Nil until first shown.
    @State private var tabBarShown: Bool?

    var body: some View {
        VStack(spacing: 0) {
            MiniPlayerSlot(ui: ui)
            if tabBarShown ?? !chrome.tabBarHidden {
                EditorialTabBar(selection: $selection)
                    .transition(Motion.move(.move(edge: .bottom).combined(with: .opacity)))
            }
        }
        .onAppear { tabBarShown = !chrome.tabBarHidden }
        .onChange(of: chrome.tabBarHidden) { _, hidden in
            withAnimation(Motion.sheet) { tabBarShown = !hidden }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            BottomChromeHeight.shared.value = height
        }
    }
}

/// The bottom chrome's measured height (mini player and tab bar, above the home
/// indicator). Changes only when the mini player or the tab bar shows or hides.
@MainActor
final class BottomChromeHeight: ObservableObject {
    static let shared = BottomChromeHeight()
    @Published var value: CGFloat = 0
    private init() {}
}

extension View {
    /// Ends this tab's content clear of the app's bottom chrome. Applied once per
    /// tab, around its NavigationStack: the inset is set on the tab's own view
    /// controller (`additionalSafeAreaInsets`), so it reaches the stack's root and
    /// every screen pushed onto it, the reader included. A SwiftUI
    /// `safeAreaInset` on the TabView or around the stack does not cross into
    /// the stack's hosting controllers.
    func clearsBottomChrome() -> some View {
        background(BottomChromeInset())
    }
}

/// Observes the chrome height (a leaf, so the tab itself doesn't) and hands it
/// to the UIKit side.
private struct BottomChromeInset: View {
    @ObservedObject private var height = BottomChromeHeight.shared

    var body: some View {
        BottomSafeAreaSetter(bottom: height.value)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

/// Sets `additionalSafeAreaInsets.bottom` on the tab's view controller: the
/// ancestor whose parent is the tab bar controller.
private struct BottomSafeAreaSetter: UIViewControllerRepresentable {
    let bottom: CGFloat

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.bottom = bottom
        controller.apply()
    }

    final class Controller: UIViewController {
        var bottom: CGFloat = 0

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        func apply() {
            var vc: UIViewController? = parent
            while let current = vc, !(current.parent is UITabBarController) { vc = current.parent }
            guard let tab = vc, tab.additionalSafeAreaInsets.bottom != bottom else { return }
            tab.additionalSafeAreaInsets.bottom = bottom
        }
    }
}

// MARK: - Mini player

/// Shows the mini player while something is loaded in the player or a saved
/// session exists, and hides it otherwise.
private struct MiniPlayerSlot: View {
    let ui: PlayerUI

    @EnvironmentObject private var audioService: AudioService
    @ObservedObject private var listening = ListeningSessionStore.shared
    /// Follows `visible` inside an animated transaction (see `BottomChrome`).
    @State private var shown: Bool?

    private var visible: Bool { audioService.currentAyah != nil || listening.session != nil }

    var body: some View {
        VStack(spacing: 0) {
            if shown ?? visible {
                MiniPlayer(audioService: audioService, session: listening.session, ui: ui)
                    .transition(Motion.move(.move(edge: .bottom).combined(with: .opacity)))
            }
        }
        .onAppear { shown = visible }
        .onChange(of: visible) { _, now in
            withAnimation(Motion.sheet) { shown = now }
            if !now { ui.closeNowPlaying() }
        }
    }
}

/// 56 pt, opaque, a 2 pt progress line on its top edge. Title and status on the
/// left (tap or swipe up for Now Playing), Repeat and Play/Pause on the right.
private struct MiniPlayer: View {
    @ObservedObject var audioService: AudioService
    let session: ListeningSession?
    let ui: PlayerUI

    private var engine: PlayerEngine { PlayerEngine(audioService: audioService) }
    /// Something is loaded in the player. Otherwise this shows the saved session,
    /// restored paused at launch.
    private var loaded: Bool { audioService.currentAyah != nil }
    private var playing: Bool { loaded && audioService.isPlaying }
    private var loading: Bool { playing && audioService.isBuffering }
    private var failed: Bool { loaded && audioService.failedAyah != nil }

    private var title: String {
        if loaded {
            return audioService.currentSurahName.isEmpty
                ? "Surah \(audioService.currentSurah)" : audioService.currentSurahName
        }
        guard let session else { return "" }
        return session.surahName.isEmpty ? "Surah \(session.surah)" : session.surahName
    }

    private var subtitle: String {
        if failed { return "Couldn't play. Tap to retry" }
        return engine.statusText(session: session)
    }

    private var repeating: Bool { engine.isRepeating(session: session) }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                Haptics.tap()
                if failed { engine.playPause() } else { ui.openNowPlaying() }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(TypeScale.rowTitleCompact)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(TypeScale.secondary)
                        .foregroundStyle(failed ? Palette.danger : Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(subtitle)
            .accessibilityHint(failed ? "Retries playback" : "Opens Now Playing")
            .accessibilityAddTraits(.isButton)

            Button {
                Haptics.tap()
                ui.openRepeat(for: audioService)
            } label: {
                ZStack {
                    Circle()
                        .fill(repeating ? Palette.accent : Color.clear)
                        .overlay(Circle().strokeBorder(repeating ? Color.clear : Palette.separator,
                                                       lineWidth: 1))
                    Image(systemName: "repeat")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(repeating ? Palette.onAccent : Palette.textSecondary)
                }
                .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat")
            .accessibilityValue(repeating ? engine.statusText(session: session) : "Off")

            Button {
                Haptics.tap()
                engine.playPause()
            } label: {
                ZStack {
                    if loading {
                        Circle().strokeBorder(Palette.accent.opacity(0.55), lineWidth: 1)
                        ProgressView().tint(Palette.accent)
                    } else {
                        PlayCircle(playing: playing, size: MinSize.hitTarget)
                    }
                }
                .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)
                .animation(Motion.quick, value: playing)
                .animation(Motion.quick, value: loading)
            }
            .buttonStyle(.plain)
            .padding(.leading, Spacing.xs)
            .accessibilityLabel(playing ? "Pause" : "Play")
        }
        .padding(.leading, Spacing.md)
        .padding(.trailing, Spacing.sm)
        .frame(height: MinSize.miniPlayer)
        .frame(maxWidth: .infinity)
        // Opaque; in the reader (no tab bar under it) it runs on under the home indicator.
        .background(Palette.surfaceRaised, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                Hairline()
                MiniProgressLine(clock: audioService.clock, live: loaded,
                                 fallback: session?.fraction ?? 0)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: Spacing.xs).onEnded { v in
                if v.translation.height <= -Spacing.xl { ui.openNowPlaying() }
            }
        )
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The 2 pt line along the mini player's top edge. Observes the clock, not the
/// service, so the ten-times-a-second playhead redraws only this line. No
/// animation: an implicit one per tick would stack.
private struct MiniProgressLine: View {
    @ObservedObject var clock: PlaybackClock
    let live: Bool
    let fallback: Double

    var body: some View {
        let f = min(1, max(0, live ? clock.progress : fallback))
        GeometryReader { geo in
            Rectangle()
                .fill(Palette.accent)
                .frame(width: geo.size.width * f, height: 2)
        }
        .frame(height: 2)
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }
}

// MARK: - Now Playing

/// Now Playing's place above the whole app. Only this re-renders when it opens
/// or closes.
struct NowPlayingSlot: View {
    @ObservedObject var ui: PlayerUI
    @EnvironmentObject private var audioService: AudioService

    var body: some View {
        if ui.nowPlayingShown {
            QuranExpandedPlayer(
                onCollapse: { ui.closeNowPlaying() },
                onRepeat: { ui.openRepeat(for: audioService) },
                onClosePlayer: {
                    Haptics.tap()
                    ui.closeNowPlaying()
                    audioService.closePlayer()
                }
            )
            .zIndex(10)
        }
    }
}

// MARK: - Root sheets

/// Presents the Repeat sheet the mini player and Now Playing ask for. A zero-size
/// background view, so the root itself never observes `PlayerUI`.
struct PlayerSheetsHost: View {
    @ObservedObject var ui: PlayerUI
    @Environment(\.audioServiceRef) private var audioService

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .sheet(item: $ui.repeatSheetSurah) { surah in
                RepeatSheet(
                    surah: surah,
                    ayahs: QuranOfflineStore.shared.ayahs(surah: surah.number,
                                                          translationId: Translation.fallbackId) ?? [],
                    focusAyah: focusAyah(in: surah)
                )
            }
    }

    /// The ayah in the player, else the saved session's, else ayah 1.
    private func focusAyah(in surah: Surah) -> Int {
        if let audioService, audioService.currentSurah == surah.number,
           let a = audioService.currentAyah { return a }
        if let s = ListeningSessionStore.shared.session, s.surah == surah.number { return s.ayah }
        return 1
    }
}
