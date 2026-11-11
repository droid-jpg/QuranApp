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

/// More (REDESIGN §3.8): everything that isn't reading or listening, as one plain
/// list. Icon, title and an optional value per row; no captions, no inline prayer
/// block. The tab reserves room for the bars (`clearsBottomChrome`), so Settings
/// ends above them with no padding here.
struct MoreView: View {
    @ObservedObject private var nav = MoreNavigation.shared

    var body: some View {
        NavigationStack(path: $nav.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("More")
                        .font(TypeScale.display)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Spacing.xs)

                    PrayerTimesMoreRow()
                    MoreRow(title: "Qibla", symbol: "location.north.line", route: .qibla)
                    MoreRow(title: "Dhikr", symbol: "hand.raised.fingers.spread", route: .dhikr)
                    BookmarksMoreRow()
                    MoreRow(title: "Memorization", symbol: "graduationcap", route: .memorization)
                    MoreRow(title: "99 Names", symbol: "text.book.closed", route: .names)
                    MoreRow(title: "Islamic Calendar", symbol: "moon.stars",
                            value: HomeDates.hijri, route: .calendar)
                    MoreRow(title: "Settings", symbol: "gearshape", route: .settings, last: true)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.md)
            }
            .background(Palette.background)
            // No bar on this root, so cover the status bar: rows scroll under it otherwise.
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    Palette.background
                        .frame(height: geo.safeAreaInsets.top)
                        .offset(y: -geo.safeAreaInsets.top)
                }
                .frame(height: 0)
                .accessibilityHidden(true)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MoreRoute.self) { $0.destination }
        }
        // Light tap on push only (not when popping back).
        .sensoryFeedback(trigger: nav.path) { old, new in
            new.count > old.count ? .impact(weight: .light) : nil
        }
    }
}

// MARK: - Routes

private enum MoreRoute: Hashable {
    case prayerTimes, memorization, qibla, dhikr, bookmarks, names, calendar, settings

    @ViewBuilder var destination: some View {
        switch self {
        case .prayerTimes:  PrayerTimesView()
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

// MARK: - Rows

/// Icon, title, optional value, chevron; 56 pt minimum, a hairline below.
private struct MoreRow: View {
    let title: String
    let symbol: String
    var value: String?
    let route: MoreRoute
    var last = false

    var body: some View {
        NavigationLink(value: route) {
            MoreRowLabel(title: title, symbol: symbol, value: value)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if !last { Hairline() } }
    }
}

private struct MoreRowLabel: View {
    let title: String
    let symbol: String
    let value: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(TypeScale.body)
                .foregroundStyle(Palette.accent)
                .frame(width: Spacing.lg)
                .accessibilityHidden(true)
            Text(title)
                .font(TypeScale.rowTitle)
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: Spacing.xs)
            if let value {
                Text(value)
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Image(systemName: "chevron.right")
                .font(TypeScale.caption)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: MinSize.moreRow)
        .contentShape(Rectangle())
    }
}

/// The count is read here, so a bookmark added elsewhere shows when More returns.
private struct BookmarksMoreRow: View {
    @EnvironmentObject private var store: BookmarkStore

    var body: some View {
        MoreRow(title: "Bookmarks", symbol: "bookmark",
                value: store.bookmarks.isEmpty ? nil : "\(store.bookmarks.count)",
                route: .bookmarks)
    }
}

/// "Maghrib 5:02 PM", "Location needed", or "—" while loading (and when the fetch
/// failed, where the screen behind the row says so in words). A leaf, so the
/// service's changes redraw this row and not the list.
private struct PrayerTimesMoreRow: View {
    @EnvironmentObject private var service: PrayerTimesService
    @State private var now = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var value: String {
        switch service.fetchStatus {
        case .notDetermined, .denied:
            return "Location needed"
        case .fetching, .failed:
            return "—"
        case .ready:
            guard let times = service.prayerTimes, service.hasTodaysTimes else { return "—" }
            let next = times.upcomingPrayer(at: now)
            return "\(next.name) \(next.date.formatted(date: .omitted, time: .shortened))"
        }
    }

    var body: some View {
        MoreRow(title: "Prayer Times", symbol: "clock", value: value, route: .prayerTimes)
            .onReceive(ticker) { now = $0 }
    }
}

#Preview {
    MoreView()
        .environmentObject(PrayerTimesService())
        .environmentObject(BookmarkStore())
}
