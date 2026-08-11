import SwiftUI

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
                TabView {
                    Tab("Home", systemImage: "house.fill") {
                        HomeView()
                    }
                    Tab("Quran", systemImage: "book.fill") {
                        SurahListView()
                    }
                    Tab("More", systemImage: "ellipsis.circle.fill") {
                        MoreView()
                    }
                }
                // Liquid Glass tab bar: float over content and tuck away while
                // reading so the scripture gets the full screen.
                .tabBarMinimizeBehavior(.onScrollDown)
                .tint(.brand)
                .environmentObject(audioService)
                .environmentObject(memorizationStore)
                .environmentObject(srStore)
                .environmentObject(targetStore)
                .environmentObject(prayerTimesService)
                .environmentObject(namesStore)
                .environmentObject(bookmarkStore)

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

            VStack(spacing: 20) {
                // Moon & star icon cluster
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.brand.opacity(0.18), Color.brand.opacity(0.04)],
                                center: .center, startRadius: 8, endRadius: 70
                            )
                        )
                        .frame(width: 132, height: 132)
                    Circle()
                        .strokeBorder(Color.brand.opacity(0.15), lineWidth: 1)
                        .frame(width: 132, height: 132)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(LinearGradient.brandHero)
                }

                VStack(spacing: 8) {
                    Text("القرآن الكريم")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(.primary)
                        .environment(\.layoutDirection, .rightToLeft)

                    Text("The Holy Quran")
                        .font(.title3)
                        .fontDesign(.serif)
                        .foregroundStyle(.secondary)
                }

                ProgressView()
                    .tint(.brand)
                    .padding(.top, 8)
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
