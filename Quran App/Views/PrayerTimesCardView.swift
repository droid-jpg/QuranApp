import SwiftUI
import Combine

struct PrayerTimesCardView: View {
    @ObservedObject var service: PrayerTimesService
    @State private var selectedOffset: Int = 0

    var body: some View {
        switch service.fetchStatus {
        case .notDetermined:
            Button { service.requestAndFetch() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.circle.fill").foregroundStyle(.brand)
                    Text("Enable Prayer Times").font(.subheadline).foregroundStyle(.brand)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }

        case .denied:
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill").foregroundStyle(.secondary)
                Text("Location access denied — enable in Settings").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)

        case .fetching:
            HStack(spacing: 8) {
                ProgressView()
                Text("Getting prayer times…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)

        case .ready:
            VStack(spacing: 0) {
                // Day picker strip
                DayPickerStrip(selectedOffset: $selectedOffset)
                    .padding(.top, 10)

                Divider().padding(.vertical, 6)

                // Prayer times for selected day
                PrayerTimesForDayView(service: service, dayOffset: selectedOffset)
            }
        }
    }
}

// MARK: - Prayer times strip (horizontal scrolling row of prayer cells)

struct PrayerTimesStrip: View {
    let times: PrayerTimes
    /// When false (a future/past date), no prayer is highlighted and no live
    /// countdown is shown — the times are purely informational.
    var isToday: Bool = true

    @State private var now = Date()
    @State private var showSunrise = false
    @State private var showMidnight = false
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private let basePrayers: [(String, String)] = [
        ("Fajr",    "moon.stars.fill"),
        ("Dhuhr",   "sun.max.fill"),
        ("Asr",     "sun.horizon.fill"),
        ("Maghrib", "sunset.fill"),
        ("Isha",    "moon.fill"),
    ]

    // Sunrise and Midnight are revealed by tapping Fajr / Isha respectively.
    private var displayEntries: [(String, String)] {
        var entries = basePrayers
        if showMidnight { entries.append(("Midnight", "moon.zzz.fill")) }
        if showSunrise, let idx = entries.firstIndex(where: { $0.0 == "Fajr" }) {
            entries.insert(("Sunrise", "sunrise.fill"), at: idx + 1)
        }
        return entries
    }

    private var current: String? { isToday ? times.currentPrayer(at: now) : nil }
    private var upcoming: (name: String, date: Date)? { isToday ? times.upcomingPrayer(at: now) : nil }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(displayEntries, id: \.0) { (name, icon) in
                    if let time = prayerTime(named: name) {
                        PrayerCell(
                            name: name,
                            icon: icon,
                            time: time,
                            isCurrent: name == current,
                            isUpcoming: name == upcoming?.name,
                            countdownDate: name == upcoming?.name ? upcoming?.date : nil,
                            now: now,
                            onTap: tapAction(for: name)
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .onReceive(ticker) { now = $0 }
    }

    private func tapAction(for name: String) -> (() -> Void)? {
        switch name {
        case "Fajr":
            return { withAnimation(.spring(duration: 0.3)) { showSunrise.toggle() } }
        case "Isha":
            return { withAnimation(.spring(duration: 0.3)) { showMidnight.toggle() } }
        default:
            return nil
        }
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

private struct PrayerCell: View {
    let name: String
    let icon: String
    let time: Date
    /// The prayer currently being prayed — gets a solid highlight.
    let isCurrent: Bool
    /// The next prayer coming up — gets a pulsing glow and a live countdown.
    let isUpcoming: Bool
    let countdownDate: Date?
    let now: Date
    let onTap: (() -> Void)?

    @State private var pulsing = false

    private var accent: Bool { isCurrent || isUpcoming }

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if isUpcoming {
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 30, height: 30)
                        .scaleEffect(pulsing ? 1.25 : 0.85)
                        .opacity(pulsing ? 0.3 : 0.12)
                        .blur(radius: 3)
                }
                Image(systemName: icon)
                    .font(.system(size: 16, weight: accent ? .semibold : .regular))
                    .foregroundStyle(accent ? .brand : .secondary)
            }
            .frame(height: 30)
            Text(name)
                .font(.system(size: 11, weight: accent ? .semibold : .regular))
                .foregroundStyle(accent ? .brand : .secondary)
            Text(Self.fmt.string(from: time))
                .font(.system(size: 12, weight: isCurrent ? .bold : .regular).monospacedDigit())
                .foregroundStyle(accent ? .primary : .secondary)
            if isUpcoming, let date = countdownDate {
                Text("in \(countdown(to: date))")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.brand)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrent ? Color.brand.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .animation(.easeInOut(duration: 0.3), value: isCurrent)
        .onAppear { if isUpcoming { startPulse() } }
        .onChange(of: isUpcoming) { _, newValue in
            if newValue { startPulse() } else { pulsing = false }
        }
    }

    private func startPulse() {
        pulsing = false
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }

    private func countdown(to date: Date) -> String {
        let secs = max(0, date.timeIntervalSince(now))
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "now"
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
                        Button {
                            withAnimation(.spring(duration: 0.3)) { selectedOffset = offset }
                        } label: {
                            Text(label(for: offset))
                                .font(.system(size: 13, weight: selectedOffset == offset ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedOffset == offset ? Color.brand : Color(.tertiarySystemBackground))
                                .foregroundStyle(selectedOffset == offset ? .white : .secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(offset)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
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
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 14)
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
