import SwiftUI
import Combine

/// The prayer times block on the More tab. The old horizontal strip of cells put
/// seven prayers behind a scroll and hid Sunrise and Midnight behind taps; ruled
/// rows show the whole day at once, which is what the screen is for.
struct PrayerTimesCardView: View {
    @ObservedObject var service: PrayerTimesService
    @State private var selectedOffset: Int = 0

    var body: some View {
        switch service.fetchStatus {
        case .notDetermined:
            OutlineButton(label: "Enable prayer times", icon: "location.fill", on: true) {
                Haptics.tap()
                service.requestAndFetch()
            }

        case .denied:
            HStack(spacing: 9) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(.label).opacity(0.4))
                Text("Location access denied — enable in Settings")
                    .font(.appSerif(15))
                    .foregroundStyle(Color(.label).opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .fetching:
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.7)
                Text("Getting prayer times…")
                    .font(.appSerif(15))
                    .foregroundStyle(Color(.label).opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .ready:
            VStack(alignment: .leading, spacing: 0) {
                DayPickerStrip(selectedOffset: $selectedOffset)
                    .padding(.bottom, 16)
                PrayerTimesForDayView(service: service, dayOffset: selectedOffset)
            }
        }
    }
}

// MARK: - Prayer rows

/// The day's prayers as ruled lines. The prayer currently being observed carries
/// an accent rule in the margin; the next one carries a live countdown.
struct PrayerTimesStrip: View {
    let times: PrayerTimes
    /// When false (a future/past date), no prayer is highlighted and no live
    /// countdown is shown — the times are purely informational.
    var isToday: Bool = true

    @State private var now = Date()
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// Sunrise and Islamic Midnight are shown outright now rather than hidden
    /// behind a tap on Fajr / Isha — they're two more lines, not two more cells.
    private let entries: [(name: String, icon: String)] = [
        ("Fajr",     "moon.stars.fill"),
        ("Sunrise",  "sunrise.fill"),
        ("Dhuhr",    "sun.max.fill"),
        ("Asr",      "sun.horizon.fill"),
        ("Maghrib",  "sunset.fill"),
        ("Isha",     "moon.fill"),
        ("Midnight", "moon.zzz.fill"),
    ]

    private var current: String? { isToday ? times.currentPrayer(at: now) : nil }
    private var upcoming: (name: String, date: Date)? { isToday ? times.upcomingPrayer(at: now) : nil }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.name) { index, entry in
                if let time = prayerTime(named: entry.name) {
                    if index > 0 {
                        Hairline(opacity: 0.6)
                    }
                    PrayerRow(
                        name: entry.name,
                        icon: entry.icon,
                        time: time,
                        isCurrent: entry.name == current,
                        isUpcoming: entry.name == upcoming?.name,
                        countdownDate: entry.name == upcoming?.name ? upcoming?.date : nil,
                        now: now,
                        isPast: isToday && time < now
                    )
                }
            }
        }
        .onReceive(ticker) { now = $0 }
    }

    private func prayerTime(named name: String) -> Date? {
        switch name {
        case "Fajr":     return times.fajr
        case "Sunrise":  return times.sunrise
        case "Dhuhr":    return times.dhuhr
        case "Asr":      return times.asr
        case "Maghrib":  return times.maghrib
        case "Isha":     return times.isha
        case "Midnight": return times.islamicMidnight
        default:         return nil
        }
    }
}

private struct PrayerRow: View {
    let name: String
    let icon: String
    let time: Date
    /// The prayer currently being observed.
    let isCurrent: Bool
    /// The next prayer coming up — carries the live countdown.
    let isUpcoming: Bool
    let countdownDate: Date?
    let now: Date
    let isPast: Bool

    private var accented: Bool { isCurrent || isUpcoming }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: accented ? .semibold : .regular))
                .foregroundStyle(accented ? Color.brand : Color(.label).opacity(0.35))
                .frame(width: 18)

            Text(name)
                .font(.appSerif(17, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(accented ? Color.brand : Color(.label))

            Spacer(minLength: 8)

            if isUpcoming, let date = countdownDate {
                MetaText("IN \(countdown(to: date))", tint: .brand, size: 9)
            }

            Text(Self.fmt.string(from: time))
                .font(.appSerif(16).monospacedDigit())
                .foregroundStyle(accented ? Color(.label) : Color(.label).opacity(0.5))
        }
        .padding(.vertical, 11)
        // Prayers already prayed step back so the eye lands on what's next.
        .opacity(isPast && !accented ? 0.45 : 1)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.brand)
                .frame(width: 2)
                .opacity(isCurrent ? 1 : 0)
                .offset(x: -12)
        }
        .animation(AppAnim.smooth, value: isCurrent)
        .accessibilityElement(children: .combine)
    }

    private func countdown(to date: Date) -> String {
        let secs = max(0, date.timeIntervalSince(now))
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        if h > 0 { return "\(h)H \(m)M" }
        if m > 0 { return "\(m)M" }
        return "NOW"
    }
}

// MARK: - Day picker

private struct DayPickerStrip: View {
    @Binding var selectedOffset: Int
    private let calendar = Calendar.current

    private func label(for offset: Int) -> String {
        if offset == 0 { return "Today" }
        if offset == 1 { return "Tomorrow" }
        guard let date = calendar.date(byAdding: .day, value: offset, to: Date()) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d"
        return fmt.string(from: date)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0...30, id: \.self) { offset in
                        let on = selectedOffset == offset
                        Button {
                            Haptics.selection()
                            withAnimation(AppAnim.smooth) { selectedOffset = offset }
                        } label: {
                            Text(label(for: offset).uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .kerning(1.1)
                                .foregroundStyle(on ? Color.brand : Color(.label).opacity(0.5))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .overlay(
                                    Rectangle().strokeBorder(on ? Color.brand : Color(.label).opacity(0.18),
                                                             lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(offset)
                    }
                }
                .padding(.vertical, 1)
            }
            .onChange(of: selectedOffset) { _, newVal in
                withAnimation { proxy.scrollTo(newVal, anchor: .center) }
            }
        }
    }
}

// MARK: - Prayer times for a given day offset

private struct PrayerTimesForDayView: View {
    @ObservedObject var service: PrayerTimesService
    let dayOffset: Int
    @State private var times: PrayerTimes? = nil
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if let t = times {
                PrayerTimesStrip(times: t, isToday: dayOffset == 0)
            } else {
                Color.clear.frame(height: 70)
            }
        }
        .task(id: dayOffset) {
            if dayOffset == 0 {
                times = service.prayerTimes
                return
            }
            if let cached = service.dailyTimings[dayOffset] {
                times = cached
                return
            }
            isLoading = true
            times = await service.fetchTimings(dayOffset: dayOffset)
            isLoading = false
        }
    }
}
