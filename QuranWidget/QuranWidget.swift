import WidgetKit
import SwiftUI

private let appGroup = "group.sami.Quran-App"

// Display order for all 7 daily events.
// Midnight sits after Isha but can fall after midnight clock-wise, so we check
// "same day" first then "tomorrow" to handle wrap-around correctly.
private let allEventOrder = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha", "Midnight"]

// MARK: - Entry

struct QuranWidgetEntry: TimelineEntry {
    let date: Date
    // Next upcoming event (prayer, Sunrise, or Midnight)
    let nextEvent: String
    let nextEventTime: String        // formatted for display (e.g. "3:45 PM")
    let nextEventDate: Date          // actual Date for countdown timers
    // Reading & memorization
    let lastSurah: String
    let memorizedCount: Int

    static let placeholder = QuranWidgetEntry(
        date: Date(),
        nextEvent: "Asr",
        nextEventTime: "3:45 PM",
        nextEventDate: Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date(),
        lastSurah: "Al-Baqarah",
        memorizedCount: 3
    )
}

// MARK: - Provider

struct QuranWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> QuranWidgetEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (QuranWidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuranWidgetEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh 30 min after now, or 1 min after the next event fires — whichever is sooner.
        let thirtyMin = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let afterEvent = entry.nextEventDate.addingTimeInterval(60)
        let next = min(thirtyMin, afterEvent)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    // MARK: - Data helpers

    private func makeEntry() -> QuranWidgetEntry {
        let ud = UserDefaults(suiteName: appGroup)
        let surah      = ud?.string(forKey: "lastSurahName") ?? "—"
        let memorized  = memorizedCount(ud: ud)
        let (name, timeStr, date) = nextEvent(ud: ud)
        return QuranWidgetEntry(
            date: Date(),
            nextEvent: name,
            nextEventTime: timeStr,
            nextEventDate: date,
            lastSurah: surah,
            memorizedCount: memorized
        )
    }

    private func memorizedCount(ud: UserDefaults?) -> Int {
        guard
            let data = ud?.data(forKey: "quran_memorization_v1"),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return 0 }
        return dict.values.filter { $0 == "memorized" }.count
    }

    /// Returns (eventName, displayTime, exactDate) for the next upcoming event from all 7.
    private func nextEvent(ud: UserDefaults?) -> (String, String, Date) {
        guard
            let data = ud?.data(forKey: "prayerTimesDict"),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return ("—", "—", Date()) }

        let hhmm    = DateFormatter(); hhmm.dateFormat = "HH:mm"
        let display = DateFormatter(); display.timeStyle = .short
        let now     = Date()
        let cal     = Calendar.current

        let todayComponents = cal.dateComponents([.year, .month, .day], from: now)

        for name in allEventOrder {
            guard let str = dict[name], let parsed = hhmm.date(from: str) else { continue }
            var c = cal.dateComponents([.hour, .minute], from: parsed)
            c.year  = todayComponents.year
            c.month = todayComponents.month
            c.day   = todayComponents.day
            if let candidate = cal.date(from: c), candidate > now {
                return (name, display.string(from: candidate), candidate)
            }
        }

        // All events passed today — return tomorrow's Fajr.
        if let fajrStr = dict["Fajr"], let parsed = hhmm.date(from: fajrStr) {
            var c = cal.dateComponents([.hour, .minute], from: parsed)
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            let tc = cal.dateComponents([.year, .month, .day], from: tomorrow)
            c.year = tc.year; c.month = tc.month; c.day = tc.day
            if let d = cal.date(from: c) {
                return ("Fajr", display.string(from: d), d)
            }
        }
        return ("Fajr", "—", Date())
    }
}

// MARK: - Home-screen views

struct QuranWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: QuranWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:              SmallView(entry: entry)
        case .systemMedium:             MediumView(entry: entry)
        // Lock-screen families
        case .accessoryRectangular:     AccessoryRectangularView(entry: entry)
        case .accessoryCircular:        AccessoryCircularView(entry: entry)
        case .accessoryInline:          AccessoryInlineView(entry: entry)
        default:                        SmallView(entry: entry)
        }
    }
}

// MARK: - Home-screen: Small

private struct SmallView: View {
    let entry: QuranWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "moon.stars.fill").font(.caption2).foregroundStyle(.teal)
                Text("Quran").font(.caption2.bold()).foregroundStyle(.teal)
            }
            Spacer()
            Text(entry.nextEvent).font(.headline)
            Text(entry.nextEventTime).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(entry.lastSurah).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Home-screen: Medium

private struct MediumView: View {
    let entry: QuranWidgetEntry
    var body: some View {
        HStack(spacing: 0) {
            // Left — next event
            VStack(alignment: .leading, spacing: 4) {
                Label("Next", systemImage: "moon.stars.fill")
                    .font(.caption2.bold()).foregroundStyle(.teal)
                Spacer()
                Text(entry.nextEvent).font(.title2.bold())
                Text(entry.nextEventTime).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16).padding(.vertical, 14)

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 0.5)
                .padding(.vertical, 12)

            // Right — reading
            VStack(alignment: .leading, spacing: 4) {
                Label("Reading", systemImage: "book.fill")
                    .font(.caption2.bold()).foregroundStyle(.teal)
                Spacer()
                Text(entry.lastSurah).font(.subheadline.bold()).lineLimit(1)
                Spacer()
                Label("\(entry.memorizedCount) memorized", systemImage: "checkmark.seal.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14).padding(.trailing, 16).padding(.vertical, 14)
        }
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Lock-screen: Rectangular

private struct AccessoryRectangularView: View {
    let entry: QuranWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Next", systemImage: "moon.stars.fill")
                .font(.caption2).foregroundStyle(.secondary)
            Text(entry.nextEvent)
                .font(.headline)
            Text(entry.nextEventTime)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Lock-screen: Circular

private struct AccessoryCircularView: View {
    let entry: QuranWidgetEntry
    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: eventSymbol(entry.nextEvent))
                .font(.system(size: 14, weight: .semibold))
            Text(shortName(entry.nextEvent))
                .font(.system(size: 12, weight: .bold))
            Text(entry.nextEventTime)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .containerBackground(.background, for: .widget)
    }

    private func shortName(_ name: String) -> String {
        name == "Midnight" ? "Mid." : name
    }

    private func eventSymbol(_ name: String) -> String {
        switch name {
        case "Fajr":    return "moon.stars.fill"
        case "Sunrise": return "sunrise.fill"
        case "Dhuhr":   return "sun.max.fill"
        case "Asr":     return "sun.horizon.fill"
        case "Maghrib": return "sunset.fill"
        case "Isha":    return "moon.fill"
        case "Midnight": return "zzz"
        default:        return "clock.fill"
        }
    }
}

// MARK: - Lock-screen: Inline

private struct AccessoryInlineView: View {
    let entry: QuranWidgetEntry
    var body: some View {
        Label("\(entry.nextEvent) · \(entry.nextEventTime)",
              systemImage: "moon.stars.fill")
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Widget

struct QuranWidget: Widget {
    let kind = "QuranWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuranWidgetProvider()) { entry in
            QuranWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Quran")
        .description("Next prayer, Sunrise, or Midnight · Reading progress.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryCircular, .accessoryInline
        ])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    QuranWidget()
} timeline: { QuranWidgetEntry.placeholder }

#Preview("Medium", as: .systemMedium) {
    QuranWidget()
} timeline: { QuranWidgetEntry.placeholder }

#Preview("Lock Rectangular", as: .accessoryRectangular) {
    QuranWidget()
} timeline: { QuranWidgetEntry.placeholder }

#Preview("Lock Circular", as: .accessoryCircular) {
    QuranWidget()
} timeline: { QuranWidgetEntry.placeholder }

#Preview("Lock Inline", as: .accessoryInline) {
    QuranWidget()
} timeline: { QuranWidgetEntry.placeholder }
