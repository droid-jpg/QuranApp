import SwiftUI
import Observation

enum AppTab: Hashable { case today, quran, more }

/// Every screen that can be pushed. One list, so any tab can open any of them.
enum Route: Hashable {
    case reader(surah: Int, ayah: Int? = nil, pickRepeat: Bool = false)
    case juz
    case prayerTimes, calendar, qibla, dhikr, bookmarks, names, settings
}

/// Where the app is: the tab, each tab's stack, and whether Now Playing is up.
/// Navigation is the system's (`TabView`, `NavigationStack`, sheets), so every
/// gesture is the system's too. This only holds the state they bind to.
@MainActor @Observable
final class AppRouter {
    var tab: AppTab = .today
    var today: [Route] = []
    var quran: [Route] = []
    var more: [Route] = []
    var showNowPlaying = false
    /// Set to ask the reader already on screen to move, rather than pushing another.
    var readerRequest: ReaderRequest?

    struct ReaderRequest: Equatable {
        let surah: Int
        let ayah: Int?
        let pickRepeat: Bool
    }

    private var path: [Route] {
        get {
            switch tab {
            case .today: today
            case .quran: quran
            case .more:  more
            }
        }
        set {
            switch tab {
            case .today: today = newValue
            case .quran: quran = newValue
            case .more:  more = newValue
            }
        }
    }

    /// A reader is open somewhere, so its scroll position is worth protecting.
    var isReading: Bool {
        (today + quran + more).contains { if case .reader = $0 { true } else { false } }
    }

    func open(_ route: Route) { path.append(route) }

    /// Opens a surah in the reader on the current tab. If that surah is already the
    /// screen on top, it scrolls there instead of stacking a second copy.
    func openReader(surah: Int, ayah: Int? = nil, pickRepeat: Bool = false) {
        showNowPlaying = false
        if case .reader(let top, _, _) = path.last, top == surah {
            readerRequest = ReaderRequest(surah: surah, ayah: ayah, pickRepeat: pickRepeat)
        } else {
            path.append(.reader(surah: surah, ayah: ayah, pickRepeat: pickRepeat))
        }
    }

    /// Swaps the reader on top for another surah, so Back still leaves the reader.
    func replaceReader(with surah: Int) {
        if case .reader = path.last { path.removeLast() }
        path.append(.reader(surah: surah))
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Namespace private var playerSpace

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack(path: $router.today) {
                    TodayView().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab("Quran", systemImage: "book", value: AppTab.quran) {
                NavigationStack(path: $router.quran) {
                    QuranListView().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab("More", systemImage: "ellipsis", value: AppTab.more) {
                NavigationStack(path: $router.more) {
                    MoreView().navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
        }
        // The system's own mini-player slot: it sits above the tab bar on every
        // screen and tucks in beside it when the bar minimises on scroll.
        .tabViewBottomAccessory {
            MiniPlayer()
                .matchedTransitionSource(id: "player", in: playerSpace)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $router.showNowPlaying) {
            NowPlayingView()
                .navigationTransition(.zoom(sourceID: "player", in: playerSpace))
        }
    }
}

private struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .reader(let number, let ayah, let pickRepeat):
            if let surah = QuranText.shared.surah(number) {
                ReaderView(surah: surah, startAyah: ayah, startPicking: pickRepeat)
            }
        case .juz:         JuzListView()
        case .prayerTimes: PrayerTimesView()
        case .calendar:    IslamicCalendarView()
        case .qibla:       QiblaView()
        case .dhikr:       DhikrView()
        case .bookmarks:   BookmarksView()
        case .names:       NamesOfAllahView()
        case .settings:    SettingsView()
        }
    }
}

// MARK: - More

struct MoreView: View {
    @EnvironmentObject private var prayer: PrayerTimesService

    private var nextPrayer: String? {
        guard prayer.hasTodaysTimes, let times = prayer.prayerTimes else { return nil }
        let next = times.upcomingPrayer(at: Date())
        return "\(next.name) \(next.date.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        List {
            Section {
                row("Prayer Times", "clock", .prayerTimes, value: nextPrayer)
                row("Qibla", "location.north.line", .qibla)
                row("Islamic Calendar", "calendar", .calendar)
            }
            Section {
                row("Bookmarks", "bookmark", .bookmarks)
                row("Dhikr", "circle.grid.3x3", .dhikr)
                row("99 Names", "sparkles", .names)
            }
            Section {
                row("Settings", "gearshape", .settings)
            }
        }
        .navigationTitle("More")
    }

    private func row(_ title: String, _ icon: String, _ route: Route, value: String? = nil) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.brand)
                    .frame(width: 28)
                Text(title)
                    .font(TypeScale.rowTitle)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: Spacing.xs)
                if let value {
                    Text(value)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(minHeight: 36)
        }
    }
}
