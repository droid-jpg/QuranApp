import SwiftUI
import UIKit

// The app's accent palette. Teal is the original brand and stays the default;
// the rest exist because the reading surface is now ink-on-paper editorial, so
// the accent is the only colour on screen and people want it to be theirs.
//
// Shared with the widget target (see the "Quran App" folder membership
// exceptions in project.pbxproj) and persisted in the App Group, so a widget
// can paint itself in the same theme without launching the app.

private let themeAppGroup = "group.sami.Quran-App"
private let themeStorageKey = "appTheme"

extension Notification.Name {
    /// Posted after `AppTheme.set(_:)`. The root scene listens and repaints.
    static let appThemeDidChange = Notification.Name("appThemeDidChange")
}

/// A light/dark pair of RGB triples. Kept as plain numbers so the same value
/// resolves identically in the app and in the widget without an asset catalog.
struct ThemeInk {
    let light: (r: Double, g: Double, b: Double)
    let dark:  (r: Double, g: Double, b: Double)

    var color: Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        })
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case teal, brass, indigo, plum, rose, sage, slate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .teal:   "Teal"
        case .brass:  "Brass"
        case .indigo: "Indigo"
        case .plum:   "Plum"
        case .rose:   "Rose"
        case .sage:   "Sage"
        case .slate:  "Slate"
        }
    }

    /// One line for the settings row — what the colour is *for*, not what it is.
    var caption: String {
        switch self {
        case .teal:   "The original mark"
        case .brass:  "Warm gilt, like a bound mushaf"
        case .indigo: "Deep night ink"
        case .plum:   "Quiet and unusual"
        case .rose:   "Soft, low-glare warmth"
        case .sage:   "Muted garden green"
        case .slate:  "Almost no colour at all"
        }
    }

    /// The accent proper — deeper in light mode so it holds on white, more
    /// luminous in dark so it doesn't glare on OLED.
    private var ink: ThemeInk {
        switch self {
        case .teal:   ThemeInk(light: (0.03, 0.47, 0.44), dark: (0.32, 0.80, 0.75))
        case .brass:  ThemeInk(light: (0.55, 0.42, 0.15), dark: (0.82, 0.70, 0.45))
        case .indigo: ThemeInk(light: (0.24, 0.28, 0.62), dark: (0.60, 0.64, 0.96))
        case .plum:   ThemeInk(light: (0.45, 0.20, 0.48), dark: (0.81, 0.58, 0.86))
        case .rose:   ThemeInk(light: (0.66, 0.20, 0.32), dark: (0.94, 0.57, 0.64))
        case .sage:   ThemeInk(light: (0.29, 0.44, 0.28), dark: (0.63, 0.81, 0.56))
        case .slate:  ThemeInk(light: (0.24, 0.33, 0.42), dark: (0.64, 0.74, 0.84))
        }
    }

    /// The far stop of accent gradients.
    private var deepInk: ThemeInk {
        switch self {
        case .teal:   ThemeInk(light: (0.01, 0.33, 0.33), dark: (0.10, 0.48, 0.46))
        case .brass:  ThemeInk(light: (0.40, 0.29, 0.08), dark: (0.55, 0.44, 0.24))
        case .indigo: ThemeInk(light: (0.15, 0.18, 0.45), dark: (0.34, 0.38, 0.74))
        case .plum:   ThemeInk(light: (0.30, 0.12, 0.34), dark: (0.56, 0.35, 0.62))
        case .rose:   ThemeInk(light: (0.46, 0.11, 0.22), dark: (0.70, 0.34, 0.44))
        case .sage:   ThemeInk(light: (0.18, 0.30, 0.18), dark: (0.40, 0.56, 0.36))
        case .slate:  ThemeInk(light: (0.14, 0.21, 0.29), dark: (0.40, 0.50, 0.62))
        }
    }

    var accent: Color { ink.color }
    var deep: Color { deepInk.color }

    /// Fixed light-mode swatch, for the settings picker — every theme has to be
    /// distinguishable in the same row regardless of the current appearance.
    var swatch: Color {
        Color(red: ink.light.r, green: ink.light.g, blue: ink.light.b)
    }

    // MARK: - Current selection

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: themeAppGroup) ?? .standard
    }

    /// Read on every `Color.brand`, so it's cached rather than hitting
    /// `UserDefaults` in the middle of a render pass.
    static var current: AppTheme {
        if let cached = themeCache.value { return cached }
        let theme = AppTheme(rawValue: defaults.string(forKey: themeStorageKey) ?? "") ?? .teal
        themeCache.value = theme
        return theme
    }

    /// Persist a new theme and tell the app to repaint. Widgets are reloaded so
    /// the home screen follows along.
    static func set(_ theme: AppTheme) {
        defaults.set(theme.rawValue, forKey: themeStorageKey)
        themeCache.value = theme
        NotificationCenter.default.post(name: .appThemeDidChange, object: nil)
    }
}

// MARK: - Cache

/// A tiny locked box: `AppTheme.current` is read from whatever actor is
/// rendering, so the cache can't be a bare mutable global under Swift 6.
private final class ThemeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppTheme?

    var value: AppTheme? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

private let themeCache = ThemeCache()
