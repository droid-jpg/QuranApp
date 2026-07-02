import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var prayerService: PrayerTimesService
    @State private var hasAppeared = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // MARK: Prayer Times
                Section {
                    PrayerTimesCardView(service: prayerService)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                } header: {
                    SectionHeader(title: "Prayer Times", systemImage: "clock.fill")
                }

                // MARK: Memorize
                Section {
                    MoreRow(title: "Memorization",
                            subtitle: "Spaced-repetition review, goals, and progress",
                            symbol: "graduationcap.fill",
                            color: .brand,
                            route: .memorization)
                } header: {
                    SectionHeader(title: "Memorize", systemImage: "brain.head.profile")
                }

                // MARK: Tools
                Section {
                    MoreRow(title: "Qibla Compass",
                            subtitle: "Find the direction of Mecca",
                            symbol: "location.north.line.fill",
                            color: .green,
                            route: .qibla)

                    MoreRow(title: "Dhikr Counter",
                            subtitle: "Track your remembrance",
                            symbol: "hand.raised.fingers.spread.fill",
                            color: .purple,
                            route: .dhikr)
                } header: {
                    SectionHeader(title: "Tools", systemImage: "wrench.and.screwdriver.fill")
                }

                // MARK: Learn
                Section {
                    MoreRow(title: "Bookmarks",
                            subtitle: "Saved ayahs for quick access",
                            symbol: "bookmark.fill",
                            color: .pink,
                            route: .bookmarks)

                    MoreRow(title: "99 Names of Allah",
                            subtitle: "Memorize and review the Beautiful Names",
                            symbol: "text.book.closed.fill",
                            color: .indigo,
                            route: .names)

                    MoreRow(title: "Islamic Calendar",
                            subtitle: "Holidays, fasting days, and special nights",
                            symbol: "moon.stars.fill",
                            color: .orange,
                            route: .calendar)
                } header: {
                    SectionHeader(title: "Learn", systemImage: "graduationcap.fill")
                }

                // MARK: App
                Section {
                    MoreRow(title: "Settings",
                            subtitle: "Theme, reciter, notifications",
                            symbol: "gear",
                            color: .gray,
                            route: .settings)
                } header: {
                    SectionHeader(title: "App", systemImage: "apps.iphone")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .navigationDestination(for: MoreRoute.self) { $0.destination }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
            .onAppear {
                guard !hasAppeared else { return }
                withAnimation(AppAnim.spring.delay(0.08)) { hasAppeared = true }
            }
        }
        // Light tap on push only (not when popping back). Replaces a per-row
        // gesture, which on List rows fired the haptic without navigating.
        .sensoryFeedback(trigger: path) { old, new in
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

// MARK: - Reusable row with coloured square icon

private struct MoreRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let route: MoreRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                // Settings-app style tile: gradient fill, white glyph.
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.95), color.opacity(0.70)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: symbol)
                        .foregroundStyle(.white)
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    MoreView()
        .environmentObject(PrayerTimesService())
}
