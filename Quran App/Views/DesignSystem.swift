import SwiftUI
import UIKit

// Shared visual primitives. The app reads as a book now — ink on paper, ruled
// rather than boxed — so the vocabulary here is editorial: hairlines, small-caps
// eyebrows, outlined actions, one accent used as a mark rather than a fill.
// Animation/interaction primitives live in AnimationKit.swift.

// MARK: - Brand palette

extension Color {
    /// The accent, resolved from the theme the user picked in Settings. Computed
    /// (not `let`) so a theme change is picked up the next time a view renders.
    static var brand: Color { AppTheme.current.accent }

    /// Darker companion used as the far stop of brand gradients.
    static var brandDeep: Color { AppTheme.current.deep }

    /// The hairline that replaced the app's cards. Ink at low opacity rather
    /// than `.separator`, which is too faint to carry structure on true black.
    static var rule: Color { Color(.label).opacity(0.13) }

    /// Page ink for editorial surfaces — full-strength body text.
    static var ink: Color { Color(.label) }
}

/// Lets `.brand` be written anywhere a `ShapeStyle` is expected — `.foregroundStyle(.brand)`,
/// `.tint(.brand)`, `fill(.brand)` — without spelling out `Color.brand`.
extension ShapeStyle where Self == Color {
    static var brand: Color { .brand }
    static var brandDeep: Color { .brandDeep }
    static var rule: Color { .rule }
}

// MARK: - Editorial type

/// The small-caps label that titles every section now that cards are gone.
/// Always SF (never the reading serif) so it reads as furniture, not prose.
struct Eyebrow: View {
    let text: String
    var tint: Color = Color(.label).opacity(0.45)
    var size: CGFloat = 9.5

    init(_ text: String, tint: Color = Color(.label).opacity(0.45), size: CGFloat = 9.5) {
        self.text = text
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .bold))
            .kerning(1.5)
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

/// Tabular metadata — times, counts, percentages. Letterspaced SF so numbers
/// don't jitter as they tick.
struct MetaText: View {
    let text: String
    var tint: Color = Color(.label).opacity(0.45)
    var size: CGFloat = 10

    init(_ text: String, tint: Color = Color(.label).opacity(0.45), size: CGFloat = 10) {
        self.text = text
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold).monospacedDigit())
            .kerning(0.8)
            .foregroundStyle(tint)
    }
}

// MARK: - Rules

/// The 1px rule that does the work cards used to do.
struct Hairline: View {
    var opacity: Double = 1

    var body: some View {
        Rectangle()
            .fill(Color.rule.opacity(opacity))
            .frame(height: 1)
    }
}

/// Line · diamond · line — the ornament under a surah title.
struct DiamondRule: View {
    var tint: Color = .brand

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.rule).frame(height: 1)
            Diamond()
                .fill(tint.opacity(0.8))
                .frame(width: 7, height: 7)
            Rectangle().fill(Color.rule).frame(height: 1)
        }
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Editorial section

/// One ruled block of the dashboard: a hairline, an eyebrow (with optional
/// trailing meta), then content. Replaces `tintedCard` everywhere the new
/// dashboard reads as a list rather than a wall of widgets.
struct EditorialSection<Content: View>: View {
    let title: String
    /// SF Symbol shown before the eyebrow. A page of nothing but small-caps
    /// labels is hard to scan; the glyph is what the eye actually lands on.
    var icon: String? = nil
    var iconTint: Color? = nil
    var trailing: String? = nil
    var trailingTint: Color? = nil
    var showsRule: Bool = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsRule {
                Hairline()
                    .padding(.bottom, 15)
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(iconTint ?? Color.brand)
                        // Symbols sit on their own baseline; pin them to the
                        // eyebrow's so the row doesn't wobble per icon.
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 0.5 }
                        .frame(width: 14, alignment: .leading)
                }
                Eyebrow(title)
                Spacer(minLength: 8)
                if let trailing {
                    MetaText(trailing, tint: trailingTint ?? Color(.label).opacity(0.5))
                }
            }
            .padding(.bottom, 7)

            content
        }
    }
}

// MARK: - Outlined action

/// The bordered, letterspaced action that replaced filled pills. Square corners
/// on purpose — the only rounded things left are the play circles.
struct OutlineButton: View {
    let label: String
    var icon: String? = nil
    var on: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                }
                Text(label.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(1.2)
            }
            .foregroundStyle(on ? Color.brand : Color(.label).opacity(0.72))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                Rectangle()
                    .strokeBorder(on ? Color.brand : Color(.label).opacity(0.18), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(AppAnim.smooth, value: on)
    }
}

/// Compact outlined chip for one-tap starts. Same language as `OutlineButton`
/// but hugs its label instead of filling the row.
struct OutlineChip: View {
    let label: String
    var icon: String? = nil
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint ?? Color.brand)
                }
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Color(.label).opacity(0.72))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .overlay(Rectangle().strokeBorder(Color(.label).opacity(0.18), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(scale: 0.95))
    }
}

// MARK: - Progress

/// The 1.5pt ruled progress bar the dashboard uses instead of capsules.
struct RuleProgress: View {
    let fraction: Double
    var tint: Color = Color(.label).opacity(0.75)
    var height: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(.label).opacity(0.16))
                Rectangle()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Play affordance

/// The one round thing on the page: a hairline circle with the accent glyph.
struct PlayCircle: View {
    let playing: Bool
    var size: CGFloat = 54
    var filled: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(filled ? Color.brand : Color.clear)
                .overlay(Circle().strokeBorder(Color.brand.opacity(filled ? 0 : 0.55), lineWidth: 1))
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.30, weight: .semibold))
                .foregroundStyle(filled ? Color(.systemBackground) : Color.brand)
                .offset(x: playing ? 0 : size * 0.035)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Bar glyph

/// A glyph in a screen's own top bar. Square hit area, no border, accent when the
/// thing behind it is on — the same vocabulary as the ayah control strip. Shared
/// by the reader's bar and the surah list's, so the two can't drift apart.
struct BarButton: View {
    let icon: String
    let label: String
    var on: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(on ? Color.brand : Color(.label).opacity(0.72))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(scale: 0.88))
        .accessibilityLabel(label)
    }
}

// MARK: - Legacy card surfaces
//
// The dashboard and reader are ruled now, but Memorization, Qibla, Dhikr, the
// 99 Names and the calendar still speak in cards. These stay so those screens
// keep their shape (and keep compiling) until they get the same pass.

/// List section header. Same call sites as before, but set as an eyebrow with a
/// glyph so a List section reads like an `EditorialSection`.
struct SectionHeader: View {
    let title: String
    let systemImage: String
    var tint: Color = .brand

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
            Eyebrow(title)
        }
        .textCase(nil)
    }
}

/// The card surface, now ruled: a hairline box in the feature's tint and no fill
/// at all. Every screen that still builds itself out of cards — the memorization
/// hub, the method guide — picks up the restyle from here rather than one by one.
struct TintedCardModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content.overlay(Rectangle().strokeBorder(color.opacity(0.38), lineWidth: 1))
    }
}

extension View {
    func tintedCard(_ color: Color) -> some View {
        modifier(TintedCardModifier(color: color))
    }
}

/// Single chip used by every juz picker (Memorize overview sheet). The parent
/// owns the selection model (`Int?` or `Int`).
struct JuzChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(isSelected ? Color.brand : Color(.label).opacity(0.5))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .overlay(
                    Rectangle().strokeBorder(isSelected ? Color.brand : Color(.label).opacity(0.18),
                                             lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

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

/// Horizontal-scroller card for a surah in a memorization state (in-progress or
/// review). Ruled rather than filled, to match the rest of the restyle.
struct MemorizationStatusCard: View {
    let surah: Surah
    let accent: Color
    let icon: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                Spacer()
                MetaText("\(surah.number)", tint: accent, size: 10)
            }
            .padding(.bottom, 12)

            Spacer()

            Text(surah.name)
                .font(.system(size: 24, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.bottom, 8)

            Text(surah.englishName)
                .font(.appSerif(17, weight: .medium))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(width: 176, height: 132)
        .overlay(Rectangle().strokeBorder(Color(.label).opacity(0.16), lineWidth: 1))
    }
}
