import SwiftUI
import UIKit
import WidgetKit

/// Tab identity, held by the scene rather than by the TabView, so a theme change
/// (which rebuilds the TabView) doesn't bounce the user back to Home.
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case home, quran, more

    var id: String { rawValue }

    /// Set in the tab bar's own letterspaced caps.
    var title: String {
        switch self {
        case .home:  "Today"
        case .quran: "Qur’an"
        case .more:  "More"
        }
    }

    /// VoiceOver reads the curly apostrophe badly, and "Today" alone is vague
    /// out of context.
    var accessibilityName: String {
        switch self {
        case .home:  "Today"
        case .quran: "Quran"
        case .more:  "More"
        }
    }
}

@main
struct QuranAppApp: App {
    @StateObject private var audioService       = AudioService()
    @StateObject private var memorizationStore  = MemorizationStore()
    @StateObject private var srStore            = MemorizationSRStore()
    @StateObject private var targetStore        = MemorizationTargetStore()
    @StateObject private var prayerTimesService = PrayerTimesService()
    @StateObject private var namesStore         = NamesStore()
    @StateObject private var bookmarkStore      = BookmarkStore()
    @AppStorage("colorSchemePreference") private var colorSchemeRaw = "system"
    @AppStorage("didOnboard") private var didOnboard = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @State private var showOnboarding = false
    @State private var selectedTab: AppTab = .home
    @ObservedObject private var chrome = Chrome.shared
    /// Bumped when the colour theme changes. `Color.brand` is computed, so the
    /// whole tree has to be rebuilt for the new accent to reach views that
    /// weren't otherwise going to re-render. Tab selection and the More tab's
    /// navigation path live outside the rebuilt subtree, so the user keeps their
    /// place — including the Settings screen they changed the theme from.
    @State private var themeEpoch = 0

    init() {
        Self.applySerifNavigationTitles()
    }

    /// The restyle takes English into serif, and a system large title in SF is
    /// the one place that would still shout. Set once at launch, and always to
    /// New York rather than the user's chosen reading face — the bar is drawn by
    /// UIKit, which can't re-resolve a custom face mid-session, and New York is
    /// the default face and the only one guaranteed present.
    private static func applySerifNavigationTitles() {
        func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes = [.font: serif(34, .bold)]
        appearance.titleTextAttributes = [.font: serif(17, .semibold)]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    /// Runs a request left by the "Continue Memorizing" Siri intent: start a chain
    /// loop of the working ayah plus the couple before it, paused after each.
    private func performPendingHifzAction() {
        guard HifzIntentAction.take() == HifzIntentAction.continueMemorizing,
              let t = targetStore.target else { return }
        let start = max(1, t.workingAyah - 2)
        let preset = LoopSettings.chain(from: start, through: t.workingAyah, pause: true)
        audioService.playLoop(surah: t.surah, settings: preset,
                              totalAyahs: t.totalAyahs, surahName: t.surahName)
    }

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                TabView(selection: $selectedTab) {
                    Tab(value: AppTab.home) {
                        HomeView().toolbar(.hidden, for: .tabBar)
                    }
                    Tab(value: AppTab.quran) {
                        SurahListView().toolbar(.hidden, for: .tabBar)
                    }
                    Tab(value: AppTab.more) {
                        MoreView().toolbar(.hidden, for: .tabBar)
                    }
                }
                // The system bar is hidden per-tab above; `EditorialTabBar` takes
                // its place as a safe-area inset, so it reserves its own space
                // instead of floating over the last row of every screen.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !chrome.tabBarHidden {
                        EditorialTabBar(selection: $selectedTab)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(AppAnim.spring, value: chrome.tabBarHidden)
                .tint(.brand)
                .environmentObject(audioService)
                .environmentObject(memorizationStore)
                .environmentObject(srStore)
                .environmentObject(targetStore)
                .environmentObject(prayerTimesService)
                .environmentObject(namesStore)
                .environmentObject(bookmarkStore)
                .id(themeEpoch)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(preferredColorScheme)
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    didOnboard = true
                    showOnboarding = false
                    prayerTimesService.requestAndFetch()
                    NotificationService.shared.scheduleMemorizationReminder()
                }
                .environmentObject(prayerTimesService)
            }
            .task {
                CloudSync.shared.start()
                CarPlayBridge.shared.audioService       = audioService
                CarPlayBridge.shared.memorizationStore  = memorizationStore

                // First launch: let onboarding request permissions in context.
                // Returning users get the usual silent refresh.
                showOnboarding = !didOnboard
                if didOnboard {
                    _ = await NotificationService.shared.requestPermission()
                    NotificationService.shared.scheduleMemorizationReminder()
                    prayerTimesService.requestAndFetch()
                }

                await DailyVerseService.shared.loadIfNeeded()

                performPendingHifzAction()

                // Dismiss splash after a brief moment
                try? await Task.sleep(for: .milliseconds(1400))
                withAnimation(.easeOut(duration: 0.5)) { showSplash = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: .appThemeDidChange)) { _ in
                themeEpoch += 1
                WidgetCenter.shared.reloadAllTimelines()
            }
            // Same trick for a change of reading face — but never while the
            // reader is open: it repaints itself in place (`ReadingType`), and a
            // rebuild would throw away the page the user is scrolled to.
            .onReceive(NotificationCenter.default.publisher(for: .readingTypeDidChange)) { _ in
                guard !chrome.tabBarHidden else { return }
                themeEpoch += 1
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { performPendingHifzAction() }
                // Leaving the app is the last chance to record exactly where
                // listening got to, so Home can resume to the second.
                if phase == .background { ListeningSessionStore.shared.flush() }
            }
        }
    }
}

// MARK: - Splash Screen

private struct SplashView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("القرآن الكريم")
                    .font(.appArabic(30))
                    .foregroundStyle(Color(.label).opacity(0.75))
                    .environment(\.layoutDirection, .rightToLeft)

                Text("Holy Quran")
                    .font(.appSerif(34, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.top, 10)

                DiamondRule()
                    .frame(width: 190)
                    .padding(.top, 22)

                ProgressView()
                    .tint(.brand)
                    .padding(.top, 26)
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                    scale   = 1.0
                    opacity = 1.0
                }
            }
        }
    }
}
