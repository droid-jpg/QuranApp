import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted when a reader leaves the screen.
    static let readerDidClose = Notification.Name("readerDidClose")
}

@main
struct QuranAppApp: App {
    // Held with `@State` and passed down through the environment. The scene itself
    // reads none of their properties, so playback never re-evaluates it.
    @State private var player = Player()
    @State private var downloads = Downloads()
    @State private var router = AppRouter()
    @StateObject private var prayerTimes = PrayerTimesService()
    @StateObject private var namesStore = NamesStore()
    @StateObject private var bookmarks = BookmarkStore()
    @AppStorage("colorSchemePreference") private var colorSchemeRaw = "system"
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("selectedReciterId") private var reciterId = Reciter.all[0].id
    @Environment(\.scenePhase) private var scenePhase
    /// Bumped when the accent or the reading face changes. Both are read through
    /// computed statics (`Color.brand`, `Font.appSerif`), so the tree is rebuilt for
    /// the change to reach every view. The router lives outside it, so the tab and
    /// each tab's navigation stack survive the rebuild.
    @State private var themeEpoch = 0
    /// A change of reading face that arrived while a reader was open. The reader
    /// repaints itself; rebuilding the tree under it would lose its place, so the
    /// rebuild waits until it closes.
    @State private var repaintWhenReaderCloses = false

    init() {
        // Serif titles in the system navigation bar. Its background is left to the system.
        func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: serif(34, .bold)]
        UINavigationBar.appearance().titleTextAttributes = [.font: serif(17, .semibold)]
    }

    /// The chosen translation is fetched if it is not on disk yet: one picked during
    /// onboarding, or one whose download was cut short. Reading falls back to the
    /// bundled translation until it arrives.
    private func fetchSelectedTranslation() {
        let id = Translation.selected.id
        guard !QuranText.shared.isAvailable(id) else { return }
        Task { try? await QuranText.shared.download(id) }
    }

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": .light
        case "dark":  .dark
        default:      nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(themeEpoch)
                .tint(.brand)
                .environment(player)
                .environment(downloads)
                .environment(router)
                .environmentObject(prayerTimes)
                .environmentObject(namesStore)
                .environmentObject(bookmarks)
                .preferredColorScheme(preferredColorScheme)
                .fullScreenCover(isPresented: .init(get: { !didOnboard }, set: { _ in })) {
                    OnboardingView {
                        didOnboard = true
                        prayerTimes.refreshIfNeeded()
                        fetchSelectedTranslation()
                    }
                    .environmentObject(prayerTimes)
                }
                .task {
                    player.onSurahFetched = { [downloads] surah in downloads.noteIfComplete(surah) }
                    if didOnboard {
                        prayerTimes.refreshIfNeeded()
                        fetchSelectedTranslation()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .appThemeDidChange)) { _ in themeEpoch += 1 }
                .onReceive(NotificationCenter.default.publisher(for: .readingTypeDidChange)) { _ in
                    if router.isReading { repaintWhenReaderCloses = true } else { themeEpoch += 1 }
                }
                .onReceive(NotificationCenter.default.publisher(for: .readerDidClose)) { _ in
                    guard repaintWhenReaderCloses, !router.isReading else { return }
                    repaintWhenReaderCloses = false
                    themeEpoch += 1
                }
                .onChange(of: reciterId) {
                    // Another voice: other files on disk, other word timings.
                    player.reciterChanged()
                    downloads.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    // A new day, or a new month: pick up today's times from the cache.
                    if phase == .active, didOnboard { prayerTimes.refreshIfNeeded() }
                }
        }
    }
}
