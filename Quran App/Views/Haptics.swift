import SwiftUI
import UIKit

// Single source of truth for haptic feedback so every button, navigation tap,
// and state change across the app speaks the same tactile vocabulary.

enum Haptics {
    /// Light tap for navigation and generic button presses.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Selection change — pickers, filters, segmented toggles.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Impact for primary / committing actions. Defaults to medium.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

extension View {
    /// Fires a light tap haptic on a genuine tap without consuming it, so it
    /// composes with `NavigationLink` / `List` row selection (navigation still
    /// happens). Uses a `TapGesture`, so it stays silent during scrolling —
    /// unlike a `ButtonStyle` press, which also triggers on touch-down.
    func hapticTap() -> some View {
        simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }
}
