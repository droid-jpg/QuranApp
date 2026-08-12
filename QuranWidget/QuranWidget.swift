import WidgetKit
import SwiftUI

private let appGroup = "group.sami.Quran-App"

// The 7 daily events the widget can surface as "next". Order only breaks ties
// between events sharing a minute (effectively never); the actual next event is
// chosen by soonest next-occurrence in `nextEvent`, which handles wrap-around.
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
    /// The ayah being drilled right now, from the shared hifz target.
    let hifz: HifzSnapshot?
    /// The last thing that was actually playing.
    let listening: ListenSnapshot?

    struct HifzSnapshot {
        let surahName: String
        let workingAyah: Int
        let totalAyahs: Int
        let learnedThrough: Int
        var fraction: Double {
            totalAyahs > 0 ? min(1, Double(learnedThrough) / Double(totalAyahs)) : 0
        }
    }

    struct ListenSnapshot {
        let surahName: String
        let ayah: Int
    }

    static let placeholder = QuranWidgetEntry(
        date: Date(),
        nextEvent: "Asr",
        nextEventTime: "3:45 PM",
        nextEventDate: Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date(),
        lastSurah: "Al-Mulk",
        memorizedCount: 12,
        hifz: .init(surahName: "Al-Mulk", workingAyah: 14, totalAyahs: 30, learnedThrough: 13),
        listening: .init(surahName: "Al-Mulk", ayah: 14)
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
            memorizedCount: memorized,
            hifz: hifzTarget(ud: ud),
            listening: listenSession(ud: ud)
        )
    }

    private func memorizedCount(ud: UserDefaults?) -> Int {
        guard
            let data = ud?.data(forKey: "quran_memorization_v1"),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return 0 }
        return dict.values.filter { $0 == "memorized" }.count
    }

    /// The hifz target the app writes on every working-ayah change. Decoded
    /// loosely — only the fields the widget draws — so a future field added on
    /// the app side can't blank the widget out.
    private func hifzTarget(ud: UserDefaults?) -> QuranWidgetEntry.HifzSnapshot? {
        guard
            let data = ud?.data(forKey: "quran_hifz_target_v1"),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = obj["surahName"] as? String,
            let working = obj["workingAyah"] as? Int,
            let total = obj["totalAyahs"] as? Int
        else { return nil }
        return .init(surahName: name, workingAyah: working, totalAyahs: total,
                     learnedThrough: obj["learnedThrough"] as? Int ?? 0)
    }

    private func listenSession(ud: UserDefaults?) -> QuranWidgetEntry.ListenSnapshot? {
        guard
            let data = ud?.data(forKey: "quran_listening_session_v1"),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = obj["surahName"] as? String, !name.isEmpty,
            let ayah = obj["ayah"] as? Int
        else { return nil }
        return .init(surahName: name, ayah: ayah)
    }

    /// Returns (eventName, displayTime, exactDate) for the next upcoming event from
    /// all 7. Each event's next occurrence is its time today if that's still ahead,
    /// otherwise the same time tomorrow; the soonest wins. Computing per-event next
    /// occurrences (rather than scanning today's clock in fixed order) is what lets
    /// Sunrise and an Islamic Midnight that lands after 00:00 surface correctly —
    /// the latter reads as "past" today in the evening, so it must roll to tomorrow.
    private func nextEvent(ud: UserDefaults?) -> (String, String, Date) {
        guard
            let data = ud?.data(forKey: "prayerTimesDict"),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return ("—", "—", Date()) }

        let hhmm    = DateFormatter(); hhmm.dateFormat = "HH:mm"
        let display = DateFormatter(); display.timeStyle = .short
        let now     = Date()
        let cal     = Calendar.current

        var best: (name: String, date: Date)?
        for name in allEventOrder {
            guard
                let str = dict[name], !str.isEmpty,
                let parsed = hhmm.date(from: str)
            else { continue }
            let c = cal.dateComponents([.hour, .minute], from: parsed)
            guard let today = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0,
                                       second: 0, of: now) else { continue }
            let occurrence = today > now
                ? today
                : (cal.date(byAdding: .day, value: 1, to: today) ?? today)
            if best == nil || occurrence < best!.date {
                best = (name, occurrence)
            }
        }

        if let best {
            return (best.name, display.string(from: best.date), best.date)
        }
        return ("Fajr", "—", Date())
    }
}

// MARK: - Widget type
//
// The widget speaks the app's restyled language: hairlines instead of cards,
// small-caps eyebrows, the reading serif for names, and the user's chosen accent
// used as a mark rather than a fill.

private struct WEyebrow: View {
    let text: String
    var tint: Color = .secondary
    var size: CGFloat = 8.5

    init(_ text: String, tint: Color = .secondary, size: CGFloat = 8.5) {
        self.text = text
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .bold))
            .kerning(1.3)
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

private struct WRule: View {
    var body: some View {
        Rectangle()
            .fill(Color(.label).opacity(0.15))
            .frame(height: 1)
    }
}

private extension Font {
    /// The widget can't reach the app's `ReadingFace`, and a custom face would
    /// have to be bundled into the extension too — so it uses New York, which is
    /// both the app's default and always present.
    static func wSerif(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let base = Font.system(size: size, weight: weight, design: .serif)
        return italic ? base.italic() : base
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
        case .systemLarge:              LargeView(entry: entry)
        // Lock-screen families
        case .accessoryRectangular:     AccessoryRectangularView(entry: entry)
        case .accessoryCircular:        AccessoryCircularView(entry: entry)
        case .accessoryInline:          AccessoryInlineView(entry: entry)
        default:                        SmallView(entry: entry)
        }
    }
}

// MARK: - Home-screen: Small

/// One thing, well: the next prayer, with the countdown as the only accent.
private struct SmallView: View {
    let entry: QuranWidgetEntry
    private var accent: Color { AppTheme.current.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WEyebrow("Next prayer", tint: accent)

            Spacer(minLength: 4)

            Text(entry.nextEvent)
                .font(.wSerif(24, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(entry.nextEventTime)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            Spacer(minLength: 4)

            WRule().padding(.bottom, 7)

            Text(entry.nextEventDate, style: .timer)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(accent)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(15)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Home-screen: Medium

/// The next prayer on the left, what you're memorizing on the right, a hairline
/// between them.
private struct MediumView: View {
    let entry: QuranWidgetEntry
    private var accent: Color { AppTheme.current.accent }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                WEyebrow("Next prayer", tint: accent)
                Spacer(minLength: 6)
                Text(entry.nextEvent)
                    .font(.wSerif(23, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entry.nextEventTime)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text(entry.nextEventDate, style: .timer)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color(.label).opacity(0.15))
                .frame(width: 1)
                .padding(.horizontal, 15)

            VStack(alignment: .leading, spacing: 0) {
                if let h = entry.hifz {
                    WEyebrow("Memorizing")
                    Spacer(minLength: 6)
                    Text(h.surahName)
                        .font(.wSerif(19, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("ayah \(h.workingAyah) of \(h.totalAyahs)")
                        .font(.wSerif(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    WProgress(fraction: h.fraction, tint: accent)
                } else {
                    WEyebrow("Last read")
                    Spacer(minLength: 6)
                    Text(entry.lastSurah)
                        .font(.wSerif(19, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 6)
                    Text("\(entry.memorizedCount) surahs memorized")
                        .font(.wSerif(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Home-screen: Large

/// The dashboard's own shape, shrunk: a masthead rule, then the same ruled
/// blocks — memorizing, listening, prayer — in the same order as the app.
private struct LargeView: View {
    let entry: QuranWidgetEntry
    private var accent: Color { AppTheme.current.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("Holy Quran")
                    .font(.wSerif(19, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Rectangle()
                    .fill(Color(.label).opacity(0.15))
                    .frame(height: 1)
                Text("\(entry.memorizedCount) MEMORIZED")
                    .font(.system(size: 8.5, weight: .bold))
                    .kerning(1.1)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)

            if let h = entry.hifz {
                WRule().padding(.bottom, 9)
                HStack {
                    WEyebrow("Memorizing", tint: accent)
                    Spacer()
                    Text("\(Int((h.fraction * 100).rounded()))%")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 5)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(h.surahName)
                        .font(.wSerif(20, weight: .medium))
                        .lineLimit(1)
                    Text("ayah \(h.workingAyah) of \(h.totalAyahs)")
                        .font(.wSerif(14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                WProgress(fraction: h.fraction, tint: accent)
                    .padding(.top, 9)
                    .padding(.bottom, 14)
            }

            if let l = entry.listening {
                WRule().padding(.bottom, 9)
                WEyebrow("Last played").padding(.bottom, 5)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(l.surahName)
                        .font(.wSerif(20, weight: .medium))
                        .lineLimit(1)
                    Text("ayah \(l.ayah)")
                        .font(.wSerif(14))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 14)
            }

            WRule().padding(.bottom, 9)
            HStack {
                WEyebrow("Next prayer")
                Spacer()
                Text(entry.nextEventDate, style: .timer)
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
            .padding(.bottom, 5)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(entry.nextEvent)
                    .font(.wSerif(20, weight: .medium))
                Text(entry.nextEventTime)
                    .font(.wSerif(15).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Progress rule

private struct WProgress: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(.label).opacity(0.16))
                Rectangle()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 1.5)
    }
}

// MARK: - Lock-screen: Rectangular

/// Lock-screen families are drawn in a single tint by the system, so these are
/// built from weight and case rather than colour.
private struct AccessoryRectangularView: View {
    let entry: QuranWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.nextEvent.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(1.2)
                .widgetAccentable()
            Text(entry.nextEventTime)
                .font(.system(size: 17, weight: .medium, design: .serif).monospacedDigit())
            Text(entry.nextEventDate, style: .timer)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
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
                .font(.system(size: 13, weight: .semibold))
                .widgetAccentable()
            Text(shortName(entry.nextEvent))
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(entry.nextEventTime)
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .containerBackground(.background, for: .widget)
    }

    private func shortName(_ name: String) -> String {
        name == "Midnight" ? "Mid." : name
    }

    private func eventSymbol(_ name: String) -> String {
        switch name {
        case "Fajr":     return "moon.stars.fill"
        case "Sunrise":  return "sunrise.fill"
        case "Dhuhr":    return "sun.max.fill"
        case "Asr":      return "sun.horizon.fill"
        case "Maghrib":  return "sunset.fill"
        case "Isha":     return "moon.fill"
        case "Midnight": return "zzz"
        default:         return "clock.fill"
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

// MARK: - Widgets

struct QuranWidget: Widget {
    let kind = "QuranWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuranWidgetProvider()) { entry in
            QuranWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Holy Quran")
        .description("Next prayer, what you're memorizing, and where you left off.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryCircular, .accessoryInline
        ])
    }
}

/// A second, single-purpose widget for people who only want the hifz thread on
/// their home screen — the working ayah, big, with the surah's progress rule.
struct HifzWidget: Widget {
    let kind = "HifzWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuranWidgetProvider()) { entry in
            HifzWidgetView(entry: entry)
        }
        .configurationDisplayName("Memorizing")
        .description("The ayah you're working on and how far through the surah you are.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HifzWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: QuranWidgetEntry
    private var accent: Color { AppTheme.current.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WEyebrow("Memorizing", tint: accent)

            Spacer(minLength: 6)

            if let h = entry.hifz {
                Text(h.surahName)
                    .font(.wSerif(family == .systemSmall ? 21 : 26, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Ayah \(h.workingAyah)")
                    .font(.wSerif(family == .systemSmall ? 14 : 17))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)

                Spacer(minLength: 8)

                WProgress(fraction: h.fraction, tint: accent)
                    .padding(.bottom, 7)

                HStack(spacing: 6) {
                    // "13 of 30 learned" doesn't fit the small family, so the
                    // long form is reserved for medium.
                    Text(family == .systemSmall
                         ? "\(h.learnedThrough)/\(h.totalAyahs) learned"
                         : "\(h.learnedThrough) of \(h.totalAyahs) ayahs learned")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("\(Int((h.fraction * 100).rounded()))%")
                        .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(accent)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            } else {
                Text("Nothing in progress")
                    .font(.wSerif(family == .systemSmall ? 17 : 20, weight: .medium))
                Text("Pick a surah to start")
                    .font(.wSerif(13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(15)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    QuranWidget()
} timeline: { QuranWidgetEntry.placeholder }

#Preview("Medium", as: .systemMedium) {
    QuranWidget()
} timeline: { QuranWidgetEntry.placeholder }

#Preview("Large", as: .systemLarge) {
    QuranWidget()
} timeline: { QuranWidgetEntry.placeholder }

#Preview("Hifz Small", as: .systemSmall) {
    HifzWidget()
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
