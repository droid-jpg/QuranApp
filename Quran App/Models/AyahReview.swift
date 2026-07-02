import SwiftUI

/// The three drill styles a review card can take. Which ones are eligible for a
/// given card is decided by its `MemorizationGoal`; the session picks one of the
/// eligible styles at random each time the card comes up.
enum ReviewMode: String, CaseIterable, Identifiable {
    case flashcard, fillBlank, audio
    var id: String { rawValue }

    var title: String {
        switch self {
        case .flashcard: return "Meaning Recall"
        case .fillBlank: return "Fill in the Blank"
        case .audio:     return "Audio Recall"
        }
    }

    var icon: String {
        switch self {
        case .flashcard: return "character.book.closed"
        case .fillBlank: return "rectangle.dashed"
        case .audio:     return "waveform"
        }
    }
}

/// What the user is trying to achieve for a memorized ayah. Non-fluent reciters
/// have genuinely different needs: someone who can recite the Arabic but doesn't
/// know the meaning, versus someone who understands it but can't yet recite it.
/// The goal tailors which drill styles a card is tested with.
enum MemorizationGoal: String, Codable, CaseIterable, Identifiable {
    /// Produce the Arabic from memory. Drilled with audio recall + fill-in-the-blank.
    case recitation
    /// Understand what the ayah means. Drilled with meaning-recall flashcards.
    case meaning
    /// Both recite and understand. Drilled with every style.
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recitation: return "Recitation"
        case .meaning:    return "Meaning"
        case .both:       return "Recite & Understand"
        }
    }

    /// Short form for compact badges.
    var shortTitle: String {
        switch self {
        case .recitation: return "Recitation"
        case .meaning:    return "Meaning"
        case .both:       return "Both"
        }
    }

    var caption: String {
        switch self {
        case .recitation: return "Recite the Arabic from memory"
        case .meaning:    return "Know what the ayah means"
        case .both:       return "Recite it and understand it"
        }
    }

    var icon: String {
        switch self {
        case .recitation: return "waveform"
        case .meaning:    return "character.book.closed"
        case .both:       return "checkmark.seal"
        }
    }

    /// Drill styles eligible for this goal. Recitation tests Arabic production
    /// (audio + fill-in-the-blank); meaning tests comprehension (flashcard).
    var modes: [ReviewMode] {
        switch self {
        case .recitation: return [.fillBlank, .audio]
        case .meaning:    return [.flashcard]
        case .both:       return [.flashcard, .fillBlank, .audio]
        }
    }
}

/// What a review card shows for the ayah itself: the Arabic, a Latin
/// transliteration, or both. A global display preference for review sessions,
/// persisted via `@AppStorage("memorizationCardScript")`.
enum MemorizationCardScript: String, CaseIterable, Identifiable {
    case arabic, transliteration, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arabic:          return "Arabic"
        case .transliteration: return "Transliteration"
        case .both:            return "Both"
        }
    }

    var showsArabic: Bool { self != .transliteration }
    var showsTransliteration: Bool { self != .arabic }
}

/// How well the user recalled an ayah in a review. Drives the SM-2 schedule;
/// the raw values double as the SM-2 quality score (0–5).
enum ReviewGrade: String, CaseIterable {
    case again, hard, good, easy

    /// SM-2 recall quality. `again` (< 3) resets the card; the rest advance it.
    var quality: Int {
        switch self {
        case .again: return 1
        case .hard:  return 3
        case .good:  return 4
        case .easy:  return 5
        }
    }

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard:  return "Hard"
        case .good:  return "Good"
        case .easy:  return "Easy"
        }
    }

    /// Canonical colour for the grade, shared by the review buttons and the
    /// how-it-works guide so the two never drift.
    var tint: Color {
        switch self {
        case .again: return .red
        case .hard:  return .orange
        case .good:  return .brand
        case .easy:  return .green
        }
    }

    /// One-line meaning of the grade, surfaced in the guide.
    var guideDetail: String {
        switch self {
        case .again: return "You blanked. The ayah resets and comes back today."
        case .hard:  return "You got it, but it was a struggle — a short wait until next time."
        case .good:  return "Solid recall. The gap until you see it again grows."
        case .easy:  return "Effortless. The gap jumps ahead so you're not over-drilling it."
        }
    }
}

/// One ayah enrolled in spaced repetition. It caches the ayah text so the
/// flashcard and fill-in-the-blank drills work offline; audio recall builds a
/// per-ayah URL on demand. Scheduling is an SM-2 variant with Anki-style
/// Hard/Easy adjustments.
struct AyahReview: Identifiable, Codable, Equatable {
    let surah: Int
    let ayah: Int
    let surahName: String          // English transliteration, e.g. "Al-Faatiha"
    let arabic: String
    var translation: String
    let transliteration: String

    /// The translation edition (`Translation` id) `translation` was captured from.
    /// Lets the store notice when the user has since switched translations and
    /// refresh the cached text to match. Empty on cards saved before this field
    /// existed, which reads as "unknown" so they refresh on the next opportunity.
    var translationEditionId: String

    /// What the user is drilling this ayah for; selects the eligible drill styles.
    var goal: MemorizationGoal = .both

    // SM-2 scheduling state.
    var easeFactor: Double = 2.5
    var interval: Int = 0          // whole days until next due
    var repetitions: Int = 0       // consecutive successful recalls
    var dueDate: Date
    var lastReviewed: Date?
    let addedDate: Date

    var id: String { "\(surah):\(ayah)" }

    /// Considered learned once the schedule has stretched past ~3 weeks — the
    /// usual "mature" boundary in spaced-repetition systems.
    var isMature: Bool { interval >= 21 }

    init(surah: Int, ayah: Int, surahName: String,
         arabic: String, translation: String, transliteration: String,
         goal: MemorizationGoal = .both, now: Date = Date()) {
        self.surah = surah
        self.ayah = ayah
        self.surahName = surahName
        self.arabic = arabic
        self.translation = translation
        // The text passed in is always fetched with the currently selected
        // edition (the reader reloads on translation change), so tag it as such.
        self.translationEditionId = Translation.selected.id
        self.transliteration = transliteration
        self.goal = goal
        self.dueDate = now         // due immediately when first enrolled
        self.addedDate = now
    }

    // Custom decoding so cards persisted before the `goal` field existed still
    // load (defaulting to `.both`). Encoding stays synthesized.
    enum CodingKeys: String, CodingKey {
        case surah, ayah, surahName, arabic, translation, translationEditionId, transliteration
        case goal, easeFactor, interval, repetitions, dueDate, lastReviewed, addedDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surah           = try c.decode(Int.self, forKey: .surah)
        ayah            = try c.decode(Int.self, forKey: .ayah)
        surahName       = try c.decode(String.self, forKey: .surahName)
        arabic          = try c.decode(String.self, forKey: .arabic)
        translation     = try c.decode(String.self, forKey: .translation)
        // Absent on cards saved before the field existed → "" (unknown), which
        // never matches a real edition id, so they refresh on the next pass.
        translationEditionId = try c.decodeIfPresent(String.self, forKey: .translationEditionId) ?? ""
        transliteration = try c.decode(String.self, forKey: .transliteration)
        goal            = try c.decodeIfPresent(MemorizationGoal.self, forKey: .goal) ?? .both
        easeFactor      = try c.decode(Double.self, forKey: .easeFactor)
        interval        = try c.decode(Int.self, forKey: .interval)
        repetitions     = try c.decode(Int.self, forKey: .repetitions)
        dueDate         = try c.decode(Date.self, forKey: .dueDate)
        lastReviewed    = try c.decodeIfPresent(Date.self, forKey: .lastReviewed)
        addedDate       = try c.decode(Date.self, forKey: .addedDate)
    }

    func isDue(asOf date: Date = Date()) -> Bool { dueDate <= date }

    /// Advances the SM-2 schedule for the given grade. `again` resets the card
    /// (and leaves it due today); the others lengthen the interval, with Hard
    /// growing slowly and Easy getting a bonus multiplier.
    ///
    /// Grading a card *before it's due* — a forced "review this surah" when nothing
    /// is due, or a second pass the same day — is treated as practice: it records
    /// the review but does not advance the schedule. Without this, repeated Easy
    /// taps compound the interval (4 → 8 → 26 → 84 …) and balloon one day's work to
    /// months. `again` is exempt: failing must always reset/return the card, and it
    /// can only shorten the interval, never inflate it.
    mutating func apply(_ grade: ReviewGrade, now: Date = Date()) {
        if grade != .again && dueDate > now {
            lastReviewed = now
            return
        }

        let q = Double(grade.quality)
        easeFactor = max(1.3, easeFactor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)))

        switch grade {
        case .again:
            repetitions = 0
            interval = 0
        case .hard:
            interval = repetitions == 0 ? 1 : max(1, Int((Double(interval) * 1.2).rounded()))
            repetitions += 1
        case .good:
            switch repetitions {
            case 0:  interval = 1
            case 1:  interval = 6
            default: interval = max(1, Int((Double(interval) * easeFactor).rounded()))
            }
            repetitions += 1
        case .easy:
            switch repetitions {
            case 0:  interval = 4
            case 1:  interval = 8
            default: interval = max(1, Int((Double(interval) * easeFactor * 1.3).rounded()))
            }
            repetitions += 1
        }

        lastReviewed = now
        let base = Calendar.current.startOfDay(for: now)
        dueDate = Calendar.current.date(byAdding: .day, value: interval, to: base) ?? now
    }
}
