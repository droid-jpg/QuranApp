import SwiftUI
import UIKit

// The restyle takes English fully into serif, so the face is no longer a
// hard-coded `.fontDesign(.serif)` — it's a reading preference, alongside the
// Arabic script and the two sizes. Everything here resolves against fonts that
// actually ship with iOS and falls back to the system serif when one is missing,
// so a bad name can never leave the reader in a fallback sans.

// MARK: - Translation face

enum ReadingFace: String, CaseIterable, Identifiable {
    /// Apple's own serif. The default: it has a real italic, tracks well at
    /// reading sizes, and follows Dynamic Type.
    case newYork
    /// Bookish and warm — the closest thing on iOS to the Garamond direction.
    case iowan
    /// Narrower and more literary; fits more translation per line.
    case charter
    /// The old look, for anyone who wants their sans back.
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newYork: "New York"
        case .iowan:   "Iowan Old Style"
        case .charter: "Charter"
        case .system:  "SF Pro"
        }
    }

    var caption: String {
        switch self {
        case .newYork: "Apple's serif"
        case .iowan:   "Classical"
        case .charter: "Literary"
        case .system:  "The old look"
        }
    }

    /// PostScript names, `nil` for the two that come from the system designs.
    fileprivate var faceNames: (roman: String, italic: String, bold: String)? {
        switch self {
        case .iowan:   ("IowanOldStyle-Roman", "IowanOldStyle-Italic", "IowanOldStyle-Bold")
        case .charter: ("Charter-Roman", "Charter-Italic", "Charter-Bold")
        case .newYork, .system: nil
        }
    }

    var isSerif: Bool { self != .system }

    static var current: ReadingFace {
        // Deliberately uncached: views that must follow a change declare
        // `@AppStorage("readingFace")`, and a cache would go stale behind them.
        ReadingFace(rawValue: UserDefaults.standard.string(forKey: "readingFace") ?? "") ?? .newYork
    }

    /// `scales` follows Dynamic Type, relative to the text style nearest `size`. Iowan and Charter
    /// keep their exact size at the default setting; New York and SF are system designs, which
    /// can only scale as a text style, so they take that style's size. Pass `false` for sizes the
    /// reader's own sliders chose: those are the person's explicit choice and shouldn't compound.
    func font(size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false, scales: Bool = true) -> Font {
        let style = scales ? Font.TextStyle.nearest(to: size) : nil
        guard let names = faceNames else {
            let design: Font.Design = isSerif ? .serif : .default
            let base = style.map { Font.system($0, design: design, weight: weight) }
                ?? Font.system(size: size, weight: weight, design: design)
            return italic ? base.italic() : base
        }
        let wanted = italic ? names.italic : (Self.isBoldish(weight) ? names.bold : names.roman)
        if UIFont(name: wanted, size: size) != nil {
            return style.map { .custom(wanted, size: size, relativeTo: $0) } ?? .custom(wanted, fixedSize: size)
        }
        // The face isn't on this device — keep the serif intent, drop the face.
        let base = style.map { Font.system($0, design: .serif, weight: weight) }
            ?? Font.system(size: size, weight: weight, design: .serif)
        return italic ? base.italic() : base
    }

    /// Iowan and Charter ship roman/italic/bold only, so anything semibold or
    /// heavier is drawn with the bold cut rather than synthesised.
    private static func isBoldish(_ weight: Font.Weight) -> Bool {
        switch weight {
        case .semibold, .bold, .heavy, .black: true
        default: false
        }
    }
}

// MARK: - Arabic script

enum ArabicScript: String, CaseIterable, Identifiable {
    /// SF Arabic. Cleanest vowel marks of the three at small sizes.
    case system
    /// A modern naskh with more contrast in the stroke.
    case alNile
    /// Rounder and more traditional; the closest to a printed mushaf.
    case damascus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:   "System"
        case .alNile:   "Al Nile"
        case .damascus: "Damascus"
        }
    }

    fileprivate var faceName: String? {
        switch self {
        case .system:   nil
        case .alNile:   "AlNile"
        case .damascus: "Damascus"
        }
    }

    /// Naskh faces sit optically smaller than SF Arabic at the same point size,
    /// so the slider's value is nudged rather than the user having to.
    private var sizeScale: CGFloat {
        switch self {
        case .system:   1.0
        case .alNile:   1.06
        case .damascus: 1.04
        }
    }

    /// True when this face renders on the current device.
    var isAvailable: Bool {
        guard let name = faceName else { return true }
        return UIFont(name: name, size: 20) != nil
    }

    static var current: ArabicScript {
        let stored = ArabicScript(rawValue: UserDefaults.standard.string(forKey: "arabicScript") ?? "") ?? .system
        return stored.isAvailable ? stored : .system
    }

    /// `scales` works as it does for `ReadingFace.font`: SF Arabic takes the nearest text style,
    /// the named faces keep their size relative to it, and slider-chosen sizes pass `false`.
    func font(size: CGFloat, scales: Bool = true) -> Font {
        let scaled = size * sizeScale
        let style = scales ? Font.TextStyle.nearest(to: size) : nil
        guard let name = faceName, UIFont(name: name, size: scaled) != nil else {
            return style.map { Font.system($0) } ?? .system(size: scaled)
        }
        return style.map { .custom(name, size: scaled, relativeTo: $0) } ?? .custom(name, fixedSize: scaled)
    }
}

// MARK: - Following a change of face

extension Notification.Name {
    /// Posted when the reading face or the Arabic script changes. The reader
    /// repaints itself (see `ReadingType`); this is how the screens that still
    /// set type through `Font.appSerif` are told to rebuild.
    static let readingTypeDidChange = Notification.Name("readingTypeDidChange")
}

/// The reading face and script as a *dependency* rather than a lookup.
///
/// `Font.appSerif` / `.appArabic` read `UserDefaults` directly, which is why a
/// view that only calls them never repaints when the face changes: SwiftUI
/// registers an `@AppStorage` dependency when the stored value is **read during
/// body**, and those helpers read behind its back. (The size sliders always
/// worked for exactly this reason — their values *are* read in body.)
///
/// Declare this in any view whose type must follow the setting live, and set
/// fonts from it:
///
///     private var type = ReadingType()
///     …
///     Text(ayah.translation).font(type.serif(17))
struct ReadingType: DynamicProperty {
    @AppStorage("readingFace")  private var faceRaw   = ReadingFace.newYork.rawValue
    @AppStorage("arabicScript") private var scriptRaw = ArabicScript.system.rawValue

    var face: ReadingFace { ReadingFace(rawValue: faceRaw) ?? .newYork }

    var script: ArabicScript {
        let stored = ArabicScript(rawValue: scriptRaw) ?? .system
        return stored.isAvailable ? stored : .system
    }

    func serif(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false, scales: Bool = true) -> Font {
        face.font(size: size, weight: weight, italic: italic, scales: scales)
    }

    func arabic(_ size: CGFloat, scales: Bool = true) -> Font { script.font(size: size, scales: scales) }
}

// MARK: - Convenience

extension Font {
    /// The app's reading serif at an explicit size. Used for prose and for the
    /// editorial headings, so the chrome and the scripture share one voice.
    static func appSerif(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false,
                         scales: Bool = true) -> Font {
        ReadingFace.current.font(size: size, weight: weight, italic: italic, scales: scales)
    }

    /// The Arabic face at an explicit size.
    static func appArabic(_ size: CGFloat, scales: Bool = true) -> Font {
        ArabicScript.current.font(size: size, scales: scales)
    }
}

// MARK: - Dynamic Type

extension Font.TextStyle {
    /// The text style whose default size (at the Large setting) is nearest `size`, so a size set
    /// by eye can scale with Dynamic Type. `nil` above 34 pt: display type like the dhikr counter
    /// is already large, and scaling it further would push it off the screen.
    static func nearest(to size: CGFloat) -> Font.TextStyle? {
        switch size {
        case ..<11.5: .caption2      // 11
        case ..<12.5: .caption       // 12
        case ..<14:   .footnote      // 13
        case ..<15.5: .subheadline   // 15
        case ..<16.5: .callout       // 16
        case ..<18.5: .body          // 17
        case ..<21:   .title3        // 20
        case ..<25:   .title2        // 22
        case ..<31:   .title         // 28
        case ...34:   .largeTitle    // 34
        default:      nil
        }
    }
}
