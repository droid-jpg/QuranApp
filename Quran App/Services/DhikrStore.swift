import Foundation
import Combine

class DhikrStore: ObservableObject {
    // MARK: - Presets
    struct Preset: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var name: String
        var goal: Int
    }

    static let defaultPresets: [Preset] = [
        Preset(name: "SubhanAllah",   goal: 33),
        Preset(name: "Alhamdulillah", goal: 33),
        Preset(name: "Allahu Akbar",  goal: 34),
        Preset(name: "Astaghfirullah",goal: 100),
        Preset(name: "Custom",        goal: 99),
    ]

    // MARK: - Published state
    @Published var count: Int = 0
    @Published var selectedPreset: Preset
    @Published var customGoal: Int = 33
    @Published var goalReached = false

    // Session history (preset name → total counts this session)
    @Published var sessionCounts: [String: Int] = [:]

    init() {
        selectedPreset = Self.defaultPresets[0]
        customGoal = selectedPreset.goal
    }

    var goal: Int { customGoal }

    var progress: Double {
        goal > 0 ? min(Double(count) / Double(goal), 1.0) : 0
    }

    // MARK: - Actions

    func tap() {
        guard !goalReached else { return }
        count += 1
        sessionCounts[selectedPreset.name, default: 0] += 1

        if count >= goal {
            goalReached = true
            Haptics.success()
        } else {
            Haptics.impact()
        }
    }

    func reset() {
        count = 0
        goalReached = false
        Haptics.tap()
    }

    func select(_ preset: Preset) {
        selectedPreset = preset
        customGoal = preset.goal
        reset()
    }
}
