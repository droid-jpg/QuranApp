import Foundation
import SwiftUI

// MARK: - Event kind

enum IslamicEventKind: String, Codable {
    case holiday      // e.g. Eid, Islamic New Year
    case fastingDay   // e.g. Arafah, Ashura, Shawwal
    case fastingMonth // Ramadan (whole month)
    case recommended  // recommended acts on specific nights/days

    var color: Color {
        switch self {
        case .holiday:      return .brand
        case .fastingDay:   return .orange
        case .fastingMonth: return .purple
        case .recommended:  return .indigo
        }
    }

    var icon: String {
        switch self {
        case .holiday:      return "star.fill"
        case .fastingDay:   return "moon.fill"
        case .fastingMonth: return "moon.stars.fill"
        case .recommended:  return "sparkles"
        }
    }

    var label: String {
        switch self {
        case .holiday:      return "Holiday"
        case .fastingDay:   return "Fast"
        case .fastingMonth: return "Fasting Month"
        case .recommended:  return "Special Night/Day"
        }
    }

    /// Stable ordering when several events share a day.
    fileprivate var sortRank: Int {
        switch self {
        case .holiday:      return 0
        case .fastingMonth: return 1
        case .recommended:  return 2
        case .fastingDay:   return 3
        }
    }
}

// MARK: - Recurrence

/// How an event repeats. Fixed annual events use `.none` and are anchored to a
/// canonical Hijri month/day; their Gregorian date is resolved per year from the
/// device's Umm al-Qura calendar (so it follows the device locale/time zone).
enum Recurrence {
    case none
    case weeklyMonThu      // every Monday & Thursday
    case monthlyWhiteDays  // 13th–15th of every Hijri month

    /// Short human-readable cadence, nil for one-off events.
    var note: String? {
        switch self {
        case .none:             return nil
        case .weeklyMonThu:     return "Every Mon & Thu"
        case .monthlyWhiteDays: return "13th–15th each month"
        }
    }
}

// MARK: - Event

struct IslamicEvent: Identifiable {
    let id: Int
    let name: String
    let arabicName: String
    let kind: IslamicEventKind
    /// Canonical Hijri anchor (1–12 month, 1–30 day). Ignored for recurring events.
    let hijriMonth: Int
    let hijriDay: Int
    let description: String
    let durationDays: Int
    var recurrence: Recurrence = .none
}

// MARK: - 1447 AH onward — anchored to canonical Hijri dates

extension IslamicEvent {
    static let all: [IslamicEvent] = [

        // ── Muharram (1) ──────────────────────────────────────────────
        IslamicEvent(id: 1,
            name: "Islamic New Year",    arabicName: "رأس السنة الهجرية",
            kind: .holiday, hijriMonth: 1, hijriDay: 1,
            description: "First day of Muharram — the start of the Islamic lunar year.",
            durationDays: 1),

        IslamicEvent(id: 2,
            name: "Day of Ashura",       arabicName: "يوم عاشوراء",
            kind: .fastingDay, hijriMonth: 1, hijriDay: 10,
            description: "10th of Muharram. Fasting expiates sins of the previous year. Recommended to also fast the 9th.",
            durationDays: 1),

        // ── Rabi' al-Awwal (3) ────────────────────────────────────────
        IslamicEvent(id: 3,
            name: "Mawlid an-Nabi ﷺ",   arabicName: "المولد النبوي الشريف",
            kind: .holiday, hijriMonth: 3, hijriDay: 12,
            description: "12th Rabi' al-Awwal — the birthday of the Prophet Muhammad ﷺ.",
            durationDays: 1),

        // ── Rajab (7) ─────────────────────────────────────────────────
        IslamicEvent(id: 4,
            name: "Isra' and Mi'raj",   arabicName: "الإسراء والمعراج",
            kind: .recommended, hijriMonth: 7, hijriDay: 27,
            description: "27th Rajab — the Night Journey and Ascension of the Prophet ﷺ to the heavens.",
            durationDays: 1),

        // ── Sha'ban (8) ───────────────────────────────────────────────
        IslamicEvent(id: 5,
            name: "Laylat al-Bara'ah",  arabicName: "ليلة البراءة",
            kind: .recommended, hijriMonth: 8, hijriDay: 15,
            description: "15th Sha'ban — the Night of Forgiveness. Many engage in extra worship and supplication.",
            durationDays: 1),

        // ── Ramadan (9) ───────────────────────────────────────────────
        IslamicEvent(id: 6,
            name: "Ramadan",            arabicName: "رمضان",
            kind: .fastingMonth, hijriMonth: 9, hijriDay: 1,
            description: "The blessed month of fasting, Quran recitation, Tarawih prayers, and increased worship.",
            durationDays: 30),

        IslamicEvent(id: 7,
            name: "Laylat al-Qadr",     arabicName: "ليلة القدر",
            kind: .recommended, hijriMonth: 9, hijriDay: 27,
            description: "The Night of Power — one of the last 10 odd nights of Ramadan, better than 1,000 months (Quran 97:3).",
            durationDays: 1),

        // ── Shawwal (10) ──────────────────────────────────────────────
        IslamicEvent(id: 8,
            name: "Eid al-Fitr",        arabicName: "عيد الفطر",
            kind: .holiday, hijriMonth: 10, hijriDay: 1,
            description: "1st Shawwal — Eid marking the end of Ramadan. Fasting is forbidden. Special congregational prayer in the morning.",
            durationDays: 3),

        IslamicEvent(id: 9,
            name: "Six Days of Shawwal", arabicName: "صيام ستة من شوال",
            kind: .fastingDay, hijriMonth: 10, hijriDay: 2,
            description: "Fasting any 6 days of Shawwal after Eid al-Fitr is like fasting the entire year (Hadith Muslim).",
            durationDays: 6),

        // ── Dhul Hijjah (12) ──────────────────────────────────────────
        IslamicEvent(id: 10,
            name: "First 10 Days of Dhul Hijjah", arabicName: "عشر ذي الحجة",
            kind: .recommended, hijriMonth: 12, hijriDay: 1,
            description: "The best 10 days of the year. Extra dhikr, fasting, and good deeds are especially rewarded.",
            durationDays: 9),

        IslamicEvent(id: 11,
            name: "Day of Arafah",      arabicName: "يوم عرفة",
            kind: .fastingDay, hijriMonth: 12, hijriDay: 9,
            description: "9th Dhul Hijjah — fasting expiates sins of the previous and coming year (Hadith Muslim).",
            durationDays: 1),

        IslamicEvent(id: 12,
            name: "Eid al-Adha",        arabicName: "عيد الأضحى",
            kind: .holiday, hijriMonth: 12, hijriDay: 10,
            description: "10th Dhul Hijjah — Eid of Sacrifice, commemorating Ibrahim's ﷺ willingness to sacrifice his son.",
            durationDays: 4),

        IslamicEvent(id: 13,
            name: "Days of Tashriq",    arabicName: "أيام التشريق",
            kind: .recommended, hijriMonth: 12, hijriDay: 11,
            description: "11th–13th Dhul Hijjah — days of eating, drinking, and remembering Allah. Fasting is prohibited.",
            durationDays: 3),

        // ── Recurring ─────────────────────────────────────────────────
        IslamicEvent(id: 14,
            name: "Fast of Mon. & Thu.", arabicName: "صيام الاثنين والخميس",
            kind: .fastingDay, hijriMonth: 0, hijriDay: 0,
            description: "The Prophet ﷺ fasted every Monday and Thursday. Deeds are presented to Allah on these days.",
            durationDays: 1, recurrence: .weeklyMonThu),

        IslamicEvent(id: 15,
            name: "White Days (Ayyam al-Bid)", arabicName: "أيام البيض",
            kind: .fastingDay, hijriMonth: 0, hijriDay: 0,
            description: "13th, 14th, and 15th of every Islamic month. Fasting on these full-moon days is like fasting all year.",
            durationDays: 3, recurrence: .monthlyWhiteDays),
    ]
}

// MARK: - Concrete occurrences

/// A single dated instance of an event. Fixed events have one per Hijri year;
/// recurring events resolve to whichever instance is relevant for a query.
struct EventOccurrence: Identifiable {
    let event: IslamicEvent
    let start: Date
    let end: Date   // inclusive

    var id: String { "\(event.id)@\(Int(start.timeIntervalSince1970))" }

    var isMultiDay: Bool { !Calendar.current.isDate(start, inSameDayAs: end) }

    func durationDays(_ cal: Calendar = .current) -> Int {
        let a = cal.startOfDay(for: start)
        let b = cal.startOfDay(for: end)
        return (cal.dateComponents([.day], from: a, to: b).day ?? 0) + 1
    }
}

extension IslamicEvent {

    /// Device Umm al-Qura calendar, in the local time zone — the source of truth
    /// for resolving canonical Hijri dates to Gregorian dates.
    static let hijri: Calendar = {
        var c = Calendar(identifier: .islamicUmmAlQura)
        c.timeZone = .current
        return c
    }()

    /// Gregorian start-of-day for this event's Hijri anchor in the given Hijri year.
    func gregorianStart(hijriYear hy: Int, calendar cal: Calendar = .current) -> Date? {
        guard recurrence == .none else { return nil }
        var comps = DateComponents()
        comps.year  = hy
        comps.month = hijriMonth
        comps.day   = hijriDay
        guard let date = IslamicEvent.hijri.date(from: comps) else { return nil }
        return cal.startOfDay(for: date)
    }

    /// The dated instance of a fixed event for a specific Hijri year.
    func occurrence(inHijriYear hy: Int, calendar cal: Calendar = .current) -> EventOccurrence? {
        guard let start = gregorianStart(hijriYear: hy, calendar: cal) else { return nil }
        let end = cal.date(byAdding: .day, value: max(0, durationDays - 1), to: start) ?? start
        return EventOccurrence(event: self, start: start, end: end)
    }

    /// Whether this event covers `day` (recurrence-aware, time ignored).
    func covers(_ day: Date, calendar cal: Calendar = .current) -> Bool {
        occurrence(covering: day, calendar: cal) != nil
    }

    /// The dated instance covering `day`, if any.
    func occurrence(covering day: Date, calendar cal: Calendar = .current) -> EventOccurrence? {
        let target = cal.startOfDay(for: day)
        switch recurrence {
        case .none:
            let hy = IslamicEvent.hijri.component(.year, from: target)
            for y in (hy - 1)...(hy + 1) {
                if let occ = occurrence(inHijriYear: y, calendar: cal),
                   occ.start <= target, target <= occ.end {
                    return occ
                }
            }
            return nil

        case .weeklyMonThu:
            let wd = cal.component(.weekday, from: target)   // 1=Sun … 7=Sat
            guard wd == 2 || wd == 5 else { return nil }
            return EventOccurrence(event: self, start: target, end: target)

        case .monthlyWhiteDays:
            let hd = IslamicEvent.hijri.component(.day, from: target)
            guard (13...15).contains(hd) else { return nil }
            let start = cal.date(byAdding: .day, value: -(hd - 13), to: target) ?? target
            let end   = cal.date(byAdding: .day, value: 15 - hd, to: target) ?? target
            return EventOccurrence(event: self, start: start, end: end)
        }
    }

    /// Next instance on or after `from` (recurrence-aware).
    func nextOccurrence(onOrAfter from: Date, calendar cal: Calendar = .current) -> EventOccurrence? {
        let startDay = cal.startOfDay(for: from)
        switch recurrence {
        case .none:
            let hy = IslamicEvent.hijri.component(.year, from: startDay)
            return ((hy - 1)...(hy + 2))
                .compactMap { occurrence(inHijriYear: $0, calendar: cal) }
                .filter { $0.end >= startDay }
                .sorted { $0.start < $1.start }
                .first

        case .weeklyMonThu:
            for offset in 0...7 {
                if let d = cal.date(byAdding: .day, value: offset, to: startDay),
                   occurrence(covering: d, calendar: cal) != nil {
                    return EventOccurrence(event: self, start: d, end: d)
                }
            }
            return nil

        case .monthlyWhiteDays:
            for offset in 0..<420 {
                guard let d = cal.date(byAdding: .day, value: offset, to: startDay) else { break }
                let hd = IslamicEvent.hijri.component(.day, from: d)
                if (13...15).contains(hd) {
                    let start = cal.date(byAdding: .day, value: -(hd - 13), to: d) ?? d
                    let end   = cal.date(byAdding: .day, value: 15 - hd, to: d) ?? d
                    return EventOccurrence(event: self, start: start, end: end)
                }
                if hd < 13 {
                    let start = cal.date(byAdding: .day, value: 13 - hd, to: d) ?? d
                    let end   = cal.date(byAdding: .day, value: 2, to: start) ?? start
                    return EventOccurrence(event: self, start: start, end: end)
                }
            }
            return nil
        }
    }

    // MARK: Collection queries

    /// Events covering `day`, optionally filtered by kind.
    static func events(on day: Date,
                       kind: IslamicEventKind? = nil,
                       calendar cal: Calendar = .current) -> [EventOccurrence] {
        all.filter { kind == nil || $0.kind == kind }
           .compactMap { $0.occurrence(covering: day, calendar: cal) }
           .sorted { $0.event.kind.sortRank < $1.event.kind.sortRank }
    }

    /// Upcoming-first agenda. Fixed events that ended more than `pastWindowDays`
    /// ago roll forward to their next yearly occurrence; recurring events resolve
    /// to their next occurrence.
    static func agenda(reference: Date = Date(),
                       pastWindowDays: Int = 21,
                       kind: IslamicEventKind? = nil,
                       calendar cal: Calendar = .current) -> [EventOccurrence] {
        let today = cal.startOfDay(for: reference)
        guard let cutoff = cal.date(byAdding: .day, value: -pastWindowDays, to: today) else { return [] }
        let hy = hijri.component(.year, from: today)

        var out: [EventOccurrence] = []
        for event in all where (kind == nil || event.kind == kind) {
            switch event.recurrence {
            case .none:
                // Soonest occurrence whose end is still within the past window or future.
                let pick = ((hy - 1)...(hy + 2))
                    .compactMap { event.occurrence(inHijriYear: $0, calendar: cal) }
                    .filter { cal.startOfDay(for: $0.end) >= cutoff }
                    .sorted { $0.start < $1.start }
                    .first
                if let pick { out.append(pick) }
            default:
                if let occ = event.nextOccurrence(onOrAfter: reference, calendar: cal) {
                    out.append(occ)
                }
            }
        }
        return out.sorted { $0.start < $1.start }
    }
}
