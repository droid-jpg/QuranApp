import SwiftUI

@main
struct QuranAppApp: App {
    @StateObject private var audioService       = AudioService()
    @StateObject private var memorizationStore  = MemorizationStore()
    @StateObject private var prayerTimesService = PrayerTimesService()
    @StateObject private var namesStore         = NamesStore()
    @AppStorage("colorSchemePreference") private var colorSchemeRaw = "system"
    @State private var showSplash = true

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
                    SurahListView()
                        .tabItem { Label("Quran", systemImage: "book") }
                    MemorizationView()
                        .tabItem { Label("Memorize", systemImage: "checkmark.circle") }
                    MoreView()
                        .tabItem { Label("More", systemImage: "ellipsis.circle") }
                }
                .environmentObject(audioService)
                .environmentObject(memorizationStore)
                .environmentObject(prayerTimesService)
                .environmentObject(namesStore)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(preferredColorScheme)
            .task {
                _ = await NotificationService.shared.requestPermission()
                prayerTimesService.requestAndFetch()
                CarPlayBridge.shared.audioService       = audioService
                CarPlayBridge.shared.memorizationStore  = memorizationStore

                await DailyVerseService.shared.loadIfNeeded()

                // Dismiss splash after a brief moment
                try? await Task.sleep(for: .milliseconds(1400))
                withAnimation(.easeOut(duration: 0.5)) { showSplash = false }
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
                        .fill(Color.teal.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.teal, .teal.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 6) {
                    Text("القرآن الكريم")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(.primary)
                        .environment(\.layoutDirection, .rightToLeft)

                    Text("The Holy Quran")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                ProgressView()
                    .tint(.teal)
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
