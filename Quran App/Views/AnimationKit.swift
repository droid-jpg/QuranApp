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

/// The old preset names, now aliases of the tokens above so nothing else had to change.
enum AppAnim {
    static var spring: Animation     { Motion.sheet }
    static var springFast: Animation { Motion.quick }
    static var smooth: Animation     { Motion.standard }
}

// MARK: - Staggered fade-up entrance

struct StaggeredAppearModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .onAppear {
                guard !appeared else { return }
                withAnimation(AppAnim.spring.delay(delay)) { appeared = true }
            }
    }
}

extension View {
    func staggeredAppear(delay: Double = 0) -> some View {
        modifier(StaggeredAppearModifier(delay: delay))
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
            .animation(AppAnim.springFast, value: configuration.isPressed)
    }
}

// Kept for non-navigable surfaces (standalone buttons, etc.)
struct CardPressModifier: ViewModifier {
    @State private var pressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.965 : 1.0)
            .brightness(pressed ? -0.025 : 0)
            .animation(AppAnim.springFast, value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true } }
                    .onEnded   { _ in pressed = false }
            )
    }
}

extension View {
    func cardPressEffect() -> some View { modifier(CardPressModifier()) }
}

// MARK: - Continuous pulse glow

struct PulseGlowModifier: ViewModifier {
    let color: Color
    let active: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: active ? color.opacity(pulsing ? 0.55 : 0.18) : .clear,
                radius: pulsing ? 9 : 3
            )
            .onChange(of: active) { _, isActive in
                pulsing = false
                if isActive { startPulse() }
            }
            .onAppear { if active { startPulse() } }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }
}

extension View {
    func pulseGlow(color: Color, active: Bool) -> some View {
        modifier(PulseGlowModifier(color: color, active: active))
    }
}

// MARK: - Shimmer skeleton

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.5

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: phase * geo.size.width)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}
