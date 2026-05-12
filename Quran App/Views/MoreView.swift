import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var prayerService: PrayerTimesService

    var body: some View {
        NavigationStack {
            List {
                // MARK: Prayer Times
                Section {
                    PrayerTimesCardView(service: prayerService)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                } header: {
                    Label("Prayer Times", systemImage: "clock.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }

                // MARK: Tools
                Section {
                    MoreRow(title: "Qibla Compass",
                            subtitle: "Find the direction of Mecca",
                            symbol: "location.north.line.fill",
                            color: .teal,
                            destination: QiblaView())

                    MoreRow(title: "Dhikr Counter",
                            subtitle: "Track your remembrance",
                            symbol: "hand.raised.fingers.spread.fill",
                            color: .teal,
                            destination: DhikrView())
                } header: {
                    Label("Tools", systemImage: "wrench.and.screwdriver.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }

                // MARK: Learn
                Section {
                    MoreRow(title: "99 Names of Allah",
                            subtitle: "Memorize and review the Beautiful Names",
                            symbol: "text.book.closed.fill",
                            color: .indigo,
                            destination: NamesOfAllahView())

                    MoreRow(title: "Islamic Calendar",
                            subtitle: "Holidays, fasting days, and special nights",
                            symbol: "moon.stars.fill",
                            color: .orange,
                            destination: IslamicCalendarView())
                } header: {
                    Label("Learn", systemImage: "graduationcap.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }

                // MARK: App
                Section {
                    MoreRow(title: "Settings",
                            subtitle: "Theme, reciter, notifications",
                            symbol: "gear",
                            color: .secondary,
                            destination: SettingsView())
                } header: {
                    Label("App", systemImage: "apps.iphone")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
        }
    }
}

// MARK: - Reusable row with coloured square icon

private struct MoreRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color == .secondary ? Color(.tertiarySystemBackground) : color.opacity(0.15))
                    Image(systemName: symbol)
                        .foregroundStyle(color)
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
