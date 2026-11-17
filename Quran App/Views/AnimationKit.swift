import SwiftUI
import UIKit

// MARK: - Motion tokens

/// The few animations the app moves with. Everything that changes state on screen uses
/// a spring, so a change that is interrupted (a second tap, the next ayah arriving)
/// carries on from where it was instead of restarting. With Reduce Motion on, each
/// becomes a plain 0.15 s cross-fade: pair them with `Motion.move(_:)` so a transition
/// that slides or scales falls back to opacity. Read per call (not cached), so a change
/// in Settings applies at once.
enum Motion {
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// What every token becomes under Reduce Motion.
    static let crossFade = Animation.easeInOut(duration: 0.15)

    /// Press states and symbol swaps: over almost as soon as it starts.
    static var quick: Animation { reduceMotion ? crossFade : .snappy(duration: 0.18) }
    /// Row and highlight changes: the highlight moving between ayahs, a banner arriving.
    static var standard: Animation { reduceMotion ? crossFade : .smooth(duration: 0.3) }
    /// Things that settle into place: the compass, a selection ring, a progress arc.
    static var spring: Animation { reduceMotion ? crossFade : .spring(response: 0.35, dampingFraction: 0.85) }
    /// A small overshoot, for the moments worth marking: a bookmark saved, a repeat
    /// set, a goal reached.
    static var bouncy: Animation { reduceMotion ? crossFade : .bouncy(duration: 0.4, extraBounce: 0.12) }

    /// A transition that moves or scales, or just fades when Reduce Motion is on.
    static func move(_ transition: AnyTransition) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }

    /// Something small popping in: it grows from 60% as it fades up.
    static var pop: AnyTransition { move(.scale(scale: 0.6).combined(with: .opacity)) }
}

// MARK: - Press styles
// Use these on NavigationLinks / Buttons instead of simultaneousGesture. A ButtonStyle
// hooks into SwiftUI's own gesture pipeline, so it never blocks the action the way a
// raw DragGesture would.

/// The press state for anything shaped like a button or a card: it sinks a little
/// and springs back.
struct CardButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.965

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Motion.reduceMotion ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            // Down fast, back up with a little spring.
            .animation(configuration.isPressed ? Motion.quick : Motion.spring, value: configuration.isPressed)
    }
}

/// The press state for a whole row of text: it dims, it doesn't shrink.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(configuration.isPressed ? nil : Motion.standard, value: configuration.isPressed)
    }
}

// MARK: - Arriving

extension View {
    /// Fades the view up into place the first time it appears, `index` steps after its
    /// siblings, so a screen's blocks settle one after another. Does nothing under
    /// Reduce Motion.
    func arrives(_ index: Int) -> some View {
        modifier(Arrival(index: index))
    }
}

private struct Arrival: ViewModifier {
    let index: Int
    @State private var shown = Motion.reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                withAnimation(.smooth(duration: 0.45).delay(0.05 + Double(index) * 0.06)) { shown = true }
            }
    }
}
