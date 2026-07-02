import SwiftUI
import UIKit

// Shared visual primitives used across the Home, Quran, and More tabs so the
// same concept always looks the same. Animation/interaction primitives live in
// AnimationKit.swift; this file is purely presentational.

// MARK: - Brand palette

/// The app's brand teal: deeper and more saturated than system teal in light
/// mode, softer and more luminous in dark mode so it doesn't glare on OLED.
extension Color {
    static let brand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.32, green: 0.80, blue: 0.75, alpha: 1)   // luminous teal
            : UIColor(red: 0.03, green: 0.47, blue: 0.44, alpha: 1)   // deep emerald-teal
    })

    /// Darker companion used as the far stop of brand gradients.
    static let brandDeep = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.48, blue: 0.46, alpha: 1)
            : UIColor(red: 0.01, green: 0.33, blue: 0.33, alpha: 1)
    })
}

/// Lets `.brand` be written anywhere a `ShapeStyle` is expected — `.foregroundStyle(.brand)`,
/// `.tint(.brand)`, `fill(.brand)` — without spelling out `Color.brand`.
extension ShapeStyle where Self == Color {
    static var brand: Color { .brand }
    static var brandDeep: Color { .brandDeep }
}

extension LinearGradient {
    /// The signature filled-card gradient (hero cards, prominent buttons).
    static let brandHero = LinearGradient(
        colors: [.brand, .brandDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Section header

/// Custom dashboard / list section header: an SF Symbol + bold subheadline,
/// tinted per feature. `textCase(nil)` keeps it readable inside grouped Lists.
struct SectionHeader: View {
    let title: String
    let systemImage: String
    var tint: Color = .primary

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.bold())
            .foregroundStyle(tint)
            .textCase(nil)
    }
}

// MARK: - Tinted card background

/// Standardized translucent card surface: a tinted gradient fill over the
/// grouped-background base, a gradient hairline, and a soft ambient drop
/// shadow. Continuous corners keep it feeling native.
struct TintedCardModifier: ViewModifier {
    let color: Color
    var cornerRadius: CGFloat = 20
    var fillOpacity: Double = 0.07
    var strokeOpacity: Double = 0.22
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background(
                shape
                    // Opaque base so the tint reads consistently over any backdrop.
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        shape.fill(
                            LinearGradient(
                                colors: [color.opacity(fillOpacity * 1.6),
                                         color.opacity(fillOpacity * 0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .overlay(
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [color.opacity(strokeOpacity),
                                         color.opacity(strokeOpacity * 0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    )
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06),
                            radius: 14, y: 6)
            )
    }
}

extension View {
    func tintedCard(_ color: Color,
                    cornerRadius: CGFloat = 20,
                    fillOpacity: Double = 0.07,
                    strokeOpacity: Double = 0.22) -> some View {
        modifier(TintedCardModifier(color: color,
                                    cornerRadius: cornerRadius,
                                    fillOpacity: fillOpacity,
                                    strokeOpacity: strokeOpacity))
    }
}

// MARK: - Hero card (filled brand gradient)

/// The one filled card on a screen — the primary daily action. White content
/// over the brand gradient with a tinted shadow that lifts it off the page.
struct HeroCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 24
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient.brandHero)
                    .overlay(
                        // Top-edge sheen so the surface catches "light".
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.35), .white.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.brandDeep.opacity(scheme == .dark ? 0.35 : 0.30),
                            radius: 16, y: 8)
            )
    }
}

extension View {
    func heroCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(HeroCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Juz chip

/// Single capsule chip used by every juz picker (Home progress card, Memorize
/// overview sheet). The parent owns the selection model (`Int?` or `Int`).
struct JuzChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? Color.brand : Color(.tertiarySystemBackground)))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Inline stat / legend dot

/// Compact "● 12 label" stat used in progress legends and the memorization strip.
struct StatDot: View {
    let color: Color
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(value)")
                .font(.caption.bold())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Memorization status card

/// Horizontal-scroller card for a surah in a memorization state (in-progress or
/// review). One design shared by the Home dashboard and the Quran tab.
struct MemorizationStatusCard: View {
    let surah: Surah
    let accent: Color
    let icon: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(accent)
                Spacer()
                Text("\(surah.number)")
                    .font(.caption2.bold())
                    .foregroundStyle(accent == .yellow ? .black : .white)
                    .frame(width: 20, height: 20)
                    .background(accent)
                    .clipShape(Circle())
            }
            .padding(.bottom, 12)

            Spacer()

            Text(surah.name)
                .font(.system(size: 26, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.bottom, 6)

            Text(surah.englishName)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 176, height: 132)
        .tintedCard(accent)
    }
}
