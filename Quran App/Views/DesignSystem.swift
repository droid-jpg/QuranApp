import SwiftUI
import UIKit

// Shared visual primitives. The app reads as a book now — ink on paper, ruled
// rather than boxed — so the vocabulary here is editorial: hairlines, small-caps
// eyebrows, outlined actions, one accent used as a mark rather than a fill.
// Animation/interaction primitives live in AnimationKit.swift.

// MARK: - Design tokens (REDESIGN §5)
//
// The one place literal sizes, spacings and colour roles live. Screens use these names:
//   Spacing.*     the 4-8-12-16-24-32-48 scale plus screenMargin / cardPadding / sectionGap
//   TypeScale.*   Font helpers that scale with Dynamic Type
//   Palette.*     colour roles for the current theme, light and dark
//   MinSize.*     hit targets and fixed control heights
//   Motion.*      in AnimationKit.swift

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat  = 8
    static let sm: CGFloat  = 12
    static let md: CGFloat  = 16
    static let lg: CGFloat  = 24
    static let xl: CGFloat  = 32
    static let xxl: CGFloat = 48

    static let screenMargin: CGFloat = 20
    static let cardPadding: CGFloat  = 16
    static let sectionGap: CGFloat   = 32
}

enum MinSize {
    static let hitTarget: CGFloat       = 44
    static let listPlayButton: CGFloat  = 44
    static let primaryPlay: CGFloat     = 56
    static let nowPlayingPlay: CGFloat  = 64
    static let surahRow: CGFloat        = 64
    static let moreRow: CGFloat         = 56
    static let miniPlayer: CGFloat      = 56
    static let ayahActionButton: CGFloat = 64
    static let segmentedControl: CGFloat = 36
}

/// The type scale. Serif tokens follow the reader's chosen serif face (`Font.appSerif`); the rest
/// are system sans text styles. Every one scales with Dynamic Type. The reader's Arabic stays
/// with `ReadingTypography`.
enum TypeScale {
    /// 34 serif regular — tab screen titles, greeting.
    static var display: Font   { .appSerif(34) }
    /// 28 serif — reader and Now Playing surah name.
    static var title: Font     { .appSerif(28) }
    /// 22 serif — card titles, prayer name.
    static var heading: Font   { .appSerif(22) }
    /// 19 serif — list rows.
    static var rowTitle: Font  { .appSerif(19) }
    /// 17 serif — row title inside the mini player.
    static var rowTitleCompact: Font { .appSerif(17) }
    /// 17 — translation, sheet rows, buttons.
    static var body: Font      { .system(.body) }
    /// 15 — subtitles, metadata, transliteration.
    static var secondary: Font { .system(.subheadline) }
    /// 13 semibold — section headings, segmented labels, values.
    static var caption: Font   { .system(.footnote, weight: .semibold) }
    /// 11 medium — tab bar labels only.
    static var tabLabel: Font  { .system(.caption2, weight: .medium) }
    /// 20 — Arabic in lists (surah names, headers). The reader uses `ReadingTypography`.
    static var arabicList: Font { .appArabic(20) }
}

/// Colour roles for the current theme. Resolved on every read like `Color.brand`, so a theme
/// change is picked up the next time a view renders. Values and contrast ratios: `AppTheme`.
enum Palette {
    static var background: Color    { AppTheme.current.background }
    /// Bars and cards. Opaque.
    static var surface: Color       { AppTheme.current.surface }
    /// Sheets and the mini player. Opaque, no material.
    static var surfaceRaised: Color { AppTheme.current.surfaceRaised }
    static var textPrimary: Color   { AppTheme.current.textPrimary }
    static var textSecondary: Color { AppTheme.current.textSecondary }
    static var textTertiary: Color  { AppTheme.current.textTertiary }
    static var accent: Color        { AppTheme.current.accent }
    static var onAccent: Color      { AppTheme.current.onAccent }
    /// Current-ayah background.
    static var highlight: Color     { AppTheme.current.highlight }
    static var separator: Color     { AppTheme.current.separator }
    static var danger: Color        { AppTheme.current.danger }
}

extension View {
    /// An opaque bar/header background with a hairline on its content edge. The replacement for
    /// every material or translucent header over scrolling content.
    func opaqueBar(_ fill: Color = Palette.surface, hairline: VerticalEdge = .bottom,
                   ignoresSafeArea: Edge.Set = []) -> some View {
        background(fill, ignoresSafeAreaEdges: ignoresSafeArea)
            .overlay(alignment: hairline == .top ? .top : .bottom) { Hairline() }
    }
}

// MARK: - Brand palette

extension Color {
    /// The accent, resolved from the theme the user picked in Settings. Computed
    /// (not `let`) so a theme change is picked up the next time a view renders.
    static var brand: Color { AppTheme.current.accent }

    /// Darker companion used as the far stop of brand gradients.
    static var brandDeep: Color { AppTheme.current.deep }

    /// The hairline that replaced the app's cards: the palette's opaque `separator`.
    static var rule: Color { Palette.separator }

    /// Page ink for editorial surfaces — full-strength body text.
    static var ink: Color { Palette.textPrimary }
}

/// Lets `.brand` be written anywhere a `ShapeStyle` is expected — `.foregroundStyle(.brand)`,
/// `.tint(.brand)`, `fill(.brand)` — without spelling out `Color.brand`.
extension ShapeStyle where Self == Color {
    static var brand: Color { .brand }
    static var brandDeep: Color { .brandDeep }
    static var rule: Color { .rule }
}

// MARK: - Editorial type

/// The label that titles every section now that cards are gone: sentence case, 13 pt semibold
/// (the floor for anything read), no letter-spacing, `textSecondary`. Always SF (never the
/// reading serif) so it reads as furniture, not prose. `size` is kept for call sites that still
/// pass one; it can only raise the size above 13, never lower it. Wraps rather than truncates.
struct Eyebrow: View {
    let text: String
    var tint: Color = Palette.textSecondary
    var size: CGFloat = 13

    init(_ text: String, tint: Color = Palette.textSecondary, size: CGFloat = 13) {
        self.text = text
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(size > 13 ? .label(size, weight: .semibold) : TypeScale.caption)
            .foregroundStyle(tint)
    }
}

/// Tabular metadata — times, counts, percentages. Monospaced digits so numbers don't jitter as
/// they tick. Same type rules as `Eyebrow`.
struct MetaText: View {
    let text: String
    var tint: Color = Palette.textSecondary
    var size: CGFloat = 13

    init(_ text: String, tint: Color = Palette.textSecondary, size: CGFloat = 13) {
        self.text = text
        self.tint = tint
        self.size = size
    }

    var body: some View {
        Text(text)
            .font((size > 13 ? Font.label(size, weight: .semibold) : TypeScale.caption).monospacedDigit())
            .foregroundStyle(tint)
    }
}

extension Font {
    /// SF for the app's furniture (eyebrows, metadata, glyphs) at a size set by eye, scaled with
    /// Dynamic Type as the nearest text style and never below the HIG's 11 pt minimum.
    static func label(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard let style = Font.TextStyle.nearest(to: max(size, 11)) else {
            return .system(size: size, weight: weight)
        }
        return .system(style, weight: weight)
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
                        .font(.label(13, weight: .semibold))
                        .foregroundStyle(iconTint ?? Color.brand)
                        // Symbols sit on their own baseline; pin them to the
                        // eyebrow's so the row doesn't wobble per icon.
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 0.5 }
                        .frame(minWidth: 14, alignment: .leading)
                        .accessibilityHidden(true)
                }
                Eyebrow(title)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let trailing {
                    MetaText(trailing, tint: trailingTint ?? Palette.textSecondary)
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
                        .font(.label(13, weight: .bold))
                }
                Text(label)
                    .font(.label(15, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(on ? Color.brand : Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .frame(minHeight: MinSize.hitTarget)
            .overlay(
                Rectangle()
                    .strokeBorder(on ? Color.brand : Palette.separator, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .animation(Motion.standard, value: on)
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
                        .font(.label(13, weight: .bold))
                        .foregroundStyle(tint ?? Color.brand)
                }
                Text(label)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: MinSize.segmentedControl)
            .overlay(Rectangle().strokeBorder(Palette.separator, lineWidth: 1))
            // Drawn at 36 pt, but the tappable area reaches the HIG's 44.
            .padding(.vertical, (MinSize.hitTarget - MinSize.segmentedControl) / 2)
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
                .foregroundStyle(filled ? Palette.onAccent : Color.brand)
                .offset(x: playing ? 0 : size * 0.035)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        // Smaller circles still get the HIG's 44 pt hit target.
        .frame(minWidth: MinSize.hitTarget, minHeight: MinSize.hitTarget)
        .contentShape(Rectangle())
    }
}

// MARK: - Bar glyph

/// A glyph in a screen's own top bar. Square hit area, no border, accent when the
/// thing behind it is on — the same vocabulary as the ayah control strip. Shared
/// by the reader's bar and the surah list's, so the two can't drift apart.
struct BarButton: View {
    /// The HIG's minimum hit target.
    static let side: CGFloat = MinSize.hitTarget

    let icon: String
    let label: String
    var on: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.label(15, weight: .medium))
                .foregroundStyle(on ? Color.brand : Palette.textSecondary)
                .frame(width: Self.side, height: Self.side)
                .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(scale: 0.88))
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Legacy card surfaces
//
// The dashboard and reader are ruled now, but Memorization, Qibla, Dhikr, the
// 99 Names and the calendar still speak in cards. These stay so those screens
// keep their shape (and keep compiling) until they get the same pass.

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
        .accessibilityElement(children: .combine)
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
                    .font(.label(13, weight: .bold))
                    .foregroundStyle(accent)
                Spacer()
                MetaText("\(surah.number)", tint: accent)
            }
            .padding(.bottom, 12)

            Spacer()

            Text(surah.name)
                .font(.appArabic(24))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.bottom, 8)

            Text(surah.englishName)
                .font(.appSerif(17, weight: .medium))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        // Grows with Dynamic Type rather than clipping the names.
        .frame(width: 176)
        .frame(minHeight: 132)
        .overlay(Rectangle().strokeBorder(Color(.label).opacity(0.16), lineWidth: 1))
    }
}
