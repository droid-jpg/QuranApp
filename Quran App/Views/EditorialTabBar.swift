import SwiftUI
import Combine

// The app's own tab bar, in place of the system one (hidden per tab): an SF Symbol over a
// sentence-case label on an opaque surface with a top hairline; the selected tab in the accent.

/// Chrome the reader needs out of its way. A published flag rather than a
/// `.toolbar(.hidden, for: .tabBar)` modifier, because the bar is now ours and
/// lives outside the tab's own view tree.
@MainActor
final class Chrome: ObservableObject {
    static let shared = Chrome()
    /// Set by the surah reader so scripture gets the whole page.
    @Published var tabBarHidden = false
    private init() {}
}

struct EditorialTabBar: View {
    /// Height of the bar's content row: a 24 pt icon over an 11 pt label, with room to spare for
    /// the 44 pt minimum hit target. A `safeAreaInset` on the TabView reserves this for scrolling
    /// content, but it does not reach a fixed layout inside a pushed NavigationStack — screens
    /// that dock their own bottom chrome (the dhikr counter) have to reserve it themselves.
    static let barHeight: CGFloat = 56

    @Binding var selection: AppTab
    @ObservedObject private var chrome = Chrome.shared

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .frame(height: Self.barHeight)
        // Like the system tab bar: the labels grow with Dynamic Type up to the largest
        // non-accessibility size, then a long press shows them in the Large Content Viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Opaque, and extended under the home indicator so no strip below the bar shows as a
        // seam. A hairline on the top edge separates it from the content above.
        .background(Palette.surface, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) { Hairline() }
        // The reader hides the bar; while it is out of sight it is out of the accessibility tree too.
        .accessibilityHidden(chrome.tabBarHidden)
    }

    private func item(_ tab: AppTab) -> some View {
        let on = tab == selection
        return Button {
            guard !on else { return }
            Haptics.selection()
            selection = tab
        } label: {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 24))
                    .frame(height: 28)
                Text(tab.title)
                    .font(TypeScale.tabLabel)
                    .lineLimit(1)
            }
            .foregroundStyle(on ? Palette.accent : Palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: MinSize.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: on)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: tab.symbol)
        }
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
