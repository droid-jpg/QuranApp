import UIKit

/// The app's haptics, in one vocabulary:
///
/// - `tap`: something opened or moved (navigation, a menu item, skip).
/// - `selection`: one of several was chosen (a segment, a theme, the first ayah of a range).
/// - `impact`: something started or stopped (play, pause, a count).
/// - `success`: something finished (a repeat set, a download kept, a goal reached).
/// - `warning` / `error`: something was removed, or did not work.
///
/// The generators are kept and re-armed after each use, so the next one fires without
/// the delay of waking the Taptic Engine.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let picker = UISelectionFeedbackGenerator()
    private static let notice = UINotificationFeedbackGenerator()

    static func tap() {
        light.impactOccurred(intensity: 0.7)
        light.prepare()
    }

    static func selection() {
        picker.selectionChanged()
        picker.prepare()
    }

    enum Weight { case light, medium, soft, rigid }

    static func impact(_ weight: Weight = .medium) {
        let generator = switch weight {
        case .light:  light
        case .medium: medium
        case .soft:   soft
        case .rigid:  rigid
        }
        generator.impactOccurred()
        generator.prepare()
    }

    static func success() {
        notice.notificationOccurred(.success)
        notice.prepare()
    }

    static func warning() {
        notice.notificationOccurred(.warning)
        notice.prepare()
    }

    static func error() {
        notice.notificationOccurred(.error)
        notice.prepare()
    }
}
