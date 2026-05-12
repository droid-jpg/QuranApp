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
        case .holiday:      return .teal
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
}

// MARK: - Event

struct IslamicEvent: Identifiable {
    let id: Int
    let name: String
    let arabicName: String
    let kind: IslamicEventKind
    /// Gregorian year (2025 or 2026).  0 = recurring (no fixed yearly date).
    let gregorianYear: Int
    let gregorianMonth: Int
    let gregorianDay: Int
    let description: String
    let durationDays: Int

    /// The exact Gregorian start date for 1447 AH, nil for recurring events.
    var actualDate: Date? {
        guard gregorianYear > 0 else { return nil }
        var c = DateComponents()
        c.year  = gregorianYear
        c.month = gregorianMonth
        c.day   = gregorianDay
        return Calendar.current.date(from: c)
    }

    /// End date (inclusive), nil for recurring events.
    var actualEndDate: Date? {
        guard let start = actualDate, durationDays > 1 else { return actualDate }
        return Calendar.current.date(byAdding: .day, value: durationDays - 1, to: start)
    }
}

// MARK: - 1447 AH / 2025–2026 CE (approximate — moon sighting may vary by 1 day)

extension IslamicEvent {
    static let all: [IslamicEvent] = [

        // ── Muharram ──────────────────────────────────────────────────
        IslamicEvent(id: 1,
            name: "Islamic New Year",    arabicName: "رأس السنة الهجرية",
            kind: .holiday,
            gregorianYear: 2025, gregorianMonth: 6, gregorianDay: 26,
            description: "First day of Muharram 1447 — the start of the Islamic lunar calendar.",
            durationDays: 1),

        IslamicEvent(id: 2,
            name: "Day of Ashura",       arabicName: "يوم عاشوراء",
            kind: .fastingDay,
            gregorianYear: 2025, gregorianMonth: 7, gregorianDay: 5,
            description: "10th of Muharram. Fasting expiates sins of the previous year. Recommended to also fast the 9th.",
            durationDays: 1),

        // ── Rabi' al-Awwal ────────────────────────────────────────────
        IslamicEvent(id: 3,
            name: "Mawlid an-Nabi ﷺ",   arabicName: "المولد النبوي الشريف",
            kind: .holiday,
            gregorianYear: 2025, gregorianMonth: 9, gregorianDay: 4,
            description: "12th Rabi' al-Awwal — the birthday of the Prophet Muhammad ﷺ.",
            durationDays: 1),

        // ── Rajab ─────────────────────────────────────────────────────
        IslamicEvent(id: 4,
            name: "Isra' and Mi'raj",   arabicName: "الإسراء والمعراج",
            kind: .recommended,
            gregorianYear: 2026, gregorianMonth: 1, gregorianDay: 27,
            description: "27th Rajab — the Night Journey and Ascension of the Prophet ﷺ to the heavens.",
            durationDays: 1),

        // ── Sha'ban ───────────────────────────────────────────────────
        IslamicEvent(id: 5,
            name: "Laylat al-Bara'ah",  arabicName: "ليلة البراءة",
            kind: .recommended,
            gregorianYear: 2026, gregorianMonth: 2, gregorianDay: 13,
            description: "15th Sha'ban — the Night of Forgiveness. Many engage in extra worship and supplication.",
            durationDays: 1),

        // ── Ramadan ───────────────────────────────────────────────────
        IslamicEvent(id: 6,
            name: "Ramadan",            arabicName: "رمضان",
            kind: .fastingMonth,
            gregorianYear: 2026, gregorianMonth: 3, gregorianDay: 1,
            description: "The blessed month of fasting, Quran recitation, Tarawih prayers, and increased worship.",
            durationDays: 30),

        IslamicEvent(id: 7,
            name: "Laylat al-Qadr",     arabicName: "ليلة القدر",
            kind: .recommended,
            gregorianYear: 2026, gregorianMonth: 3, gregorianDay: 27,
            description: "The Night of Power — one of the last 10 odd nights of Ramadan, better than 1,000 months (Quran 97:3).",
            durationDays: 1),

        // ── Shawwal ───────────────────────────────────────────────────
        IslamicEvent(id: 8,
            name: "Eid al-Fitr",        arabicName: "عيد الفطر",
            kind: .holiday,
            gregorianYear: 2026, gregorianMonth: 3, gregorianDay: 30,
            description: "1st Shawwal — Eid marking the end of Ramadan. Fasting is forbidden. Special congregational prayer in the morning.",
            durationDays: 3),

        IslamicEvent(id: 9,
            name: "Six Days of Shawwal", arabicName: "صيام ستة من شوال",
            kind: .fastingDay,
            gregorianYear: 2026, gregorianMonth: 4, gregorianDay: 2,
            description: "Fasting any 6 days of Shawwal after Eid al-Fitr is like fasting the entire year (Hadith Muslim).",
            durationDays: 6),

        // ── Dhul Hijjah ───────────────────────────────────────────────
        IslamicEvent(id: 10,
            name: "First 10 Days of Dhul Hijjah", arabicName: "عشر ذي الحجة",
            kind: .recommended,
            gregorianYear: 2026, gregorianMonth: 6, gregorianDay: 6,
            description: "The best 10 days of the year. Extra dhikr, fasting, and good deeds are especially rewarded.",
            durationDays: 9),

        IslamicEvent(id: 11,
            name: "Day of Arafah",      arabicName: "يوم عرفة",
            kind: .fastingDay,
            gregorianYear: 2026, gregorianMonth: 6, gregorianDay: 14,
            description: "9th Dhul Hijjah — fasting expiates sins of the previous and coming year (Hadith Muslim).",
            durationDays: 1),

        IslamicEvent(id: 12,
            name: "Eid al-Adha",        arabicName: "عيد الأضحى",
            kind: .holiday,
            gregorianYear: 2026, gregorianMonth: 6, gregorianDay: 15,
            description: "10th Dhul Hijjah — Eid of Sacrifice, commemorating Ibrahim's ﷺ willingness to sacrifice his son.",
            durationDays: 4),

        IslamicEvent(id: 13,
            name: "Days of Tashriq",    arabicName: "أيام التشريق",
            kind: .recommended,
            gregorianYear: 2026, gregorianMonth: 6, gregorianDay: 16,
            description: "11th–13th Dhul Hijjah — days of eating, drinking, and remembering Allah. Fasting is prohibited.",
            durationDays: 3),

        // ── Recurring ─────────────────────────────────────────────────
        IslamicEvent(id: 14,
            name: "Fast of Mon. & Thu.", arabicName: "صيام الاثنين والخميس",
            kind: .fastingDay,
            gregorianYear: 0, gregorianMonth: 0, gregorianDay: 0,
            description: "The Prophet ﷺ fasted every Monday and Thursday. Deeds are presented to Allah on these days.",
            durationDays: 1),

        IslamicEvent(id: 15,
            name: "White Days (Ayyam al-Bid)", arabicName: "أيام البيض",
            kind: .fastingDay,
            gregorianYear: 0, gregorianMonth: 0, gregorianDay: 0,
            description: "13th, 14th, and 15th of every Islamic month. Fasting on these full-moon days is like fasting all year.",
            durationDays: 3),
    ]
}
