import Foundation

/// The one repeat model: "repeat ayahs `from`–`to` of `surah`, `times` times,
/// with an optional pause after each ayah". A single ayah is just `from == to`.
///
/// `AudioService.repeatState` is the only owner. Every decision about ranges,
/// passes and what plays next lives here as a pure function, so it can be tested
/// without a player.
struct RepeatState: Equatable {
    /// Total plays of the range. There is no "1": playing once is just repeat off.
    enum Times: String, Codable, CaseIterable, Identifiable, Hashable {
        case two = "2", three = "3", five = "5", ten = "10", infinite

        var id: String { rawValue }
        /// `nil` for infinite.
        var count: Int? {
            switch self {
            case .two: return 2
            case .three: return 3
            case .five: return 5
            case .ten: return 10
            case .infinite: return nil
            }
        }
        var label: String { count.map(String.init) ?? "∞" }

        /// The allowed value nearest to an old free-form count (0 = infinite).
        /// Returns `nil` for 1, which now means "repeat off".
        static func nearest(toLegacy n: Int) -> Times? {
            if n <= 0 { return .infinite }
            if n == 1 { return nil }
            let finite: [Times] = [.two, .three, .five, .ten]
            return finite.min { abs($0.count! - n) < abs($1.count! - n) }
        }
    }

    /// Silence after each ayah, so the listener can recite it. Only applies while
    /// repeat is on.
    enum Pause: Hashable, Identifiable {
        case none, ayahLength, seconds(Int)

        static let allCases: [Pause] = [.none, .ayahLength, .seconds(5), .seconds(10)]
        var id: String { label }
        var label: String {
            switch self {
            case .none: return "None"
            case .ayahLength: return "Ayah length"
            case .seconds(let s): return "\(s) s"
            }
        }
    }

    var isOn = false
    /// 0 until a range has been chosen for some surah.
    var surah = 0
    var from = 1
    var to = 1
    var times: Times = .infinite
    var pause: Pause = .none
    /// Passes finished, for "2 of 5". Runtime only; never persisted.
    var completed = 0

    var isSingleAyah: Bool { from == to }
    func contains(_ ayah: Int) -> Bool { (from...max(from, to)).contains(ayah) }
}

/// A word-range loop inside one ayah. While set it suspends, but never changes,
/// `RepeatState`.
struct WordRepeat: Equatable {
    var surah: Int
    var ayah: Int
    var fromWord: Int
    var toWord: Int
}

// MARK: - Memorization presets

extension RepeatState {
    /// The single "join with previous 2" range, shared by every caller (Today,
    /// the player, the Repeat sheet, Siri) so Chain means the same thing everywhere.
    static func joinRange(ending ayah: Int) -> ClosedRange<Int> {
        let end = max(1, ayah)
        return max(1, end - 2)...end
    }

    static func repeatThisAyah(surah: Int, ayah: Int) -> RepeatState {
        RepeatState(isOn: true, surah: surah, from: ayah, to: ayah, times: .infinite, pause: .none)
    }

    static func listenThenRecite(surah: Int, ayah: Int) -> RepeatState {
        RepeatState(isOn: true, surah: surah, from: ayah, to: ayah, times: .infinite, pause: .ayahLength)
    }

    static func joinWithPrevious2(surah: Int, ayah: Int) -> RepeatState {
        let r = joinRange(ending: ayah)
        return RepeatState(isOn: true, surah: surah, from: r.lowerBound, to: r.upperBound,
                           times: .infinite, pause: .none)
    }
}

// MARK: - Engine decisions (pure)

extension RepeatState {
    /// What happens after an ayah finishes.
    enum Step: Equatable {
        case ayah(Int)
        /// Ayah 1 of the next surah, or stop after An-Nas.
        case nextSurah
    }

    struct Advance: Equatable {
        var state: RepeatState
        var step: Step
        /// Silence before `step` plays.
        var pause: Pause
    }

    /// `from`/`to` forced into 1…ayahCount with `to >= from`.
    func clamped(ayahCount: Int) -> RepeatState {
        var s = self
        let n = max(1, ayahCount)
        s.from = min(max(1, s.from), n)
        s.to = min(max(s.from, s.to), n)
        return s
    }

    /// Repeat switched on. Keeps an existing range for this surah; with none,
    /// repeats the current ayah (or ayah 1) forever.
    func switchedOn(surah: Int, currentAyah: Int?) -> RepeatState {
        var s = self
        if s.surah != surah {
            s.surah = surah
            s.from = currentAyah ?? 1
            s.to = s.from
            s.times = .infinite
        }
        s.isOn = true
        s.completed = 0
        return s
    }

    /// Playback starts at `ayah` of `surah`. Repeat survives only when it is for
    /// that surah and the ayah is inside the range; a fresh start resets the passes.
    func keptWhenPlaying(surah: Int, ayah: Int) -> RepeatState {
        var s = self
        s.completed = 0
        if !(s.isOn && s.surah == surah && s.contains(ayah)) { s.isOn = false }
        return s
    }

    /// After a change, the ayah playback must jump to, if the current one has
    /// fallen outside the range.
    func jumpTarget(current ayah: Int) -> Int? {
        isOn && !contains(ayah) ? from : nil
    }

    /// The decision at the end of `ayah` in a surah of `ayahCount` ayahs.
    func advance(after ayah: Int, ayahCount: Int) -> Advance {
        let nextInSurah: Step = ayah < ayahCount ? .ayah(ayah + 1) : .nextSurah
        guard isOn else { return Advance(state: self, step: nextInSurah, pause: .none) }

        // Outside the range (changed while paused): go back into it.
        if !contains(ayah) { return Advance(state: self, step: .ayah(from), pause: pause) }
        if ayah < to { return Advance(state: self, step: .ayah(ayah + 1), pause: pause) }

        var s = self
        let passes = completed + 1
        if let n = times.count, passes >= n {
            // Last pass: repeat turns off and listening carries on. The pause still
            // follows this ayah, since it was heard as part of the repeat.
            s.isOn = false
            s.completed = 0
            return Advance(state: s, step: nextInSurah, pause: pause)
        }
        s.completed = passes
        return Advance(state: s, step: .ayah(from), pause: pause)
    }

    /// Next ayah button. Inside a repeat it wraps from `to` back to `from`.
    func nextAyah(after ayah: Int, ayahCount: Int) -> Int? {
        if isOn {
            if ayah < from || ayah >= to { return from }
            return ayah + 1
        }
        return ayah < ayahCount ? ayah + 1 : nil
    }

    /// Previous ayah button. Inside a repeat it wraps from `from` back to `to`.
    func previousAyah(before ayah: Int) -> Int? {
        if isOn {
            if ayah <= from || ayah > to { return to }
            return ayah - 1
        }
        return ayah > 1 ? ayah - 1 : nil
    }
}

// MARK: - Text

extension RepeatState {
    /// The one place the playback status line is written (mini player, Now
    /// Playing, Today, lock screen, saved sessions).
    func status(currentAyah: Int, reciterName: String, wordRepeat: WordRepeat? = nil) -> String {
        if let w = wordRepeat {
            return w.fromWord == w.toWord
                ? "Repeating word \(w.fromWord) of ayah \(w.ayah)"
                : "Repeating words \(w.fromWord)–\(w.toWord) of ayah \(w.ayah)"
        }
        guard isOn else { return "Ayah \(currentAyah) · \(reciterName)" }
        let range = isSingleAyah ? "Repeating ayah \(from)" : "Repeating ayahs \(from)–\(to)"
        guard let n = times.count else { return range }
        return "\(range) · \(min(completed + 1, n)) of \(n)"
    }

    /// The Repeat sheet's one-line summary, e.g. "Ayahs 3–4, 5 times, pausing after each".
    var summary: String {
        guard isOn else { return "Off" }
        let range = isSingleAyah ? "Ayah \(from)" : "Ayahs \(from)–\(to)"
        let count = times.count.map { "\($0) times" } ?? "∞"
        return "\(range), \(count)" + (pause == .none ? "" : ", pausing after each")
    }
}

// MARK: - Persistence and migration

extension RepeatState: Codable {
    private enum CodingKeys: String, CodingKey { case isOn, surah, from, to, times, pause }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isOn = (try? c.decodeIfPresent(Bool.self, forKey: .isOn)) ?? false
        surah = (try? c.decodeIfPresent(Int.self, forKey: .surah)) ?? 0
        from = max(1, (try? c.decodeIfPresent(Int.self, forKey: .from)) ?? 1)
        to = max(from, (try? c.decodeIfPresent(Int.self, forKey: .to)) ?? from)
        times = (try? c.decodeIfPresent(Times.self, forKey: .times)) ?? .infinite
        pause = (try? c.decodeIfPresent(Pause.self, forKey: .pause)) ?? .none
        completed = 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isOn, forKey: .isOn)
        try c.encode(surah, forKey: .surah)
        try c.encode(from, forKey: .from)
        try c.encode(to, forKey: .to)
        try c.encode(times, forKey: .times)
        try c.encode(pause, forKey: .pause)
    }

    /// The old `LoopSettings` JSON, every field optional so a partial blob still
    /// migrates instead of failing.
    struct Legacy: Decodable {
        var mode: String?            // "Off" | "Single Ayah" | "Segment"
        var startAyah: Int?
        var endAyah: Int?
        var repeatCount: Int?        // 0 = infinite
        var listenAndRepeat: Bool?
        var listenRepeatDelay: Double?   // seconds; -1 = match ayah length
    }

    init(legacy l: Legacy, surah: Int) {
        let start = max(1, l.startAyah ?? 1)
        let end = max(1, l.endAyah ?? start)
        self.surah = surah
        switch l.mode {
        case "Single Ayah":
            isOn = true; from = start; to = start
        case "Segment":
            isOn = true; from = min(start, end); to = max(start, end)
        default:
            isOn = false; from = start; to = max(start, end)
        }
        if let t = Times.nearest(toLegacy: l.repeatCount ?? 0) {
            times = t
        } else {
            times = .infinite
            isOn = false
        }
        if l.listenAndRepeat == true {
            let d = l.listenRepeatDelay ?? -1
            pause = d < 0 ? .ayahLength : (d <= 5 ? .seconds(5) : .seconds(10))
        } else {
            pause = .none
        }
    }
}

extension RepeatState.Pause: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(Int.self) {
            self = .seconds(s <= 5 ? 5 : 10)
        } else {
            self = try c.decode(String.self) == "ayahLength" ? .ayahLength : .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .none: try c.encode("none")
        case .ayahLength: try c.encode("ayahLength")
        case .seconds(let s): try c.encode(s)
        }
    }
}
