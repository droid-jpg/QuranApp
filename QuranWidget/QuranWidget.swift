import WidgetKit
import SwiftUI

// The lock-screen prayer time widget: the next prayer, its time and a countdown.
// The app writes the coming days' prayer times to the App Group, and the timeline
// here holds one entry per prayer, so the widget stays right for days without the
// app being opened.

private let appGroup = "group.com.saminukta.Quran-App"

struct PrayerEntry: TimelineEntry {
    let date: Date
    let name: String
    let time: Date?

    static let placeholder = PrayerEntry(date: .now, name: "Asr", time: Date().addingTimeInterval(2 * 3600))
    static let empty = PrayerEntry(date: .now, name: "Prayer", time: nil)
}

struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        completion(context.isPreview ? .placeholder : (entries().first ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        let entries = entries()
        if entries.isEmpty {
            // Nothing from the app yet: look again in an hour.
            completion(Timeline(entries: [.empty], policy: .after(Date().addingTimeInterval(3600))))
        } else {
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    /// One entry per upcoming prayer. Each takes over the moment the one before it begins.
    private func entries() -> [PrayerEntry] {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "prayerEvents"),
              let raw = try? JSONDecoder().decode([[String: String]].self, from: data) else { return [] }
        let now = Date()
        let events: [(name: String, time: Date)] = raw.compactMap { item in
            guard let name = item["n"], let t = item["t"].flatMap(Double.init) else { return nil }
            return (name, Date(timeIntervalSince1970: t))
        }
        .filter { $0.time > now }
        .sorted { $0.time < $1.time }

        var result: [PrayerEntry] = []
        var startsAt = now
        for event in events.prefix(40) {
            result.append(PrayerEntry(date: startsAt, name: event.name, time: event.time))
            startsAt = event.time
        }
        return result
    }
}

// Lock-screen families are drawn in one tint by the system, so these are built from
// weight rather than colour.

private struct RectangularView: View {
    let entry: PrayerEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.name)
                .font(.system(size: 12, weight: .bold))
                .widgetAccentable()
            if let time = entry.time {
                Text(time, style: .time)
                    .font(.system(size: 17, weight: .medium, design: .serif).monospacedDigit())
                Text(time, style: .timer)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Open Quran to load prayer times")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CircularView: View {
    let entry: PrayerEntry
    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .widgetAccentable()
            Text(entry.name == "Midnight" ? "Mid." : entry.name)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let time = entry.time {
                Text(time, style: .time)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var symbol: String {
        switch entry.name {
        case "Fajr":     "moon.stars.fill"
        case "Sunrise":  "sunrise.fill"
        case "Dhuhr":    "sun.max.fill"
        case "Asr":      "sun.horizon.fill"
        case "Maghrib":  "sunset.fill"
        case "Isha":     "moon.fill"
        case "Midnight": "zzz"
        default:         "clock.fill"
        }
    }
}

private struct InlineView: View {
    let entry: PrayerEntry
    var body: some View {
        if let time = entry.time {
            Label("\(entry.name) · \(time.formatted(date: .omitted, time: .shortened))", systemImage: "moon.stars.fill")
        } else {
            Label("Prayer times", systemImage: "moon.stars.fill")
        }
    }
}

private struct PrayerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrayerEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: CircularView(entry: entry)
            case .accessoryInline:   InlineView(entry: entry)
            default:                 RectangularView(entry: entry)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

struct QuranWidget: Widget {
    let kind = "QuranWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerProvider()) { entry in
            PrayerWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Prayer")
        .description("The next prayer, its time and a countdown.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

#Preview(as: .accessoryRectangular) {
    QuranWidget()
} timeline: {
    PrayerEntry.placeholder
}
