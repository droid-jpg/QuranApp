import SwiftUI
import Combine

/// Holds the More tab's navigation stack outside the view, so changing the
/// colour theme — which rebuilds the whole tab tree to repaint it — puts the
/// user back on the screen they were on rather than at the top of the tab.
@MainActor
final class MoreNavigation: ObservableObject {
    static let shared = MoreNavigation()
    @Published var path = NavigationPath()
    private init() {}
}

/// The index to everything that isn't reading or the dashboard. Ruled rows
/// rather than a grouped List of gradient tiles — the tiles were the last place
/// in the app still speaking the old language.
struct MoreView: View {
    @EnvironmentObject private var prayerService: PrayerTimesService
    @ObservedObject private var nav = MoreNavigation.shared
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack(path: $nav.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {

                    EditorialSection(title: "Prayer times", icon: "clock.fill") {
                        PrayerTimesCardView(service: prayerService)
                    }

                    EditorialSection(title: "Memorize", icon: "brain.head.profile") {
                        MoreRow(title: "Memorization",
                                caption: "Spaced-repetition review, goals, and progress",
                                symbol: "graduationcap.fill",
                                route: .memorization)
                    }

                    EditorialSection(title: "Tools", icon: "wrench.and.screwdriver.fill") {
                        MoreRow(title: "Qibla compass",
                                caption: "Find the direction of Mecca",
                                symbol: "location.north.line.fill",
                                route: .qibla)
                        Hairline().padding(.vertical, 14)
                        MoreRow(title: "Dhikr counter",
                                caption: "Track your remembrance",
                                symbol: "hand.raised.fingers.spread.fill",
                                route: .dhikr)
                    }

                    EditorialSection(title: "Learn", icon: "book.closed.fill") {
                        MoreRow(title: "Bookmarks",
                                caption: "Saved ayahs for quick access",
                                symbol: "bookmark.fill",
                                route: .bookmarks)
                        Hairline().padding(.vertical, 14)
                        MoreRow(title: "99 Names of Allah",
                                caption: "Memorize and review the Beautiful Names",
                                symbol: "text.book.closed.fill",
                                route: .names)
                        Hairline().padding(.vertical, 14)
                        MoreRow(title: "Islamic calendar",
                                caption: "Holidays, fasting days, and special nights",
                                symbol: "moon.stars.fill",
                                route: .calendar)
                    }

                    EditorialSection(title: "App", icon: "gearshape.fill") {
                        MoreRow(title: "Settings",
                                caption: "Theme, type, reciter, notifications",
                                symbol: "gear",
                                route: .settings)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: MoreRoute.self) { $0.destination }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
            .onAppear {
                guard !hasAppeared else { return }
                withAnimation(AppAnim.spring.delay(0.08)) { hasAppeared = true }
            }
        }
        // Light tap on push only (not when popping back).
        .sensoryFeedback(trigger: nav.path) { old, new in
            new.count > old.count ? .impact(weight: .light) : nil
        }
    }
}

// MARK: - Routes

private enum MoreRoute: Hashable {
    case memorization, qibla, dhikr, bookmarks, names, calendar, settings

    @ViewBuilder var destination: some View {
        switch self {
        case .memorization: MemorizationHubView()
        case .qibla:        QiblaView()
        case .dhikr:        DhikrView()
        case .bookmarks:    BookmarksView()
        case .names:        NamesOfAllahView()
        case .calendar:     IslamicCalendarView()
        case .settings:     SettingsView()
        }
    }
}

// MARK: - Row

private struct MoreRow: View {
    let title: String
    let caption: String
    let symbol: String
    let route: MoreRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.brand)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.appSerif(18))
                        .foregroundStyle(Color(.label))
                    Text(caption)
                        .font(.appSerif(13.5, italic: true))
                        .foregroundStyle(Color(.label).opacity(0.45))
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(.label).opacity(0.3))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(scale: 0.985))
    }
}

#Preview {
    MoreView()
        .environmentObject(PrayerTimesService())
}
