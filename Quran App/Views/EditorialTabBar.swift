import SwiftUI
import Combine

// The app's own tab bar. The system bar is a rounded, icon-led control that
// belongs to a different app than the one this became — so it's hidden, and this
// takes its place: three letterspaced words on a ruled edge, the active one held
// by a rule in the accent.

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
    /// Height of the label row. A `safeAreaInset` on the TabView reserves this
    /// for scrolling content, but it does not reach a fixed layout inside a
    /// pushed NavigationStack — screens that dock their own bottom chrome
    /// (the dhikr counter) have to reserve it themselves.
    static let barHeight: CGFloat = 50

    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            // Content dissolves into the bar instead of being clipped by it.
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 20)
            .allowsHitTesting(false)

            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    item(tab)
                }
            }
            .frame(height: Self.barHeight)
            // Extend the fill under the home indicator, or the strip below the
            // bar shows as a seam against a dark page.
            .background(Color(.systemBackground), ignoresSafeAreaEdges: .bottom)
            .overlay(alignment: .top) { Hairline() }
        }
    }

    private func item(_ tab: AppTab) -> some View {
        let on = tab == selection
        return Button {
            guard !on else { return }
            Haptics.selection()
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Text(tab.title.uppercased())
                    .font(.system(size: 10, weight: on ? .bold : .semibold))
                    .kerning(1.5)
                    .foregroundStyle(on ? Color(.label) : Color(.label).opacity(0.4))
                // The rule is always laid out so switching tabs doesn't shift
                // the labels by a pixel and a half.
                Rectangle()
                    .fill(on ? Color.brand : .clear)
                    .frame(width: 26, height: 1.5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(AppAnim.smooth, value: on)
        .accessibilityLabel(tab.accessibilityName)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
