import SwiftUI

// MARK: - Spring presets

enum AppAnim {
    static let spring     = Animation.spring(response: 0.42, dampingFraction: 0.76)
    static let springFast = Animation.spring(response: 0.22, dampingFraction: 0.82)
    static let smooth     = Animation.easeInOut(duration: 0.22)
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

// MARK: - Active playback indicator (animated bars)

struct PlayingIndicatorView: View {
    let color: Color
    @State private var animating = false

    private let heights: [CGFloat] = [6, 10, 8, 12, 7]
    private let delays: [Double]   = [0, 0.15, 0.3, 0.1, 0.25]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: animating ? heights[i] : 3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(delays[i]),
                        value: animating
                    )
            }
        }
        .frame(width: 20, height: 14, alignment: .bottom)
        .onAppear { animating = true }
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
