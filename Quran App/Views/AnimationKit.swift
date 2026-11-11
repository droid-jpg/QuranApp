import SwiftUI
import UIKit

// MARK: - Motion tokens (REDESIGN §5)

/// The three durations the app animates with. With Reduce Motion on, each becomes a plain
/// 0.15 s cross-fade: pair them with `Motion.move(_:)` so a transition that slides or scales
/// falls back to opacity. Read per call (not cached), so a change in Settings applies at once.
enum Motion {
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// What every token becomes under Reduce Motion.
    static let crossFade = Animation.easeInOut(duration: 0.15)

    /// 0.15 s ease-out: play/pause symbol, button press.
    static var quick: Animation { reduceMotion ? crossFade : .easeOut(duration: 0.15) }
    /// 0.25 s ease-in-out: highlight moving between ayahs, row state.
    static var standard: Animation { reduceMotion ? crossFade : .easeInOut(duration: 0.25) }
    /// Spring, response 0.35, damping 0.85: mini player to Now Playing, sheets.
    static var sheet: Animation { reduceMotion ? crossFade : .spring(response: 0.35, dampingFraction: 0.85) }

    /// A transition that moves or scales, or just fades when Reduce Motion is on.
    static func move(_ transition: AnyTransition) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

// MARK: - Card press ButtonStyle
// Use this on NavigationLinks / Buttons instead of simultaneousGesture.
// ButtonStyle hooks into SwiftUI's unified gesture pipeline, so it never
// blocks the navigation action the way a raw DragGesture would.

struct CardButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.965

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .brightness(configuration.isPressed ? -0.022 : 0)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}
