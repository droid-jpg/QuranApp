import SwiftUI
import Combine
import UIKit

/// Prayer Times (REDESIGN §3.8), pushed from More and from Today's prayer card.
/// A date with previous/next arrows, the five prayers and sunrise as rows with the
/// next prayer highlighted, and a "Notifications" row. Every state has words and,
/// where there is a way out, a button: it never sits on a spinner.
struct PrayerTimesView: View {
    @EnvironmentObject private var service: PrayerTimesService

    /// Days from today. Bounded so the arrows can't wander off the calendar.
    @State private var dayOffset = 0
    @State private var otherDay: PrayerTimes?
    @State private var otherDayFailed = false
    @State private var now = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private static let range = -30...30

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"; return f
    }()

    private var date: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: now) ?? now
    }

    private var dayName: String {
        switch dayOffset {
        case 0:  return "Today"
        case 1:  return "Tomorrow"
        case -1: return "Yesterday"
        default: return ""
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                content
                NotificationsRow()
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .background(Palette.background)
        .navigationTitle("Prayer Times")
        .navigationBarTitleDisplayMode(.inline)
        // Stale or missing data is refetched when the screen appears.
        .task { service.refreshIfNeeded() }
        .task(id: dayOffset) { await loadOtherDay() }
        .onReceive(ticker) { tick in
            now = tick
            if !service.hasTodaysTimes { service.refreshIfNeeded() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.fetchStatus {
        case .ready where service.hasTodaysTimes:
            VStack(alignment: .leading, spacing: Spacing.sm) {
                dayHeader
                if dayOffset == 0, let times = service.prayerTimes {
                    rows(times, isToday: true)
                } else if let times = otherDay {
                    rows(times, isToday: false)
                } else if otherDayFailed {
                    StateMessage(text: "Couldn’t load prayer times", action: "Try again") {
                        Task { await loadOtherDay() }
                    }
                } else {
                    StateMessage(text: "Getting prayer times…", spinner: true)
                }
            }
        case .ready, .fetching:
            // `.ready` without today's times is a refetch already on its way.
            StateMessage(text: "Getting prayer times…", spinner: true)
        case .notDetermined, .denied:
            StateMessage(text: "Prayer times need your location", action: "Allow location") {
                service.allowLocationAccess()
            }
        case .failed:
            StateMessage(text: "Couldn’t load prayer times", action: "Try again") {
                service.requestAndFetch()
            }
        }
    }

    // MARK: Date with arrows

    private var dayHeader: some View {
        HStack(spacing: Spacing.xs) {
            arrow("chevron.left", label: "Previous day", enabled: dayOffset > Self.range.lowerBound) {
                step(-1)
            }
            VStack(spacing: 0) {
                Text(Self.dateFmt.string(from: date))
                    .font(TypeScale.heading)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText(value: Double(dayOffset)))
                if !dayName.isEmpty {
                    Text(dayName)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .animation(Motion.standard, value: dayOffset)
            arrow("chevron.right", label: "Next day", enabled: dayOffset < Self.range.upperBound) {
                step(1)
            }
        }
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool,
                       action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(TypeScale.body.weight(.semibold))
                .foregroundStyle(enabled ? Palette.accent : Palette.textTertiary)
                .frame(width: MinSize.hitTarget, height: MinSize.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(scale: 0.85))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func step(_ delta: Int) {
        let next = dayOffset + delta
        guard Self.range.contains(next) else { return }
        dayOffset = next
        otherDay = nil
        otherDayFailed = false
    }

    private func loadOtherDay() async {
        guard dayOffset != 0, service.fetchStatus == .ready else { return }
        let offset = dayOffset
        let times = await service.fetchTimings(dayOffset: offset)
        guard offset == dayOffset else { return }
        otherDay = times
        otherDayFailed = times == nil
    }

    // MARK: Rows

    private func rows(_ times: PrayerTimes, isToday: Bool) -> some View {
        let next = isToday ? times.upcomingPrayer(at: now) : nil
        let entries: [(name: String, time: Date)] = [
            ("Fajr", times.fajr), ("Sunrise", times.sunrise), ("Dhuhr", times.dhuhr),
            ("Asr", times.asr), ("Maghrib", times.maghrib), ("Isha", times.isha),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.name) { index, entry in
                if index > 0 { Hairline() }
                PrayerRow(name: entry.name, time: entry.time,
                          countdown: next?.name == entry.name
                            ? "in \(PrayerCountdown.text(to: next?.date ?? now, from: now))" : nil)
            }
        }
    }
}

// MARK: - Row

/// One prayer: name and time. The next one is highlighted, its name in the accent
/// colour, with the time left under it.
private struct PrayerRow: View {
    let name: String
    let time: Date
    /// "in 1 h 12 min" on the next prayer of today; nil elsewhere.
    let countdown: String?

    private var isNext: Bool { countdown != nil }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(TypeScale.rowTitle)
                    .foregroundStyle(isNext ? Palette.accent : Palette.textPrimary)
                if let countdown {
                    Text(countdown)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer(minLength: Spacing.xs)
            Text(time.formatted(date: .omitted, time: .shortened))
                .font(TypeScale.rowTitle.monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.numericText())
                .animation(Motion.standard, value: time)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: MinSize.moreRow)
        .background(isNext ? Palette.highlight : Color.clear,
                    in: RoundedRectangle(cornerRadius: Spacing.xs))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Notifications

/// Leads to the per-prayer switches, the same section Settings shows.
private struct NotificationsRow: View {
    var body: some View {
        NavigationLink {
            PrayerNotificationSettingsView()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "bell")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.accent)
                    .frame(width: Spacing.lg)
                    .accessibilityHidden(true)
                Text("Notifications")
                    .font(TypeScale.rowTitle)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: MinSize.moreRow)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}

/// The pushed screen behind the "Notifications" row.
struct PrayerNotificationSettingsView: View {
    var body: some View {
        ScrollView {
            PrayerNotificationsSection()
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)
        }
        .background(Palette.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - States

/// A sentence, and the one button that gets out of it. Keeps a fixed minimum
/// height so the screen never collapses to a blank gap.
private struct StateMessage: View {
    let text: String
    var spinner = false
    var action: String?
    var perform: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.sm) {
                if spinner { ProgressView() }
                Text(text)
                    .font(TypeScale.body)
                    .foregroundStyle(spinner ? Palette.textSecondary : Palette.textPrimary)
            }
            if let action {
                Button {
                    Haptics.tap()
                    perform()
                } label: {
                    Text(action)
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: MinSize.hitTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: MinSize.primaryPlay * 2, alignment: .leading)
    }
}

// MARK: - Shared pieces

/// "1 h 12 min", "12 min", "less than a minute". One wording for Today and here.
enum PrayerCountdown {
    static func text(to date: Date, from now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let h = minutes / 60, m = minutes % 60
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
        if m > 0 { return "\(m) min" }
        return "less than a minute"
    }
}

extension PrayerTimesService {
    /// "Allow location": the system settings if the answer was already no, the
    /// permission request otherwise. Only ever runs from a button the user pressed.
    func allowLocationAccess() {
        if fetchStatus == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        } else {
            requestAndFetch()
        }
    }
}
