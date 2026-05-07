import Foundation

struct LoopSettings {
    enum Mode: String, CaseIterable, Identifiable {
        case off = "Off"
        case single = "Single Ayah"
        case segment = "Segment"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .off:      return "arrow.right"
            case .single:   return "repeat.1"
            case .segment:  return "repeat"
            }
        }
    }

    var mode: Mode = .off
    var startAyah: Int = 1
    var endAyah: Int = 1
    /// 0 = infinite
    var repeatCount: Int = 0
}
