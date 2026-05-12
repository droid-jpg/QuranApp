import Foundation

struct LoopSettings {
    enum Mode: String, CaseIterable, Identifiable {
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

    enum RepeatDelay: Double, CaseIterable, Identifiable {
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
