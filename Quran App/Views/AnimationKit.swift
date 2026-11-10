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

/// Five bars rising and falling, shown only while audio plays (callers swap it
/// for a still glyph when paused, which stops it).
///
/// Drawn into a `Canvas` from the timeline's clock rather than animating each
/// bar's frame: the old `repeatForever` frame animations re-ran layout every
/// frame for as long as audio played. This repaints a 20×14 pt canvas at up to
/// 30 fps and never touches layout. Reduce Motion holds the bars still.
struct PlayingIndicatorView: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let heights: [CGFloat] = [6, 10, 8, 12, 7]
    private static let delays: [Double]   = [0, 0.15, 0.3, 0.1, 0.25]
    private static let barWidth: CGFloat = 2.5
    private static let spacing: CGFloat = 2
    private static let rest: CGFloat = 3
    /// One rise (or fall), as the old `.easeInOut(duration: 0.5)` autoreversing.
    private static let halfPeriod: Double = 0.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? nil : context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let n = Self.heights.count
                let total = CGFloat(n) * Self.barWidth + CGFloat(n - 1) * Self.spacing
                var x = (size.width - total) / 2
                for i in 0..<n {
                    let h = Self.barHeight(i, at: t)
                    let rect = CGRect(x: x, y: size.height - h, width: Self.barWidth, height: h)
                    gc.fill(Capsule().path(in: rect), with: .color(color))
                    x += Self.barWidth + Self.spacing
                }
            }
        }
        .frame(width: 20, height: 14)
        .accessibilityHidden(true)
    }

    /// The bar's height at time `t`: a triangle wave between rest and its peak,
    /// eased in and out. `nil` (Reduce Motion) holds it midway.
    private static func barHeight(_ i: Int, at t: Double?) -> CGFloat {
        guard let t else { return (rest + heights[i]) / 2 }
        let p = max(0, t - delays[i]) / halfPeriod
        let tri = p.truncatingRemainder(dividingBy: 2)
        let linear = tri <= 1 ? tri : 2 - tri
        let eased = linear * linear * (3 - 2 * linear)
        return rest + (heights[i] - rest) * CGFloat(eased)
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
