import Foundation

struct LoopSettings: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case off     = "Off"
        case single  = "Single Ayah"
        case segment = "Segment"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .off:     return "arrow.right"
            case .single:  return "repeat.1"
            case .segment: return "repeat"
            }
        }
    }

    enum RepeatDelay: Double, Codable, CaseIterable, Identifiable {
        case three   = 3
        case five    = 5
        case ten     = 10
        case fifteen = 15
        case thirty  = 30
        case matchAyah = -1   // negative = use actual ayah duration

        var id: Double { rawValue }
        var label: String {
            switch self {
            case .three:     return "3 seconds"
            case .five:      return "5 seconds"
            case .ten:       return "10 seconds"
            case .fifteen:   return "15 seconds"
            case .thirty:    return "30 seconds"
            case .matchAyah: return "Match ayah length"
            }
        }
    }

    var mode: Mode          = .off
    var startAyah: Int      = 1
    var endAyah: Int        = 1
    /// 0 = infinite
    var repeatCount: Int    = 0

    // Listen & Repeat — pause after each ayah so the listener can repeat it
    var listenAndRepeat: Bool      = false
    var listenRepeatDelay: RepeatDelay = .matchAyah
}

// MARK: - Memorization presets
//
// The three drills that make up the acquisition method: hear the ayah on repeat,
// hear-then-recite it in the gap, then chain it onto the ayahs before it. Each is
// just a `LoopSettings` shape, so the same audio engine drives all of them.
extension LoopSettings {
    /// Stage 1–2 — loop one ayah's recitation back-to-back so it can be absorbed.
    static func listen(ayah: Int, repeatCount: Int = 0) -> LoopSettings {
        LoopSettings(mode: .single, startAyah: ayah, endAyah: ayah,
                     repeatCount: repeatCount,
                     listenAndRepeat: false, listenRepeatDelay: .matchAyah)
    }

    /// Stage 3 — loop one ayah with a gap after each pass so the reciter can say it
    /// back before hearing it again.
    static func repeatAfter(ayah: Int, gap: RepeatDelay = .matchAyah,
                            repeatCount: Int = 0) -> LoopSettings {
        LoopSettings(mode: .single, startAyah: ayah, endAyah: ayah,
                     repeatCount: repeatCount,
                     listenAndRepeat: true, listenRepeatDelay: gap)
    }

    /// Stage 4 — chain: loop the run of already-learned ayahs up through the new
    /// one, optionally pausing after each so it's recited from memory.
    static func chain(from start: Int, through end: Int,
                      pause: Bool = true, gap: RepeatDelay = .matchAyah,
                      repeatCount: Int = 0) -> LoopSettings {
        LoopSettings(mode: .segment,
                     startAyah: min(start, end), endAyah: max(start, end),
                     repeatCount: repeatCount,
                     listenAndRepeat: pause, listenRepeatDelay: gap)
    }
}
