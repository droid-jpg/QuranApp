import Foundation

/// Thin singleton so the CarPlay scene delegate can reach the same
/// AudioService / MemorizationStore instances that the SwiftUI app owns.
final class CarPlayBridge {
    static let shared = CarPlayBridge()
    private init() {}

    weak var audioService: AudioService?
    weak var memorizationStore: MemorizationStore?
}
